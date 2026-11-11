-- ROLLBACK for supabase/migrations/20261002214500_streak_events.sql
-- NOT a migration: lives in docs/ so `supabase db push` never runs it.
-- Restores reconcile_stale_streaks (M3 body, prosrc md5
-- 15e9471d6e4536233d0999871c9fc1e1) and recompute_team_streak (prosrc md5
-- 133189417637180d81b0cde19ef338f2), then drops streak_events and its
-- helpers. Roll back get_pending_notice (M5) first. Event rows are lost.
-- Run as postgres.
BEGIN;
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
          v_broken := true;
          EXIT; -- STRICT: one member's definitive miss is enough
        END IF;
      END IF;
    END LOOP;

    IF v_broken THEN
      UPDATE team_streaks SET current_streak = 0, updated_at = now() WHERE id = v_streak.id;
      v_reset_count := v_reset_count + 1;
    END IF;
  END LOOP;

  RETURN jsonb_build_object('reset_count', v_reset_count);
END;
$function$;

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

REVOKE EXECUTE ON FUNCTION public.reconcile_stale_streaks() FROM PUBLIC, anon, authenticated;
REVOKE EXECUTE ON FUNCTION public.recompute_team_streak(uuid, date) FROM PUBLIC, anon;
GRANT  EXECUTE ON FUNCTION public.recompute_team_streak(uuid, date) TO authenticated;

DROP FUNCTION public._record_streak_loss(uuid, integer, uuid[]);
DROP TABLE public.streak_events;
DROP FUNCTION public._guard_streak_event_seen();
COMMIT;
