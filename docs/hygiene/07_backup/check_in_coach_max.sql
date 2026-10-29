CREATE OR REPLACE FUNCTION public.check_in_coach_max(p_user_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
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
$function$
