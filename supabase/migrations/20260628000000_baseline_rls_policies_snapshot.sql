-- ============================================================
-- SB-1: Baseline RLS policy snapshot, as of 2026-06-28.
--
-- This was never version-controlled before this point -- the
-- original Fable audit's #1 finding was that supabase/migrations/
-- didn't exist at all, so RLS could not be verified from the repo.
-- This file documents every policy currently enforced, exactly as
-- it lives in production today (including all of the S1/S2/S3/SB-4
-- changes from the migrations immediately preceding this one).
--
-- This is idempotent (DROP IF EXISTS + CREATE for every policy) so
-- it's both documentation AND a working rebuild script.
-- ============================================================

-- ============================================================
-- Enable RLS on every table that currently has it on. Without this,
-- the CREATE POLICY statements below would exist but not be enforced
-- on a fresh database.
-- ============================================================
ALTER TABLE public.achievements ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.active_checkin_sessions ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.break_day_usage ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.buddy_nudges ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.buddy_teams ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.buddy_teams_backup ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.check_ins ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.coach_max_schedule ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.coin_transactions ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.cosmetic_unlock_conditions ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.daily_check_ins ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.daily_team_checkins ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.daily_team_checkins_backup ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.device_tokens ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.friend_nicknames ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.friendships ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.friendships_backup ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.invites ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.level_definitions ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.notification_log ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.notification_settings ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.shop_items ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.team_members ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.team_members_backup ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.team_names ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.team_streaks ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.team_streaks_backup ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.user_achievements ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.user_inventory ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.user_profiles ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.user_unlocked_cosmetics ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.weekly_break_plans ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.weekly_commitments ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.workout_invites ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.workout_logs ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.workout_templates ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.workouts ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.xp_transactions ENABLE ROW LEVEL SECURITY;

-- Note: buddy_teams_backup, daily_team_checkins_backup, and
-- friendships_backup have RLS enabled but NO policies defined --
-- this is intentional and correctly locks them down completely
-- (Postgres denies all access by default when RLS is on with zero
-- policies). team_members_backup uses an explicit USING (false)
-- policy instead, achieving the same end result.

-- ── achievements ──
DROP POLICY IF EXISTS "achievements_public_read" ON public.achievements;
CREATE POLICY "achievements_public_read" ON public.achievements
  FOR SELECT TO public USING (true);

-- ── active_checkin_sessions ──
DROP POLICY IF EXISTS "Users can delete own sessions" ON public.active_checkin_sessions;
CREATE POLICY "Users can delete own sessions" ON public.active_checkin_sessions
  FOR DELETE TO public USING (auth.uid() = user_id);

DROP POLICY IF EXISTS "Users can delete their own sessions or linked buddy sessions" ON public.active_checkin_sessions;
CREATE POLICY "Users can delete their own sessions or linked buddy sessions" ON public.active_checkin_sessions
  FOR DELETE TO public USING (
    (auth.uid() = user_id) OR (EXISTS ( SELECT 1
       FROM workouts w
      WHERE ((w.id = active_checkin_sessions.linked_workout_id) AND (((w.user_id = auth.uid()) AND (w.buddy_id = w.user_id)) OR ((w.buddy_id = auth.uid()) AND (w.user_id = w.user_id))))))
  );

DROP POLICY IF EXISTS "Users can create sessions for themselves or workout buddies" ON public.active_checkin_sessions;
CREATE POLICY "Users can create sessions for themselves or workout buddies" ON public.active_checkin_sessions
  FOR INSERT TO public WITH CHECK (
    (auth.uid() = user_id) OR (EXISTS ( SELECT 1
       FROM workouts w
      WHERE ((w.id = active_checkin_sessions.linked_workout_id) AND (((w.user_id = auth.uid()) AND (w.buddy_id = w.user_id)) OR ((w.buddy_id = auth.uid()) AND (w.user_id = w.user_id))))))
  );

DROP POLICY IF EXISTS "Users can insert own sessions" ON public.active_checkin_sessions;
CREATE POLICY "Users can insert own sessions" ON public.active_checkin_sessions
  FOR INSERT TO public WITH CHECK (auth.uid() = user_id);

