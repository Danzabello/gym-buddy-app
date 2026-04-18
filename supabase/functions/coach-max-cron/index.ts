import { serve } from 'https://deno.land/std@0.168.0/http/server.ts'
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2'

const SUPABASE_URL = Deno.env.get('SUPABASE_URL')!
const SUPABASE_SERVICE_KEY = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!

const COACH_MAX_ID = '00000000-0000-0000-0000-000000000001'

serve(async () => {
  try {
    const supabase = createClient(SUPABASE_URL, SUPABASE_SERVICE_KEY)

    const now = new Date()
    const todayStr = now.toISOString().split('T')[0]
    // Current time as HH:MM:SS for comparison
    const currentTime = now.toTimeString().split(' ')[0]

    console.log(`⏰ Coach Max cron running at ${todayStr} ${currentTime}`)

    // ── Find all pending check-ins where scheduled time has passed ──
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

    if (!pendingSchedules || pendingSchedules.length === 0) {
      console.log('✅ No pending Coach Max check-ins right now')
      return new Response(JSON.stringify({ processed: 0 }), { status: 200 })
    }

    console.log(`📋 Found ${pendingSchedules.length} pending check-ins`)

    let processed = 0
    let failed = 0

    for (const schedule of pendingSchedules) {
      const { user_id, id: scheduleId } = schedule

      try {
        // ── Step 1: Get Coach Max team for this user ──
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

        // ── Step 2: Get active streak ──
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

        // ── Step 3: Check Coach Max hasn't already checked in today ──
        const { data: existingCheckIn } = await supabase
          .from('daily_team_checkins')
          .select('id')
          .eq('team_streak_id', streakId)
          .eq('user_id', COACH_MAX_ID)
          .eq('check_in_date', todayStr)
          .maybeSingle()

        if (existingCheckIn) {
          console.log(`✅ Coach Max already checked in for user ${user_id}`)
          // Mark as done so we don't keep processing it
          await supabase
            .from('coach_max_schedule')
            .update({ has_checked_in: true, checked_in_at: now.toISOString() })
            .eq('id', scheduleId)
          continue
        }

        // ── Step 4: Perform Coach Max check-in ──
        await supabase.from('daily_team_checkins').insert({
          team_streak_id: streakId,
          user_id: COACH_MAX_ID,
          check_in_date: todayStr,
          check_in_time: now.toISOString(),
        })

        // ── Step 5: Mark schedule as complete ──
        await supabase
          .from('coach_max_schedule')
          .update({ has_checked_in: true, checked_in_at: now.toISOString() })
          .eq('id', scheduleId)

        // ── Step 6: Check if user has also checked in (update streak if so) ──
        const { data: userCheckIn } = await supabase
          .from('daily_team_checkins')
          .select('id')
          .eq('team_streak_id', streakId)
          .eq('check_in_date', todayStr)
          .neq('user_id', COACH_MAX_ID)
          .maybeSingle()

        if (userCheckIn) {
          // Both checked in — update streak
          await _updateStreak(supabase, streakId, todayStr)
        }

        // ── Step 7: Send push notification ──
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

    return new Response(
      JSON.stringify({ processed, failed, total: pendingSchedules.length }),
      { status: 200 }
    )

  } catch (error) {
    console.error('❌ Fatal error:', error)
    return new Response(JSON.stringify({ error: error.message }), { status: 500 })
  }
})

// ── Update streak when both have checked in ──────────────────────────────
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

    if (daysDiff === 0) return      // already counted
    if (daysDiff === 1) {
      newStreak = currentStreak + 1
      if (newStreak > longestStreak) newLongest = newStreak
    } else {
      newStreak = 1                  // streak broken
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
