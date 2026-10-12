-- Hygiene 05a (Phase A): search_path, grants, policies, duplicate indexes, FK, cron purge.
-- Items: A1 search_path, A2 grants sweep, A3 get_user_team_ids anon, A4 award_checkin_rewards,
-- A5 safe_user_tz guard, A6 workouts_buddy_not_self, A7 buddy_teams DELETE, A8 duplicate indexes,
-- A9 check_duplicate_team (never fires), A10 active_checkin_sessions UPDATE WITH CHECK,
-- A12 FKs to auth.users, A13 cron.job_run_details purge.
-- Not here: A11 (rule not mirrorable from DB), A14 (no CURRENT_DATE in notify_buddy_checkin;
-- workout_date feeds streak logic; vault secret has no consumers, left untouched).
-- Rollback: docs/rollback_20261013000000.sql

-- A1: pin search_path (bodies unchanged; check_duplicate_team is dropped below)
ALTER FUNCTION public.award_xp(uuid, integer, text, text) SET search_path = public;
ALTER FUNCTION public.can_take_rest_day(uuid) SET search_path = public;
ALTER FUNCTION public.check_team_streak_status(uuid, date) SET search_path = public;
ALTER FUNCTION public.cleanup_workout_sessions() SET search_path = public;
ALTER FUNCTION public.get_current_weekly_commitment(uuid) SET search_path = public;
ALTER FUNCTION public.get_level_for_xp(integer) SET search_path = public;
ALTER FUNCTION public.get_random_team_name() SET search_path = public;
ALTER FUNCTION public.is_user_in_active_workout(uuid) SET search_path = public;
ALTER FUNCTION public.notify_workout_invite() SET search_path = public;
ALTER FUNCTION public.notify_workout_invite_response() SET search_path = public;
ALTER FUNCTION public.update_updated_at_column() SET search_path = public;
ALTER FUNCTION public.validate_user_timezone() SET search_path = public;

-- A2: read-only reference/ledger tables get no client writes
REVOKE INSERT, UPDATE, DELETE ON public.achievements, public.shop_items, public.level_definitions, public.coin_transactions, public.cosmetic_unlock_conditions, public.team_names FROM authenticated;
REVOKE UPDATE, DELETE ON public.xp_transactions FROM authenticated;
REVOKE ALL ON public.invite_reward_dead_letters FROM authenticated, anon;
-- anon never needs REFERENCES / TRIGGER / MAINTAIN on any public table (SEC-B)
REVOKE REFERENCES, TRIGGER, MAINTAIN ON ALL TABLES IN SCHEMA public FROM anon;
-- DB-2, DB-5, DB-8: no client DELETE
REVOKE DELETE ON public.daily_team_checkins FROM authenticated;
REVOKE DELETE ON public.workout_templates FROM authenticated;
DROP POLICY IF EXISTS "Users can create custom templates" ON public.workout_templates;
DROP POLICY IF EXISTS "Users can update their own templates" ON public.workout_templates;
DROP POLICY IF EXISTS "Users can delete their own teams" ON public.buddy_teams;
REVOKE DELETE ON public.buddy_teams FROM authenticated;