DROP POLICY IF EXISTS "Users can view own sessions" ON public.active_checkin_sessions;
CREATE POLICY "Users can view own sessions" ON public.active_checkin_sessions
  FOR SELECT TO public USING (auth.uid() = user_id);

DROP POLICY IF EXISTS "Users can view their own sessions or workout buddy sessions" ON public.active_checkin_sessions;
CREATE POLICY "Users can view their own sessions or workout buddy sessions" ON public.active_checkin_sessions
  FOR SELECT TO public USING (
    (auth.uid() = user_id) OR (EXISTS ( SELECT 1
       FROM workouts w
      WHERE ((w.id = active_checkin_sessions.linked_workout_id) AND (((w.user_id = auth.uid()) AND (w.buddy_id = w.user_id)) OR ((w.buddy_id = auth.uid()) AND (w.user_id = w.user_id))))))
  );

DROP POLICY IF EXISTS "Users can update own sessions" ON public.active_checkin_sessions;
CREATE POLICY "Users can update own sessions" ON public.active_checkin_sessions
  FOR UPDATE TO public USING (auth.uid() = user_id);

DROP POLICY IF EXISTS "Users can update their own sessions or linked buddy sessions" ON public.active_checkin_sessions;
CREATE POLICY "Users can update their own sessions or linked buddy sessions" ON public.active_checkin_sessions
  FOR UPDATE TO public USING (
    (auth.uid() = user_id) OR (EXISTS ( SELECT 1
       FROM workouts w
      WHERE ((w.id = active_checkin_sessions.linked_workout_id) AND (((w.user_id = auth.uid()) AND (w.buddy_id = w.user_id)) OR ((w.buddy_id = auth.uid()) AND (w.user_id = w.user_id))))))
  );

-- ── break_day_usage ──
DROP POLICY IF EXISTS "Users can delete their own break days" ON public.break_day_usage;
CREATE POLICY "Users can delete their own break days" ON public.break_day_usage
  FOR DELETE TO public USING (auth.uid() = user_id);

DROP POLICY IF EXISTS "Users can insert their own break days" ON public.break_day_usage;
CREATE POLICY "Users can insert their own break days" ON public.break_day_usage
  FOR INSERT TO public WITH CHECK (auth.uid() = user_id);

DROP POLICY IF EXISTS "Users can view their own break days" ON public.break_day_usage;
CREATE POLICY "Users can view their own break days" ON public.break_day_usage
  FOR SELECT TO public USING (auth.uid() = user_id);

DROP POLICY IF EXISTS "Users can view their partners' break days" ON public.break_day_usage;
CREATE POLICY "Users can view their partners' break days" ON public.break_day_usage
  FOR SELECT TO public USING (
    EXISTS ( SELECT 1
       FROM (team_streaks ts
         JOIN team_members tm1 ON (((tm1.team_id = ts.team_id) AND (tm1.user_id = auth.uid()))))
         JOIN team_members tm2 ON (((tm2.team_id = ts.team_id) AND (tm2.user_id = break_day_usage.user_id)))
      WHERE (ts.is_active = true))
  );

DROP POLICY IF EXISTS "Users can update their own break days" ON public.break_day_usage;
CREATE POLICY "Users can update their own break days" ON public.break_day_usage
  FOR UPDATE TO public USING (auth.uid() = user_id) WITH CHECK (auth.uid() = user_id);

-- ── buddy_nudges ──
DROP POLICY IF EXISTS "Users can insert own nudges" ON public.buddy_nudges;
CREATE POLICY "Users can insert own nudges" ON public.buddy_nudges
  FOR INSERT TO public WITH CHECK (auth.uid() = sender_id);

DROP POLICY IF EXISTS "Users can read own nudges" ON public.buddy_nudges;
CREATE POLICY "Users can read own nudges" ON public.buddy_nudges
  FOR SELECT TO public USING (auth.uid() = sender_id);

