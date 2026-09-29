-- ══════════════════════════════════════════════════════════════
-- avatar_unlock_paths
-- Adds the 5-spoke Avatar Unlock Tree: Level (Wolf/Lion), Workout
-- (Eagle/Gorilla), Co-op (Bison/Mammoth), Special (Robot/Seasonal).
-- Social path is a client-only "coming soon" placeholder — no DB rows.
-- ══════════════════════════════════════════════════════════════

-- ── 1. Tag columns on shop_items so the tree can select exactly its
--      8 rows out of the shared 'avatar' category (which also holds
--      unrelated premium skins: Alien/Dragon/Ninja/Phoenix/Unicorn).
ALTER TABLE public.shop_items
  ADD COLUMN IF NOT EXISTS unlock_path text,
  ADD COLUMN IF NOT EXISTS unlock_tier smallint;

ALTER TABLE public.shop_items
  ADD CONSTRAINT shop_items_unlock_path_check
  CHECK (unlock_path IS NULL OR unlock_path IN ('level', 'workout', 'coop', 'special'));

ALTER TABLE public.shop_items
  ADD CONSTRAINT shop_items_unlock_tier_check
  CHECK (unlock_tier IS NULL OR unlock_tier IN (1, 2));

-- ── 2. New achievements (sort_order continues from live max of 470) ──
INSERT INTO public.achievements
  (id, name, description, category, icon, rarity, xp_reward, coin_reward, target_value, sort_order)
VALUES
  ('workout_path_eagle',   'Eagle',   'Complete 25 workouts to unlock the Eagle avatar',
   'avatar_unlock', '🦅', 'common', 0, 0, 25,  471),
  ('workout_path_gorilla', 'Gorilla', 'Complete 100 workouts to unlock the Gorilla avatar',
   'avatar_unlock', '🦍', 'rare',   0, 0, 100, 472),
  ('coop_path_bison',      'Bison',   'Reach a 30-day team streak to unlock the Bison avatar',
   'avatar_unlock', '🦬', 'common', 0, 0, 30,  473),
  ('coop_path_mammoth',    'Mammoth', 'Reach a 100-day team streak to unlock the Mammoth avatar',
   'avatar_unlock', '🦣', 'rare',   0, 0, 100, 474),
  ('special_path_robot',   'Robot',   'Check in with Coach Max 10 times to unlock the Robot avatar',
   'avatar_unlock', '🤖', 'common', 0, 0, 10,  475);

-- ── 3. shop_items rows for the tree ──────────────────────────────
-- Level path — gated by unlock_level only, no achievement.
INSERT INTO public.shop_items
  (name, description, category, cost, emoji, asset_id, is_available, unlock_level, unlock_path, unlock_tier)
VALUES
  ('Wolf', 'Speed & loyalty — unlocked at level 5',  'avatar', 350, '🐺', 'avatar_wolf', true, 5,  'level', 1),
  ('Lion', 'Power & courage — unlocked at level 15',  'avatar', 550, '🦁', 'avatar_lion', true, 15, 'level', 2);

-- Workout path — gated by the achievements above.
INSERT INTO public.shop_items
  (name, description, category, cost, emoji, asset_id, is_available, unlock_achievement_id, unlock_path, unlock_tier)
VALUES
  ('Eagle',   'Reach 25 completed workouts', 'avatar', 350, '🦅', 'avatar_eagle',   true, 'workout_path_eagle',   'workout', 1),
  ('Gorilla', 'Reach 100 completed workouts', 'avatar', 650, '🦍', 'avatar_gorilla', true, 'workout_path_gorilla', 'workout', 2);

-- Co-op path — gated by the achievements above.
INSERT INTO public.shop_items
  (name, description, category, cost, emoji, asset_id, is_available, unlock_achievement_id, unlock_path, unlock_tier)
VALUES
  ('Bison',   'Reach a 30-day team streak',  'avatar', 350, '🦬', 'avatar_bison',   true, 'coop_path_bison',   'coop', 1),
  ('Mammoth', 'Reach a 100-day team streak', 'avatar', 650, '🦣', 'avatar_mammoth', true, 'coop_path_mammoth', 'coop', 2);

-- Special path, tier 1 — Robot already exists as a premium shop_items
-- row (id 784d3451-..., unlock_level 2, cost 350). We reuse that same
-- row rather than creating a duplicate, so it now also carries the
-- achievement gate for the unlock tree. Its existing unlock_level
-- purchase gate in the premium shop is untouched.
UPDATE public.shop_items
SET unlock_achievement_id = 'special_path_robot',
    unlock_path = 'special',
    unlock_tier = 1
