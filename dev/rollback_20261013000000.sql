-- Rollback for 20261013000000_hygiene_05a. Restores the pre-05a state captured 2026-10-12.
-- Dropped objects are recreated from their captured definitions.
SELECT cron.unschedule('purge-cron-run-details');
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

-- function EXECUTE (original ACL: PUBLIC + anon + authenticated + service_role for these)
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
-- original ACL for these three: postgres, authenticated, service_role (no PUBLIC, no anon)
GRANT EXECUTE ON FUNCTION public._grant_achievement_shop_items() TO authenticated;
GRANT EXECUTE ON FUNCTION public.user_created_team(uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public.award_checkin_rewards(uuid, date) TO authenticated;

-- table grants
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

-- A1: search_path back to unset (check_duplicate_team was recreated above without one)
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