-- ── buddy_teams ──
DROP POLICY IF EXISTS "Users can delete their own teams" ON public.buddy_teams;
CREATE POLICY "Users can delete their own teams" ON public.buddy_teams
  FOR DELETE TO public USING (created_by = auth.uid());

DROP POLICY IF EXISTS "Authenticated users can create teams" ON public.buddy_teams;
CREATE POLICY "Authenticated users can create teams" ON public.buddy_teams
  FOR INSERT TO public WITH CHECK (auth.uid() IS NOT NULL);

DROP POLICY IF EXISTS "Users can view teams they created" ON public.buddy_teams;
CREATE POLICY "Users can view teams they created" ON public.buddy_teams
  FOR SELECT TO public USING (created_by = auth.uid());

DROP POLICY IF EXISTS "Users can view their teams" ON public.buddy_teams;
CREATE POLICY "Users can view their teams" ON public.buddy_teams
  FOR SELECT TO public USING (id IN ( SELECT team_members.team_id FROM team_members WHERE (team_members.user_id = auth.uid())));

DROP POLICY IF EXISTS "Users can update teams they created" ON public.buddy_teams;
CREATE POLICY "Users can update teams they created" ON public.buddy_teams
  FOR UPDATE TO public USING (created_by = auth.uid());

DROP POLICY IF EXISTS "Users can update their own teams" ON public.buddy_teams;
CREATE POLICY "Users can update their own teams" ON public.buddy_teams
  FOR UPDATE TO public USING (created_by = auth.uid());

-- ── check_ins (legacy table) ──
DROP POLICY IF EXISTS "Users can delete own check-ins" ON public.check_ins;
CREATE POLICY "Users can delete own check-ins" ON public.check_ins
  FOR DELETE TO public USING (auth.uid() = user_id);

DROP POLICY IF EXISTS "Users can create own check-ins" ON public.check_ins;
CREATE POLICY "Users can create own check-ins" ON public.check_ins
  FOR INSERT TO public WITH CHECK (auth.uid() = user_id);

DROP POLICY IF EXISTS "Users can view own check-ins" ON public.check_ins;
CREATE POLICY "Users can view own check-ins" ON public.check_ins
  FOR SELECT TO public USING (auth.uid() = user_id);

DROP POLICY IF EXISTS "Users can update own check-ins" ON public.check_ins;
CREATE POLICY "Users can update own check-ins" ON public.check_ins
  FOR UPDATE TO public USING (auth.uid() = user_id);

-- ── coach_max_schedule ──
DROP POLICY IF EXISTS "Users can insert their own Coach Max schedule" ON public.coach_max_schedule;
CREATE POLICY "Users can insert their own Coach Max schedule" ON public.coach_max_schedule
  FOR INSERT TO public WITH CHECK (user_id = auth.uid());

DROP POLICY IF EXISTS "Users can view their own Coach Max schedule" ON public.coach_max_schedule;
CREATE POLICY "Users can view their own Coach Max schedule" ON public.coach_max_schedule
  FOR SELECT TO public USING (user_id = auth.uid());

DROP POLICY IF EXISTS "Users can update their own Coach Max schedule" ON public.coach_max_schedule;
CREATE POLICY "Users can update their own Coach Max schedule" ON public.coach_max_schedule
  FOR UPDATE TO public USING (user_id = auth.uid());

-- ── coin_transactions (client INSERT intentionally removed by S2/S3 -- see economy migration) ──
DROP POLICY IF EXISTS "Users see own transactions" ON public.coin_transactions;
CREATE POLICY "Users see own transactions" ON public.coin_transactions
  FOR SELECT TO public USING (auth.uid() = user_id);

-- ── cosmetic_unlock_conditions ──
DROP POLICY IF EXISTS "Anyone reads cosmetic_unlock_conditions" ON public.cosmetic_unlock_conditions;
CREATE POLICY "Anyone reads cosmetic_unlock_conditions" ON public.cosmetic_unlock_conditions
  FOR SELECT TO public USING (true);

-- ── daily_check_ins (legacy table, singular) ──
DROP POLICY IF EXISTS "Users can delete their own check-ins" ON public.daily_check_ins;
CREATE POLICY "Users can delete their own check-ins" ON public.daily_check_ins
  FOR DELETE TO public USING (auth.uid() = user_id);

