-- New entry point for the intentional "instant mirror" product behavior:
-- when a user checks in to their real Coach Max team via checkInAllTeams,
-- Coach Max should check in alongside them immediately, without waiting for
-- its own randomized daily scheduled_time. This used to be a direct,
-- unvalidated client insert into daily_team_checkins
-- (team_streak_service.dart's _checkInCoachMax) with no gate at all beyond
-- "has Coach Max already checked in today" -- worse than the schedule-gated
-- hole check_in_coach_max already closed, since it never looked at
-- coach_max_schedule at all.
--
-- This has no scheduled_time check by design (that's what makes it
-- "instant"). The gate that makes it safe instead: Coach Max only ever
-- mirrors a check-in that has genuinely already landed, for this exact
-- team, today -- so it cannot be used to unlock has_checked_in / the
-- streak / special_path_robot ahead of the user's own real check-in.
CREATE OR REPLACE FUNCTION public.check_in_coach_max_with_buddy(p_user_id uuid)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_caller uuid := auth.uid();
  v_coach_max_id uuid := '00000000-0000-0000-0000-000000000001';
  v_streak_id uuid;
  v_today date;
BEGIN
  IF v_caller IS NULL OR v_caller <> p_user_id THEN
    RAISE EXCEPTION 'forbidden';
  END IF;

  SELECT ts.id INTO v_streak_id
  FROM team_streaks ts
  JOIN team_members tm ON tm.team_id = ts.team_id
  JOIN buddy_teams bt ON bt.id = ts.team_id
  WHERE tm.user_id = p_user_id AND bt.is_coach_max_team = true AND ts.is_active = true
  LIMIT 1;

  IF v_streak_id IS NULL THEN
    RETURN jsonb_build_object('checked_in', false, 'reason', 'no_coach_max_team');
  END IF;

  v_today := (now() AT TIME ZONE safe_user_tz(p_user_id))::date;

  IF EXISTS (
    SELECT 1 FROM daily_team_checkins
    WHERE team_streak_id = v_streak_id AND user_id = v_coach_max_id AND check_in_date = v_today
  ) THEN
    RETURN jsonb_build_object('checked_in', true, 'already_done', true);
  END IF;

  -- The real gate: Coach Max only mirrors a check-in that genuinely already
  -- happened, for this exact team, today. This is what makes the instant
  -- path safe with no schedule check at all.
  IF NOT EXISTS (
    SELECT 1 FROM daily_team_checkins
    WHERE team_streak_id = v_streak_id AND user_id = p_user_id AND check_in_date = v_today
  ) THEN
    RETURN jsonb_build_object('checked_in', false, 'reason', 'user_not_checked_in_yet');
  END IF;

  RETURN public._finish_coach_max_checkin(v_streak_id, p_user_id, v_today);
END;
$$;

REVOKE EXECUTE ON FUNCTION public.check_in_coach_max_with_buddy(uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.check_in_coach_max_with_buddy(uuid) TO authenticated;
