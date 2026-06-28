-- Single authoritative streak-increment function, faithfully ported
-- from TeamStreakService._incrementStreak (the most correct of the
-- four existing implementations: break-day aware, UTC dates). All
-- four writers (Dart main path, coach-max-cron, CoachMaxService,
-- TeamSyncService) will be redirected to call this instead of their
-- own divergent math.
CREATE OR REPLACE FUNCTION public.recompute_team_streak(
  p_streak_id uuid,
  p_check_in_date date
) RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_team_id uuid;
  v_current_streak integer;
  v_longest_streak integer;
  v_total_workouts integer;
  v_best_streak integer;
  v_last_workout_date date;
  v_member_ids uuid[];
  v_new_streak integer;
  v_new_longest integer;
  v_coach_max_id uuid := '00000000-0000-0000-0000-000000000001';
  v_days_diff integer;
  v_someone_worked_out boolean;
  v_gap_is_valid boolean;
  v_check_date date;
  v_everyone_on_break boolean;
  i integer;
BEGIN
  SELECT team_id, current_streak, longest_streak, total_workouts, best_streak, last_workout_date
  INTO v_team_id, v_current_streak, v_longest_streak, v_total_workouts, v_best_streak, v_last_workout_date
  FROM team_streaks WHERE id = p_streak_id;

  IF v_team_id IS NULL THEN
    RAISE EXCEPTION 'invalid_streak';
  END IF;

  v_current_streak := COALESCE(v_current_streak, 0);
  v_longest_streak := COALESCE(v_longest_streak, 0);
  v_total_workouts := COALESCE(v_total_workouts, 0);
  v_best_streak := COALESCE(v_best_streak, 0);

  SELECT array_agg(user_id) INTO v_member_ids
  FROM team_members WHERE team_id = v_team_id AND user_id <> v_coach_max_id;

  v_new_streak := v_current_streak;
  v_new_longest := v_longest_streak;

  IF v_last_workout_date IS NULL OR v_last_workout_date = p_check_in_date THEN
    IF v_last_workout_date = p_check_in_date AND v_current_streak > 0 THEN
      RETURN jsonb_build_object('updated', false, 'reason', 'already_today', 'current_streak', v_current_streak);
    END IF;
    v_new_streak := 1;
    v_new_longest := CASE WHEN v_current_streak > 0 THEN v_longest_streak ELSE 1 END;
  ELSE
    v_days_diff := p_check_in_date - v_last_workout_date;

    IF v_days_diff = 1 THEN
      SELECT EXISTS (
        SELECT 1 FROM daily_team_checkins dtc
        WHERE dtc.team_streak_id = p_streak_id
          AND dtc.check_in_date = p_check_in_date
          AND dtc.user_id = ANY(v_member_ids)
          AND NOT EXISTS (
            SELECT 1 FROM break_day_usage bdu
            WHERE bdu.user_id = dtc.user_id
              AND bdu.break_date = p_check_in_date
              AND bdu.cancelled_at IS NULL
          )
      ) INTO v_someone_worked_out;

      IF v_someone_worked_out THEN
        v_new_streak := v_current_streak + 1;
        IF v_new_streak > v_longest_streak THEN v_new_longest := v_new_streak; END IF;
      ELSE
        v_new_streak := v_current_streak;
      END IF;

    ELSIF v_days_diff > 1 THEN
      IF v_current_streak = 0 THEN
        v_new_streak := 1;
        v_new_longest := CASE WHEN v_longest_streak > 0 THEN v_longest_streak ELSE 1 END;
      ELSE
        v_gap_is_valid := true;
        FOR i IN 1..(v_days_diff - 1) LOOP
          v_check_date := v_last_workout_date + i;
          SELECT NOT EXISTS (
            SELECT 1 FROM unnest(v_member_ids) AS uid
            WHERE NOT EXISTS (
              SELECT 1 FROM break_day_usage bdu
              WHERE bdu.user_id = uid AND bdu.break_date = v_check_date AND bdu.cancelled_at IS NULL
            )
          ) INTO v_everyone_on_break;

          IF NOT v_everyone_on_break THEN
            v_gap_is_valid := false;
            EXIT;
          END IF;
        END LOOP;

        IF v_gap_is_valid THEN
          v_new_streak := v_current_streak + 1;
          IF v_new_streak > v_longest_streak THEN v_new_longest := v_new_streak; END IF;
        ELSE
          v_new_streak := 1;
        END IF;
      END IF;
    ELSE
      RETURN jsonb_build_object('updated', false, 'reason', 'same_day_or_past', 'current_streak', v_current_streak);
    END IF;
  END IF;

  UPDATE team_streaks SET
    current_streak = v_new_streak,
    longest_streak = v_new_longest,
    total_workouts = v_total_workouts + 1,
    best_streak = GREATEST(v_best_streak, v_new_streak),
    last_workout_date = p_check_in_date,
    last_interaction_at = now(),
    updated_at = now()
  WHERE id = p_streak_id;

  RETURN jsonb_build_object(
    'updated', true,
    'old_streak', v_current_streak,
    'new_streak', v_new_streak,
    'longest_streak', v_new_longest
  );