DROP POLICY IF EXISTS "Users can insert their own check-ins" ON public.daily_check_ins;
CREATE POLICY "Users can insert their own check-ins" ON public.daily_check_ins
  FOR INSERT TO public WITH CHECK (auth.uid() = user_id);

DROP POLICY IF EXISTS "Users can view their own check-ins" ON public.daily_check_ins;
CREATE POLICY "Users can view their own check-ins" ON public.daily_check_ins
  FOR SELECT TO public USING ((auth.uid() = user_id) OR (auth.uid() = buddy_id));

DROP POLICY IF EXISTS "Users can update their own check-ins" ON public.daily_check_ins;
CREATE POLICY "Users can update their own check-ins" ON public.daily_check_ins
  FOR UPDATE TO public USING (auth.uid() = user_id);

-- ── daily_team_checkins (the friend-proxy forgery policy was DROPPED by S2/S3 -- not recreated here) ──
DROP POLICY IF EXISTS "Coach Max can check in" ON public.daily_team_checkins;
CREATE POLICY "Coach Max can check in" ON public.daily_team_checkins
  FOR INSERT TO public WITH CHECK (user_id = '00000000-0000-0000-0000-000000000001'::uuid);

DROP POLICY IF EXISTS "Users can create check-ins for their teams" ON public.daily_team_checkins;
CREATE POLICY "Users can create check-ins for their teams" ON public.daily_team_checkins
  FOR INSERT TO public WITH CHECK (
    (user_id = auth.uid()) AND (team_streak_id IN ( SELECT ts.id
       FROM (team_streaks ts JOIN team_members tm ON ((tm.team_id = ts.team_id)))
      WHERE (tm.user_id = auth.uid())))
  );

DROP POLICY IF EXISTS "Users can view check-ins for their teams and friends" ON public.daily_team_checkins;
CREATE POLICY "Users can view check-ins for their teams and friends" ON public.daily_team_checkins
  FOR SELECT TO public USING (
    (user_id = auth.uid()) OR (EXISTS ( SELECT 1
       FROM (team_streaks ts JOIN team_members tm ON ((tm.team_id = ts.team_id)))
      WHERE ((ts.id = daily_team_checkins.team_streak_id) AND (tm.user_id = auth.uid())))) OR (EXISTS ( SELECT 1
       FROM friendships
      WHERE (((friendships.user_id = auth.uid()) AND (friendships.friend_id = daily_team_checkins.user_id)) OR ((friendships.friend_id = auth.uid()) AND (friendships.user_id = daily_team_checkins.user_id) AND (friendships.status = 'accepted'::text)))))
  );

DROP POLICY IF EXISTS "Users can update their own check-ins" ON public.daily_team_checkins;
CREATE POLICY "Users can update their own check-ins" ON public.daily_team_checkins
  FOR UPDATE TO public USING (user_id = auth.uid()) WITH CHECK (user_id = auth.uid());

-- ── device_tokens ──
DROP POLICY IF EXISTS "Users manage own tokens" ON public.device_tokens;
CREATE POLICY "Users manage own tokens" ON public.device_tokens
  FOR ALL TO public USING (auth.uid() = user_id);

-- ── friend_nicknames ──
DROP POLICY IF EXISTS "Users can delete own nicknames" ON public.friend_nicknames;
CREATE POLICY "Users can delete own nicknames" ON public.friend_nicknames
  FOR DELETE TO public USING (auth.uid() = user_id);

DROP POLICY IF EXISTS "Users can insert own nicknames" ON public.friend_nicknames;
CREATE POLICY "Users can insert own nicknames" ON public.friend_nicknames
  FOR INSERT TO public WITH CHECK (auth.uid() = user_id);

DROP POLICY IF EXISTS "Users can view own nicknames" ON public.friend_nicknames;
CREATE POLICY "Users can view own nicknames" ON public.friend_nicknames
  FOR SELECT TO public USING (auth.uid() = user_id);

