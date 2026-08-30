import { serve } from 'https://deno.land/std@0.168.0/http/server.ts'
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2'

const SUPABASE_URL = Deno.env.get('SUPABASE_URL')!
const SUPABASE_SERVICE_KEY = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!

// Fires 15+ minutes past a workout's planned duration, then every 30 minutes
// after that, capped at 3 nags total (see workouts.overtime_nag_count).
const OVERTIME_GRACE_MINUTES = 15
const RENAG_INTERVAL_MINUTES = 30
const MAX_NAGS = 3

// Fallback for a missing/unset user_profiles.timezone — same as coach-max-cron.
const FALLBACK_TZ = 'Europe/Dublin'

// ── tz helpers, copied verbatim from coach-max-cron (kept in sync there —
// each edge function deploys standalone, so no shared import) ─────────────
function tzParts(d: Date, tz: string): Record<string, string> {
  const fmt = new Intl.DateTimeFormat('en-GB', {
    timeZone: tz,
    hour12: false,
    year: 'numeric',
    month: '2-digit',
    day: '2-digit',
    hour: '2-digit',
    minute: '2-digit',
    second: '2-digit',
  })
  return Object.fromEntries(fmt.formatToParts(d).map((x) => [x.type, x.value]))
}

// Wall-clock "HH:MM:SS" in the given zone.
function localTimeOfDay(d: Date, tz: string): string {
  const p = tzParts(d, tz)
  const hh = p.hour === '24' ? '00' : p.hour // en-GB midnight edge
  return `${hh}:${p.minute}:${p.second}`
}

serve(async (req) => {
  try {
    // ============================================
    // AUTHORIZATION (same pattern as coach-max-cron / send-notification)
    // Scheduled service job only, never called by a user. Only the
    // service-role key may run it -- pg_cron sends exactly that, reading
    // vault.decrypted_secrets 'service_role_key'.
    // ============================================
    const bearer = (req.headers.get('Authorization') ?? '').replace(/^Bearer\s+/i, '').trim()
    if (bearer !== SUPABASE_SERVICE_KEY) {
      console.log('⛔ workout-overtime-cron: caller is not the service role')
      return new Response(JSON.stringify({ error: 'forbidden' }), { status: 403 })
    }

    const supabase = createClient(SUPABASE_URL, SUPABASE_SERVICE_KEY)
    const now = new Date()

    // Coarse candidate fetch (mirrors coach-max-cron PART 2): let SQL narrow
    // to workouts that could possibly be due, then do the exact time math in
    // JS. planned_duration_minutes/workout_started_at are both nullable in
    // theory (defensive filter only -- the app always sets workout_started_at
    // in the same update that sets status='in_progress').
    const { data: workouts, error: fetchError } = await supabase
      .from('workouts')
      .select('id, user_id, workout_started_at, planned_duration_minutes, overtime_nag_count, last_overtime_nag_at')
      .eq('status', 'in_progress')
      .lt('overtime_nag_count', MAX_NAGS)
      .not('workout_started_at', 'is', null)
      .not('planned_duration_minutes', 'is', null)

    if (fetchError) {
      console.error('❌ Error fetching in-progress workouts:', fetchError)
      return new Response(JSON.stringify({ error: fetchError.message }), { status: 500 })
    }

    const dueCandidates = (workouts ?? []).filter((w: any) => {
      const overtimeAt = new Date(w.workout_started_at).getTime() +
        (w.planned_duration_minutes + OVERTIME_GRACE_MINUTES) * 60_000
      if (now.getTime() < overtimeAt) return false

      if (w.last_overtime_nag_at) {
        const sinceLast = now.getTime() - new Date(w.last_overtime_nag_at).getTime()
        if (sinceLast < RENAG_INTERVAL_MINUTES * 60_000) return false
      }

      return true
    })

    if (dueCandidates.length === 0) {
      console.log('✅ No overtime workouts due right now')
      return new Response(JSON.stringify({ sent: 0, skipped_quiet_hours: 0 }), { status: 200 })
    }

    // Batched lookups for everyone in play, same shape as coach-max-cron.
    const userIds = [...new Set(dueCandidates.map((w: any) => w.user_id))]

    const { data: tzRows } = await supabase
      .from('user_profiles')
      .select('id, timezone')
      .in('id', userIds)
    const tzByUser = new Map<string, string>(
      (tzRows ?? []).map((r: any) => [r.id, r.timezone || FALLBACK_TZ]),
    )

    const { data: settingsRows } = await supabase
      .from('notification_settings')
      .select('user_id, quiet_hours_enabled, quiet_hours_start, quiet_hours_end')
      .in('user_id', userIds)
    const settingsByUser = new Map<string, any>(
      (settingsRows ?? []).map((r: any) => [r.user_id, r]),
    )

    let sent = 0
    let skippedQuietHours = 0

    for (const w of dueCandidates) {
      try {
        const tz = tzByUser.get(w.user_id) ?? FALLBACK_TZ
        const settings = settingsByUser.get(w.user_id)

        // Same branching send-notification itself uses for quiet hours, just
        // fed the user's own local hour instead of the server's UTC hour --
        // this check has to run BEFORE sending (not after) because the nag
        // budget must not burn a slot on an attempt nobody will see.
        if (settings?.quiet_hours_enabled) {
          const hour = Number(localTimeOfDay(now, tz).slice(0, 2))
          const start = settings.quiet_hours_start
          const end = settings.quiet_hours_end
          const inQuietHours = start > end
            ? (hour >= start || hour < end)
            : (hour >= start && hour < end)

          if (inQuietHours) {
            console.log(`🌙 workout-overtime: skipping user ${w.user_id} (quiet hours, ${tz} ${hour}:00)`)
            skippedQuietHours++
            continue
          }
        }

        const nextNagNumber = w.overtime_nag_count + 1

        await fetch(`${SUPABASE_URL}/functions/v1/send-notification`, {
          method: 'POST',
          headers: {
            'Content-Type': 'application/json',
            'Authorization': `Bearer ${SUPABASE_SERVICE_KEY}`,
          },
          body: JSON.stringify({
            user_id: w.user_id,
            title: '⏱️ Still working out?',
            body: "Your workout has run well past its planned time — tap to end it if you're done.",
            type: 'workout_overtime',
            reference_id: w.id,
            // Nag-number-scoped so a retry within the same nag can't double
            // send, but the next nag (30 min later) is a distinct key.
            batch_key: `workout_overtime_${w.id}_${nextNagNumber}`,
          }),
        })

        await supabase
          .from('workouts')
          .update({ overtime_nag_count: nextNagNumber, last_overtime_nag_at: now.toISOString() })
          .eq('id', w.id)

        console.log(`⏱️ Overtime nag ${nextNagNumber}/${MAX_NAGS} sent for workout ${w.id} (user ${w.user_id})`)
        sent++

      } catch (err) {
        console.error(`❌ Overtime nag failed for workout ${w.id}:`, err)
      }
    }

    return new Response(
      JSON.stringify({ sent, skipped_quiet_hours: skippedQuietHours, total_due: dueCandidates.length }),
      { status: 200 },
    )

  } catch (error) {
    console.error('❌ Fatal error:', error)
    return new Response(JSON.stringify({ error: error.message }), { status: 500 })
  }
})
