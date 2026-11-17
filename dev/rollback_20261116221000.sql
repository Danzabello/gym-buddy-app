-- Rollback for 20261116221000_tz_names_lookup.sql. Roll back 20261116222000 first: the scheduler reads tz_names.
-- Restores the live trigger body of 2026-11-16 (md5 5c2dba7d8f625a70391ec394bd66eac5, SECURITY INVOKER) and its
-- ACL ({postgres, authenticated, service_role}), then drops the table.
DO $guard$
BEGIN
  IF pg_get_functiondef('public.schedule_coach_max_today()'::regprocedure) LIKE '%tz_names%' THEN
    RAISE EXCEPTION 'roll back 20261116222000 first: schedule_coach_max_today still reads tz_names';
  END IF;
END
$guard$;
CREATE OR REPLACE FUNCTION public.validate_user_timezone()
 RETURNS trigger
 LANGUAGE plpgsql
 SET search_path TO 'public'
AS $function$
BEGIN
  IF NEW.timezone IS NULL
     OR NOT EXISTS (SELECT 1 FROM pg_timezone_names WHERE name = NEW.timezone) THEN
    NEW.timezone := 'Europe/Dublin';
  END IF;
  RETURN NEW;
END;
$function$;

GRANT EXECUTE ON FUNCTION public.validate_user_timezone() TO authenticated;
DROP TABLE public.tz_names;