DROP POLICY IF EXISTS "Users see only nicknames they set" ON public.friend_nicknames;
CREATE POLICY "Users see only nicknames they set" ON public.friend_nicknames
  FOR SELECT TO public USING (user_id = auth.uid());

DROP POLICY IF EXISTS "Users can update own nicknames" ON public.friend_nicknames;
CREATE POLICY "Users can update own nicknames" ON public.friend_nicknames
  FOR UPDATE TO public USING (auth.uid() = user_id);

-- ── friendships ──
DROP POLICY IF EXISTS "Users can delete friendships they're part of" ON public.friendships;
CREATE POLICY "Users can delete friendships they're part of" ON public.friendships
  FOR DELETE TO public USING ((auth.uid() = user_id) OR (auth.uid() = friend_id));

DROP POLICY IF EXISTS "Users can create friend requests" ON public.friendships;
CREATE POLICY "Users can create friend requests" ON public.friendships
  FOR INSERT TO public WITH CHECK (auth.uid() = user_id);

DROP POLICY IF EXISTS "Users can send friend requests" ON public.friendships;
CREATE POLICY "Users can send friend requests" ON public.friendships
  FOR INSERT TO authenticated WITH CHECK (auth.uid() = user_id);

DROP POLICY IF EXISTS "Users can view their friendships" ON public.friendships;
CREATE POLICY "Users can view their friendships" ON public.friendships
  FOR SELECT TO public USING ((auth.uid() = user_id) OR (auth.uid() = friend_id));

DROP POLICY IF EXISTS "Recipients can accept friend requests" ON public.friendships;
CREATE POLICY "Recipients can accept friend requests" ON public.friendships
  FOR UPDATE TO authenticated USING (auth.uid() = friend_id);

DROP POLICY IF EXISTS "Users can update friendships they're part of" ON public.friendships;
CREATE POLICY "Users can update friendships they're part of" ON public.friendships
  FOR UPDATE TO public USING (auth.uid() = friend_id);

-- ── invites ──
DROP POLICY IF EXISTS "Users can create own invites" ON public.invites;
CREATE POLICY "Users can create own invites" ON public.invites
  FOR INSERT TO public WITH CHECK (auth.uid() = inviter_id);

DROP POLICY IF EXISTS "Authenticated users can look up invite by code" ON public.invites;
CREATE POLICY "Authenticated users can look up invite by code" ON public.invites
  FOR SELECT TO public USING (auth.role() = 'authenticated'::text);

DROP POLICY IF EXISTS "Users can view own invites" ON public.invites;
CREATE POLICY "Users can view own invites" ON public.invites
  FOR SELECT TO public USING ((auth.uid() = inviter_id) OR (auth.uid() = accepted_by));

DROP POLICY IF EXISTS "Authenticated users can accept invites" ON public.invites;
CREATE POLICY "Authenticated users can accept invites" ON public.invites
  FOR UPDATE TO public USING (auth.role() = 'authenticated'::text) WITH CHECK (status = 'accepted'::text);

-- ── level_definitions ──
DROP POLICY IF EXISTS "Anyone reads level_definitions" ON public.level_definitions;
CREATE POLICY "Anyone reads level_definitions" ON public.level_definitions
  FOR SELECT TO public USING (true);

-- ── notification_log ──
DROP POLICY IF EXISTS "Service role manages logs" ON public.notification_log;
CREATE POLICY "Service role manages logs" ON public.notification_log
  FOR ALL TO public USING (auth.role() = 'service_role'::text);

DROP POLICY IF EXISTS "Users read own logs" ON public.notification_log;
CREATE POLICY "Users read own logs" ON public.notification_log
  FOR SELECT TO public USING (auth.uid() = user_id);

-- ── notification_settings ──
DROP POLICY IF EXISTS "Users manage own settings" ON public.notification_settings;
CREATE POLICY "Users manage own settings" ON public.notification_settings
  FOR ALL TO public USING (auth.uid() = user_id);

-- ── shop_items ──
DROP POLICY IF EXISTS "Users see all shop items" ON public.shop_items;
CREATE POLICY "Users see all shop items" ON public.shop_items
  FOR SELECT TO public USING (is_available = true);