END;
$$;

REVOKE ALL ON FUNCTION public.recompute_team_streak(uuid, date) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.recompute_team_streak(uuid, date) TO authenticated, service_role;


-- The missing piece: nothing today ever proactively detects a streak
-- that's gone stale (no qualifying check-in, gap not covered by break
-- days). This scans all active streaks daily and zeroes out any that
-- should have broken but never got told.
CREATE OR REPLACE FUNCTION public.reconcile_stale_streaks() RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_streak record;
  v_yesterday date := (now() AT TIME ZONE 'utc')::date - 1;
  v_member_ids uuid[];
  v_gap_is_valid boolean;
  v_everyone_on_break boolean;
  v_days_diff integer;
  i integer;
  v_check_date date;
  v_reset_count integer := 0;
BEGIN
  FOR v_streak IN
    SELECT id, team_id, current_streak, last_workout_date
    FROM team_streaks
    WHERE is_active = true AND current_streak > 0
      AND (last_workout_date IS NULL OR last_workout_date < v_yesterday)
  LOOP
    SELECT array_agg(user_id) INTO v_member_ids
    FROM team_members WHERE team_id = v_streak.team_id AND user_id <> '00000000-0000-0000-0000-000000000001';

    IF v_streak.last_workout_date IS NULL THEN
      UPDATE team_streaks SET current_streak = 0, updated_at = now() WHERE id = v_streak.id;
      v_reset_count := v_reset_count + 1;
      CONTINUE;
    END IF;

    v_days_diff := v_yesterday - v_streak.last_workout_date;
    v_gap_is_valid := true;

    FOR i IN 1..v_days_diff LOOP
      v_check_date := v_streak.last_workout_date + i;
      SELECT NOT EXISTS (
        SELECT 1 FROM unnest(v_member_ids) AS uid
        WHERE NOT EXISTS (
          SELECT 1 FROM break_day_usage bdu
          WHERE bdu.user_id = uid AND bdu.break_date = v_check_date AND bdu.cancelled_at IS NULL
        )
      ) INTO v_everyone_on_break;

      IF NOT v_everyone_on_break THEN
        v_gap_is_valid := false;
        EXIT;
      END IF;
    END LOOP;

    IF NOT v_gap_is_valid THEN
      UPDATE team_streaks SET current_streak = 0, updated_at = now() WHERE id = v_streak.id;
      v_reset_count := v_reset_count + 1;
    END IF;
  END LOOP;

  RETURN jsonb_build_object('reset_count', v_reset_count);
END;
$$;

REVOKE ALL ON FUNCTION public.reconcile_stale_streaks() FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.reconcile_stale_streaks() TO service_role;

-- Run daily at 00:10 UTC, well clear of the existing hourly Coach Max cron.
SELECT cron.schedule(
  'reconcile-stale-streaks-daily',
  '10 0 * * *',
  $$SELECT public.reconcile_stale_streaks();$$
);