WHERE id = '784d3451-c8d9-4586-b329-b012cb6c5444';

-- Special path, tier 2 — Seasonal creature. unlock_achievement_id is
-- intentionally left NULL: this tier is event-gated (a future rotating
-- seasonal-event feature), not achievement-gated. That unlock logic is
-- out of scope for this migration — do not wire it up here.
INSERT INTO public.shop_items
  (name, description, category, cost, emoji, asset_id, is_available, unlock_achievement_id, unlock_path, unlock_tier)
VALUES
  ('Seasonal Creature', 'Unlocked during a limited-time seasonal event',
   'avatar', 0, '❄️', 'avatar_seasonal_creature', false, NULL, 'special', 2);

-- ── 4. Extend verify_achievement_progress with the 5 new ids ────────
-- Same server-verified mechanism every other achievement uses: the
-- server re-derives real progress from source tables, client never
-- supplies a number. workout_path_eagle/gorilla reuse the existing
-- completed-workout-count branch; coop_path_bison/mammoth and
-- special_path_robot are new branches.
CREATE OR REPLACE FUNCTION public.verify_achievement_progress(p_achievement_id text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_caller uuid := auth.uid();
  v_category text;
  v_target integer;
  v_xp integer;
  v_coins integer;
  v_name text;
  v_real_progress integer;
  v_existing_unlocked timestamptz;
  v_clamped integer;
  v_did_unlock boolean;
  v_account_age_days integer;
  v_coach_max_id uuid := '00000000-0000-0000-0000-000000000001';
BEGIN
  IF v_caller IS NULL THEN
    RAISE EXCEPTION 'unauthenticated';
  END IF;

  SELECT category, target_value, xp_reward, coin_reward, name
  INTO v_category, v_target, v_xp, v_coins, v_name
  FROM achievements WHERE id = p_achievement_id;

  IF v_name IS NULL THEN
    RAISE EXCEPTION 'unknown_achievement';
  END IF;

  SELECT unlocked_at INTO v_existing_unlocked
  FROM user_achievements WHERE user_id = v_caller AND achievement_id = p_achievement_id;

  IF v_existing_unlocked IS NOT NULL THEN
    RETURN jsonb_build_object('already_unlocked', true);
  END IF;

  SELECT EXTRACT(DAY FROM now() - created_at)::integer INTO v_account_age_days
  FROM user_profiles WHERE id = v_caller;

  IF p_achievement_id IN ('first_flame','week_warrior','two_weeks_strong','month_machine','unstoppable','century_club','half_year_hero','year_of_the_beast') THEN
    SELECT COALESCE(MAX(ts.best_streak), 0) INTO v_real_progress
    FROM team_streaks ts
    JOIN team_members tm ON tm.team_id = ts.team_id
    WHERE tm.user_id = v_caller;

  ELSIF p_achievement_id = 'personal_best' THEN
    -- True schema limitation: there's no streak-history table, so
    -- "broke your own previous record" can't be re-derived after the
    -- fact. Using a reasonable, non-trivial, ungameable bar instead of
    -- leaving this fully client-trusted.
    SELECT (CASE WHEN COALESCE(MAX(ts.best_streak), 0) >= 2 THEN 1 ELSE 0 END) INTO v_real_progress
    FROM team_streaks ts
    JOIN team_members tm ON tm.team_id = ts.team_id
    WHERE tm.user_id = v_caller;

  ELSIF p_achievement_id IN ('first_rep','warm_up_done','ten_strong','fifty_club','century_lifter','workout_path_eagle','workout_path_gorilla') THEN
    SELECT COUNT(*) INTO v_real_progress
    FROM workouts WHERE user_id = v_caller AND status = 'completed';

  ELSIF p_achievement_id = 'marathon' THEN
    SELECT (CASE WHEN EXISTS(
      SELECT 1 FROM workouts
      WHERE user_id = v_caller AND status = 'completed' AND actual_duration_minutes > 90
    ) THEN 1 ELSE 0 END) INTO v_real_progress;

  ELSIF p_achievement_id = 'mixed_bag' THEN
    SELECT COUNT(DISTINCT workout_type) INTO v_real_progress
    FROM workouts WHERE user_id = v_caller AND status = 'completed';

  ELSIF p_achievement_id = 'iron_will' THEN
    WITH dates AS (
      SELECT DISTINCT (completed_at AT TIME ZONE 'utc')::date AS d
      FROM workouts
      WHERE user_id = v_caller AND status = 'completed' AND completed_at IS NOT NULL
    ), grouped AS (
      SELECT d, d - (row_number() OVER (ORDER BY d))::int AS grp FROM dates
    )
    SELECT COALESCE(MAX(cnt), 0) INTO v_real_progress
    FROM (SELECT count(*) AS cnt FROM grouped GROUP BY grp) sub;

  ELSIF p_achievement_id IN ('level_5','level_10','level_25','level_50','level_99') THEN
    SELECT COALESCE(level, 1) INTO v_real_progress FROM user_profiles WHERE id = v_caller;

  ELSIF p_achievement_id IN ('coin_collector','rich_in_spirit','loaded') THEN
    SELECT COALESCE(SUM(amount), 0) INTO v_real_progress
    FROM coin_transactions WHERE user_id = v_caller AND amount > 0;

  ELSIF p_achievement_id IN ('collector','hoarder','full_wardrobe') THEN
    SELECT COUNT(*) INTO v_real_progress FROM user_inventory WHERE user_id = v_caller;

  ELSIF p_achievement_id IN ('first_friend','squad_goals','social_butterfly','influencer') THEN
    SELECT COUNT(*) INTO v_real_progress
    FROM friendships WHERE status = 'accepted' AND (user_id = v_caller OR friend_id = v_caller);

  ELSIF p_achievement_id = 'connector' THEN
    SELECT COUNT(*) INTO v_real_progress FROM friendships WHERE user_id = v_caller;

  ELSIF p_achievement_id IN ('day_one','veteran','og_member') THEN
    v_real_progress := COALESCE(v_account_age_days, 0);

  ELSIF p_achievement_id = 'dynamic_duo' THEN
    SELECT (CASE WHEN EXISTS (
      SELECT 1
      FROM daily_team_checkins dtc1
      WHERE dtc1.user_id = v_caller
        AND dtc1.team_streak_id IN (
          SELECT ts.id FROM team_streaks ts
          JOIN team_members tm ON tm.team_id = ts.team_id
          JOIN buddy_teams bt ON bt.id = ts.team_id
          WHERE tm.user_id = v_caller AND bt.is_coach_max_team = false
        )
        AND EXISTS (
          SELECT 1 FROM daily_team_checkins dtc2
          WHERE dtc2.team_streak_id = dtc1.team_streak_id
            AND dtc2.check_in_date = dtc1.check_in_date
            AND dtc2.user_id <> v_caller
        )
    ) THEN 1 ELSE 0 END) INTO v_real_progress;

  ELSIF p_achievement_id = 'in_sync' THEN
    SELECT (CASE WHEN EXISTS (
      SELECT 1
      FROM daily_team_checkins dtc1
      JOIN daily_team_checkins dtc2
        ON dtc2.team_streak_id = dtc1.team_streak_id
       AND dtc2.check_in_date = dtc1.check_in_date
       AND dtc2.user_id <> dtc1.user_id
      WHERE dtc1.user_id = v_caller
        AND dtc1.team_streak_id IN (
          SELECT ts.id FROM team_streaks ts
          JOIN team_members tm ON tm.team_id = ts.team_id
          JOIN buddy_teams bt ON bt.id = ts.team_id
          WHERE tm.user_id = v_caller AND bt.is_coach_max_team = false
        )
        AND abs(extract(epoch from (dtc1.check_in_time - dtc2.check_in_time))) <= 1800
    ) THEN 1 ELSE 0 END) INTO v_real_progress;

  ELSIF p_achievement_id = 'early_bird' THEN
    -- Uses UTC, not phone-local time (server has no concept of the
    -- caller's timezone) -- a reasonable simplification for a
    -- low-stakes flavor achievement.
    SELECT (CASE WHEN EXISTS (
      SELECT 1 FROM daily_team_checkins
      WHERE user_id = v_caller
        AND team_streak_id IN (
          SELECT ts.id FROM team_streaks ts
          JOIN team_members tm ON tm.team_id = ts.team_id
          JOIN buddy_teams bt ON bt.id = ts.team_id
          WHERE tm.user_id = v_caller AND bt.is_coach_max_team = false
        )
        AND extract(hour from check_in_time at time zone 'utc') < 8
    ) THEN 1 ELSE 0 END) INTO v_real_progress;

  ELSIF p_achievement_id = 'night_owl' THEN
    SELECT (CASE WHEN EXISTS (
      SELECT 1 FROM daily_team_checkins
      WHERE user_id = v_caller
        AND team_streak_id IN (
          SELECT ts.id FROM team_streaks ts
          JOIN team_members tm ON tm.team_id = ts.team_id
          JOIN buddy_teams bt ON bt.id = ts.team_id
          WHERE tm.user_id = v_caller AND bt.is_coach_max_team = false
        )
        AND extract(hour from check_in_time at time zone 'utc') >= 22
    ) THEN 1 ELSE 0 END) INTO v_real_progress;

  ELSIF p_achievement_id IN ('reliable_partner','ride_or_die','power_couple') THEN
    WITH my_teams AS (
      SELECT ts.id AS streak_id
      FROM team_streaks ts
      JOIN team_members tm ON tm.team_id = ts.team_id
      JOIN buddy_teams bt ON bt.id = ts.team_id
      WHERE tm.user_id = v_caller AND bt.is_coach_max_team = false
    ),
    mutual_days AS (
      SELECT team_streak_id, check_in_date, count(*) AS n
      FROM daily_team_checkins
      WHERE team_streak_id IN (SELECT streak_id FROM my_teams)
      GROUP BY team_streak_id, check_in_date
      HAVING count(*) >= 2
    )
    SELECT COALESCE(MAX(cnt), 0) INTO v_real_progress
    FROM (SELECT team_streak_id, count(*) AS cnt FROM mutual_days GROUP BY team_streak_id) per_team;

  ELSIF p_achievement_id = 'coach_max_grad' THEN
    SELECT count(*) INTO v_real_progress
    FROM daily_team_checkins dtc
    WHERE dtc.user_id = v_caller
      AND dtc.team_streak_id IN (
        SELECT ts.id FROM team_streaks ts
        JOIN team_members tm ON tm.team_id = ts.team_id
        JOIN buddy_teams bt ON bt.id = ts.team_id
        WHERE tm.user_id = v_caller AND bt.is_coach_max_team = true
      );

  ELSIF p_achievement_id IN ('coop_path_bison','coop_path_mammoth') THEN
    -- Real co-op flavor (excludes the solo Coach Max team), current
    -- (not best) streak — matches the task spec's live "current_streak"
    -- gate rather than the lifetime-best gate the streak achievements use.
    SELECT COALESCE(MAX(ts.current_streak), 0) INTO v_real_progress
    FROM team_streaks ts
    JOIN team_members tm ON tm.team_id = ts.team_id
    JOIN buddy_teams bt ON bt.id = ts.team_id
    WHERE tm.user_id = v_caller AND bt.is_coach_max_team = false;

  ELSIF p_achievement_id = 'special_path_robot' THEN
    SELECT COUNT(*) INTO v_real_progress
    FROM coach_max_schedule
    WHERE user_id = v_caller AND has_checked_in = true;

  ELSE
    RAISE EXCEPTION 'achievement_not_server_verifiable: %', p_achievement_id;
  END IF;

  IF v_category IN ('streak', 'loyalty', 'coop') AND v_target > COALESCE(v_account_age_days, 0) + 1 THEN
    RETURN jsonb_build_object('blocked', true, 'reason', 'account_too_new', 'account_age_days', v_account_age_days);
  END IF;

  v_clamped := LEAST(v_real_progress, v_target);
  v_did_unlock := v_real_progress >= v_target;

  INSERT INTO user_achievements (user_id, achievement_id, progress, unlocked_at)
  VALUES (v_caller, p_achievement_id, v_clamped, CASE WHEN v_did_unlock THEN now() ELSE NULL END)
  ON CONFLICT (user_id, achievement_id) DO UPDATE
    SET progress = v_clamped,
        unlocked_at = CASE WHEN v_did_unlock THEN now() ELSE user_achievements.unlocked_at END;

  IF NOT v_did_unlock THEN
    RETURN jsonb_build_object('unlocked', false, 'progress', v_clamped, 'target', v_target);
  END IF;

  IF v_xp > 0 THEN
    PERFORM award_xp(v_caller, v_xp, 'achievement', 'achievement_' || p_achievement_id);
  END IF;
  IF v_coins > 0 THEN
    PERFORM award_coins(v_caller, v_coins, 'earn', 'Achievement: ' || v_name, 'achievement_' || p_achievement_id);
  END IF;

  RETURN jsonb_build_object('unlocked', true, 'xp_awarded', v_xp, 'coins_awarded', v_coins);
END;
$function$;