-- ── team_members ──
DROP POLICY IF EXISTS "System can insert Coach Max" ON public.team_members;
CREATE POLICY "System can insert Coach Max" ON public.team_members
  FOR INSERT TO public WITH CHECK (user_id = '00000000-0000-0000-0000-000000000001'::uuid);

DROP POLICY IF EXISTS "Team creators can add members" ON public.team_members;
CREATE POLICY "Team creators can add members" ON public.team_members
  FOR INSERT TO authenticated WITH CHECK (
    EXISTS ( SELECT 1 FROM buddy_teams WHERE ((buddy_teams.id = team_members.team_id) AND (buddy_teams.created_by = auth.uid())))
  );

DROP POLICY IF EXISTS "Users can insert themselves" ON public.team_members;
CREATE POLICY "Users can insert themselves" ON public.team_members
  FOR INSERT TO authenticated WITH CHECK (auth.uid() = user_id);

DROP POLICY IF EXISTS "team_members_select" ON public.team_members;
CREATE POLICY "team_members_select" ON public.team_members
  FOR SELECT TO public USING (team_id IN ( SELECT get_user_team_ids() AS get_user_team_ids));

-- ── team_members_backup (locked down -- no access at all) ──
DROP POLICY IF EXISTS "Only admins can access backups" ON public.team_members_backup;
CREATE POLICY "Only admins can access backups" ON public.team_members_backup
  FOR ALL TO public USING (false);

-- ── team_names ──
DROP POLICY IF EXISTS "Anyone can view team names" ON public.team_names;
CREATE POLICY "Anyone can view team names" ON public.team_names
  FOR SELECT TO public USING (true);

-- ── team_streaks ──
DROP POLICY IF EXISTS "Users can insert streaks for their teams" ON public.team_streaks;
CREATE POLICY "Users can insert streaks for their teams" ON public.team_streaks
  FOR INSERT TO public WITH CHECK (team_id IN ( SELECT team_members.team_id FROM team_members WHERE (team_members.user_id = auth.uid())));

DROP POLICY IF EXISTS "Users can view streaks for their teams" ON public.team_streaks;
CREATE POLICY "Users can view streaks for their teams" ON public.team_streaks
  FOR SELECT TO public USING (team_id IN ( SELECT team_members.team_id FROM team_members WHERE (team_members.user_id = auth.uid())));

DROP POLICY IF EXISTS "Users can update streaks for their teams" ON public.team_streaks;
CREATE POLICY "Users can update streaks for their teams" ON public.team_streaks
  FOR UPDATE TO public USING (team_id IN ( SELECT team_members.team_id FROM team_members WHERE (team_members.user_id = auth.uid())));

-- ── user_achievements ──
DROP POLICY IF EXISTS "user_achievements_own" ON public.user_achievements;
CREATE POLICY "user_achievements_own" ON public.user_achievements
  FOR ALL TO public USING (auth.uid() = user_id);

-- ── user_inventory ──
DROP POLICY IF EXISTS "Users can buy items" ON public.user_inventory;
CREATE POLICY "Users can buy items" ON public.user_inventory
  FOR INSERT TO public WITH CHECK (auth.uid() = user_id);

DROP POLICY IF EXISTS "Users see own inventory" ON public.user_inventory;
CREATE POLICY "Users see own inventory" ON public.user_inventory
  FOR SELECT TO public USING (auth.uid() = user_id);

DROP POLICY IF EXISTS "Users can equip items" ON public.user_inventory;
CREATE POLICY "Users can equip items" ON public.user_inventory
  FOR UPDATE TO public USING (auth.uid() = user_id);

-- ── user_profiles ──
DROP POLICY IF EXISTS "Users can insert own profile" ON public.user_profiles;
CREATE POLICY "Users can insert own profile" ON public.user_profiles
  FOR INSERT TO public WITH CHECK (auth.uid() = id);

DROP POLICY IF EXISTS "Users can view other profiles" ON public.user_profiles;
CREATE POLICY "Users can view other profiles" ON public.user_profiles
  FOR SELECT TO public USING (auth.uid() IS NOT NULL);

