import { serve } from 'https://deno.land/std@0.168.0/http/server.ts'
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2'

const SUPABASE_URL = Deno.env.get('SUPABASE_URL')!
const SUPABASE_SERVICE_KEY = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!

const COACH_MAX_ID = '00000000-0000-0000-0000-000000000001'

const DEFAULT_ACTIVE_START = 5
const DEFAULT_ACTIVE_END = 15

serve(async () => {
  try {
    const supabase = createClient(SUPABASE_URL, SUPABASE_SERVICE_KEY)

    const now = new Date()
    const todayStr = now.toISOString().split('T')[0]
    const currentTime = now.toTimeString().split(' ')[0]
    const currentHour = now.getUTCHours()

    console.log(`⏰ Coach Max cron running at ${todayStr} ${currentTime}`)

    // ── PART 1: Create today's schedules for users who don't have one yet ──
    const { data: allUsers } = await supabase
      .from('coach_max_schedule')
      .select('user_id')
      .eq('scheduled_date', todayStr)

    const scheduledUserIds = new Set((allUsers ?? []).map((r: any) => r.user_id))

    const { data: coachMaxTeamMembers } = await supabase
      .from('team_members')
      .select('user_id, buddy_teams!inner(is_coach_max_team)')
      .eq('buddy_teams.is_coach_max_team', true)
      .neq('user_id', COACH_MAX_ID)

    if (coachMaxTeamMembers) {
      for (const member of coachMaxTeamMembers) {
        const userId = member.user_id
        if (scheduledUserIds.has(userId)) continue

        const { data: notifSettings } = await supabase
          .from('notification_settings')
          .select('quiet_hours_enabled, quiet_hours_start, quiet_hours_end')
          .eq('user_id', userId)
          .maybeSingle()

        const scheduledTime = _generateActiveWindowTime(notifSettings)

        await supabase.from('coach_max_schedule').insert({
          user_id: userId,
          scheduled_date: todayStr,
          scheduled_time: scheduledTime,
          has_checked_in: false,
        })

        console.log(`📅 Scheduled Coach Max for user ${userId} at ${scheduledTime}`)
      }
    }

    // ── PART 2: Process pending check-ins where time has passed ──
    const { data: pendingSchedules, error: fetchError } = await supabase
      .from('coach_max_schedule')
      .select('id, user_id, scheduled_time')
      .eq('scheduled_date', todayStr)
      .eq('has_checked_in', false)
      .lte('scheduled_time', currentTime)

    if (fetchError) {
      console.error('❌ Error fetching schedules:', fetchError)
      return new Response(JSON.stringify({ error: fetchError.message }), { status: 500 })
    }

    let processed = 0
    let failed = 0

    if (pendingSchedules && pendingSchedules.length > 0) {
      console.log(`📋 Found ${pendingSchedules.length} pending check-ins`)

      for (const schedule of pendingSchedules) {
        const { user_id, id: scheduleId } = schedule

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

          const { data: existingCheckIn } = await supabase
            .from('daily_team_checkins')
            .select('id')
            .eq('team_streak_id', streakId)
            .eq('user_id', COACH_MAX_ID)
            .eq('check_in_date', todayStr)
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
            check_in_date: todayStr,
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
            .eq('check_in_date', todayStr)
            .neq('user_id', COACH_MAX_ID)
            .maybeSingle()

          if (userCheckIn) {
            await _updateStreak(supabase, streakId, todayStr)
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
              batch_key: `coach_max_daily_${todayStr}_${user_id}`,
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
      console.log('✅ No pending Coach Max check-ins right now')
    }

    // ── PART 3: Streak danger notifications at 18:00 UTC ──
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
      JSON.stringify({ processed, failed, total: pendingSchedules?.length ?? 0 }),
      { status: 200 }
    )

  } catch (error) {
    console.error('❌ Fatal error:', error)
    return new Response(JSON.stringify({ error: error.message }), { status: 500 })
  }
})

// ── Generate random time within user's active (non-quiet) hours ──────────
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
  const { data: streakData } = await supabase
    .from('team_streaks')
    .select('current_streak, longest_streak, last_workout_date')
    .eq('id', streakId)
    .single()

  if (!streakData) return

  const currentStreak = streakData.current_streak ?? 0
  const longestStreak = streakData.longest_streak ?? 0
  const lastWorkoutDate = streakData.last_workout_date

  let newStreak = currentStreak
  let newLongest = longestStreak

  if (!lastWorkoutDate) {
    newStreak = 1
    newLongest = 1
  } else {
    const lastDate = new Date(lastWorkoutDate)
    const todayDate = new Date(today)
    const daysDiff = Math.round(
      (todayDate.getTime() - lastDate.getTime()) / (1000 * 60 * 60 * 24)
    )

    if (daysDiff === 0) return
    if (daysDiff === 1) {
      newStreak = currentStreak + 1
      if (newStreak > longestStreak) newLongest = newStreak
    } else {
      newStreak = 1
    }
  }

  await supabase
    .from('team_streaks')
    .update({
      current_streak: newStreak,
      longest_streak: newLongest,
      last_workout_date: today,
      updated_at: new Date().toISOString(),
    })
    .eq('id', streakId)

  console.log(`🔥 Streak updated → current: ${newStreak}, longest: ${newLongest}`)
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