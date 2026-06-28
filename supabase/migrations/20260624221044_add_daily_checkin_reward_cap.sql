-- Anti-farming daily ceiling on check-in rewards. Per-team formula
-- is unchanged (base 10/10, +5/+5 real-buddy coop bonus, milestone
-- bonuses) -- this only clamps the COMBINED total across all of a
-- user's teams per calendar day, so it never binds for a normal
-- user (1-5 real buddies) but stops unbounded scaling for someone
-- with dozens of buddy-team accounts.
CREATE OR REPLACE FUNCTION public._apply_checkin_rewards(
  p_user_id uuid,
  p_streak_id uuid,
  p_check_in_date date
) RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_ref text := p_streak_id::text || ':' || p_check_in_date::text;
  v_current_streak integer;
  v_xp integer := 10;
  v_coins integer := 10;
  v_coop_xp integer := 5;
  v_coop_coins integer := 5;
  v_reasons jsonb := '[]'::jsonb;
  v_partner_checked_in boolean := false;
  v_teammate record;
  v_coach_max_id uuid := '00000000-0000-0000-0000-000000000001';
  v_old_level integer;
  v_new_level integer;
  v_daily_cap_xp constant integer := 1000;
  v_daily_cap_coins constant integer := 100;
  v_already_xp integer;
  v_already_coins integer;
  v_capped boolean := false;
BEGIN
  IF EXISTS (
    SELECT 1 FROM xp_transactions
    WHERE user_id = p_user_id AND reference_id = v_ref
  ) THEN
    RETURN jsonb_build_object('already_awarded', true);
  END IF;

  SELECT level INTO v_old_level FROM user_profiles WHERE id = p_user_id;
  v_old_level := COALESCE(v_old_level, 1);

  SELECT current_streak INTO v_current_streak FROM team_streaks WHERE id = p_streak_id;
  v_current_streak := COALESCE(v_current_streak, 1);

  SELECT EXISTS (
    SELECT 1 FROM daily_team_checkins
    WHERE team_streak_id = p_streak_id
      AND check_in_date = p_check_in_date
      AND user_id <> p_user_id
      AND user_id <> v_coach_max_id
  ) INTO v_partner_checked_in;

  IF v_partner_checked_in THEN
    v_xp := v_xp + v_coop_xp;
    v_coins := v_coins + v_coop_coins;
    v_reasons := v_reasons || jsonb_build_array('coop_bonus');
  END IF;

  IF v_current_streak = 7 THEN
    v_xp := v_xp + 50; v_coins := v_coins + 50;
    v_reasons := v_reasons || jsonb_build_array('milestone_7');
  ELSIF v_current_streak = 30 THEN
    v_xp := v_xp + 50; v_coins := v_coins + 100;
    v_reasons := v_reasons || jsonb_build_array('milestone_30');
  ELSIF v_current_streak = 100 THEN
    v_xp := v_xp + 50; v_coins := v_coins + 250;
    v_reasons := v_reasons || jsonb_build_array('milestone_100');
  END IF;

  -- Daily cap check for the primary user (UTC, matching app convention)
  SELECT COALESCE(SUM(amount), 0) INTO v_already_xp
  FROM xp_transactions
  WHERE user_id = p_user_id
    AND transaction_type IN ('daily_checkin', 'partner_bonus')
    AND (created_at AT TIME ZONE 'utc')::date = p_check_in_date;

  SELECT COALESCE(SUM(amount), 0) INTO v_already_coins
  FROM coin_transactions
  WHERE user_id = p_user_id
    AND transaction_type IN ('daily_checkin', 'partner_bonus')
    AND (created_at AT TIME ZONE 'utc')::date = p_check_in_date;

  IF v_already_xp + v_xp > v_daily_cap_xp THEN
    v_xp := GREATEST(0, v_daily_cap_xp - v_already_xp);
    v_capped := true;
  END IF;
  IF v_already_coins + v_coins > v_daily_cap_coins THEN
    v_coins := GREATEST(0, v_daily_cap_coins - v_already_coins);
    v_capped := true;
  END IF;

  PERFORM award_xp(p_user_id, v_xp, 'daily_checkin', v_ref);
  PERFORM award_coins(p_user_id, v_coins, 'daily_checkin', 'Daily check-in rewards', v_ref);

  SELECT level INTO v_new_level FROM user_profiles WHERE id = p_user_id;

  IF v_partner_checked_in THEN
    FOR v_teammate IN
      SELECT DISTINCT dtc.user_id
      FROM daily_team_checkins dtc
      WHERE dtc.team_streak_id = p_streak_id
        AND dtc.check_in_date = p_check_in_date
        AND dtc.user_id <> p_user_id
        AND dtc.user_id <> v_coach_max_id
    LOOP
      IF NOT EXISTS (
        SELECT 1 FROM coin_transactions
        WHERE user_id = v_teammate.user_id
          AND transaction_type = 'partner_bonus'
          AND reference_id = v_ref
      ) THEN
        DECLARE
          v_t_already_xp integer;
          v_t_already_coins integer;
          v_t_xp integer := v_coop_xp;
          v_t_coins integer := v_coop_coins;
        BEGIN
          SELECT COALESCE(SUM(amount), 0) INTO v_t_already_xp
          FROM xp_transactions
          WHERE user_id = v_teammate.user_id
            AND transaction_type IN ('daily_checkin', 'partner_bonus')
            AND (created_at AT TIME ZONE 'utc')::date = p_check_in_date;

          SELECT COALESCE(SUM(amount), 0) INTO v_t_already_coins
          FROM coin_transactions
          WHERE user_id = v_teammate.user_id
            AND transaction_type IN ('daily_checkin', 'partner_bonus')
            AND (created_at AT TIME ZONE 'utc')::date = p_check_in_date;

          IF v_t_already_xp + v_t_xp > v_daily_cap_xp THEN
            v_t_xp := GREATEST(0, v_daily_cap_xp - v_t_already_xp);
          END IF;
          IF v_t_already_coins + v_t_coins > v_daily_cap_coins THEN
            v_t_coins := GREATEST(0, v_daily_cap_coins - v_t_already_coins);
          END IF;

          PERFORM award_xp(v_teammate.user_id, v_t_xp, 'partner_bonus', v_ref);
          PERFORM award_coins(v_teammate.user_id, v_t_coins, 'partner_bonus', 'Partner checked in too!', v_ref);
        END;
      END IF;
    END LOOP;
  END IF;

  RETURN jsonb_build_object(
    'xp_awarded', v_xp,
    'coins_awarded', v_coins,
    'current_streak', v_current_streak,
    'reasons', v_reasons,
    'old_level', v_old_level,
    'new_level', v_new_level,
    'did_level_up', v_new_level > v_old_level,
    'daily_cap_reached', v_capped
  );
END;
$$;