-- A2/A3: trigger functions and legacy invoker functions are not PUBLIC/anon executable
REVOKE EXECUTE ON FUNCTION public._clamp_client_coach_max_schedule() FROM PUBLIC, anon;
REVOKE EXECUTE ON FUNCTION public._clamp_client_workout_writes() FROM PUBLIC, anon;
REVOKE EXECUTE ON FUNCTION public._enforce_friendship_transition() FROM PUBLIC, anon;
REVOKE EXECUTE ON FUNCTION public._enforce_workout_completion_duration() FROM PUBLIC, anon;
REVOKE EXECUTE ON FUNCTION public._enforce_workout_daily_cap() FROM PUBLIC, anon;
REVOKE EXECUTE ON FUNCTION public._enforce_workout_log_duration() FROM PUBLIC, anon;
REVOKE EXECUTE ON FUNCTION public._enforce_workout_type_catalog() FROM PUBLIC, anon;
REVOKE EXECUTE ON FUNCTION public._guard_client_auto_complete_flags() FROM PUBLIC, anon;
REVOKE EXECUTE ON FUNCTION public._guard_streak_event_seen() FROM PUBLIC, anon;
REVOKE EXECUTE ON FUNCTION public._pin_client_session_start() FROM PUBLIC, anon;
REVOKE EXECUTE ON FUNCTION public._set_workout_planned_at() FROM PUBLIC, anon;
REVOKE EXECUTE ON FUNCTION public.cleanup_workout_sessions() FROM PUBLIC, anon;
REVOKE EXECUTE ON FUNCTION public.notify_workout_invite() FROM PUBLIC, anon;
REVOKE EXECUTE ON FUNCTION public.notify_workout_invite_response() FROM PUBLIC, anon;
REVOKE EXECUTE ON FUNCTION public.update_updated_at_column() FROM PUBLIC, anon;
REVOKE EXECUTE ON FUNCTION public.validate_user_timezone() FROM PUBLIC, anon;
REVOKE EXECUTE ON FUNCTION public.can_take_rest_day(uuid) FROM PUBLIC, anon;
REVOKE EXECUTE ON FUNCTION public.check_team_streak_status(uuid, date) FROM PUBLIC, anon;
REVOKE EXECUTE ON FUNCTION public.get_current_weekly_commitment(uuid) FROM PUBLIC, anon;
REVOKE EXECUTE ON FUNCTION public.get_level_for_xp(integer) FROM PUBLIC, anon;
REVOKE EXECUTE ON FUNCTION public.get_random_team_name() FROM PUBLIC, anon;
REVOKE EXECUTE ON FUNCTION public.get_user_team_ids() FROM PUBLIC, anon;

-- A2/A4: trigger-only and unused definer functions are not client RPCs
REVOKE EXECUTE ON FUNCTION public._grant_achievement_shop_items() FROM PUBLIC, anon, authenticated;
REVOKE EXECUTE ON FUNCTION public.user_created_team(uuid) FROM PUBLIC, anon, authenticated;
REVOKE EXECUTE ON FUNCTION public.award_checkin_rewards(uuid, date) FROM PUBLIC, anon, authenticated;

-- A5: safe_user_tz returns a real timezone only for service/cron (no uid), self, or a teammate
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

-- A6: a workout cannot name its creator as the buddy (0 violating rows at apply time)
ALTER TABLE public.workouts ADD CONSTRAINT workouts_buddy_not_self
  CHECK (buddy_id IS NULL OR buddy_id <> user_id) NOT VALID;
ALTER TABLE public.workouts VALIDATE CONSTRAINT workouts_buddy_not_self;

-- A8: duplicate unique indexes (no constraint owns either; the *_key constraints remain)
DROP INDEX public.idx_daily_team_checkins_unique;
DROP INDEX public.unique_buddy_team;

-- A9: trigger can never fire (needs tm3.team_id = NEW.team_id and = tm.team_id with tm.team_id <> NEW.team_id)
DROP TRIGGER prevent_duplicate_teams ON public.team_members;
DROP FUNCTION public.check_duplicate_team();

-- A10: owner-only UPDATE with WITH CHECK
DROP POLICY "Users can update own sessions" ON public.active_checkin_sessions;
CREATE POLICY "Users can update own sessions" ON public.active_checkin_sessions
  FOR UPDATE USING ((SELECT auth.uid()) = user_id) WITH CHECK ((SELECT auth.uid()) = user_id);

-- A12: account deletion cleans these (0 rows, no orphans at apply time)
DELETE FROM public.invite_accept_attempts a WHERE NOT EXISTS (SELECT 1 FROM auth.users u WHERE u.id = a.user_id);
ALTER TABLE public.invite_accept_attempts ADD CONSTRAINT invite_accept_attempts_user_id_fkey
  FOREIGN KEY (user_id) REFERENCES auth.users(id) ON DELETE CASCADE;
DELETE FROM public.invite_reward_dead_letters d WHERE NOT EXISTS (SELECT 1 FROM auth.users u WHERE u.id = d.inviter_id);
ALTER TABLE public.invite_reward_dead_letters ADD CONSTRAINT invite_reward_dead_letters_inviter_id_fkey
  FOREIGN KEY (inviter_id) REFERENCES auth.users(id) ON DELETE CASCADE;

-- A13: keep 7 days of cron run history
SELECT cron.schedule('purge-cron-run-details', '17 3 * * *',
  $$DELETE FROM cron.job_run_details WHERE end_time < now() - interval '7 days'$$);
