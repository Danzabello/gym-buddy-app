-- Rollback for 20261113231829_drop_legacy_objects.sql.
-- Table DDL is copied from dev/pre_vc_schema_baseline_20260720.sql (lines 547-569, 140-153, 199-224, 405-415),
-- which records these four tables as of 2026-07-20. weekly_commitments first: daily_check_ins has a foreign key to it.

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

-- ── team_names seed rows (live, 2026-11-12) ──
INSERT INTO public.team_names (id, name, category, emoji, created_at) VALUES
('4bb5f594-f07e-4a84-81cc-4683ead2d534','Athletic Academy','serious','🎯','2025-10-15 16:04:21.227846+00'),
('08ed7513-24ec-4a47-ab8a-4da0fcef2f08','Bench Press Besties','funny','🏋️','2025-10-15 16:04:21.227846+00'),
('1b839db4-ffd8-4a8e-807c-af6086c17093','Buff Buddies','silly','🦸','2025-10-15 16:04:21.227846+00'),
('b90c7399-6995-4fc2-8492-a12da3ce06c9','Burpee Buddies','funny','🤸','2025-10-15 16:04:21.227846+00'),
('65f32d7f-c329-46bd-b155-1b54f4c93ea5','Cardio Criminals','funny','🏃','2025-10-15 16:04:21.227846+00'),
('091f14a7-d6da-48ca-8d95-ab22a568c6a5','Champions Circle','serious','👑','2025-10-15 16:04:21.227846+00'),
('b8eea6af-5bb6-402b-afd9-a11d59187ba3','Dumbbell Divas','silly','💅','2025-10-15 16:04:21.227846+00'),
('8153b290-58d7-4db1-b8c8-82b3e3dd711a','Elite Training','serious','💪','2025-10-15 16:04:21.227846+00'),
('db81d7f3-8617-4bed-987b-b2709672f08e','Endurance Alliance','serious','🔥','2025-10-15 16:04:21.227846+00'),
('9c6d904d-9c98-4038-bfb4-ec4e567a8e2c','Fitness Elite','serious','🏅','2025-10-15 16:04:21.227846+00'),
('f3e83bf2-2a8a-4cfd-9d31-8c3c3336818d','Fitness Freaks','silly','🤡','2025-10-15 16:04:21.227846+00'),
('22a30d52-0b49-4c3a-84d8-b30d5446f592','Flex Force','funny','💪','2025-10-15 16:04:21.227846+00'),
('90e004e9-6dbe-456b-bdd1-556e14d48d52','Gains Goblins','funny','👹','2025-10-15 16:04:21.227846+00'),
('39f401bf-126b-4988-b28b-756fd1bd21d5','Gym Jammers','silly','🎵','2025-10-15 16:04:21.227846+00'),
('f099a7c0-b4d2-4819-bbca-6864dd5bac20','Gym Rats United','funny','🐀','2025-10-15 16:04:21.227846+00'),
('e7305862-753c-4eb9-b7cf-fc87ac999aca','Iron Warriors','serious','⚔️','2025-10-15 16:04:21.227846+00'),
('17538a3d-7fe2-455c-9849-cff3e5623765','Lift Legends','funny','🏆','2025-10-15 16:04:21.227846+00'),
('7fb1ae76-7cec-4bac-a65e-6938eb3fc2d4','Muscle Maniacs','silly','🤪','2025-10-15 16:04:21.227846+00'),
('65f4a79a-cd10-40d1-8df6-e6c27c638bc3','Peak Performance','serious','⛰️','2025-10-15 16:04:21.227846+00'),
('91f63f5e-1ee5-40b0-8536-67ba0147dfe7','Plank Pirates','silly','🏴‍☠️','2025-10-15 16:04:21.227846+00'),
('f6ca3e13-93b7-4c07-b2f0-9c0f8c776bca','Power Partners','serious','⚡','2025-10-15 16:04:21.227846+00'),
('da480ee7-4c31-4ce4-a46e-488263004cdb','Protein Pals','funny','🥤','2025-10-15 16:04:21.227846+00'),
('34e382fa-f676-4428-8c05-f2a3134f2380','Squat Squad','funny','🍑','2025-10-15 16:04:21.227846+00'),
('deb2b7c6-573f-4d47-876b-8b795a18a2b8','Strength Society','serious','💎','2025-10-15 16:04:21.227846+00'),
('55b68f84-7e20-4ac9-af85-97c6dfa62fdf','Sweat & Tears','silly','😭','2025-10-15 16:04:21.227846+00'),
('733506b8-f654-4a1d-aa5f-135c0433442a','Swole Patrol','funny','💪','2025-10-15 16:04:21.227846+00'),
('b7f225ce-ea5e-4be1-b12c-d9607f27fe7d','Thunder Thighs','silly','⚡','2025-10-15 16:04:21.227846+00'),
('5c87f159-2167-40e9-b87d-a7082e0c6c9f','Treadmill Troopers','silly','🚀','2025-10-15 16:04:21.227846+00'),
('58419258-060f-4a31-bcdb-34a80667fea0','Victory Crew','serious','🏆','2025-10-15 16:04:21.227846+00'),
('36a52920-abfa-42b7-b181-c5488a7591b6','Workout Weirdos','silly','👽','2025-10-15 16:04:21.227846+00');

