-- ROLLBACK for supabase/migrations/20261002231500_recompute_team_streak_member_check.sql
-- NOT a migration: lives in docs/ so `supabase db push` never runs it.
-- Puts the full body back into recompute_team_streak (prosrc md5
-- 4f95daa2e349d7af8c062b569338f0a9), points _finish_coach_max_checkin and
-- _server_checkin back at it, drops _recompute_team_streak. Re-opens SEC-C.
-- Run as postgres.
BEGIN;
CREATE OR REPLACE FUNCTION public.recompute_team_streak(p_streak_id uuid, p_check_in_date date)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
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
  v_day_complete boolean;
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

  IF v_member_ids IS NULL THEN
    RETURN jsonb_build_object('updated', false, 'reason', 'no_members', 'current_streak', v_current_streak);
  END IF;

  -- ── AND-gate ──────────────────────────────────────────────────────────
  -- (1) every member has a check-in for D or an uncancelled break on D
  SELECT NOT EXISTS (
    SELECT 1 FROM unnest(v_member_ids) AS uid
    WHERE NOT EXISTS (
        SELECT 1 FROM daily_team_checkins dtc
        WHERE dtc.team_streak_id = p_streak_id
          AND dtc.user_id = uid
          AND dtc.check_in_date = p_check_in_date
      )
      AND NOT EXISTS (
        SELECT 1 FROM break_day_usage bdu
        WHERE bdu.user_id = uid
          AND bdu.break_date = p_check_in_date
          AND bdu.cancelled_at IS NULL
      )
  ) INTO v_day_complete;

  -- (2) at least one genuine workout: a member checked in while NOT on break
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

  IF NOT v_day_complete OR NOT v_someone_worked_out THEN
    -- Row untouched: last_workout_date must not advance on an incomplete day.
    RETURN jsonb_build_object('updated', false, 'reason', 'day_incomplete', 'current_streak', v_current_streak);
  END IF;

  -- ── Branch skeleton (label D is fully complete from here on) ──────────
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
      v_new_streak := v_current_streak + 1;
      IF v_new_streak > v_longest_streak THEN v_new_longest := v_new_streak; END IF;

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
          -- Approved: gapped-but-mutually-complete day starts a fresh streak.
          v_new_streak := 1;
          PERFORM public._record_streak_loss(v_team_id, v_current_streak, ARRAY(
            SELECT uid FROM unnest(v_member_ids) AS uid
            WHERE EXISTS (
              SELECT 1 FROM generate_series((v_last_workout_date + 1)::timestamp,
                                            (p_check_in_date - 1)::timestamp, interval '1 day') AS g(day)
              WHERE NOT EXISTS (SELECT 1 FROM daily_team_checkins dtc
                                WHERE dtc.team_streak_id = p_streak_id AND dtc.user_id = uid
                                  AND dtc.check_in_date = g.day::date)
                AND NOT EXISTS (SELECT 1 FROM break_day_usage bdu
                                WHERE bdu.user_id = uid AND bdu.break_date = g.day::date
                                  AND bdu.cancelled_at IS NULL))));
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
    'longest_streak', v_new_longest,
    'old_best_streak', v_best_streak,
    'new_best_streak', GREATEST(v_best_streak, v_new_streak)
  );
END;
$function$;

CREATE OR REPLACE FUNCTION public._finish_coach_max_checkin(p_streak_id uuid, p_user_id uuid, p_today date)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_coach_max_id uuid := '00000000-0000-0000-0000-000000000001';
  v_recompute jsonb;
BEGIN
  INSERT INTO daily_team_checkins (team_streak_id, user_id, check_in_date, check_in_time)
  VALUES (p_streak_id, v_coach_max_id, p_today, now());

  -- Opportunistic: close out today's schedule row if one exists, but don't
  -- require it -- the instant-mirror path (check_in_coach_max_with_buddy)
  -- can fire before Coach Max's own randomized scheduled_time.
  UPDATE coach_max_schedule
  SET has_checked_in = true, checked_in_at = now()
  WHERE user_id = p_user_id AND scheduled_date = p_today AND has_checked_in IS NOT TRUE;

  SELECT recompute_team_streak(p_streak_id, p_today) INTO v_recompute;

  RETURN jsonb_build_object('checked_in', true, 'streak_result', v_recompute);
END;
$function$;

CREATE OR REPLACE FUNCTION public._server_checkin(p_user_id uuid, p_day date)
RETURNS void
LANGUAGE plpgsql
SET search_path = public
AS $$
DECLARE
  t record;
  v_coach_max_id constant uuid := '00000000-0000-0000-0000-000000000001';
BEGIN
  -- Same as BreakDayService.cancelBreakDay: working out cancels today's break.
  UPDATE break_day_usage SET cancelled_at = now()
  WHERE user_id = p_user_id AND break_date = p_day AND cancelled_at IS NULL;

  FOR t IN
    SELECT ts.id, bt.is_coach_max_team
    FROM team_streaks ts
    JOIN team_members tm ON tm.team_id = ts.team_id
    JOIN buddy_teams bt ON bt.id = ts.team_id
    WHERE tm.user_id = p_user_id AND ts.is_active = true
  LOOP
    INSERT INTO daily_team_checkins (team_streak_id, user_id, check_in_date, check_in_time)
    VALUES (t.id, p_user_id, p_day, now())
    ON CONFLICT (team_streak_id, user_id, check_in_date) DO NOTHING;
    CONTINUE WHEN NOT FOUND;

    IF (public.recompute_team_streak(t.id, p_day)->>'updated')::boolean THEN
      PERFORM public._apply_checkin_rewards(p_user_id, t.id, p_day);
    END IF;

    IF t.is_coach_max_team AND NOT EXISTS (
      SELECT 1 FROM daily_team_checkins
      WHERE team_streak_id = t.id AND user_id = v_coach_max_id AND check_in_date = p_day
    ) THEN
      PERFORM public._finish_coach_max_checkin(t.id, p_user_id, p_day);
    END IF;
  END LOOP;
END;
$$;

REVOKE EXECUTE ON FUNCTION public.recompute_team_streak(uuid, date) FROM PUBLIC, anon;
GRANT  EXECUTE ON FUNCTION public.recompute_team_streak(uuid, date) TO authenticated;
REVOKE EXECUTE ON FUNCTION public._finish_coach_max_checkin(uuid, uuid, date) FROM PUBLIC, anon, authenticated;
REVOKE EXECUTE ON FUNCTION public._server_checkin(uuid, date) FROM PUBLIC, anon, authenticated;
DROP FUNCTION public._recompute_team_streak(uuid, date);
COMMIT;
