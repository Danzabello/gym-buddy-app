-- Extracts check_in_coach_max's shared tail (insert the Coach Max
-- daily_team_checkins row, opportunistically close out today's
-- coach_max_schedule row, recompute the streak) into a private helper so
-- the upcoming check_in_coach_max_with_buddy (instant-mirror path, no
-- scheduled_time gate) can share it instead of duplicating it. Pure
-- refactor for check_in_coach_max itself -- its own gating logic
-- (ownership check, schedule lookup, not-due-yet check) is unchanged, only
-- the final INSERT/UPDATE/recompute block now delegates to the helper.
--
-- The has_checked_in IS NOT TRUE guard on the schedule UPDATE (absent from
-- check_in_coach_max's original inline version) is a no-op for
-- check_in_coach_max's own callers: by the time it reaches this tail it has
-- already confirmed via the EXISTS check that no daily_team_checkins row
-- exists yet today, so has_checked_in is never already true here. It exists
-- for check_in_coach_max_with_buddy, which can legitimately race the
-- schedule cron.
CREATE OR REPLACE FUNCTION public._finish_coach_max_checkin(
  p_streak_id uuid, p_user_id uuid, p_today date
) RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
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
$$;

-- Matches _apply_checkin_rewards' verified live pattern exactly
-- (proacl = {postgres=X/postgres,service_role=X/postgres}): PUBLIC's
-- default EXECUTE revoked, service_role explicitly re-granted, no grant to
-- authenticated -- this is an internal helper only its two SECURITY
-- DEFINER callers (owned by postgres) should ever invoke.
REVOKE ALL ON FUNCTION public._finish_coach_max_checkin(uuid, uuid, date) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public._finish_coach_max_checkin(uuid, uuid, date) TO service_role;

CREATE OR REPLACE FUNCTION public.check_in_coach_max(p_user_id uuid)
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
  v_scheduled_time time;
  v_local_now time;
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

  SELECT scheduled_time INTO v_scheduled_time
  FROM coach_max_schedule
  WHERE user_id = p_user_id AND scheduled_date = v_today;

  IF NOT FOUND THEN
    RETURN jsonb_build_object('checked_in', false, 'reason', 'no_schedule_today');
  END IF;

  v_local_now := (now() AT TIME ZONE safe_user_tz(p_user_id))::time;

  IF v_scheduled_time > v_local_now THEN
    RETURN jsonb_build_object('checked_in', false, 'reason', 'not_due_yet',
                               'scheduled_time', v_scheduled_time);
  END IF;

  RETURN public._finish_coach_max_checkin(v_streak_id, p_user_id, v_today);
END;
$$;

REVOKE EXECUTE ON FUNCTION public.check_in_coach_max(uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.check_in_coach_max(uuid) TO authenticated;
