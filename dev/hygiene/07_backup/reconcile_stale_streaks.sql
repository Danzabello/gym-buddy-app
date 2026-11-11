CREATE OR REPLACE FUNCTION public.reconcile_stale_streaks()
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_streak record;
  v_utc_today date := (now() AT TIME ZONE 'utc')::date;
  v_member_ids uuid[];
  v_member uuid;
  v_m_yesterday date;
  v_broken boolean;
  v_missers uuid[];
  v_reset_count integer := 0;
BEGIN
  FOR v_streak IN
    SELECT id, team_id, current_streak, last_workout_date
    FROM team_streaks
    WHERE is_active = true AND current_streak > 0
      AND (last_workout_date IS NULL OR last_workout_date < v_utc_today)
  LOOP
    SELECT array_agg(user_id) INTO v_member_ids
    FROM team_members
    WHERE team_id = v_streak.team_id
      AND user_id <> '00000000-0000-0000-0000-000000000001';

    IF v_streak.last_workout_date IS NULL THEN
      -- Active streak count with no completed day on record: inconsistent,
      -- reset (unchanged from the current function).
      UPDATE team_streaks SET current_streak = 0, updated_at = now() WHERE id = v_streak.id;
      v_reset_count := v_reset_count + 1;
      CONTINUE;
    END IF;

    IF v_member_ids IS NULL THEN
      CONTINUE; -- memberless: nothing to judge (matches current behavior)
    END IF;

    v_broken := false;
    v_missers := '{}';

    FOREACH v_member IN ARRAY v_member_ids LOOP
      -- This member's own fully-elapsed yesterday.
      v_m_yesterday := (now() AT TIME ZONE public.safe_user_tz(v_member))::date - 1;

      IF v_streak.last_workout_date + 1 <= v_m_yesterday THEN
        IF EXISTS (
          SELECT 1
          FROM generate_series(
                 (v_streak.last_workout_date + 1)::timestamp,
                 v_m_yesterday::timestamp,
                 interval '1 day') AS g(day)
          WHERE NOT EXISTS (
              SELECT 1 FROM daily_team_checkins dtc
              WHERE dtc.team_streak_id = v_streak.id
                AND dtc.user_id = v_member
                AND dtc.check_in_date = g.day::date
            )
            AND NOT EXISTS (
              SELECT 1 FROM break_day_usage bdu
              WHERE bdu.user_id = v_member
                AND bdu.break_date = g.day::date
                AND bdu.cancelled_at IS NULL
            )
            -- Grace (Rule 1): a workout that started on this member's
            -- yesterday and is still running will be credited to that day.
            AND NOT (g.day::date = v_m_yesterday AND (
              EXISTS (
                SELECT 1 FROM active_checkin_sessions s
                WHERE s.user_id = v_member
                  AND s.started_at >= now() - interval '220 minutes'
                  AND (s.started_at AT TIME ZONE public.safe_user_tz(v_member))::date = g.day::date
              )
              OR EXISTS (
                SELECT 1 FROM workouts w
                WHERE w.status = 'in_progress'
                  AND w.workout_started_at >= now() - interval '220 minutes'
                  AND (w.workout_started_at AT TIME ZONE public.safe_user_tz(v_member))::date = g.day::date
                  AND ((w.user_id = v_member AND w.creator_ready AND NOT w.creator_cancelled)
                    OR (w.buddy_id = v_member AND w.buddy_ready AND NOT w.buddy_cancelled))
              )
            ))
        ) THEN
          v_broken := true;  -- STRICT: one member's definitive miss is enough
          v_missers := v_missers || v_member;  -- keep going: record every misser
        END IF;
      END IF;
    END LOOP;

    IF v_broken THEN
      UPDATE team_streaks SET current_streak = 0, updated_at = now() WHERE id = v_streak.id;
      v_reset_count := v_reset_count + 1;
      PERFORM public._record_streak_loss(v_streak.team_id, v_streak.current_streak, v_missers);
    END IF;
  END LOOP;

  RETURN jsonb_build_object('reset_count', v_reset_count);
END;
$function$
