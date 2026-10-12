-- Applies 05a then its rollback in ONE DO block that raises at the end (all rolled back); prints catalog differences.
DO $t$
DECLARE a text; b text; d text;
BEGIN
a := (SELECT string_agg(k, E'\n' ORDER BY k) FROM (
 SELECT 'fn:'||p.oid::regprocedure||':'||coalesce((SELECT string_agg(e::text, ',' ORDER BY e::text) FROM unnest(p.proacl) e),'')||':'||coalesce(p.proconfig::text,'')||':'||md5(p.prosrc) k FROM pg_proc p WHERE p.pronamespace='public'::regnamespace
 UNION ALL SELECT 'tbl:'||c.relname||':'||coalesce((SELECT string_agg(e::text, ',' ORDER BY e::text) FROM unnest(c.relacl) e),'') FROM pg_class c WHERE c.relnamespace='public'::regnamespace AND c.relkind IN ('r','p')
 UNION ALL SELECT 'pol:'||tablename||':'||policyname||':'||cmd||':'||roles::text||':'||coalesce(qual,'')||':'||coalesce(with_check,'') FROM pg_policies WHERE schemaname='public'
 UNION ALL SELECT 'idx:'||indexdef FROM pg_indexes WHERE schemaname='public'
 UNION ALL SELECT 'con:'||conrelid::regclass||':'||conname||':'||pg_get_constraintdef(oid) FROM pg_constraint WHERE connamespace='public'::regnamespace
 UNION ALL SELECT 'trg:'||tgrelid::regclass||':'||tgname FROM pg_trigger WHERE NOT tgisinternal AND tgrelid::regclass::text NOT LIKE 'storage.%'
 UNION ALL SELECT 'cron:'||jobname||':'||schedule FROM cron.job) z);

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

REVOKE INSERT, UPDATE, DELETE ON public.achievements, public.shop_items, public.level_definitions, public.coin_transactions, public.cosmetic_unlock_conditions, public.team_names FROM authenticated;
REVOKE UPDATE, DELETE ON public.xp_transactions FROM authenticated;
REVOKE ALL ON public.invite_reward_dead_letters FROM authenticated, anon;
REVOKE REFERENCES, TRIGGER, MAINTAIN ON ALL TABLES IN SCHEMA public FROM anon;
REVOKE DELETE ON public.daily_team_checkins FROM authenticated;
REVOKE DELETE ON public.workout_templates FROM authenticated;
DROP POLICY IF EXISTS "Users can create custom templates" ON public.workout_templates;
DROP POLICY IF EXISTS "Users can update their own templates" ON public.workout_templates;
DROP POLICY IF EXISTS "Users can delete their own teams" ON public.buddy_teams;
REVOKE DELETE ON public.buddy_teams FROM authenticated;

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

REVOKE EXECUTE ON FUNCTION public._grant_achievement_shop_items() FROM PUBLIC, anon, authenticated;
REVOKE EXECUTE ON FUNCTION public.user_created_team(uuid) FROM PUBLIC, anon, authenticated;
REVOKE EXECUTE ON FUNCTION public.award_checkin_rewards(uuid, date) FROM PUBLIC, anon, authenticated;

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

ALTER TABLE public.workouts ADD CONSTRAINT workouts_buddy_not_self
  CHECK (buddy_id IS NULL OR buddy_id <> user_id) NOT VALID;
ALTER TABLE public.workouts VALIDATE CONSTRAINT workouts_buddy_not_self;

DROP INDEX public.idx_daily_team_checkins_unique;
DROP INDEX public.unique_buddy_team;

DROP TRIGGER prevent_duplicate_teams ON public.team_members;
DROP FUNCTION public.check_duplicate_team();

DROP POLICY "Users can update own sessions" ON public.active_checkin_sessions;
CREATE POLICY "Users can update own sessions" ON public.active_checkin_sessions
  FOR UPDATE USING ((SELECT auth.uid()) = user_id) WITH CHECK ((SELECT auth.uid()) = user_id);

DELETE FROM public.invite_accept_attempts a WHERE NOT EXISTS (SELECT 1 FROM auth.users u WHERE u.id = a.user_id);
ALTER TABLE public.invite_accept_attempts ADD CONSTRAINT invite_accept_attempts_user_id_fkey
  FOREIGN KEY (user_id) REFERENCES auth.users(id) ON DELETE CASCADE;
