import { serve } from 'https://deno.land/std@0.168.0/http/server.ts'
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2'

const SUPABASE_URL = Deno.env.get('SUPABASE_URL')!
const SUPABASE_SERVICE_KEY = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!

const COACH_MAX_ID = '00000000-0000-0000-0000-000000000001'

// Coach Max fires between 07:00 and 17:00 in EACH HUMAN MEMBER'S OWN
// timezone (user_profiles.timezone — trigger-validated IANA name; fallback
// Europe/Dublin, matching the DB-side safe_user_tz()). DST-correct via the
// IANA tz database — never a hardcoded UTC offset.
const DEFAULT_ACTIVE_START = 7
const DEFAULT_ACTIVE_END = 17
const FALLBACK_TZ = 'Europe/Dublin'

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

// Calendar date "YYYY-MM-DD" in the given zone — matches the per-user
// check_in_date labels (safe_user_tz frame) used by the streak RPCs.
function localDateStr(d: Date, tz: string): string {
  const p = tzParts(d, tz)
  return `${p.year}-${p.month}-${p.day}`
}

serve(async () => {
  try {
    const supabase = createClient(SUPABASE_URL, SUPABASE_SERVICE_KEY)

    const now = new Date()
    // UTC date is used ONLY by PART 3 (streak danger, deliberately UTC) and
    // as a lower bound for range queries. scheduled_date / check_in_date are
    // per-user local dates (the human member's own tz), matching the
    // safe_user_tz labels the streak RPCs use.
    const todayStr = now.toISOString().split('T')[0]
    const recentDateStr = new Date(now.getTime() - 2 * 86400000).toISOString().split('T')[0]
    // PART 3 (streak danger) intentionally still keys off UTC — see below.
    const currentHour = now.getUTCHours()

    console.log(`⏰ Coach Max cron: UTC ${todayStr} ${now.toISOString().split('T')[1].slice(0, 8)}`)

    // ── PART 1: Create today's schedule per member, in THEIR local today ──
    const { data: coachMaxTeamMembers } = await supabase
      .from('team_members')
      .select('user_id, buddy_teams!inner(is_coach_max_team)')
      .eq('buddy_teams.is_coach_max_team', true)
      .neq('user_id', COACH_MAX_ID)

    const memberIds = [...new Set((coachMaxTeamMembers ?? []).map((m: any) => m.user_id))]

    // One tz lookup for everyone (column is trigger-validated; fallback
    // mirrors safe_user_tz).
    const { data: tzRows } = await supabase
      .from('user_profiles')
      .select('id, timezone')
      .in('id', memberIds)
    const tzByUser = new Map<string, string>(
      (tzRows ?? []).map((r: any) => [r.id, r.timezone || FALLBACK_TZ]),
    )

    // Existing schedules near today — a date range covers every tz's "today"
    // (the old single-date .eq can't, now that dates are per-user).
    const { data: allSchedules } = await supabase
      .from('coach_max_schedule')
      .select('user_id, scheduled_date')
      .gte('scheduled_date', recentDateStr)
    const scheduledKeys = new Set(
      (allSchedules ?? []).map((r: any) => `${r.user_id}:${r.scheduled_date}`),
    )

    for (const userId of memberIds) {
      const tz = tzByUser.get(userId) ?? FALLBACK_TZ
      const userToday = localDateStr(now, tz)
      if (scheduledKeys.has(`${userId}:${userToday}`)) continue

      const { data: notifSettings } = await supabase
        .from('notification_settings')
        .select('quiet_hours_enabled, quiet_hours_start, quiet_hours_end')
        .eq('user_id', userId)
        .maybeSingle()

      const scheduledTime = _generateActiveWindowTime(notifSettings)

      await supabase.from('coach_max_schedule').insert({
        user_id: userId,
        scheduled_date: userToday,
        scheduled_time: scheduledTime,
        has_checked_in: false,
      })

      console.log(`📅 Scheduled Coach Max for user ${userId} at ${scheduledTime} (${tz} ${userToday})`)
    }

    // ── PART 2: Process pending check-ins where time has passed ──
    // Fire when the schedule's date is the member's CURRENT local date and
    // the wall-clock time has passed in the member's own zone. (Stale
    // schedules from previous local days are ignored, as before.)
    const { data: pendingSchedules, error: fetchError } = await supabase
      .from('coach_max_schedule')
      .select('id, user_id, scheduled_date, scheduled_time')
      .eq('has_checked_in', false)
      .gte('scheduled_date', recentDateStr)

    if (fetchError) {
      console.error('❌ Error fetching schedules:', fetchError)
      return new Response(JSON.stringify({ error: fetchError.message }), { status: 500 })
    }

    const dueSchedules = (pendingSchedules ?? []).filter((s: any) => {
      const tz = tzByUser.get(s.user_id) ?? FALLBACK_TZ
      return s.scheduled_date === localDateStr(now, tz) &&
             s.scheduled_time <= localTimeOfDay(now, tz)
    })

    let processed = 0
    let failed = 0

    if (dueSchedules.length > 0) {
      console.log(`📋 Found ${dueSchedules.length} due check-ins`)

      for (const schedule of dueSchedules) {
        const { user_id, id: scheduleId, scheduled_date: userToday } = schedule

        try {
          const { data: teamMember } = await supabase
            .from('team_members')
            .select('team_id, buddy_teams!inner(is_coach_max_team)')
            .eq('user_id', user_id)
            .eq('buddy_teams.is_coach_max_team', true)
            .maybeSingle()

          if (!teamMember) {
            console.log(`⚠️ No Coach Max team for user ${user_id}`)
            continue
          }

          const teamId = teamMember.team_id

          const { data: streak } = await supabase
            .from('team_streaks')
            .select('id, current_streak')
            .eq('team_id', teamId)
            .eq('is_active', true)
            .maybeSingle()

          if (!streak) {
            console.log(`⚠️ No active streak for team ${teamId}`)
            continue
          }

          const streakId = streak.id
          const currentStreak = streak.current_streak ?? 0

          // Coach Max's row is dated in the HUMAN member's local today
          // (userToday = the schedule's per-user date), so it lands on the
          // same label as the human's own check-in.
          const { data: existingCheckIn } = await supabase
            .from('daily_team_checkins')
            .select('id')
            .eq('team_streak_id', streakId)
            .eq('user_id', COACH_MAX_ID)
            .eq('check_in_date', userToday)
            .maybeSingle()

          if (existingCheckIn) {
            console.log(`✅ Coach Max already checked in for user ${user_id}`)
            await supabase
              .from('coach_max_schedule')
              .update({ has_checked_in: true, checked_in_at: now.toISOString() })
              .eq('id', scheduleId)
            continue
          }

          await supabase.from('daily_team_checkins').insert({
            team_streak_id: streakId,
            user_id: COACH_MAX_ID,
            check_in_date: userToday,
            check_in_time: now.toISOString(),
          })

          await supabase
            .from('coach_max_schedule')
            .update({ has_checked_in: true, checked_in_at: now.toISOString() })
            .eq('id', scheduleId)

          const { data: userCheckIn } = await supabase
            .from('daily_team_checkins')
            .select('id')
            .eq('team_streak_id', streakId)
            .eq('check_in_date', userToday)
            .neq('user_id', COACH_MAX_ID)
            .maybeSingle()

          if (userCheckIn) {
            await _updateStreak(supabase, streakId, userToday)
          }

          const message = _getMotivationalMessage(currentStreak)

          await fetch(`${SUPABASE_URL}/functions/v1/send-notification`, {
            method: 'POST',
            headers: {
              'Content-Type': 'application/json',
              'Authorization': `Bearer ${SUPABASE_SERVICE_KEY}`,
            },
            body: JSON.stringify({
              user_id,
              title: '🤖 Coach Max',
              body: message,
              type: 'coach_max_motivational',
              batch_key: `coach_max_daily_${userToday}_${user_id}`,
            }),
          })

          console.log(`✅ Processed Coach Max check-in for user ${user_id}`)
          processed++

        } catch (err) {
          console.error(`❌ Failed for user ${user_id}:`, err)
          failed++
        }
      }
    } else {
      console.log('✅ No due Coach Max check-ins right now')
    }

    // ── PART 3: Streak danger notifications at 18:00 UTC ──
    // NOTE: separate from Coach Max's per-user firing window and deliberately
    // still UTC-framed (todayStr) — localizing danger alerts per member is a
    // future follow-up, out of this step's scope.
    if (currentHour === 18) {
      console.log('🚨 Running streak danger check...')

      const { data: activeStreaks } = await supabase
        .from('team_streaks')
        .select('id, team_id, current_streak')
        .eq('is_active', true)
        .gt('current_streak', 0)

      if (activeStreaks && activeStreaks.length > 0) {
        for (const streak of activeStreaks) {
          try {
            const { id: streakId, team_id: teamId, current_streak: currentStreak } = streak

            const { data: team } = await supabase
              .from('buddy_teams')
              .select('team_name, is_coach_max_team')
              .eq('id', teamId)
              .single()

            if (!team) continue

            const { data: todayCheckIns } = await supabase
              .from('daily_team_checkins')
              .select('user_id')
              .eq('team_streak_id', streakId)
              .eq('check_in_date', todayStr)

            const checkedInUserIds = new Set(
              (todayCheckIns ?? []).map((c: any) => c.user_id)
            )

            const { data: members } = await supabase
              .from('team_members')
              .select('user_id')
              .eq('team_id', teamId)
              .neq('user_id', COACH_MAX_ID)

            if (!members || members.length === 0) continue

            const isCoachMaxTeam = team.is_coach_max_team
            const humanMembers = members.map((m: any) => m.user_id)

            let shouldAlert = false
            if (isCoachMaxTeam) {
              shouldAlert = !checkedInUserIds.has(humanMembers[0])
            } else {
              const anyoneCheckedIn = humanMembers.some((id: string) => checkedInUserIds.has(id))
              shouldAlert = !anyoneCheckedIn
            }

            if (!shouldAlert) continue

            for (const userId of humanMembers) {
              if (checkedInUserIds.has(userId)) continue

              await fetch(`${SUPABASE_URL}/functions/v1/send-notification`, {
                method: 'POST',
                headers: {
                  'Content-Type': 'application/json',
                  'Authorization': `Bearer ${SUPABASE_SERVICE_KEY}`,
                },
                body: JSON.stringify({
                  user_id: userId,
                  title: '🔥 Streak in Danger!',
                  body: currentStreak === 1
                    ? `Don't lose your first streak day! Check in before midnight!`
                    : `Your ${currentStreak}-day streak ends at midnight — check in now!`,
                  type: 'streak_danger',
                  reference_id: streakId,
                  batch_key: `streak_danger_${userId}_${todayStr}`,
                }),
              })

              console.log(`🚨 Streak danger sent to user ${userId} — ${currentStreak} day streak at risk`)
            }

          } catch (err) {
            console.error(`❌ Streak danger failed for team ${streak.team_id}:`, err)
          }
        }
      }
    }

    return new Response(
      JSON.stringify({ processed, failed, total: dueSchedules.length }),
      { status: 200 }
    )

  } catch (error) {
    console.error('❌ Fatal error:', error)
    return new Response(JSON.stringify({ error: error.message }), { status: 500 })
  }
})

