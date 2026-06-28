-- ============================================================
-- PART 1: Clean up rokitest's 10 false-positive unlocks.
-- Confirmed via ledger: zero XP/coin transactions ever matched any
-- of these 10 achievement_ids -- the old code's reward-payment step
-- failed silently every time, so nothing to claw back. Just resetting
-- progress/unlocked_at to the real current values.
-- ============================================================
UPDATE user_achievements
SET unlocked_at = NULL, progress = 2
WHERE user_id = 'c4afd6cd-0a6e-4279-a2cb-21f26b9ce37f'
  AND achievement_id IN ('week_warrior','two_weeks_strong','month_machine','unstoppable','century_club','half_year_hero','year_of_the_beast');

UPDATE user_achievements
SET unlocked_at = NULL, progress = 9
WHERE user_id = 'c4afd6cd-0a6e-4279-a2cb-21f26b9ce37f'
  AND achievement_id IN ('ten_strong','fifty_club','century_lifter');

-- ============================================================
-- PART 2: Server-validated achievement unlocking.
-- Independently re-derives real progress from the actual underlying
-- tables for every category where that's feasible -- the client
-- never gets to supply a progress number for these. Closes the same
-- vulnerability class as the old S2 coin/XP bug, but for achievements.
--
-- Categories handled here: streak (first_flame + all 7 thresholds),
-- workout (count-based + marathon/mixed_bag/iron_will), level,
-- coin (also fixes SB-7's 'earn'-only filter), prestige, social,
-- loyalty.
--
-- Deliberately NOT handled here (left on the existing client-driven
-- + server-paid path from tonight's earlier S2/S3 fix): coop
-- achievements that depend on a specific check-in event's timing
-- (dynamic_duo, in_sync, early_bird, night_owl), personal_best
-- (a moment-in-time comparison, not a persistent state),
-- coach_max_grad/reliable_partner/ride_or_die/power_couple (need a
-- specific team context this function doesn't take), and feeling_lucky
-- (no underlying data to verify -- it's a flavor unlock).
-- ============================================================
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
    -- Also fixes SB-7: sums every positive (earning) transaction, not
    -- just ones labeled 'earn' -- the old _getLifetimeCoins bug missed
    -- daily_checkin/partner_bonus/achievement-type earnings.
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

  ELSE
    RAISE EXCEPTION 'achievement_not_server_verifiable: %', p_achievement_id;
  END IF;

  -- Sanity backstop: a streak/loyalty achievement requiring N days
  -- cannot possibly be true if the account itself is younger than N
  -- days. Catches this exact bug class regardless of root cause.
  IF v_category IN ('streak', 'loyalty') AND v_target > COALESCE(v_account_age_days, 0) + 1 THEN
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

REVOKE ALL ON FUNCTION public.verify_achievement_progress(text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.verify_achievement_progress(text) TO authenticated;