DELETE FROM public.invite_reward_dead_letters d WHERE NOT EXISTS (SELECT 1 FROM auth.users u WHERE u.id = d.inviter_id);
ALTER TABLE public.invite_reward_dead_letters ADD CONSTRAINT invite_reward_dead_letters_inviter_id_fkey
  FOREIGN KEY (inviter_id) REFERENCES auth.users(id) ON DELETE CASCADE;

PERFORM cron.schedule('purge-cron-run-details', '17 3 * * *',
  $$DELETE FROM cron.job_run_details WHERE end_time < now() - interval '7 days'$$);

PERFORM cron.unschedule('purge-cron-run-details');
ALTER TABLE public.invite_reward_dead_letters DROP CONSTRAINT IF EXISTS invite_reward_dead_letters_inviter_id_fkey;
ALTER TABLE public.invite_accept_attempts DROP CONSTRAINT IF EXISTS invite_accept_attempts_user_id_fkey;

DROP POLICY "Users can update own sessions" ON public.active_checkin_sessions;
CREATE POLICY "Users can update own sessions" ON public.active_checkin_sessions
  FOR UPDATE USING (auth.uid() = user_id);

CREATE OR REPLACE FUNCTION public.check_duplicate_team()
 RETURNS trigger
 LANGUAGE plpgsql
AS $function$
BEGIN
  IF EXISTS (
    SELECT 1 FROM team_members tm
    JOIN buddy_teams bt ON bt.id = tm.team_id
    WHERE tm.user_id = NEW.user_id
    AND bt.is_coach_max_team = false
    AND bt.id != NEW.team_id
    AND EXISTS (
      SELECT 1 FROM team_members tm2
      JOIN team_members tm3 ON tm3.team_id = tm2.team_id
      WHERE tm2.team_id = NEW.team_id
      AND tm3.user_id != NEW.user_id
      AND tm3.team_id = tm.team_id
    )
  ) THEN
    RAISE EXCEPTION 'Team already exists between these users';
  END IF;
  RETURN NEW;
END;
$function$;
CREATE TRIGGER prevent_duplicate_teams BEFORE INSERT ON public.team_members FOR EACH ROW EXECUTE FUNCTION check_duplicate_team();

CREATE UNIQUE INDEX idx_daily_team_checkins_unique ON public.daily_team_checkins USING btree (team_streak_id, user_id, check_in_date);
CREATE UNIQUE INDEX unique_buddy_team ON public.team_members USING btree (team_id, user_id);

ALTER TABLE public.workouts DROP CONSTRAINT IF EXISTS workouts_buddy_not_self;

CREATE OR REPLACE FUNCTION public.safe_user_tz(p_user_id uuid)
 RETURNS text
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  SELECT COALESCE(
    (SELECT up.timezone FROM user_profiles up WHERE up.id = p_user_id),
    'Europe/Dublin'
  );
