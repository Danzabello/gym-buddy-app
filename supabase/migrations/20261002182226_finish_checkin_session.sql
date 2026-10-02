-- Streak events M2: Finish goes through the server so the check-in can carry
-- the local day the workout STARTED (Rule 1). For auth.uid() only:
--   start = the caller's open session (anchored to its linked workout's
--           start when the caller is in it), else p_workout_id's start when
--           the caller is in that workout (a buddy Finish may have deleted
--           the session first), else none.
--   credit day = local date of start if start is at most 3h30 old; with no
--           start, the day of a check-in made in the last 3h30 (repeat
--           call); else local today. 3h30 back never reaches before yesterday, so the
--           [today-1, today] reward window holds.
-- Check-in, streak, rewards and the Coach Max mirror all go through
-- _server_checkin (no reward logic here). The per-team result is read back
-- from before/after snapshots so the app can keep its achievement checks.
-- Idempotent: UNIQUE per team/user/day + the reward ledger dedupe.
CREATE OR REPLACE FUNCTION public.finish_checkin_session(p_workout_id uuid DEFAULT NULL)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_uid uuid := auth.uid();
  v_tz text;
  v_start timestamptz;
  v_day date;
  v_level_before integer;
  v_level_after integer;
  v_on_break boolean;
  v_before jsonb;
  v_teams jsonb;
  v_checked_in integer;
BEGIN
  IF v_uid IS NULL THEN
    RAISE EXCEPTION 'unauthenticated';
  END IF;
  v_tz := public.safe_user_tz(v_uid);

  SELECT COALESCE(w.workout_started_at, s.started_at) INTO v_start
  FROM active_checkin_sessions s
  LEFT JOIN workouts w ON w.id = s.workout_id AND v_uid IN (w.user_id, w.buddy_id)
  WHERE s.user_id = v_uid
  FOR UPDATE OF s;

  IF v_start IS NULL AND p_workout_id IS NOT NULL THEN
    SELECT workout_started_at INTO v_start
    FROM workouts WHERE id = p_workout_id AND v_uid IN (user_id, buddy_id);
  END IF;

  -- No start known (repeat call, session already cleared): stay on the day a
  -- Finish just credited, so a second call is a no-op instead of a new day.
  IF v_start IS NULL THEN
    SELECT check_in_date INTO v_day FROM daily_team_checkins
    WHERE user_id = v_uid AND check_in_time >= now() - interval '210 minutes'
    ORDER BY check_in_time DESC LIMIT 1;
  END IF;

  v_day := COALESCE(v_day, CASE WHEN v_start >= now() - interval '210 minutes'
                                THEN (v_start AT TIME ZONE v_tz)::date
                                ELSE (now() AT TIME ZONE v_tz)::date END);

  SELECT level INTO v_level_before FROM user_profiles WHERE id = v_uid;
  v_on_break := EXISTS (SELECT 1 FROM break_day_usage
                        WHERE user_id = v_uid AND break_date = v_day AND cancelled_at IS NULL);
  SELECT jsonb_object_agg(ts.id, jsonb_build_object(
           'total', ts.total_workouts, 'best', ts.best_streak,
           'in', EXISTS (SELECT 1 FROM daily_team_checkins d
                         WHERE d.team_streak_id = ts.id AND d.user_id = v_uid AND d.check_in_date = v_day)))
  INTO v_before
  FROM team_streaks ts JOIN team_members tm ON tm.team_id = ts.team_id
  WHERE tm.user_id = v_uid AND ts.is_active = true;

  PERFORM public._server_checkin(v_uid, v_day);
  DELETE FROM active_checkin_sessions WHERE user_id = v_uid;

  SELECT level INTO v_level_after FROM user_profiles WHERE id = v_uid;
  SELECT COALESCE(jsonb_agg(jsonb_build_object(
           'streak_id', ts.id, 'team_id', ts.team_id, 'is_coach_max_team', bt.is_coach_max_team,
           'updated', ts.total_workouts IS DISTINCT FROM (v_before->ts.id::text->>'total')::integer,
           'new_streak', ts.current_streak,
           'old_best_streak', COALESCE((v_before->ts.id::text->>'best')::integer, 0),
           'new_best_streak', ts.best_streak)), '[]'::jsonb),
         count(*) FILTER (WHERE NOT COALESCE((v_before->ts.id::text->>'in')::boolean, false)
                            AND EXISTS (SELECT 1 FROM daily_team_checkins d
                                        WHERE d.team_streak_id = ts.id AND d.user_id = v_uid AND d.check_in_date = v_day))
  INTO v_teams, v_checked_in
  FROM team_streaks ts
  JOIN team_members tm ON tm.team_id = ts.team_id
  JOIN buddy_teams bt ON bt.id = ts.team_id
  WHERE tm.user_id = v_uid AND ts.is_active = true;

  RETURN jsonb_build_object(
    'credit_date', v_day,
    'checked_in', v_checked_in,
    'break_cancelled', v_on_break AND NOT EXISTS (SELECT 1 FROM break_day_usage
                         WHERE user_id = v_uid AND break_date = v_day AND cancelled_at IS NULL),
    'did_level_up', COALESCE(v_level_after, 1) > COALESCE(v_level_before, 1),
    'new_level', COALESCE(v_level_after, 1),
    'teams', v_teams);
END;
$$;

REVOKE EXECUTE ON FUNCTION public.finish_checkin_session(uuid) FROM PUBLIC, anon;
GRANT  EXECUTE ON FUNCTION public.finish_checkin_session(uuid) TO authenticated;
