-- LIVE-22 (a): clients could insert daily_team_checkins rows with any
-- check_in_date / check_in_time, and move rows to any date or streak via UPDATE,
-- then claim award_checkin_rewards for each fabricated day.
--
-- Client inserts (current_user authenticated/anon) get their date pinned to the
-- user's own local today and their time to now(). SECURITY DEFINER paths run as
-- their owner and the Coach Max cron runs as service_role, so they keep the
-- dates they pass (Coach Max rows are dated in the human member's local day).
-- The client never updates this table, so UPDATE is removed outright.

CREATE OR REPLACE FUNCTION public._pin_client_checkin_date()
RETURNS trigger
LANGUAGE plpgsql
SECURITY INVOKER
SET search_path = public
AS $$
BEGIN
  IF current_user IN ('authenticated', 'anon') THEN
    NEW.check_in_date := (now() AT TIME ZONE public.safe_user_tz(NEW.user_id))::date;
    NEW.check_in_time := now();
  END IF;
  RETURN NEW;
END;
$$;

REVOKE EXECUTE ON FUNCTION public._pin_client_checkin_date() FROM PUBLIC, anon, authenticated;

CREATE TRIGGER pin_client_checkin_date
  BEFORE INSERT ON public.daily_team_checkins
  FOR EACH ROW EXECUTE FUNCTION public._pin_client_checkin_date();

REVOKE UPDATE ON public.daily_team_checkins FROM authenticated;
DROP POLICY "Users can update their own check-ins" ON public.daily_team_checkins;