-- ── RLS as it was: enabled on all four, with the 13 policies copied from
--    supabase/migrations/20260628000000_baseline_rls_policies_snapshot.sql (no later migration altered them) ──
ALTER TABLE public.check_ins ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.daily_check_ins ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.weekly_commitments ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.team_names ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON public.check_ins, public.daily_check_ins, public.weekly_commitments, public.team_names FROM anon, authenticated;
-- Client grants are not restored: nothing reads these tables, and the grants at drop time were not captured.
-- The policies below are back in the catalog but admit nothing until a grant is added under the CLAUDE.md
-- table-grant rule.
CREATE POLICY "Users can delete own check-ins" ON public.check_ins
  FOR DELETE TO public USING (auth.uid() = user_id);
CREATE POLICY "Users can create own check-ins" ON public.check_ins
  FOR INSERT TO public WITH CHECK (auth.uid() = user_id);
CREATE POLICY "Users can view own check-ins" ON public.check_ins
  FOR SELECT TO public USING (auth.uid() = user_id);
CREATE POLICY "Users can update own check-ins" ON public.check_ins
  FOR UPDATE TO public USING (auth.uid() = user_id);
CREATE POLICY "Users can delete their own check-ins" ON public.daily_check_ins
  FOR DELETE TO public USING (auth.uid() = user_id);
CREATE POLICY "Users can insert their own check-ins" ON public.daily_check_ins
  FOR INSERT TO public WITH CHECK (auth.uid() = user_id);
CREATE POLICY "Users can view their own check-ins" ON public.daily_check_ins
  FOR SELECT TO public USING ((auth.uid() = user_id) OR (auth.uid() = buddy_id));
CREATE POLICY "Users can update their own check-ins" ON public.daily_check_ins
  FOR UPDATE TO public USING (auth.uid() = user_id);
CREATE POLICY "Anyone can view team names" ON public.team_names
  FOR SELECT TO public USING (true);
CREATE POLICY "Users can delete their own weekly commitments" ON public.weekly_commitments
  FOR DELETE TO public USING (auth.uid() = user_id);
CREATE POLICY "Users can insert their own weekly commitments" ON public.weekly_commitments
  FOR INSERT TO public WITH CHECK (auth.uid() = user_id);
CREATE POLICY "Users can view their own weekly commitments" ON public.weekly_commitments
  FOR SELECT TO public USING (auth.uid() = user_id);
CREATE POLICY "Users can update their own weekly commitments" ON public.weekly_commitments
  FOR UPDATE TO public USING (auth.uid() = user_id);

-- ── functions (pg_get_functiondef from live, 2026-11-12; CRLF line ends normalised) ──
CREATE OR REPLACE FUNCTION public.can_take_rest_day(p_user_id uuid)
 RETURNS boolean
 LANGUAGE plpgsql
 SET search_path TO 'public'
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
$function$;

CREATE OR REPLACE FUNCTION public.get_current_weekly_commitment(p_user_id uuid)
 RETURNS TABLE(commitment_id uuid, planned_days integer, rest_tokens integer, workouts_completed integer, goal_achieved boolean)
 LANGUAGE plpgsql
 SET search_path TO 'public'
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
$function$;

CREATE OR REPLACE FUNCTION public.get_random_team_name()
 RETURNS TABLE(name text, emoji text)
 LANGUAGE plpgsql
 SET search_path TO 'public'
AS $function$
BEGIN
  RETURN QUERY
  SELECT team_names.name, team_names.emoji
  FROM team_names
  ORDER BY RANDOM()
  LIMIT 1;
END;
$function$;

CREATE OR REPLACE FUNCTION public.check_team_streak_status(p_team_id uuid, p_check_date date)
 RETURNS boolean
 LANGUAGE plpgsql
 SET search_path TO 'public'
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
$function$;

CREATE OR REPLACE FUNCTION public.get_team_checkin_order(p_team_streak_id uuid, p_check_date date)
 RETURNS TABLE(user_id uuid, display_name text, check_in_time timestamp with time zone, check_order integer)
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
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
    -- same rows the daily_team_checkins SELECT policy shows the caller
    AND (dtc.user_id = auth.uid()
         OR EXISTS (SELECT 1 FROM team_streaks ts
                    JOIN team_members tm ON tm.team_id = ts.team_id
                    WHERE ts.id = dtc.team_streak_id AND tm.user_id = auth.uid())
         OR EXISTS (SELECT 1 FROM friendships f
                    WHERE f.status = 'accepted'
                      AND ((f.user_id = auth.uid() AND f.friend_id = dtc.user_id)
                        OR (f.friend_id = auth.uid() AND f.user_id = dtc.user_id))))
  ORDER BY dtc.check_in_time;
END;
$function$;

CREATE OR REPLACE FUNCTION public.delete_own_account()
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
BEGIN
  DELETE FROM user_profiles WHERE id = auth.uid();
  DELETE FROM auth.users WHERE id = auth.uid();
END;
$function$;

-- ACLs as they were: authenticated + service_role on the first five, service_role only on delete_own_account.
REVOKE EXECUTE ON FUNCTION public.can_take_rest_day(uuid), public.get_current_weekly_commitment(uuid),
  public.get_random_team_name(), public.check_team_streak_status(uuid, date),
  public.get_team_checkin_order(uuid, date), public.delete_own_account() FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.can_take_rest_day(uuid), public.get_current_weekly_commitment(uuid),
  public.get_random_team_name(), public.check_team_streak_status(uuid, date),
  public.get_team_checkin_order(uuid, date) TO authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.delete_own_account() TO service_role;
