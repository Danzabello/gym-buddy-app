-- M1 (DB audit DB-1): validate_user_timezone checks a new timezone value against public.tz_names, a copy of
-- pg_timezone_names, and an unchanged value returns at once. Anything unknown still becomes 'Europe/Dublin'.
-- SECURITY DEFINER because the trigger fires as the caller (authenticated) and the table has no client grant.
-- Trigger functions are not EXECUTE-checked when they fire; the revoke only takes it off the RPC surface.
-- Table grants (ASK FIRST): RLS on, no policy, nothing for PUBLIC, anon or authenticated. service_role keeps the
-- default privileges. Advisor: rls_enabled_no_policy +1 (INFO, intended, like the other service-only tables).
CREATE TABLE public.tz_names (name text PRIMARY KEY);
ALTER TABLE public.tz_names ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON public.tz_names FROM PUBLIC, anon, authenticated;
INSERT INTO public.tz_names (name) SELECT DISTINCT name FROM pg_timezone_names;

CREATE OR REPLACE FUNCTION public.validate_user_timezone()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path = public
AS $function$
BEGIN
  IF TG_OP = 'UPDATE' AND NEW.timezone IS NOT DISTINCT FROM OLD.timezone THEN
    RETURN NEW;
  END IF;
  IF NEW.timezone IS NOT NULL AND NOT EXISTS (SELECT 1 FROM tz_names WHERE name = NEW.timezone) THEN
    INSERT INTO tz_names (name) SELECT name FROM pg_timezone_names WHERE name = NEW.timezone ON CONFLICT DO NOTHING;
  END IF;
  IF NEW.timezone IS NULL
     OR NOT EXISTS (SELECT 1 FROM tz_names WHERE name = NEW.timezone) THEN
    NEW.timezone := 'Europe/Dublin';
  END IF;
  RETURN NEW;
END;
$function$;
REVOKE EXECUTE ON FUNCTION public.validate_user_timezone() FROM PUBLIC, anon, authenticated;