// ── Generate random time within user's active (non-quiet) hours ──────────
// Hours are the USER'S OWN local wall-clock (default 07:00–17:00); the
// scheduled_time is later compared against localTimeOfDay(now, userTz), so
// generation and firing share the same per-user frame.
function _generateActiveWindowTime(notifSettings: any): string {
  let activeStart = DEFAULT_ACTIVE_START
  let activeEnd = DEFAULT_ACTIVE_END

  if (notifSettings?.quiet_hours_enabled) {
    const quietStart = notifSettings.quiet_hours_start
    const quietEnd = notifSettings.quiet_hours_end

    if (quietStart > quietEnd) {
      activeStart = quietEnd
      activeEnd = quietStart
    } else {
      activeStart = quietEnd
      activeEnd = quietStart + 24
    }
  }

  const totalMinutes = (activeEnd - activeStart) * 60
  const randomMinutes = Math.floor(Math.random() * totalMinutes)
  const hour = (activeStart + Math.floor(randomMinutes / 60)) % 24
  const minute = randomMinutes % 60

  return `${hour.toString().padStart(2, '0')}:${minute.toString().padStart(2, '0')}:00`
}

// ── Update streak when both have checked in ───────────────────────────────
async function _updateStreak(supabase: any, streakId: string, today: string) {
  const { data, error } = await supabase.rpc('recompute_team_streak', {
    p_streak_id: streakId,
    p_check_in_date: today,
  })

  if (error) {
    console.error('❌ recompute_team_streak failed:', error)
    return
  }

  console.log(`🔥 Streak updated via recompute_team_streak →`, data)
}

// ── Motivational messages ─────────────────────────────────────────────────
function _getMotivationalMessage(currentStreak: number): string {
  const messages =
    currentStreak === 0 ? [
      "Day 1 starts now! Let's build something great! 💪",
      "Every champion started somewhere. Today is your day!",
      "Ready to begin? Let's go! 🚀",
    ] : currentStreak >= 30 ? [
      `${currentStreak} DAYS! You're a legend! 🏆`,
      `This ${currentStreak}-day streak is INSANE! Keep it alive! 🔥`,
      `Champion mentality! ${currentStreak} days strong! 👑`,
    ] : currentStreak >= 7 ? [
      `${currentStreak} days strong! You're building something special! 🔥`,
      `Look at that ${currentStreak}-day streak! Consistency is key! 💪`,
      `${currentStreak} consecutive days! You're on fire! 🔥`,
    ] : [
      "Ready to work? Let's do this! 💪",
      "Another day, another opportunity! Let's go!",
      `Day ${currentStreak + 1} awaits! Let's make it count! 🔥`,
      "Keep the momentum going! 🚀",
    ]

  return messages[Math.floor(Math.random() * messages.length)]
}