DROP POLICY IF EXISTS "Users can view own profile" ON public.user_profiles;
CREATE POLICY "Users can view own profile" ON public.user_profiles
  FOR SELECT TO public USING (auth.uid() = id);

DROP POLICY IF EXISTS "Users can update own profile" ON public.user_profiles;
CREATE POLICY "Users can update own profile" ON public.user_profiles
  FOR UPDATE TO public USING (auth.uid() = id);

-- NOTE: column-level REVOKE on xp/level/coin_balance (from the S2/S3
-- migration) is a separate, additional restriction layered on top of
-- this row-level policy -- both apply together.

-- ── user_unlocked_cosmetics ──
DROP POLICY IF EXISTS "Service role inserts unlocked cosmetics" ON public.user_unlocked_cosmetics;
CREATE POLICY "Service role inserts unlocked cosmetics" ON public.user_unlocked_cosmetics
  FOR INSERT TO public WITH CHECK (true);

DROP POLICY IF EXISTS "Users can insert own unlocked cosmetics" ON public.user_unlocked_cosmetics;
CREATE POLICY "Users can insert own unlocked cosmetics" ON public.user_unlocked_cosmetics
  FOR INSERT TO public WITH CHECK (auth.uid() = user_id);

DROP POLICY IF EXISTS "Users read own unlocked cosmetics" ON public.user_unlocked_cosmetics;
CREATE POLICY "Users read own unlocked cosmetics" ON public.user_unlocked_cosmetics
  FOR SELECT TO public USING (auth.uid() = user_id);

-- ── weekly_break_plans ──
DROP POLICY IF EXISTS "Users can delete their own break plans" ON public.weekly_break_plans;
CREATE POLICY "Users can delete their own break plans" ON public.weekly_break_plans
  FOR DELETE TO public USING (auth.uid() = user_id);

DROP POLICY IF EXISTS "Users can insert their own break plans" ON public.weekly_break_plans;
CREATE POLICY "Users can insert their own break plans" ON public.weekly_break_plans
  FOR INSERT TO public WITH CHECK (auth.uid() = user_id);

DROP POLICY IF EXISTS "Users can view their own break plans" ON public.weekly_break_plans;
CREATE POLICY "Users can view their own break plans" ON public.weekly_break_plans
  FOR SELECT TO public USING (auth.uid() = user_id);

DROP POLICY IF EXISTS "Users can update their own break plans" ON public.weekly_break_plans;
CREATE POLICY "Users can update their own break plans" ON public.weekly_break_plans
  FOR UPDATE TO public USING (auth.uid() = user_id) WITH CHECK (auth.uid() = user_id);

-- ── weekly_commitments ──
DROP POLICY IF EXISTS "Users can delete their own weekly commitments" ON public.weekly_commitments;
CREATE POLICY "Users can delete their own weekly commitments" ON public.weekly_commitments
  FOR DELETE TO public USING (auth.uid() = user_id);

DROP POLICY IF EXISTS "Users can insert their own weekly commitments" ON public.weekly_commitments;
CREATE POLICY "Users can insert their own weekly commitments" ON public.weekly_commitments
  FOR INSERT TO public WITH CHECK (auth.uid() = user_id);

DROP POLICY IF EXISTS "Users can view their own weekly commitments" ON public.weekly_commitments;
CREATE POLICY "Users can view their own weekly commitments" ON public.weekly_commitments
  FOR SELECT TO public USING (auth.uid() = user_id);

DROP POLICY IF EXISTS "Users can update their own weekly commitments" ON public.weekly_commitments;
CREATE POLICY "Users can update their own weekly commitments" ON public.weekly_commitments
  FOR UPDATE TO public USING (auth.uid() = user_id);

-- ── workout_invites ──
DROP POLICY IF EXISTS "Users can delete their own invites" ON public.workout_invites;
CREATE POLICY "Users can delete their own invites" ON public.workout_invites
  FOR DELETE TO public USING (auth.uid() = sender_id);

