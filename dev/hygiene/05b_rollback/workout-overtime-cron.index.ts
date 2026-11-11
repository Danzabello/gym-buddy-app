import { serve } from 'https://deno.land/std@0.168.0/http/server.ts'
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2'

const SUPABASE_URL = Deno.env.get('SUPABASE_URL')!
const SUPABASE_SERVICE_KEY = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!

// "Still going?" fires 15+ minutes past a workout's planned duration, then
// every 30 minutes after that, capped at 3 nags total (see
// workouts.overtime_nag_count). "Before auto check-in" fires once at 3h15,
// 15 minutes before process_stale_sessions auto-completes at 3h30.
const OVERTIME_GRACE_MINUTES = 15
const RENAG_INTERVAL_MINUTES = 30
const MAX_NAGS = 3
const BEFORE_AUTO_MINUTES = 195

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

    const { data: workouts, error: fetchError } = await supabase
      .from('workouts')
      .select('id, user_id, buddy_id, creator_cancelled, buddy_cancelled, workout_started_at, planned_duration_minutes, overtime_nag_count, last_overtime_nag_at, before_auto_sent_at')
      .eq('status', 'in_progress')
      .not('workout_started_at', 'is', null)

    if (fetchError) {
      console.error('❌ Error fetching in-progress workouts:', fetchError)
      return new Response(JSON.stringify({ error: fetchError.message }), { status: 500 })
    }

    // Both people, minus anyone who left. Quiet hours, settings and the
    // per-recipient dedupe are applied by send-notification (both pushes are
    // urgent: they are time-critical, so they ignore quiet hours).
    const recipients = (w: any) => [
      ...(w.creator_cancelled ? [] : [w.user_id]),
      ...(w.buddy_id && !w.buddy_cancelled ? [w.buddy_id] : []),
    ]
    const push = (userId: string, key: string, w: any) =>
      supabase.rpc('_send_push', {
        p_user: userId, p_key: key, p_vars: {}, p_kind: 'amber', p_channel: 'handshake',
        p_type: key, p_ref: w.id, p_tag: `run_${w.id}`, p_urgent: true,
        p_sender: userId === w.user_id ? w.buddy_id : w.user_id,
      })

    let sent = 0
    let warned = 0

    for (const w of workouts ?? []) {
      const to = recipients(w)
      if (to.length === 0) continue
      const startedAt = new Date(w.workout_started_at).getTime()

      try {
        if (!w.before_auto_sent_at && now.getTime() >= startedAt + BEFORE_AUTO_MINUTES * 60_000) {
          // Claim first, so an overlapping run can't send it twice.
          const { data: claimed } = await supabase
            .from('workouts')
            .update({ before_auto_sent_at: now.toISOString() })
            .eq('id', w.id)
            .is('before_auto_sent_at', null)
            .select('id')
          if (claimed && claimed.length > 0) {
            for (const u of to) await push(u, 'before_auto', w)
            warned++
          }
          continue
        }

        if (w.planned_duration_minutes == null || w.overtime_nag_count >= MAX_NAGS) continue
        const overtimeAt = startedAt + (w.planned_duration_minutes + OVERTIME_GRACE_MINUTES) * 60_000
        if (now.getTime() < overtimeAt) continue
        if (w.last_overtime_nag_at &&
            now.getTime() - new Date(w.last_overtime_nag_at).getTime() < RENAG_INTERVAL_MINUTES * 60_000) continue

        for (const u of to) await push(u, 'still_going', w)
        await supabase
          .from('workouts')
          .update({ overtime_nag_count: w.overtime_nag_count + 1, last_overtime_nag_at: now.toISOString() })
          .eq('id', w.id)
        console.log(`⏱️ Still going ${w.overtime_nag_count + 1}/${MAX_NAGS} for workout ${w.id} → ${to.length} recipient(s)`)
        sent++
      } catch (err) {
        console.error(`❌ Overtime nag failed for workout ${w.id}:`, err)
      }
    }

    return new Response(JSON.stringify({ sent, before_auto: warned }), { status: 200 })
  } catch (error) {
    console.error('❌ Fatal error:', error)
    return new Response(JSON.stringify({ error: error.message }), { status: 500 })
  }
})
