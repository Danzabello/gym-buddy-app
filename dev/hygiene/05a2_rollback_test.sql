-- Applies 05a2 then its rollback in one DO that raises (rolled back); prints catalog differences.
DO $t$
DECLARE a text; b text; d text;
BEGIN
a := (SELECT string_agg(k, E'\n' ORDER BY k) FROM (
 SELECT 'fn:'||p.oid::regprocedure||':'||coalesce((SELECT string_agg(e::text, ',' ORDER BY e::text) FROM unnest(p.proacl) e),'')||':'||coalesce(p.proconfig::text,'')||':'||md5(p.prosrc) k FROM pg_proc p WHERE p.pronamespace='public'::regnamespace
 UNION ALL SELECT 'tbl:'||c.relname||':'||coalesce((SELECT string_agg(e::text, ',' ORDER BY e::text) FROM unnest(c.relacl) e),'') FROM pg_class c WHERE c.relnamespace='public'::regnamespace AND c.relkind IN ('r','p')
 UNION ALL SELECT 'dacl:'||defaclrole::regrole||':'||defaclobjtype::text||':'||coalesce((SELECT string_agg(e::text, ',' ORDER BY e::text) FROM unnest(defaclacl) e),'') FROM pg_default_acl WHERE defaclnamespace='public'::regnamespace) z);
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

GRANT REFERENCES, TRIGGER, MAINTAIN ON public.achievements, public.active_checkin_sessions, public.break_day_usage, public.buddy_nudges, public.buddy_teams, public.check_ins, public.coach_max_schedule, public.coin_transactions, public.cosmetic_unlock_conditions, public.daily_check_ins, public.daily_team_checkins, public.device_tokens, public.friend_nicknames, public.friendships, public.invites, public.level_definitions, public.notification_log, public.notification_settings, public.shop_items, public.team_members, public.team_names, public.team_streaks, public.user_achievements, public.user_profiles, public.user_unlocked_cosmetics, public.weekly_break_plans, public.weekly_commitments, public.workout_invites, public.workout_logs, public.workout_templates, public.workouts, public.xp_transactions TO authenticated;
ALTER DEFAULT PRIVILEGES FOR ROLE postgres IN SCHEMA public GRANT REFERENCES, TRIGGER, MAINTAIN ON TABLES TO authenticated, anon;
GRANT EXECUTE ON FUNCTION public._enforce_workout_daily_cap() TO authenticated;
GRANT EXECUTE ON FUNCTION public.notify_workout_invite() TO authenticated;
GRANT EXECUTE ON FUNCTION public.notify_workout_invite_response() TO authenticated;
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
                         WHERE a.user_id = (SELECT auth.uid()) AND b.user_id = p_user_id))),
    'Europe/Dublin'
  );
$function$;
REVOKE EXECUTE ON FUNCTION public.safe_user_tz(uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.safe_user_tz(uuid) TO authenticated, service_role;

b := (SELECT string_agg(k, E'\n' ORDER BY k) FROM (
 SELECT 'fn:'||p.oid::regprocedure||':'||coalesce((SELECT string_agg(e::text, ',' ORDER BY e::text) FROM unnest(p.proacl) e),'')||':'||coalesce(p.proconfig::text,'')||':'||md5(p.prosrc) k FROM pg_proc p WHERE p.pronamespace='public'::regnamespace
 UNION ALL SELECT 'tbl:'||c.relname||':'||coalesce((SELECT string_agg(e::text, ',' ORDER BY e::text) FROM unnest(c.relacl) e),'') FROM pg_class c WHERE c.relnamespace='public'::regnamespace AND c.relkind IN ('r','p')
 UNION ALL SELECT 'dacl:'||defaclrole::regrole||':'||defaclobjtype::text||':'||coalesce((SELECT string_agg(e::text, ',' ORDER BY e::text) FROM unnest(defaclacl) e),'') FROM pg_default_acl WHERE defaclnamespace='public'::regnamespace) z);
SELECT string_agg(x, E'\n') INTO d FROM (
  SELECT '- '||l x FROM unnest(string_to_array(a, E'\n')) l WHERE l <> ALL (string_to_array(b, E'\n'))
  UNION ALL SELECT '+ '||l FROM unnest(string_to_array(b, E'\n')) l WHERE l <> ALL (string_to_array(a, E'\n'))) q;
RAISE EXCEPTION E'ROLLBACK_DIFF\n%', coalesce(d, 'IDENTICAL');
END $t$;
