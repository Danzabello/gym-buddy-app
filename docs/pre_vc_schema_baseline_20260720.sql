-- ============================================================================
-- REFERENCE ONLY -- NOT A MIGRATION -- DO NOT APPLY -- DO NOT PLACE IN supabase/migrations/
-- ============================================================================
--
-- Pre-version-control schema baseline, captured 2026-07-20 (Group F).
--
-- This file documents the database objects that PREDATE version control and
-- exist in NO migration file: all base TABLES (columns/types/defaults/
-- constraints/indexes), the 18 pre-VC FUNCTIONS, and the 10 pre-VC TRIGGERS.
-- Generated from the live catalog (pg_get_functiondef / pg_get_triggerdef /
-- pg_get_constraintdef / pg_get_indexdef) because `supabase db dump` needs
-- Docker, which is unavailable in this environment.
--
-- WHY THIS IS REFERENCE-ONLY (see CLAUDE.md "Migration history & schema
-- baseline (Group F)"):
--   * `supabase db reset` does NOT work from the migration history -- these
--     base tables are created by no migration, so a fresh replay fails at the
--     very first migration. This doc is the missing piece for a human doing a
--     from-scratch reconstruction, NOT an executable step.
--   * It must never be added to supabase/migrations/ or run by db push/reset.
--     If a real from-scratch-migrations initiative is undertaken, THAT project
--     turns this into ordered, executable migrations and resolves the baseline
--     ordering conflict (user_created_team) as part of its own scope.
--
-- REDACTION: the four notify_* trigger functions (notify_friend_request,
-- notify_friend_accepted, notify_workout_invite, notify_workout_invite_response)
-- hardcoded the project anon JWT in their net.http_post Authorization header.
-- That key is gitignored (.env) and appears in no committed file, so it is
-- replaced here with <ANON_KEY_REDACTED_see_.env> to avoid committing it.
--
-- SUPERSEDED 2026-07-22: the anon bearer was a real bug -- send-notification
-- rejected those calls 401, so friend-request/accepted and workout-invite/
-- response notifications were silently failing. Fixed by migration
-- 20260722221100_fix_notify_triggers_use_vault_service_role.sql (switches all 4
-- to the Vault service-role pattern; verified 200 on live). The pre-fix bodies
-- below are kept as the historical pre-VC record ONLY -- the live functions no
-- longer match them.
--
-- Coverage: every live function/trigger/table is represented either in a
-- committed migration OR in this file. Verified 2026-07-20.
-- ============================================================================


-- ========================================================================
-- SECTION 1 -- TABLES (38)
-- ========================================================================

-- table: achievements
CREATE TABLE achievements (
  id text NOT NULL,
  name text NOT NULL,
  description text NOT NULL,
  category text NOT NULL,
  icon text NOT NULL,
  rarity text NOT NULL,
  xp_reward integer NOT NULL DEFAULT 0,
  coin_reward integer NOT NULL DEFAULT 0,
  target_value integer NOT NULL DEFAULT 1,
  sort_order integer NOT NULL DEFAULT 0
);
ALTER TABLE achievements ADD CONSTRAINT achievements_pkey PRIMARY KEY (id);

-- table: active_checkin_sessions
CREATE TABLE active_checkin_sessions (
  id uuid NOT NULL DEFAULT uuid_generate_v4(),
  user_id uuid NOT NULL,
  started_at timestamp with time zone NOT NULL DEFAULT now(),
  created_at timestamp with time zone DEFAULT now(),
  workout_type text,
  workout_emoji text,
  planned_duration integer,
  linked_workout_id uuid,
  workout_id uuid
);
ALTER TABLE active_checkin_sessions ADD CONSTRAINT active_checkin_sessions_pkey PRIMARY KEY (id);
ALTER TABLE active_checkin_sessions ADD CONSTRAINT active_checkin_sessions_user_id_key UNIQUE (user_id);
ALTER TABLE active_checkin_sessions ADD CONSTRAINT active_checkin_sessions_linked_workout_id_fkey FOREIGN KEY (linked_workout_id) REFERENCES workouts(id) ON DELETE CASCADE;
ALTER TABLE active_checkin_sessions ADD CONSTRAINT active_checkin_sessions_user_id_fkey FOREIGN KEY (user_id) REFERENCES auth.users(id) ON DELETE CASCADE;
ALTER TABLE active_checkin_sessions ADD CONSTRAINT active_checkin_sessions_workout_id_fkey FOREIGN KEY (workout_id) REFERENCES workouts(id) ON DELETE CASCADE;
CREATE INDEX idx_active_checkin_sessions_user ON public.active_checkin_sessions USING btree (user_id);
CREATE INDEX idx_active_sessions_linked_workout ON public.active_checkin_sessions USING btree (linked_workout_id);
CREATE INDEX idx_active_sessions_workout_id ON public.active_checkin_sessions USING btree (workout_id);

-- table: break_day_usage
CREATE TABLE break_day_usage (
  id uuid NOT NULL DEFAULT uuid_generate_v4(),
  user_id uuid NOT NULL,
  break_date date NOT NULL,
  declared_at timestamp with time zone DEFAULT now(),
  cancelled_at timestamp with time zone,
  created_at timestamp with time zone DEFAULT now()
);
ALTER TABLE break_day_usage ADD CONSTRAINT break_day_usage_pkey PRIMARY KEY (id);
ALTER TABLE break_day_usage ADD CONSTRAINT break_day_usage_user_id_break_date_key UNIQUE (user_id, break_date);
ALTER TABLE break_day_usage ADD CONSTRAINT break_day_usage_user_id_fkey FOREIGN KEY (user_id) REFERENCES auth.users(id) ON DELETE CASCADE;
CREATE INDEX idx_break_day_usage_active ON public.break_day_usage USING btree (user_id, break_date) WHERE (cancelled_at IS NULL);
CREATE INDEX idx_break_day_usage_user_date ON public.break_day_usage USING btree (user_id, break_date);

-- table: buddy_nudges
CREATE TABLE buddy_nudges (
  id uuid NOT NULL DEFAULT gen_random_uuid(),
  sender_id uuid NOT NULL,
  receiver_id uuid NOT NULL,
  nudge_date date NOT NULL DEFAULT CURRENT_DATE,
  created_at timestamp with time zone DEFAULT now()
);
ALTER TABLE buddy_nudges ADD CONSTRAINT buddy_nudges_pkey PRIMARY KEY (id);
ALTER TABLE buddy_nudges ADD CONSTRAINT buddy_nudges_sender_id_receiver_id_nudge_date_key UNIQUE (sender_id, receiver_id, nudge_date);
ALTER TABLE buddy_nudges ADD CONSTRAINT buddy_nudges_receiver_id_fkey FOREIGN KEY (receiver_id) REFERENCES auth.users(id) ON DELETE CASCADE;
ALTER TABLE buddy_nudges ADD CONSTRAINT buddy_nudges_sender_id_fkey FOREIGN KEY (sender_id) REFERENCES auth.users(id) ON DELETE CASCADE;

-- table: buddy_teams
CREATE TABLE buddy_teams (
  id uuid NOT NULL DEFAULT uuid_generate_v4(),
  team_name text,
  team_emoji text DEFAULT '🔥'::text,
  is_coach_max_team boolean DEFAULT false,
  max_members integer DEFAULT 4,
  created_by uuid,
  created_at timestamp with time zone DEFAULT now(),
  updated_at timestamp with time zone DEFAULT now()
);
ALTER TABLE buddy_teams ADD CONSTRAINT buddy_teams_pkey PRIMARY KEY (id);
ALTER TABLE buddy_teams ADD CONSTRAINT buddy_teams_created_by_fkey FOREIGN KEY (created_by) REFERENCES user_profiles(id) ON DELETE SET NULL;
CREATE INDEX idx_buddy_teams_coach_max ON public.buddy_teams USING btree (is_coach_max_team);
CREATE INDEX idx_buddy_teams_created_by ON public.buddy_teams USING btree (created_by);

-- table: buddy_teams_backup
CREATE TABLE buddy_teams_backup (
  id uuid,
  team_name text,
  team_emoji text,
  is_coach_max_team boolean,
  max_members integer,
  created_by uuid,
  created_at timestamp with time zone,
  updated_at timestamp with time zone
);

-- table: check_ins
CREATE TABLE check_ins (
  id uuid NOT NULL DEFAULT gen_random_uuid(),
  user_id uuid NOT NULL,
  check_in_date date NOT NULL,
  workout_id uuid,
  notes text,
  created_at timestamp with time zone DEFAULT now()
);
ALTER TABLE check_ins ADD CONSTRAINT check_ins_pkey PRIMARY KEY (id);
ALTER TABLE check_ins ADD CONSTRAINT check_ins_user_id_check_in_date_key UNIQUE (user_id, check_in_date);
ALTER TABLE check_ins ADD CONSTRAINT check_ins_user_id_fkey FOREIGN KEY (user_id) REFERENCES user_profiles(id) ON DELETE CASCADE;
ALTER TABLE check_ins ADD CONSTRAINT check_ins_workout_id_fkey FOREIGN KEY (workout_id) REFERENCES workouts(id) ON DELETE SET NULL;
CREATE INDEX idx_check_ins_user_date ON public.check_ins USING btree (user_id, check_in_date DESC);

-- table: coach_max_schedule
CREATE TABLE coach_max_schedule (
  id uuid NOT NULL DEFAULT uuid_generate_v4(),
  user_id uuid NOT NULL,
  scheduled_date date NOT NULL,
  scheduled_time time without time zone NOT NULL,
  has_checked_in boolean DEFAULT false,
  checked_in_at timestamp with time zone,
  created_at timestamp with time zone DEFAULT now()
);
ALTER TABLE coach_max_schedule ADD CONSTRAINT coach_max_schedule_pkey PRIMARY KEY (id);
ALTER TABLE coach_max_schedule ADD CONSTRAINT coach_max_schedule_user_id_scheduled_date_key UNIQUE (user_id, scheduled_date);
ALTER TABLE coach_max_schedule ADD CONSTRAINT coach_max_schedule_user_id_fkey FOREIGN KEY (user_id) REFERENCES user_profiles(id) ON DELETE CASCADE;
CREATE INDEX idx_coach_max_schedule_date ON public.coach_max_schedule USING btree (scheduled_date);
CREATE INDEX idx_coach_max_schedule_pending ON public.coach_max_schedule USING btree (scheduled_date, has_checked_in);
CREATE INDEX idx_coach_max_schedule_user ON public.coach_max_schedule USING btree (user_id);

-- table: coin_transactions
CREATE TABLE coin_transactions (
  id uuid NOT NULL DEFAULT gen_random_uuid(),
  user_id uuid,
  amount integer NOT NULL,
  transaction_type text NOT NULL,
  description text,
  reference_id text,
  created_at timestamp with time zone DEFAULT now()
);
ALTER TABLE coin_transactions ADD CONSTRAINT coin_transactions_pkey PRIMARY KEY (id);
ALTER TABLE coin_transactions ADD CONSTRAINT coin_transactions_user_id_fkey FOREIGN KEY (user_id) REFERENCES user_profiles(id) ON DELETE CASCADE;

-- table: cosmetic_unlock_conditions
CREATE TABLE cosmetic_unlock_conditions (
  id uuid NOT NULL DEFAULT gen_random_uuid(),
  shop_item_id uuid NOT NULL,
  unlock_type text NOT NULL,
  required_level integer,
  milestone_key text,
  created_at timestamp with time zone NOT NULL DEFAULT now()
);
ALTER TABLE cosmetic_unlock_conditions ADD CONSTRAINT cosmetic_unlock_conditions_pkey PRIMARY KEY (id);
ALTER TABLE cosmetic_unlock_conditions ADD CONSTRAINT cosmetic_unlock_conditions_shop_item_id_fkey FOREIGN KEY (shop_item_id) REFERENCES shop_items(id) ON DELETE CASCADE;
ALTER TABLE cosmetic_unlock_conditions ADD CONSTRAINT cosmetic_unlock_conditions_unlock_type_check CHECK ((unlock_type = ANY (ARRAY['level'::text, 'milestone'::text, 'starter'::text])));
CREATE INDEX idx_cosmetic_unlock_item ON public.cosmetic_unlock_conditions USING btree (shop_item_id);

-- table: daily_check_ins
CREATE TABLE daily_check_ins (
  id uuid NOT NULL DEFAULT gen_random_uuid(),
  user_id uuid NOT NULL,
  check_in_date date NOT NULL,
  status text NOT NULL,
  workout_id uuid,
  confirmed_at timestamp with time zone NOT NULL DEFAULT now(),
  confirmation_type text,
  buddy_id uuid,
  buddy_completed boolean DEFAULT false,
  weekly_commitment_id uuid,
  created_at timestamp with time zone DEFAULT now(),
  updated_at timestamp with time zone DEFAULT now()
);
ALTER TABLE daily_check_ins ADD CONSTRAINT daily_check_ins_pkey PRIMARY KEY (id);
ALTER TABLE daily_check_ins ADD CONSTRAINT daily_check_ins_user_id_check_in_date_key UNIQUE (user_id, check_in_date);
ALTER TABLE daily_check_ins ADD CONSTRAINT daily_check_ins_buddy_id_fkey FOREIGN KEY (buddy_id) REFERENCES auth.users(id) ON DELETE SET NULL;
ALTER TABLE daily_check_ins ADD CONSTRAINT daily_check_ins_user_id_fkey FOREIGN KEY (user_id) REFERENCES auth.users(id) ON DELETE CASCADE;
ALTER TABLE daily_check_ins ADD CONSTRAINT daily_check_ins_weekly_commitment_id_fkey FOREIGN KEY (weekly_commitment_id) REFERENCES weekly_commitments(id) ON DELETE SET NULL;
ALTER TABLE daily_check_ins ADD CONSTRAINT daily_check_ins_workout_id_fkey FOREIGN KEY (workout_id) REFERENCES workouts(id) ON DELETE SET NULL;
ALTER TABLE daily_check_ins ADD CONSTRAINT daily_check_ins_confirmation_type_check CHECK ((confirmation_type = ANY (ARRAY['manual_checkin'::text, 'scheduled_workout'::text, 'rest_day_confirmation'::text])));
ALTER TABLE daily_check_ins ADD CONSTRAINT daily_check_ins_status_check CHECK ((status = ANY (ARRAY['workout_completed'::text, 'rest_day_taken'::text, 'missed'::text, 'extra_workout'::text])));
CREATE INDEX idx_daily_check_ins_buddy ON public.daily_check_ins USING btree (buddy_id, check_in_date);
CREATE INDEX idx_daily_check_ins_status ON public.daily_check_ins USING btree (user_id, status);
CREATE INDEX idx_daily_check_ins_user_date ON public.daily_check_ins USING btree (user_id, check_in_date);

-- table: daily_team_checkins
CREATE TABLE daily_team_checkins (
  id uuid NOT NULL DEFAULT uuid_generate_v4(),
  team_streak_id uuid NOT NULL,
  user_id uuid NOT NULL,
  check_in_date date NOT NULL DEFAULT CURRENT_DATE,
  check_in_time timestamp with time zone DEFAULT now(),
  created_at timestamp with time zone DEFAULT now()
);
ALTER TABLE daily_team_checkins ADD CONSTRAINT daily_team_checkins_pkey PRIMARY KEY (id);
ALTER TABLE daily_team_checkins ADD CONSTRAINT daily_team_checkins_team_streak_id_user_id_check_in_date_key UNIQUE (team_streak_id, user_id, check_in_date);
ALTER TABLE daily_team_checkins ADD CONSTRAINT daily_team_checkins_team_streak_id_fkey FOREIGN KEY (team_streak_id) REFERENCES team_streaks(id) ON DELETE CASCADE;
ALTER TABLE daily_team_checkins ADD CONSTRAINT daily_team_checkins_user_id_fkey FOREIGN KEY (user_id) REFERENCES user_profiles(id) ON DELETE CASCADE;
CREATE INDEX idx_daily_team_checkins_date ON public.daily_team_checkins USING btree (check_in_date);
CREATE INDEX idx_daily_team_checkins_streak ON public.daily_team_checkins USING btree (team_streak_id);
CREATE UNIQUE INDEX idx_daily_team_checkins_unique ON public.daily_team_checkins USING btree (team_streak_id, user_id, check_in_date);
CREATE INDEX idx_daily_team_checkins_user ON public.daily_team_checkins USING btree (user_id);

-- table: daily_team_checkins_backup
CREATE TABLE daily_team_checkins_backup (
  id uuid,
  team_streak_id uuid,
  user_id uuid,
  check_in_date date,
  check_in_time timestamp with time zone,
  created_at timestamp with time zone
);

-- table: device_tokens
CREATE TABLE device_tokens (
  id uuid NOT NULL DEFAULT gen_random_uuid(),
  user_id uuid NOT NULL,
  token text NOT NULL,
  platform text DEFAULT 'android'::text,
  created_at timestamp with time zone DEFAULT now(),
  updated_at timestamp with time zone DEFAULT now()
);
ALTER TABLE device_tokens ADD CONSTRAINT device_tokens_pkey PRIMARY KEY (id);
ALTER TABLE device_tokens ADD CONSTRAINT device_tokens_user_id_token_key UNIQUE (user_id, token);
ALTER TABLE device_tokens ADD CONSTRAINT device_tokens_user_id_fkey FOREIGN KEY (user_id) REFERENCES auth.users(id) ON DELETE CASCADE;

-- table: friend_nicknames
CREATE TABLE friend_nicknames (
  id uuid NOT NULL DEFAULT gen_random_uuid(),
  user_id uuid NOT NULL,
  friend_id uuid NOT NULL,
  nickname text NOT NULL,
  created_at timestamp with time zone DEFAULT now(),
  updated_at timestamp with time zone DEFAULT now()
);
ALTER TABLE friend_nicknames ADD CONSTRAINT friend_nicknames_pkey PRIMARY KEY (id);
ALTER TABLE friend_nicknames ADD CONSTRAINT friend_nicknames_user_id_friend_id_key UNIQUE (user_id, friend_id);
ALTER TABLE friend_nicknames ADD CONSTRAINT friend_nicknames_friend_id_fkey FOREIGN KEY (friend_id) REFERENCES auth.users(id) ON DELETE CASCADE;
ALTER TABLE friend_nicknames ADD CONSTRAINT friend_nicknames_user_id_fkey FOREIGN KEY (user_id) REFERENCES auth.users(id) ON DELETE CASCADE;

-- table: friendships
CREATE TABLE friendships (
  id uuid NOT NULL DEFAULT gen_random_uuid(),
  user_id uuid,
  friend_id uuid,
  status text DEFAULT 'pending'::text,
  created_at timestamp with time zone DEFAULT now()
);
ALTER TABLE friendships ADD CONSTRAINT friendships_pkey PRIMARY KEY (id);
ALTER TABLE friendships ADD CONSTRAINT friendships_user_id_friend_id_key UNIQUE (user_id, friend_id);
ALTER TABLE friendships ADD CONSTRAINT friendships_friend_id_fkey FOREIGN KEY (friend_id) REFERENCES user_profiles(id) ON DELETE CASCADE;
ALTER TABLE friendships ADD CONSTRAINT friendships_user_id_fkey FOREIGN KEY (user_id) REFERENCES user_profiles(id) ON DELETE CASCADE;
CREATE UNIQUE INDEX unique_friendship ON public.friendships USING btree (LEAST(user_id, friend_id), GREATEST(user_id, friend_id));

-- table: friendships_backup
CREATE TABLE friendships_backup (
  id uuid,
  user_id uuid,
  friend_id uuid,
  status text,
  created_at timestamp with time zone
);

-- table: invites
CREATE TABLE invites (
  id uuid NOT NULL DEFAULT gen_random_uuid(),
  code text NOT NULL DEFAULT substr(md5((random())::text), 1, 8),
  inviter_id uuid NOT NULL,
  invitee_email text,
  status text NOT NULL DEFAULT 'pending'::text,
  created_at timestamp with time zone DEFAULT now(),
  accepted_at timestamp with time zone,
  accepted_by uuid
);
ALTER TABLE invites ADD CONSTRAINT invites_pkey PRIMARY KEY (id);
ALTER TABLE invites ADD CONSTRAINT invites_code_key UNIQUE (code);
ALTER TABLE invites ADD CONSTRAINT invites_accepted_by_fkey FOREIGN KEY (accepted_by) REFERENCES user_profiles(id) ON DELETE SET NULL;
ALTER TABLE invites ADD CONSTRAINT invites_inviter_id_fkey FOREIGN KEY (inviter_id) REFERENCES user_profiles(id) ON DELETE CASCADE;
ALTER TABLE invites ADD CONSTRAINT invites_status_check CHECK ((status = ANY (ARRAY['pending'::text, 'accepted'::text, 'expired'::text])));
CREATE INDEX idx_invites_code ON public.invites USING btree (code);
CREATE INDEX idx_invites_inviter ON public.invites USING btree (inviter_id);

-- table: level_definitions
CREATE TABLE level_definitions (
  level integer NOT NULL,
  xp_required integer NOT NULL,
  title text NOT NULL
);
ALTER TABLE level_definitions ADD CONSTRAINT level_definitions_pkey PRIMARY KEY (level);

-- table: notification_log
CREATE TABLE notification_log (
  id uuid NOT NULL DEFAULT gen_random_uuid(),
  user_id uuid NOT NULL,
  notification_type text NOT NULL,
  reference_id text,
  sent_at timestamp with time zone DEFAULT now(),
  batch_key text
);
ALTER TABLE notification_log ADD CONSTRAINT notification_log_pkey PRIMARY KEY (id);
ALTER TABLE notification_log ADD CONSTRAINT notification_log_user_id_fkey FOREIGN KEY (user_id) REFERENCES auth.users(id) ON DELETE CASCADE;
CREATE INDEX idx_notification_log_user_type_date ON public.notification_log USING btree (user_id, notification_type, sent_at);

-- table: notification_settings
CREATE TABLE notification_settings (
  user_id uuid NOT NULL,
  notif_social boolean DEFAULT true,
  notif_workouts boolean DEFAULT true,
  notif_streaks boolean DEFAULT true,
  notif_coach_max boolean DEFAULT true,
  quiet_hours_enabled boolean DEFAULT true,
  quiet_hours_start integer DEFAULT 23,
  quiet_hours_end integer DEFAULT 7,
  created_at timestamp with time zone DEFAULT now(),
  updated_at timestamp with time zone DEFAULT now()
);
ALTER TABLE notification_settings ADD CONSTRAINT notification_settings_pkey PRIMARY KEY (user_id);
ALTER TABLE notification_settings ADD CONSTRAINT notification_settings_user_id_fkey FOREIGN KEY (user_id) REFERENCES auth.users(id) ON DELETE CASCADE;

-- table: shop_items
CREATE TABLE shop_items (
  id uuid NOT NULL DEFAULT gen_random_uuid(),
  name text NOT NULL,
  description text,
  category text NOT NULL,
  cost integer NOT NULL,
  emoji text,
  asset_id text,
  is_available boolean DEFAULT true,
  created_at timestamp with time zone DEFAULT now(),
  unlock_level integer NOT NULL DEFAULT 1
);
ALTER TABLE shop_items ADD CONSTRAINT shop_items_pkey PRIMARY KEY (id);

-- table: team_members
CREATE TABLE team_members (
  id uuid NOT NULL DEFAULT uuid_generate_v4(),
  team_id uuid NOT NULL,
  user_id uuid NOT NULL,
  role text DEFAULT 'member'::text,
  joined_at timestamp with time zone DEFAULT now(),
  created_at timestamp with time zone DEFAULT now(),
  is_favorite boolean DEFAULT false
);
ALTER TABLE team_members ADD CONSTRAINT team_members_pkey PRIMARY KEY (id);
ALTER TABLE team_members ADD CONSTRAINT team_members_team_id_user_id_key UNIQUE (team_id, user_id);
ALTER TABLE team_members ADD CONSTRAINT team_members_team_id_fkey FOREIGN KEY (team_id) REFERENCES buddy_teams(id) ON DELETE CASCADE;
ALTER TABLE team_members ADD CONSTRAINT team_members_user_id_fkey FOREIGN KEY (user_id) REFERENCES user_profiles(id) ON DELETE CASCADE;
ALTER TABLE team_members ADD CONSTRAINT team_members_role_check CHECK ((role = ANY (ARRAY['owner'::text, 'member'::text, 'coach_max'::text])));
CREATE INDEX idx_team_members_role ON public.team_members USING btree (role);
CREATE INDEX idx_team_members_team ON public.team_members USING btree (team_id);
CREATE INDEX idx_team_members_user ON public.team_members USING btree (user_id);
CREATE UNIQUE INDEX unique_buddy_team ON public.team_members USING btree (team_id, user_id);

-- table: team_members_backup
CREATE TABLE team_members_backup (
  id uuid,
  team_id uuid,
  user_id uuid,
  role text,
  joined_at timestamp with time zone,
  created_at timestamp with time zone
);

-- table: team_names
CREATE TABLE team_names (
  id uuid NOT NULL DEFAULT uuid_generate_v4(),
  name text NOT NULL,
  category text,
  emoji text,
  created_at timestamp with time zone DEFAULT now()
);
ALTER TABLE team_names ADD CONSTRAINT team_names_pkey PRIMARY KEY (id);
ALTER TABLE team_names ADD CONSTRAINT team_names_name_key UNIQUE (name);
ALTER TABLE team_names ADD CONSTRAINT team_names_category_check CHECK ((category = ANY (ARRAY['funny'::text, 'serious'::text, 'silly'::text])));

-- table: team_streaks
CREATE TABLE team_streaks (
  id uuid NOT NULL DEFAULT uuid_generate_v4(),
  team_id uuid NOT NULL,
  current_streak integer DEFAULT 0,
  longest_streak integer DEFAULT 0,
  last_workout_date date,
  start_date date DEFAULT CURRENT_DATE,
  end_date date,
  end_reason text,
  is_active boolean DEFAULT true,
  created_at timestamp with time zone DEFAULT now(),
  updated_at timestamp with time zone DEFAULT now(),
  total_workouts integer DEFAULT 0,
  best_streak integer DEFAULT 0,
  last_interaction_at timestamp with time zone,
  is_favorite boolean DEFAULT false
);
ALTER TABLE team_streaks ADD CONSTRAINT team_streaks_pkey PRIMARY KEY (id);
ALTER TABLE team_streaks ADD CONSTRAINT team_streaks_team_id_fkey FOREIGN KEY (team_id) REFERENCES buddy_teams(id) ON DELETE CASCADE;
CREATE INDEX idx_team_streaks_active ON public.team_streaks USING btree (is_active);
CREATE INDEX idx_team_streaks_favorite ON public.team_streaks USING btree (is_favorite) WHERE (is_favorite = true);
CREATE INDEX idx_team_streaks_team ON public.team_streaks USING btree (team_id);
CREATE INDEX idx_team_streaks_team_active ON public.team_streaks USING btree (team_id, is_active);
CREATE UNIQUE INDEX idx_team_streaks_unique_active ON public.team_streaks USING btree (team_id) WHERE (is_active = true);

-- table: team_streaks_backup
CREATE TABLE team_streaks_backup (
  id uuid,
  team_id uuid,
  current_streak integer,
  longest_streak integer,
  last_workout_date date,
  start_date date,
  end_date date,
  end_reason text,
  is_active boolean,
  created_at timestamp with time zone,
  updated_at timestamp with time zone
);

-- table: user_achievements
CREATE TABLE user_achievements (
  id uuid NOT NULL DEFAULT gen_random_uuid(),
  user_id uuid NOT NULL,
  achievement_id text NOT NULL,
  unlocked_at timestamp with time zone DEFAULT now(),
  progress integer NOT NULL DEFAULT 0
);
ALTER TABLE user_achievements ADD CONSTRAINT user_achievements_pkey PRIMARY KEY (id);
ALTER TABLE user_achievements ADD CONSTRAINT user_achievements_user_id_achievement_id_key UNIQUE (user_id, achievement_id);
ALTER TABLE user_achievements ADD CONSTRAINT user_achievements_achievement_id_fkey FOREIGN KEY (achievement_id) REFERENCES achievements(id);
ALTER TABLE user_achievements ADD CONSTRAINT user_achievements_user_id_fkey FOREIGN KEY (user_id) REFERENCES auth.users(id) ON DELETE CASCADE;

-- table: user_inventory
CREATE TABLE user_inventory (
  id uuid NOT NULL DEFAULT gen_random_uuid(),
  user_id uuid,
  shop_item_id uuid,
  equipped boolean DEFAULT false,
  purchased_at timestamp with time zone DEFAULT now()
);
ALTER TABLE user_inventory ADD CONSTRAINT user_inventory_pkey PRIMARY KEY (id);
ALTER TABLE user_inventory ADD CONSTRAINT user_inventory_user_id_shop_item_id_key UNIQUE (user_id, shop_item_id);
ALTER TABLE user_inventory ADD CONSTRAINT user_inventory_shop_item_id_fkey FOREIGN KEY (shop_item_id) REFERENCES shop_items(id) ON DELETE CASCADE;
ALTER TABLE user_inventory ADD CONSTRAINT user_inventory_user_id_fkey FOREIGN KEY (user_id) REFERENCES user_profiles(id) ON DELETE CASCADE;

-- table: user_profiles
CREATE TABLE user_profiles (
  id uuid NOT NULL,
  display_name text,
  age integer,
  gender text,
  fitness_goals text[],
  workout_days_per_week integer,
  fitness_level text,
  preferred_workout_time text,
  looking_for_buddy boolean DEFAULT true,
  created_at timestamp with time zone DEFAULT now(),
  updated_at timestamp with time zone DEFAULT now(),
  last_check_in_date date,
  current_weekly_goal integer DEFAULT 2,
  rest_tokens_available integer DEFAULT 3,
  weekly_commitment_active boolean DEFAULT false,
  is_bot boolean DEFAULT false,
  avatar_id text DEFAULT 'lion'::text,
  onboarding_completed boolean DEFAULT false,
  preferred_streak_sort character varying(50) DEFAULT 'highest_current'::character varying,
  custom_streak_order text[],
  username text,
  workout_join_popups_enabled boolean DEFAULT true,
  coin_balance integer DEFAULT 0,
  avatar_border text DEFAULT 'simple'::text,
  preferred_workout_style text DEFAULT 'both'::text,
  xp integer NOT NULL DEFAULT 0,
  level integer NOT NULL DEFAULT 1,
  timezone text NOT NULL DEFAULT 'Europe/Dublin'::text
);
ALTER TABLE user_profiles ADD CONSTRAINT user_profiles_pkey PRIMARY KEY (id);
ALTER TABLE user_profiles ADD CONSTRAINT user_profiles_username_key UNIQUE (username);
CREATE INDEX idx_user_profiles_username ON public.user_profiles USING btree (username);

-- table: user_unlocked_cosmetics
CREATE TABLE user_unlocked_cosmetics (
  id uuid NOT NULL DEFAULT gen_random_uuid(),
  user_id uuid NOT NULL,
  shop_item_id uuid NOT NULL,
  unlocked_at timestamp with time zone NOT NULL DEFAULT now(),
  unlock_reason text
);
ALTER TABLE user_unlocked_cosmetics ADD CONSTRAINT user_unlocked_cosmetics_pkey PRIMARY KEY (id);
ALTER TABLE user_unlocked_cosmetics ADD CONSTRAINT user_unlocked_cosmetics_user_id_shop_item_id_key UNIQUE (user_id, shop_item_id);
ALTER TABLE user_unlocked_cosmetics ADD CONSTRAINT user_unlocked_cosmetics_shop_item_id_fkey FOREIGN KEY (shop_item_id) REFERENCES shop_items(id) ON DELETE CASCADE;
ALTER TABLE user_unlocked_cosmetics ADD CONSTRAINT user_unlocked_cosmetics_user_id_fkey FOREIGN KEY (user_id) REFERENCES auth.users(id) ON DELETE CASCADE;
CREATE INDEX idx_user_unlocked_cosmetics_user ON public.user_unlocked_cosmetics USING btree (user_id);

-- table: weekly_break_plans
CREATE TABLE weekly_break_plans (
  id uuid NOT NULL DEFAULT uuid_generate_v4(),
  user_id uuid NOT NULL,
  week_start_date date NOT NULL,
  max_break_days integer NOT NULL,
  created_at timestamp with time zone DEFAULT now()
);
ALTER TABLE weekly_break_plans ADD CONSTRAINT weekly_break_plans_pkey PRIMARY KEY (id);
ALTER TABLE weekly_break_plans ADD CONSTRAINT weekly_break_plans_user_id_week_start_date_key UNIQUE (user_id, week_start_date);
ALTER TABLE weekly_break_plans ADD CONSTRAINT weekly_break_plans_user_id_fkey FOREIGN KEY (user_id) REFERENCES auth.users(id) ON DELETE CASCADE;
ALTER TABLE weekly_break_plans ADD CONSTRAINT weekly_break_plans_max_break_days_check CHECK (((max_break_days >= 0) AND (max_break_days <= 3)));
CREATE INDEX idx_weekly_break_plans_user_week ON public.weekly_break_plans USING btree (user_id, week_start_date);

-- table: weekly_commitments
CREATE TABLE weekly_commitments (
  id uuid NOT NULL DEFAULT gen_random_uuid(),
  user_id uuid NOT NULL,
  week_start_date date NOT NULL,
  week_end_date date NOT NULL,
  planned_workout_days integer NOT NULL,
  rest_tokens_total integer NOT NULL,
  rest_tokens_remaining integer NOT NULL DEFAULT 0,
  workouts_completed_this_week integer NOT NULL DEFAULT 0,
  rest_days_taken_this_week integer NOT NULL DEFAULT 0,
  goal_achieved boolean DEFAULT false,
  week_status text DEFAULT 'active'::text,
  created_at timestamp with time zone DEFAULT now(),
  updated_at timestamp with time zone DEFAULT now()
);
ALTER TABLE weekly_commitments ADD CONSTRAINT weekly_commitments_pkey PRIMARY KEY (id);
ALTER TABLE weekly_commitments ADD CONSTRAINT weekly_commitments_user_id_week_start_date_key UNIQUE (user_id, week_start_date);
ALTER TABLE weekly_commitments ADD CONSTRAINT weekly_commitments_user_id_fkey FOREIGN KEY (user_id) REFERENCES auth.users(id) ON DELETE CASCADE;
ALTER TABLE weekly_commitments ADD CONSTRAINT weekly_commitments_planned_workout_days_check CHECK (((planned_workout_days >= 4) AND (planned_workout_days <= 7)));
ALTER TABLE weekly_commitments ADD CONSTRAINT weekly_commitments_week_status_check CHECK ((week_status = ANY (ARRAY['active'::text, 'completed'::text, 'failed'::text])));
CREATE INDEX idx_weekly_commitments_active ON public.weekly_commitments USING btree (user_id, week_status) WHERE (week_status = 'active'::text);
CREATE INDEX idx_weekly_commitments_user_date ON public.weekly_commitments USING btree (user_id, week_start_date);

-- table: workout_invites
CREATE TABLE workout_invites (
  id uuid NOT NULL DEFAULT uuid_generate_v4(),
  sender_id uuid,
  recipient_id uuid,
  scheduled_for timestamp with time zone NOT NULL,
  message text,
  status text DEFAULT 'pending'::text,
  created_at timestamp with time zone DEFAULT now(),
  updated_at timestamp with time zone DEFAULT now()
);
ALTER TABLE workout_invites ADD CONSTRAINT workout_invites_pkey PRIMARY KEY (id);
ALTER TABLE workout_invites ADD CONSTRAINT workout_invites_recipient_id_fkey FOREIGN KEY (recipient_id) REFERENCES user_profiles(id) ON DELETE CASCADE;
ALTER TABLE workout_invites ADD CONSTRAINT workout_invites_sender_id_fkey FOREIGN KEY (sender_id) REFERENCES user_profiles(id) ON DELETE CASCADE;
ALTER TABLE workout_invites ADD CONSTRAINT workout_invites_status_check CHECK ((status = ANY (ARRAY['pending'::text, 'accepted'::text, 'declined'::text])));
CREATE INDEX idx_workout_invites_recipient ON public.workout_invites USING btree (recipient_id);
CREATE INDEX idx_workout_invites_status ON public.workout_invites USING btree (status);

-- table: workout_logs
CREATE TABLE workout_logs (
  id uuid NOT NULL DEFAULT gen_random_uuid(),
  user_id uuid NOT NULL,
  workout_date date NOT NULL,
  workout_time timestamp with time zone NOT NULL,
  template_id uuid,
  workout_name text NOT NULL,
  workout_category text NOT NULL,
  workout_emoji text DEFAULT '💪'::text,
  planned_duration_minutes integer,
  actual_duration_minutes integer,
  buddy_id uuid,
  team_id uuid,
  notes text,
  intensity_rating integer,
  created_at timestamp with time zone DEFAULT now()
);
ALTER TABLE workout_logs ADD CONSTRAINT workout_logs_pkey PRIMARY KEY (id);
ALTER TABLE workout_logs ADD CONSTRAINT workout_logs_buddy_id_fkey FOREIGN KEY (buddy_id) REFERENCES user_profiles(id) ON DELETE SET NULL;
ALTER TABLE workout_logs ADD CONSTRAINT workout_logs_team_id_fkey FOREIGN KEY (team_id) REFERENCES buddy_teams(id);
ALTER TABLE workout_logs ADD CONSTRAINT workout_logs_template_id_fkey FOREIGN KEY (template_id) REFERENCES workout_templates(id) ON DELETE SET NULL;
ALTER TABLE workout_logs ADD CONSTRAINT workout_logs_user_id_fkey FOREIGN KEY (user_id) REFERENCES user_profiles(id) ON DELETE CASCADE;
ALTER TABLE workout_logs ADD CONSTRAINT workout_logs_intensity_rating_check CHECK (((intensity_rating >= 1) AND (intensity_rating <= 5)));
CREATE INDEX idx_workout_logs_template ON public.workout_logs USING btree (template_id);
CREATE INDEX idx_workout_logs_user_date ON public.workout_logs USING btree (user_id, workout_date DESC);

-- table: workout_templates
CREATE TABLE workout_templates (
  id uuid NOT NULL DEFAULT gen_random_uuid(),
  name text NOT NULL,
  description text,
  category text NOT NULL,
  default_duration_minutes integer DEFAULT 30,
  emoji text DEFAULT '💪'::text,
  is_system_template boolean DEFAULT true,
  created_by uuid,
  created_at timestamp with time zone DEFAULT now()
);
ALTER TABLE workout_templates ADD CONSTRAINT workout_templates_pkey PRIMARY KEY (id);
ALTER TABLE workout_templates ADD CONSTRAINT workout_templates_created_by_fkey FOREIGN KEY (created_by) REFERENCES user_profiles(id) ON DELETE SET NULL;
ALTER TABLE workout_templates ADD CONSTRAINT workout_templates_category_check CHECK ((category = ANY (ARRAY['strength'::text, 'cardio'::text, 'hiit'::text, 'yoga'::text, 'sports'::text, 'other'::text, 'cycling'::text, 'swimming'::text, 'outside'::text, 'martial_arts'::text, 'recovery'::text])));

-- table: workouts
CREATE TABLE workouts (
  id uuid NOT NULL DEFAULT gen_random_uuid(),
  user_id uuid NOT NULL,
  buddy_id uuid,
  workout_type text NOT NULL,
  workout_date date NOT NULL,
  workout_time time without time zone NOT NULL,
  status text DEFAULT 'scheduled'::text,
  notes text,
  created_at timestamp with time zone DEFAULT now(),
  updated_at timestamp with time zone DEFAULT now(),
  buddy_status text DEFAULT 'pending'::text,
  planned_duration_minutes integer,
  actual_duration_minutes integer,
  workout_started_at timestamp with time zone,
  workout_completed_at timestamp with time zone,
  cancel_requested_by uuid,
  cancel_requested_at timestamp with time zone,
  started_by_user_id uuid,
  creator_joined boolean DEFAULT false,
  creator_joined_at timestamp with time zone,
  creator_popup_shown boolean DEFAULT false,
  creator_cancelled boolean DEFAULT false,
  buddy_cancelled boolean DEFAULT false,
  buddy_completed_at timestamp with time zone,
  creator_ready boolean DEFAULT false,
  buddy_ready boolean DEFAULT false,
  ready_expires_at timestamp with time zone
);
ALTER TABLE workouts ADD CONSTRAINT workouts_pkey PRIMARY KEY (id);
ALTER TABLE workouts ADD CONSTRAINT workouts_buddy_id_fkey FOREIGN KEY (buddy_id) REFERENCES user_profiles(id) ON DELETE SET NULL;
ALTER TABLE workouts ADD CONSTRAINT workouts_cancel_requested_by_fkey FOREIGN KEY (cancel_requested_by) REFERENCES auth.users(id) ON DELETE SET NULL;
ALTER TABLE workouts ADD CONSTRAINT workouts_started_by_user_id_fkey FOREIGN KEY (started_by_user_id) REFERENCES auth.users(id) ON DELETE SET NULL;
ALTER TABLE workouts ADD CONSTRAINT workouts_user_id_fkey FOREIGN KEY (user_id) REFERENCES user_profiles(id) ON DELETE CASCADE;
ALTER TABLE workouts ADD CONSTRAINT workouts_buddy_status_check CHECK ((buddy_status = ANY (ARRAY['pending'::text, 'accepted'::text, 'declined'::text])));
ALTER TABLE workouts ADD CONSTRAINT workouts_status_check CHECK ((status = ANY (ARRAY['scheduled'::text, 'in_progress'::text, 'completed'::text, 'cancelled'::text])));
CREATE INDEX idx_workouts_buddy_date ON public.workouts USING btree (buddy_id, workout_date);
CREATE INDEX idx_workouts_cancel_request ON public.workouts USING btree (cancel_requested_by) WHERE (cancel_requested_by IS NOT NULL);
CREATE INDEX idx_workouts_in_progress_buddy ON public.workouts USING btree (buddy_id, status) WHERE (status = 'in_progress'::text);
CREATE INDEX idx_workouts_started_by ON public.workouts USING btree (started_by_user_id) WHERE (started_by_user_id IS NOT NULL);
CREATE INDEX idx_workouts_user_date ON public.workouts USING btree (user_id, workout_date);

-- table: xp_transactions
CREATE TABLE xp_transactions (
  id uuid NOT NULL DEFAULT gen_random_uuid(),
  user_id uuid NOT NULL,
  amount integer NOT NULL,
  transaction_type text NOT NULL,
  description text,
  reference_id text,
  created_at timestamp with time zone NOT NULL DEFAULT now()
);
ALTER TABLE xp_transactions ADD CONSTRAINT xp_transactions_pkey PRIMARY KEY (id);
ALTER TABLE xp_transactions ADD CONSTRAINT xp_transactions_user_id_fkey FOREIGN KEY (user_id) REFERENCES auth.users(id) ON DELETE CASCADE;
CREATE INDEX idx_xp_transactions_user_id ON public.xp_transactions USING btree (user_id, created_at DESC);


-- ========================================================================
-- SECTION 2 -- PRE-VC FUNCTIONS (18 names / 19 signatures)
-- ========================================================================

-- function: backfill_team_checkins_on_creation()
CREATE OR REPLACE FUNCTION public.backfill_team_checkins_on_creation()
 RETURNS trigger
 LANGUAGE plpgsql
AS $function$
DECLARE
    today_date DATE := CURRENT_DATE;
    team_member RECORD;
    existing_checkin RECORD;
    team_streak_record RECORD;
    backfilled_count INT := 0;
BEGIN
    -- Only process for new buddy teams (not Coach Max teams)
    IF NEW.is_coach_max_team = false THEN
        
        -- Wait a moment for team_members and team_streaks to be created
        -- (This is a bit hacky but necessary due to transaction timing)
        PERFORM pg_sleep(0.5);
        
        -- Get the team streak ID for this team
        SELECT * INTO team_streak_record
        FROM team_streaks
        WHERE team_id = NEW.id
        AND is_active = true
        LIMIT 1;
        
        -- If we found a team streak, process backfills
        IF team_streak_record.id IS NOT NULL THEN
            
            -- For each team member
            FOR team_member IN 
                SELECT * FROM team_members 
                WHERE team_id = NEW.id
                AND user_id != '00000000-0000-0000-0000-000000000001' -- Exclude Coach Max
            LOOP
                -- Check if this user has already checked in today (in any team)
                SELECT * INTO existing_checkin
                FROM daily_team_checkins
                WHERE user_id = team_member.user_id
                AND check_in_date = today_date
                LIMIT 1;
                
                -- If they have checked in today, backfill to this new team
                IF existing_checkin.id IS NOT NULL THEN
                    -- Check if not already backfilled
                    IF NOT EXISTS (
                        SELECT 1 FROM daily_team_checkins 
                        WHERE team_streak_id = team_streak_record.id
                        AND user_id = team_member.user_id
                        AND check_in_date = today_date
                    ) THEN
                        INSERT INTO daily_team_checkins (
                            team_streak_id,
                            user_id,
                            check_in_date,
                            check_in_time
                        ) VALUES (
                            team_streak_record.id,
                            team_member.user_id,
                            today_date,
                            existing_checkin.check_in_time
                        );
                        
                        backfilled_count := backfilled_count + 1;
                    END IF;
                END IF;
            END LOOP;
            
            -- If both members had checked in, update the streak
            IF backfilled_count >= 2 THEN
                UPDATE team_streaks
                SET 
                    current_streak = 1,
                    longest_streak = 1,
                    last_workout_date = today_date,
                    updated_at = NOW()
                WHERE id = team_streak_record.id;
            END IF;
            
        END IF;
    END IF;
    
    RETURN NEW;
END;
$function$
;

-- function: can_take_rest_day(p_user_id uuid)
CREATE OR REPLACE FUNCTION public.can_take_rest_day(p_user_id uuid)
 RETURNS boolean
 LANGUAGE plpgsql
AS $function$
DECLARE
  v_rest_tokens INTEGER;
  v_current_time TIME;
  v_cutoff_time TIME := '20:00:00';
BEGIN
  -- Check time restriction (6 AM to 8 PM)
  v_current_time := CURRENT_TIME;
  IF v_current_time < '06:00:00' OR v_current_time > v_cutoff_time THEN
    RETURN FALSE;
  END IF;
  
  -- Check if user has rest tokens available
  SELECT rest_tokens_remaining INTO v_rest_tokens
  FROM weekly_commitments
  WHERE user_id = p_user_id
    AND week_start_date <= CURRENT_DATE
    AND week_end_date >= CURRENT_DATE
    AND week_status = 'active';
  
  RETURN (v_rest_tokens > 0);
END;
$function$
;

-- function: check_duplicate_team()
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
$function$
;

-- function: check_team_streak_status(p_team_id uuid, p_check_date date)
CREATE OR REPLACE FUNCTION public.check_team_streak_status(p_team_id uuid, p_check_date date)
 RETURNS boolean
 LANGUAGE plpgsql
AS $function$
DECLARE
  v_total_members INTEGER;
  v_checked_in_members INTEGER;
BEGIN
  SELECT COUNT(*) INTO v_total_members
  FROM team_members
  WHERE team_id = p_team_id AND role != 'coach_max';
  
  SELECT COUNT(DISTINCT dtc.user_id) INTO v_checked_in_members
  FROM daily_team_checkins dtc
  JOIN team_streaks ts ON dtc.team_streak_id = ts.id
  WHERE ts.team_id = p_team_id 
    AND dtc.check_in_date = p_check_date
    AND dtc.user_id != '00000000-0000-0000-0000-000000000001'::UUID;
  
  RETURN v_checked_in_members >= v_total_members;
END;
$function$
;

-- function: cleanup_workout_sessions()
CREATE OR REPLACE FUNCTION public.cleanup_workout_sessions()
 RETURNS trigger
 LANGUAGE plpgsql
AS $function$
BEGIN
  -- When a workout is cancelled or completed, delete related sessions
  IF NEW.status IN ('cancelled', 'completed') AND OLD.status = 'in_progress' THEN
    DELETE FROM active_checkin_sessions 
    WHERE workout_id = NEW.id;
    
    RAISE NOTICE 'Cleaned up sessions for workout %', NEW.id;
  END IF;
  
  RETURN NEW;
END;
$function$
;

-- function: create_buddy_workout_sessions(p_creator_id uuid, p_buddy_id uuid, p_workout_id uuid, p_started_at timestamp with time zone, p_workout_type text, p_workout_emoji text, p_planned_duration integer)
CREATE OR REPLACE FUNCTION public.create_buddy_workout_sessions(p_creator_id uuid, p_buddy_id uuid, p_workout_id uuid, p_started_at timestamp with time zone, p_workout_type text, p_workout_emoji text, p_planned_duration integer)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
BEGIN
  -- Insert session for creator
  INSERT INTO active_checkin_sessions (
    user_id, started_at, workout_type, workout_emoji, 
    planned_duration, linked_workout_id
  ) VALUES (
    p_creator_id, p_started_at, p_workout_type, 
    p_workout_emoji, p_planned_duration, p_workout_id
  )
  ON CONFLICT (user_id) DO UPDATE SET
    started_at = EXCLUDED.started_at,
    workout_type = EXCLUDED.workout_type,
    workout_emoji = EXCLUDED.workout_emoji,
    planned_duration = EXCLUDED.planned_duration,
    linked_workout_id = EXCLUDED.linked_workout_id;

  -- Insert session for buddy
  INSERT INTO active_checkin_sessions (
    user_id, started_at, workout_type, workout_emoji, 
    planned_duration, linked_workout_id
  ) VALUES (
    p_buddy_id, p_started_at, p_workout_type, 
    p_workout_emoji, p_planned_duration, p_workout_id
  )
  ON CONFLICT (user_id) DO UPDATE SET
    started_at = EXCLUDED.started_at,
    workout_type = EXCLUDED.workout_type,
    workout_emoji = EXCLUDED.workout_emoji,
    planned_duration = EXCLUDED.planned_duration,
    linked_workout_id = EXCLUDED.linked_workout_id;
END;
$function$
;

-- function: get_current_weekly_commitment(p_user_id uuid)
CREATE OR REPLACE FUNCTION public.get_current_weekly_commitment(p_user_id uuid)
 RETURNS TABLE(commitment_id uuid, planned_days integer, rest_tokens integer, workouts_completed integer, goal_achieved boolean)
 LANGUAGE plpgsql
AS $function$
BEGIN
  RETURN QUERY
  SELECT 
    id,
    planned_workout_days,
    rest_tokens_remaining,
    workouts_completed_this_week,
    weekly_commitments.goal_achieved
  FROM weekly_commitments
  WHERE user_id = p_user_id
    AND week_start_date <= CURRENT_DATE
    AND week_end_date >= CURRENT_DATE
    AND week_status = 'active'
  LIMIT 1;
END;
$function$
;

-- function: get_level_for_xp(total_xp integer)
CREATE OR REPLACE FUNCTION public.get_level_for_xp(total_xp integer)
 RETURNS integer
 LANGUAGE sql
 STABLE
AS $function$
  SELECT COALESCE(
    (SELECT level FROM level_definitions
     WHERE xp_required <= total_xp
     ORDER BY xp_required DESC
     LIMIT 1),
    1
  );
$function$
;

-- function: get_random_team_name()
CREATE OR REPLACE FUNCTION public.get_random_team_name()
 RETURNS TABLE(name text, emoji text)
 LANGUAGE plpgsql
AS $function$
BEGIN
  RETURN QUERY
  SELECT team_names.name, team_names.emoji
  FROM team_names
  ORDER BY RANDOM()
  LIMIT 1;
END;
$function$
;

-- function: get_team_checkin_order(p_team_streak_id uuid, p_check_date date)
CREATE OR REPLACE FUNCTION public.get_team_checkin_order(p_team_streak_id uuid, p_check_date date)
 RETURNS TABLE(user_id uuid, display_name text, check_in_time timestamp with time zone, check_order integer)
 LANGUAGE plpgsql
AS $function$
BEGIN
  RETURN QUERY
  SELECT 
    dtc.user_id,
    up.display_name,
    dtc.check_in_time,
    ROW_NUMBER() OVER (ORDER BY dtc.check_in_time)::INTEGER as check_order
  FROM daily_team_checkins dtc
  JOIN user_profiles up ON dtc.user_id = up.id
  WHERE dtc.team_streak_id = p_team_streak_id
    AND dtc.check_in_date = p_check_date
  ORDER BY dtc.check_in_time;
END;
$function$
;

-- function: get_user_team_ids()
CREATE OR REPLACE FUNCTION public.get_user_team_ids()
 RETURNS SETOF uuid
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  SELECT team_id FROM public.team_members WHERE user_id = auth.uid();
$function$
;

-- function: get_user_team_ids(target_user_id uuid)
CREATE OR REPLACE FUNCTION public.get_user_team_ids(target_user_id uuid)
 RETURNS TABLE(team_id uuid)
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
BEGIN
  RETURN QUERY
  SELECT tm.team_id 
  FROM team_members tm
  WHERE tm.user_id = target_user_id;
END;
$function$
;

-- function: get_workouts_awaiting_creator_join(creator_id uuid)
CREATE OR REPLACE FUNCTION public.get_workouts_awaiting_creator_join(creator_id uuid)
 RETURNS TABLE(workout_id uuid, workout_type text, buddy_name text, planned_duration_minutes integer, started_at timestamp with time zone, join_window_end timestamp with time zone, time_remaining_seconds integer, popup_already_shown boolean)
 LANGUAGE plpgsql
 SECURITY DEFINER
AS $function$
BEGIN
  RETURN QUERY
  SELECT 
    w.id as workout_id,
    w.workout_type,
    up.display_name as buddy_name,
    w.planned_duration_minutes,
    w.workout_started_at as started_at,
    -- Join window = started_at + (planned_duration / 4)
    w.workout_started_at + (w.planned_duration_minutes * INTERVAL '1 minute' / 4) as join_window_end,
    -- Time remaining in seconds
    EXTRACT(EPOCH FROM (
      (w.workout_started_at + (w.planned_duration_minutes * INTERVAL '1 minute' / 4)) - NOW()
    ))::INTEGER as time_remaining_seconds,
    COALESCE(w.creator_popup_shown, FALSE) as popup_already_shown
  FROM workouts w
  LEFT JOIN user_profiles up ON up.id = w.buddy_id
  WHERE w.user_id = creator_id
    AND w.status = 'in_progress'
    AND w.started_by_user_id = w.buddy_id  -- Buddy started it
    AND (w.creator_joined IS NULL OR w.creator_joined = FALSE)  -- Creator hasn't joined
    AND w.workout_started_at IS NOT NULL;
END;
$function$
;

-- function: is_user_in_active_workout(check_user_id uuid)
CREATE OR REPLACE FUNCTION public.is_user_in_active_workout(check_user_id uuid)
 RETURNS boolean
 LANGUAGE plpgsql
 SECURITY DEFINER
AS $function$
DECLARE
  has_active BOOLEAN;
BEGIN
  SELECT EXISTS (
    SELECT 1 FROM workouts w
    WHERE w.status = 'in_progress'
    AND (
      -- User started this workout
      (w.started_by_user_id = check_user_id)
      OR
      -- User is creator and has joined
      (w.user_id = check_user_id AND w.creator_joined = TRUE)
      OR
      -- User has an active check-in session
      EXISTS (
        SELECT 1 FROM active_checkin_sessions acs
        WHERE acs.user_id = check_user_id
        AND acs.linked_workout_id = w.id
      )
    )
  ) INTO has_active;
  
  RETURN has_active;
END;
$function$
;

-- function: notify_friend_accepted()
CREATE OR REPLACE FUNCTION public.notify_friend_accepted()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
AS $function$
DECLARE
  v_accepter_name TEXT;
BEGIN
  IF NEW.status = 'accepted' AND OLD.status = 'pending' THEN
    SELECT COALESCE(display_name, username, 'Your friend') INTO v_accepter_name
    FROM user_profiles WHERE id = NEW.friend_id;

    PERFORM net.http_post(
      url := 'https://jwpbunulswiihkzpjopy.supabase.co/functions/v1/send-notification',
      headers := '{"Content-Type": "application/json", "Authorization": "Bearer <ANON_KEY_REDACTED_see_.env>"}'::jsonb,
      body := json_build_object(
        'user_id', NEW.user_id,
        'title', '🎉 Friend Request Accepted!',
        'body', v_accepter_name || ' is now your gym buddy!',
        'type', 'friend_accepted',
        'reference_id', NEW.id::text
      )::jsonb
    );
  END IF;
  RETURN NEW;
END;
$function$
;

-- function: notify_friend_request()
CREATE OR REPLACE FUNCTION public.notify_friend_request()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
AS $function$
DECLARE
  v_requester_name TEXT;
BEGIN
  SELECT COALESCE(display_name, username, 'Someone') INTO v_requester_name
  FROM user_profiles WHERE id = NEW.user_id;

  PERFORM net.http_post(
    url := 'https://jwpbunulswiihkzpjopy.supabase.co/functions/v1/send-notification',
    headers := '{"Content-Type": "application/json", "Authorization": "Bearer <ANON_KEY_REDACTED_see_.env>"}'::jsonb,
    body := json_build_object(
      'user_id', NEW.friend_id,
      'title', '👋 New Friend Request!',
      'body', v_requester_name || ' wants to be your gym buddy!',
      'type', 'friend_request',
      'reference_id', NEW.id::text
    )::jsonb
  );
  RETURN NEW;
END;
$function$
;

-- function: notify_workout_invite()
CREATE OR REPLACE FUNCTION public.notify_workout_invite()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
AS $function$
DECLARE
  v_sender_name TEXT;
BEGIN
  SELECT COALESCE(display_name, username, 'Your buddy') INTO v_sender_name
  FROM user_profiles WHERE id = NEW.sender_id;

  PERFORM net.http_post(
    url := 'https://jwpbunulswiihkzpjopy.supabase.co/functions/v1/send-notification',
    headers := '{"Content-Type": "application/json", "Authorization": "Bearer <ANON_KEY_REDACTED_see_.env>"}'::jsonb,
    body := json_build_object(
      'user_id', NEW.recipient_id,
      'title', '🏋️ Workout Invite!',
      'body', v_sender_name || ' invited you to a workout!',
      'type', 'workout_invite',
      'reference_id', NEW.id::text
    )::jsonb
  );
  RETURN NEW;
END;
$function$
;

-- function: notify_workout_invite_response()
CREATE OR REPLACE FUNCTION public.notify_workout_invite_response()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
AS $function$
DECLARE
  v_recipient_name TEXT;
BEGIN
  IF NEW.status IN ('accepted', 'declined') AND OLD.status = 'pending' THEN
    SELECT COALESCE(display_name, username, 'Your buddy') INTO v_recipient_name
    FROM user_profiles WHERE id = NEW.recipient_id;

    PERFORM net.http_post(
      url := 'https://jwpbunulswiihkzpjopy.supabase.co/functions/v1/send-notification',
      headers := '{"Content-Type": "application/json", "Authorization": "Bearer <ANON_KEY_REDACTED_see_.env>"}'::jsonb,
      body := json_build_object(
        'user_id', NEW.sender_id,
        'title', CASE WHEN NEW.status = 'accepted' THEN '✅ Workout Accepted!' ELSE '❌ Workout Declined' END,
        'body', CASE WHEN NEW.status = 'accepted' 
          THEN v_recipient_name || ' is joining your workout!' 
          ELSE v_recipient_name || ' can''t make the workout.' END,
        'type', CASE WHEN NEW.status = 'accepted' THEN 'workout_accepted' ELSE 'workout_declined' END,
        'reference_id', NEW.id::text
      )::jsonb
    );
  END IF;
  RETURN NEW;
END;
$function$
;

-- function: update_updated_at_column()
CREATE OR REPLACE FUNCTION public.update_updated_at_column()
 RETURNS trigger
 LANGUAGE plpgsql
AS $function$
BEGIN
  NEW.updated_at = NOW();
  RETURN NEW;
END;
$function$
;


-- ========================================================================
-- SECTION 3 -- PRE-VC TRIGGERS (10)
-- ========================================================================

CREATE TRIGGER trigger_backfill_checkins_on_team_creation AFTER INSERT ON public.buddy_teams FOR EACH ROW EXECUTE FUNCTION backfill_team_checkins_on_creation();
CREATE TRIGGER on_buddy_checkin AFTER INSERT ON public.daily_team_checkins FOR EACH ROW EXECUTE FUNCTION notify_buddy_checkin();
CREATE TRIGGER on_friend_accepted AFTER UPDATE ON public.friendships FOR EACH ROW EXECUTE FUNCTION notify_friend_accepted();
CREATE TRIGGER on_friend_request AFTER INSERT ON public.friendships FOR EACH ROW WHEN ((new.status = 'pending'::text)) EXECUTE FUNCTION notify_friend_request();
CREATE TRIGGER prevent_duplicate_teams BEFORE INSERT ON public.team_members FOR EACH ROW EXECUTE FUNCTION check_duplicate_team();
CREATE TRIGGER on_streak_update AFTER UPDATE ON public.team_streaks FOR EACH ROW EXECUTE FUNCTION notify_streak_update();
CREATE TRIGGER update_team_streaks_updated_at BEFORE UPDATE ON public.team_streaks FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();
CREATE TRIGGER on_workout_invite AFTER INSERT ON public.workout_invites FOR EACH ROW WHEN ((new.status = 'pending'::text)) EXECUTE FUNCTION notify_workout_invite();
CREATE TRIGGER on_workout_invite_response AFTER UPDATE ON public.workout_invites FOR EACH ROW EXECUTE FUNCTION notify_workout_invite_response();
CREATE TRIGGER trigger_cleanup_workout_sessions AFTER UPDATE ON public.workouts FOR EACH ROW EXECUTE FUNCTION cleanup_workout_sessions();
