-- LIVE-22 (b): award_checkin_rewards paid for any p_check_in_date that had a
-- check-in row, and _apply_checkin_rewards' daily cap is keyed on that same
-- date, so backdated claims were never capped. Only the caller's local today
-- and yesterday (a check-in that straddles local midnight) are now accepted.
-- _apply_checkin_rewards is untouched (also used by checkin_team_for_user).

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

REVOKE EXECUTE ON FUNCTION public.award_checkin_rewards(uuid, date) FROM PUBLIC, anon;
GRANT  EXECUTE ON FUNCTION public.award_checkin_rewards(uuid, date) TO authenticated;

