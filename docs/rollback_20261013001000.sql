-- Rollback for 20261013001000_hygiene_05a2.
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