DROP POLICY IF EXISTS "Users can send invites" ON public.workout_invites;
CREATE POLICY "Users can send invites" ON public.workout_invites
  FOR INSERT TO public WITH CHECK (auth.uid() = sender_id);

DROP POLICY IF EXISTS "Users can view their own invites" ON public.workout_invites;
CREATE POLICY "Users can view their own invites" ON public.workout_invites
  FOR SELECT TO public USING ((auth.uid() = sender_id) OR (auth.uid() = recipient_id));

DROP POLICY IF EXISTS "Users can update their own invites" ON public.workout_invites;
CREATE POLICY "Users can update their own invites" ON public.workout_invites
  FOR UPDATE TO public
  USING ((auth.uid() = sender_id) OR (auth.uid() = recipient_id))
  WITH CHECK ((auth.uid() = sender_id) OR (auth.uid() = recipient_id));

-- ── workout_logs ──
DROP POLICY IF EXISTS "Users can create their own workout logs" ON public.workout_logs;
CREATE POLICY "Users can create their own workout logs" ON public.workout_logs
  FOR INSERT TO public WITH CHECK (user_id = auth.uid());

DROP POLICY IF EXISTS "Users can view their own workout logs" ON public.workout_logs;
CREATE POLICY "Users can view their own workout logs" ON public.workout_logs
  FOR SELECT TO public USING (user_id = auth.uid());

DROP POLICY IF EXISTS "Users can update their own workout logs" ON public.workout_logs;
CREATE POLICY "Users can update their own workout logs" ON public.workout_logs
  FOR UPDATE TO public USING (user_id = auth.uid());

-- ── workout_templates ──
DROP POLICY IF EXISTS "Users can create custom templates" ON public.workout_templates;
CREATE POLICY "Users can create custom templates" ON public.workout_templates
  FOR INSERT TO public WITH CHECK (created_by = auth.uid());

DROP POLICY IF EXISTS "Anyone can view system templates" ON public.workout_templates;
CREATE POLICY "Anyone can view system templates" ON public.workout_templates
  FOR SELECT TO public USING ((is_system_template = true) OR (created_by = auth.uid()));

DROP POLICY IF EXISTS "Users can update their own templates" ON public.workout_templates;
CREATE POLICY "Users can update their own templates" ON public.workout_templates
  FOR UPDATE TO public USING (created_by = auth.uid());

-- ── workouts ──
DROP POLICY IF EXISTS "Users can delete their workouts" ON public.workouts;
CREATE POLICY "Users can delete their workouts" ON public.workouts
  FOR DELETE TO public USING (auth.uid() = user_id);

DROP POLICY IF EXISTS "Users can create workouts" ON public.workouts;
CREATE POLICY "Users can create workouts" ON public.workouts
  FOR INSERT TO public WITH CHECK (auth.uid() = user_id);

DROP POLICY IF EXISTS "Users can view their workouts" ON public.workouts;
CREATE POLICY "Users can view their workouts" ON public.workouts
  FOR SELECT TO public USING ((auth.uid() = user_id) OR (auth.uid() = buddy_id));

DROP POLICY IF EXISTS "Users can update own or buddy workouts" ON public.workouts;
CREATE POLICY "Users can update own or buddy workouts" ON public.workouts
  FOR UPDATE TO public USING ((auth.uid() = user_id) OR (auth.uid() = buddy_id));

DROP POLICY IF EXISTS "Users can update their workouts" ON public.workouts;
CREATE POLICY "Users can update their workouts" ON public.workouts
  FOR UPDATE TO public USING (auth.uid() = user_id);

-- ── xp_transactions ──
DROP POLICY IF EXISTS "Service role inserts xp_transactions" ON public.xp_transactions;
CREATE POLICY "Service role inserts xp_transactions" ON public.xp_transactions
  FOR INSERT TO public WITH CHECK (true);

DROP POLICY IF EXISTS "Users can read own xp_transactions" ON public.xp_transactions;
CREATE POLICY "Users can read own xp_transactions" ON public.xp_transactions
  FOR SELECT TO public USING (auth.uid() = user_id);
