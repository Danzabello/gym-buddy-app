-- STEP 3, migration #1 of the per-user timezone rework (Option B).
--
-- checkin_team_for_user is the buddy-proxy path: one workout participant checks
-- their partner in across the partner's active team streaks. The check-in must
-- be dated in the TARGET's own local timezone (their "today"), not UTC, so it
-- lands on the same date label the target's own client would produce.
--
-- ONLY CHANGE vs the live function: v_today now resolves via
-- safe_user_tz(p_target_user_id). Participant validation, the per-streak dedup
-- guard, and the _apply_checkin_rewards call are unchanged. Coach Max never
-- appears here (the target is always a human workout participant).

CREATE OR REPLACE FUNCTION public.checkin_team_for_user(p_target_user_id uuid, p_workout_id uuid)
 RETURNS integer
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_caller uuid := auth.uid();
  v_creator uuid;
  v_buddy uuid;
  v_team record;
  v_checked_in_count integer := 0;
  -- Per-user tz: the target's own local "today" (was (now() AT TIME ZONE 'utc')::date).
  v_today date := (now() AT TIME ZONE public.safe_user_tz(p_target_user_id))::date;
BEGIN
  IF v_caller IS NULL THEN
    RAISE EXCEPTION 'unauthenticated';
  END IF;

  SELECT user_id, buddy_id INTO v_creator, v_buddy
  FROM workouts WHERE id = p_workout_id;

  IF v_creator IS NULL THEN
    RAISE EXCEPTION 'workout_not_found';
  END IF;

  IF v_caller IS DISTINCT FROM v_creator AND v_caller IS DISTINCT FROM v_buddy THEN
    RAISE EXCEPTION 'caller_not_a_participant';
  END IF;

  IF p_target_user_id IS DISTINCT FROM v_creator AND p_target_user_id IS DISTINCT FROM v_buddy THEN
    RAISE EXCEPTION 'target_not_a_participant';
  END IF;

  FOR v_team IN
    SELECT ts.id AS streak_id
    FROM team_members tm
    JOIN team_streaks ts ON ts.team_id = tm.team_id AND ts.is_active = true
    WHERE tm.user_id = p_target_user_id
  LOOP
    IF NOT EXISTS (
      SELECT 1 FROM daily_team_checkins
      WHERE team_streak_id = v_team.streak_id
        AND user_id = p_target_user_id
        AND check_in_date = v_today
    ) THEN
      INSERT INTO daily_team_checkins (team_streak_id, user_id, check_in_date, check_in_time)
      VALUES (v_team.streak_id, p_target_user_id, v_today, now());

      v_checked_in_count := v_checked_in_count + 1;

      PERFORM public._apply_checkin_rewards(p_target_user_id, v_team.streak_id, v_today);
    END IF;
  END LOOP;

  RETURN v_checked_in_count;
END;
$function$;
