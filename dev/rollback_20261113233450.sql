-- Rollback for 20261113233450_drop_dead_checkin_objects.sql. Bodies are pg_get_functiondef from live, 2026-11-12.
-- ACLs before the drop: all three functions {postgres, service_role} only.

CREATE OR REPLACE FUNCTION public._pin_client_checkin_date()
 RETURNS trigger
 LANGUAGE plpgsql
 SET search_path TO 'public'
AS $function$
BEGIN
  IF current_user IN ('authenticated', 'anon') THEN
    NEW.check_in_date := (now() AT TIME ZONE public.safe_user_tz(NEW.user_id))::date;
    NEW.check_in_time := now();
  END IF;
  RETURN NEW;
END;
$function$;
REVOKE EXECUTE ON FUNCTION public._pin_client_checkin_date() FROM PUBLIC, anon, authenticated;

CREATE TRIGGER pin_client_checkin_date BEFORE INSERT ON public.daily_team_checkins
  FOR EACH ROW EXECUTE FUNCTION public._pin_client_checkin_date();

CREATE POLICY "Users can create check-ins for their teams" ON public.daily_team_checkins
  FOR INSERT TO public
  WITH CHECK ((user_id = auth.uid()) AND (team_streak_id IN ( SELECT ts.id
     FROM (team_streaks ts
       JOIN team_members tm ON ((tm.team_id = ts.team_id)))
    WHERE (tm.user_id = auth.uid()))));

CREATE OR REPLACE FUNCTION public.award_checkin_rewards(p_streak_id uuid, p_check_in_date date)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_caller uuid := auth.uid();
  v_team_id uuid;
  v_today date;
BEGIN
  IF v_caller IS NULL THEN
    RAISE EXCEPTION 'unauthenticated';
  END IF;

  v_today := (now() AT TIME ZONE public.safe_user_tz(v_caller))::date;
  IF p_check_in_date NOT BETWEEN v_today - 1 AND v_today THEN
    RAISE EXCEPTION 'check_in_date_out_of_window';
  END IF;

  SELECT team_id INTO v_team_id FROM team_streaks WHERE id = p_streak_id;
  IF v_team_id IS NULL THEN
    RAISE EXCEPTION 'invalid_streak';
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM team_members WHERE team_id = v_team_id AND user_id = v_caller
  ) THEN
    RAISE EXCEPTION 'not_a_team_member';
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM daily_team_checkins
    WHERE team_streak_id = p_streak_id AND user_id = v_caller AND check_in_date = p_check_in_date
  ) THEN
    RAISE EXCEPTION 'no_checkin_found_for_caller';
  END IF;

  RETURN public._apply_checkin_rewards(v_caller, p_streak_id, p_check_in_date);
END;
$function$;
REVOKE EXECUTE ON FUNCTION public.award_checkin_rewards(uuid, date) FROM PUBLIC, anon, authenticated;
GRANT  EXECUTE ON FUNCTION public.award_checkin_rewards(uuid, date) TO service_role;

CREATE OR REPLACE FUNCTION public.check_in_coach_max_with_buddy(p_user_id uuid)
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
$function$;
REVOKE EXECUTE ON FUNCTION public.check_in_coach_max_with_buddy(uuid) FROM PUBLIC, anon, authenticated;
GRANT  EXECUTE ON FUNCTION public.check_in_coach_max_with_buddy(uuid) TO service_role;
