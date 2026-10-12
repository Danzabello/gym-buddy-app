-- Hygiene 05a2: authenticated loses REFERENCES/TRIGGER/MAINTAIN on public tables (and the defaults that would
-- re-grant them), trigger-only functions lose authenticated EXECUTE, safe_user_tz also serves accepted friends.
-- Rollback: docs/rollback_20261013001000.sql
REVOKE REFERENCES, TRIGGER, MAINTAIN ON ALL TABLES IN SCHEMA public FROM authenticated;
ALTER DEFAULT PRIVILEGES FOR ROLE postgres IN SCHEMA public REVOKE REFERENCES, TRIGGER, MAINTAIN ON TABLES FROM authenticated, anon;

REVOKE EXECUTE ON FUNCTION public._enforce_workout_daily_cap() FROM authenticated;
REVOKE EXECUTE ON FUNCTION public.notify_workout_invite() FROM authenticated;
REVOKE EXECUTE ON FUNCTION public.notify_workout_invite_response() FROM authenticated;

CREATE OR REPLACE FUNCTION public.safe_user_tz(p_user_id uuid)
 RETURNS text
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  SELECT COALESCE(
    (SELECT up.timezone FROM user_profiles up
      WHERE up.id = p_user_id
        AND ((SELECT auth.uid()) IS NULL
             OR up.id = (SELECT auth.uid())
             OR EXISTS (SELECT 1 FROM team_members a JOIN team_members b ON b.team_id = a.team_id
                         WHERE a.user_id = (SELECT auth.uid()) AND b.user_id = p_user_id)
             OR EXISTS (SELECT 1 FROM friendships f
                         WHERE f.status = 'accepted'
                           AND ((f.user_id = (SELECT auth.uid()) AND f.friend_id = p_user_id)
                             OR (f.friend_id = (SELECT auth.uid()) AND f.user_id = p_user_id))))),
    'Europe/Dublin'
  );
$function$;
REVOKE EXECUTE ON FUNCTION public.safe_user_tz(uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.safe_user_tz(uuid) TO authenticated, service_role;
