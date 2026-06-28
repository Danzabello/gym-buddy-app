CREATE OR REPLACE FUNCTION public.verify_achievement_progress(
  p_achievement_id text
) RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
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

  ELSIF p_achievement_id IN ('first_rep','warm_up_done','ten_strong','fifty_club','century_lifter') THEN
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
$$;