$function$;
REVOKE EXECUTE ON FUNCTION public.safe_user_tz(uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.safe_user_tz(uuid) TO authenticated, service_role;

GRANT EXECUTE ON FUNCTION public._clamp_client_coach_max_schedule() TO PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public._clamp_client_workout_writes() TO PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public._enforce_friendship_transition() TO PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public._enforce_workout_completion_duration() TO PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public._enforce_workout_daily_cap() TO PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public._enforce_workout_log_duration() TO PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public._enforce_workout_type_catalog() TO PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public._guard_client_auto_complete_flags() TO PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public._guard_streak_event_seen() TO PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public._pin_client_session_start() TO PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public._set_workout_planned_at() TO PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.cleanup_workout_sessions() TO PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.notify_workout_invite() TO PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.notify_workout_invite_response() TO PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.update_updated_at_column() TO PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.validate_user_timezone() TO PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.can_take_rest_day(uuid) TO PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.check_team_streak_status(uuid, date) TO PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.get_current_weekly_commitment(uuid) TO PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.get_level_for_xp(integer) TO PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.get_random_team_name() TO PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.get_user_team_ids() TO PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public._grant_achievement_shop_items() TO authenticated;
GRANT EXECUTE ON FUNCTION public.user_created_team(uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public.award_checkin_rewards(uuid, date) TO authenticated;

GRANT DELETE ON public.buddy_teams TO authenticated;
CREATE POLICY "Users can delete their own teams" ON public.buddy_teams FOR DELETE USING (created_by = auth.uid());
GRANT DELETE ON public.workout_templates TO authenticated;
CREATE POLICY "Users can create custom templates" ON public.workout_templates FOR INSERT WITH CHECK (created_by = auth.uid());
CREATE POLICY "Users can update their own templates" ON public.workout_templates FOR UPDATE USING (created_by = auth.uid());
GRANT DELETE ON public.daily_team_checkins TO authenticated;
GRANT REFERENCES, TRIGGER, MAINTAIN ON public.achievements, public.break_day_usage, public.buddy_nudges, public.buddy_teams, public.check_ins, public.coach_max_schedule, public.coin_transactions, public.cosmetic_unlock_conditions, public.daily_check_ins, public.daily_team_checkins, public.device_tokens, public.friend_nicknames, public.friendships, public.invite_reward_dead_letters, public.invites, public.level_definitions, public.notification_log, public.notification_settings, public.shop_items, public.team_members, public.team_names, public.team_streaks, public.user_unlocked_cosmetics, public.weekly_break_plans, public.weekly_commitments, public.workout_invites, public.workout_logs, public.workout_templates, public.workouts, public.xp_transactions TO anon;
GRANT SELECT ON public.invite_reward_dead_letters TO anon;
GRANT DELETE, INSERT, REFERENCES, SELECT, TRIGGER, UPDATE, MAINTAIN ON public.invite_reward_dead_letters TO authenticated;
GRANT UPDATE, DELETE ON public.xp_transactions TO authenticated;
GRANT INSERT, UPDATE, DELETE ON public.achievements, public.shop_items, public.level_definitions, public.coin_transactions, public.cosmetic_unlock_conditions, public.team_names TO authenticated;

ALTER FUNCTION public.award_xp(uuid, integer, text, text) RESET search_path;
ALTER FUNCTION public.can_take_rest_day(uuid) RESET search_path;
ALTER FUNCTION public.check_team_streak_status(uuid, date) RESET search_path;
ALTER FUNCTION public.cleanup_workout_sessions() RESET search_path;
ALTER FUNCTION public.get_current_weekly_commitment(uuid) RESET search_path;
ALTER FUNCTION public.get_level_for_xp(integer) RESET search_path;
ALTER FUNCTION public.get_random_team_name() RESET search_path;
ALTER FUNCTION public.is_user_in_active_workout(uuid) RESET search_path;
ALTER FUNCTION public.notify_workout_invite() RESET search_path;
ALTER FUNCTION public.notify_workout_invite_response() RESET search_path;
ALTER FUNCTION public.update_updated_at_column() RESET search_path;
ALTER FUNCTION public.validate_user_timezone() RESET search_path;

b := (SELECT string_agg(k, E'\n' ORDER BY k) FROM (
 SELECT 'fn:'||p.oid::regprocedure||':'||coalesce((SELECT string_agg(e::text, ',' ORDER BY e::text) FROM unnest(p.proacl) e),'')||':'||coalesce(p.proconfig::text,'')||':'||md5(p.prosrc) k FROM pg_proc p WHERE p.pronamespace='public'::regnamespace
 UNION ALL SELECT 'tbl:'||c.relname||':'||coalesce((SELECT string_agg(e::text, ',' ORDER BY e::text) FROM unnest(c.relacl) e),'') FROM pg_class c WHERE c.relnamespace='public'::regnamespace AND c.relkind IN ('r','p')
 UNION ALL SELECT 'pol:'||tablename||':'||policyname||':'||cmd||':'||roles::text||':'||coalesce(qual,'')||':'||coalesce(with_check,'') FROM pg_policies WHERE schemaname='public'
 UNION ALL SELECT 'idx:'||indexdef FROM pg_indexes WHERE schemaname='public'
 UNION ALL SELECT 'con:'||conrelid::regclass||':'||conname||':'||pg_get_constraintdef(oid) FROM pg_constraint WHERE connamespace='public'::regnamespace
 UNION ALL SELECT 'trg:'||tgrelid::regclass||':'||tgname FROM pg_trigger WHERE NOT tgisinternal AND tgrelid::regclass::text NOT LIKE 'storage.%'
 UNION ALL SELECT 'cron:'||jobname||':'||schedule FROM cron.job) z);
SELECT string_agg(x, E'\n') INTO d FROM (
  SELECT '- '||l x FROM unnest(string_to_array(a, E'\n')) l WHERE l <> ALL (string_to_array(b, E'\n'))
  UNION ALL SELECT '+ '||l FROM unnest(string_to_array(b, E'\n')) l WHERE l <> ALL (string_to_array(a, E'\n'))) q;
RAISE EXCEPTION E'ROLLBACK_DIFF\n%', coalesce(d, 'IDENTICAL');
END $t$;
