-- STEP 3, migration #3 of the per-user timezone rework (Option B).
--
-- recompute_team_streak becomes the single authority for streak-day
-- completion. Previously it used OR-semantics ("someone worked out") and
-- trusted the CLIENT's participating>=total gate — and every call that
-- reached the end unconditionally advanced last_workout_date and bumped
-- total_workouts. Under per-user date labels that unconditional write lets an
-- ahead-of-the-boundary member's lone call consume the day label before the
-- slower member completes it.
--
-- New shape: GATE FIRST, BRANCH SECOND, WRITE ONLY ON COMPLETION.
--   * AND-gate: label D is complete when EVERY human member (Coach Max is
--     excluded from v_member_ids, unchanged) has a check-in row dated D or an
--     uncancelled break for D, AND at least one member genuinely worked out
--     (check-in while not on break — preserves "an all-break day neither
--     increments nor breaks; it is bridged by the gap loop").
--   * Incomplete D -> no-op 'day_incomplete'; the row is NOT touched
--     (last_workout_date does not advance).
--   * Completed D: last==D -> no-op 'already_today' (idempotent);
--     D==last+1 -> increment; D>last+1 -> gap-bridge via all-on-break days
--     (loop preserved verbatim) else RESET TO 1; D<last -> no-op
--     'same_day_or_past' (stale/offset label guard).
--   * recompute NEVER resets a streak to 0 for absence — definitive lapse
--     judgment belongs to reconcile_stale_streaks (migration #5, STRICT).
--
-- The client's participating>=total gate becomes redundant but harmless and
-- is deliberately left in place (flagged as later cleanup).

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
