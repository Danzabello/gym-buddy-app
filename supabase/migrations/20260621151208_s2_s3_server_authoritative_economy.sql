-- ============================================================
-- S2/S3 FIX: server-authoritative XP/coins + validated,
-- atomic check-in rewards. Replaces client-direct coin_balance
-- writes and the friend-proxy daily_team_checkins INSERT policy.
-- ============================================================

-- 1. award_coins: atomic equivalent of the existing award_xp()
CREATE OR REPLACE FUNCTION public.award_coins(
  p_user_id uuid,
  p_amount integer,
  p_transaction_type text,
  p_description text,
  p_reference_id text DEFAULT NULL
) RETURNS integer
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_new_balance integer;
BEGIN
  UPDATE user_profiles
  SET coin_balance = COALESCE(coin_balance, 0) + p_amount
  WHERE id = p_user_id
  RETURNING coin_balance INTO v_new_balance;

  IF v_new_balance IS NULL THEN
    RAISE EXCEPTION 'user_not_found: %', p_user_id;
  END IF;

  INSERT INTO coin_transactions (user_id, amount, transaction_type, description, reference_id)
  VALUES (p_user_id, p_amount, p_transaction_type, p_description, p_reference_id);

  RETURN v_new_balance;
END;
$$;

-- award_xp/award_coins are money primitives: only callable from
-- other SECURITY DEFINER functions (which run as the postgres
-- owner) or service_role. Never directly by an authenticated client.
REVOKE ALL ON FUNCTION public.award_coins(uuid, integer, text, text, text) FROM PUBLIC, authenticated, anon;
GRANT EXECUTE ON FUNCTION public.award_coins(uuid, integer, text, text, text) TO service_role;

REVOKE ALL ON FUNCTION public.award_xp(uuid, integer, text, text) FROM PUBLIC, authenticated, anon;
GRANT EXECUTE ON FUNCTION public.award_xp(uuid, integer, text, text) TO service_role;


-- 2. Internal helper: compute + apply check-in rewards for one
--    user on one team/date. Idempotent. Also retroactively tops
--    up any teammate who already checked in today but hasn't
--    received their co-op bonus yet (the safe, validated version
--    of the old client-side awardRetroactivePartnerBonus).
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
BEGIN
  IF EXISTS (
    SELECT 1 FROM xp_transactions
    WHERE user_id = p_user_id AND reference_id = v_ref
  ) THEN
    RETURN jsonb_build_object('already_awarded', true);
  END IF;

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

  PERFORM award_xp(p_user_id, v_xp, 'daily_checkin', v_ref);
  PERFORM award_coins(p_user_id, v_coins, 'daily_checkin', 'Daily check-in rewards', v_ref);

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
        PERFORM award_xp(v_teammate.user_id, v_coop_xp, 'partner_bonus', v_ref);
        PERFORM award_coins(v_teammate.user_id, v_coop_coins, 'partner_bonus', 'Partner checked in too!', v_ref);
      END IF;
    END LOOP;
  END IF;

  RETURN jsonb_build_object(
    'xp_awarded', v_xp,
    'coins_awarded', v_coins,
    'current_streak', v_current_streak,
    'reasons', v_reasons
  );
END;
$$;

REVOKE ALL ON FUNCTION public._apply_checkin_rewards(uuid, uuid, date) FROM PUBLIC, authenticated, anon;


-- 3. Public RPC: self check-in rewards. Validates caller is a
--    real team member with a real check-in row before paying out.
--    Replaces CoinService.awardDailyCheckIn + awardRetroactivePartnerBonus
--    + LevelService.awardCheckInXP, called once from the client
--    after its own team_streaks update.
CREATE OR REPLACE FUNCTION public.award_checkin_rewards(
  p_streak_id uuid,
  p_check_in_date date
) RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_caller uuid := auth.uid();
  v_team_id uuid;
BEGIN
  IF v_caller IS NULL THEN
    RAISE EXCEPTION 'unauthenticated';
  END IF;

  SELECT team_id INTO v_team_id FROM team_streaks WHERE id = p_streak_id;
  IF v_team_id IS NULL THEN
    RAISE EXCEPTION 'invalid_streak';
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM team_members WHERE team_id = v_team_id AND user_id = v_caller
  ) THEN
    RAISE EXCEPTION 'not_a_team_member';
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM daily_team_checkins
    WHERE team_streak_id = p_streak_id AND user_id = v_caller AND check_in_date = p_check_in_date
  ) THEN
    RAISE EXCEPTION 'no_checkin_found_for_caller';
  END IF;

  RETURN public._apply_checkin_rewards(v_caller, p_streak_id, p_check_in_date);
END;
$$;

REVOKE ALL ON FUNCTION public.award_checkin_rewards(uuid, date) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.award_checkin_rewards(uuid, date) TO authenticated;


-- 4. Public RPC: proxy check-in for a co-op partner. Validates
--    BOTH the caller and the target are real participants on the
--    SAME real workouts row before touching the target's
--    check-in/reward data -- replaces the friend-on-shared-team
--    RLS policy (the literal S3 forgery vector) with a check tied
--    to an actual completed workout session.
CREATE OR REPLACE FUNCTION public.checkin_team_for_user(
  p_target_user_id uuid,
  p_workout_id uuid
) RETURNS integer
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_caller uuid := auth.uid();
  v_creator uuid;
  v_buddy uuid;
  v_team record;
  v_checked_in_count integer := 0;
  v_today date := (now() AT TIME ZONE 'utc')::date;
BEGIN
  IF v_caller IS NULL THEN
    RAISE EXCEPTION 'unauthenticated';
  END IF;

  SELECT user_id, buddy_id INTO v_creator, v_buddy
  FROM workouts WHERE id = p_workout_id;

  IF v_creator IS NULL THEN
    RAISE EXCEPTION 'workout_not_found';
  END IF;

  IF v_caller IS DISTINCT FROM v_creator AND v_caller IS DISTINCT FROM v_buddy THEN
    RAISE EXCEPTION 'caller_not_a_participant';
  END IF;

  IF p_target_user_id IS DISTINCT FROM v_creator AND p_target_user_id IS DISTINCT FROM v_buddy THEN
    RAISE EXCEPTION 'target_not_a_participant';
  END IF;

  FOR v_team IN
    SELECT ts.id AS streak_id
    FROM team_members tm
    JOIN team_streaks ts ON ts.team_id = tm.team_id AND ts.is_active = true
    WHERE tm.user_id = p_target_user_id
  LOOP
    IF NOT EXISTS (
      SELECT 1 FROM daily_team_checkins
      WHERE team_streak_id = v_team.streak_id
        AND user_id = p_target_user_id
        AND check_in_date = v_today
    ) THEN
      INSERT INTO daily_team_checkins (team_streak_id, user_id, check_in_date, check_in_time)
      VALUES (v_team.streak_id, p_target_user_id, v_today, now());

      v_checked_in_count := v_checked_in_count + 1;

      PERFORM public._apply_checkin_rewards(p_target_user_id, v_team.streak_id, v_today);
    END IF;
  END LOOP;

  RETURN v_checked_in_count;
END;
$$;

REVOKE ALL ON FUNCTION public.checkin_team_for_user(uuid, uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.checkin_team_for_user(uuid, uuid) TO authenticated;


-- 5. Achievement rewards: server looks up the correct xp_reward/
--    coin_reward from the achievements table itself rather than
--    trusting a client-supplied amount. Idempotent per achievement.
CREATE OR REPLACE FUNCTION public.award_achievement_rewards(
  p_achievement_id text
) RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_caller uuid := auth.uid();
  v_xp integer;
  v_coins integer;
  v_name text;
  v_unlocked timestamptz;
  v_ref text := 'achievement_' || p_achievement_id;
BEGIN
  IF v_caller IS NULL THEN
    RAISE EXCEPTION 'unauthenticated';
  END IF;

  SELECT xp_reward, coin_reward, name INTO v_xp, v_coins, v_name
  FROM achievements WHERE id = p_achievement_id;

  IF v_name IS NULL THEN
    RAISE EXCEPTION 'unknown_achievement';
  END IF;

  SELECT unlocked_at INTO v_unlocked
  FROM user_achievements
  WHERE user_id = v_caller AND achievement_id = p_achievement_id;

  IF v_unlocked IS NULL THEN
    RAISE EXCEPTION 'achievement_not_unlocked';
  END IF;

  IF EXISTS (
    SELECT 1 FROM xp_transactions WHERE user_id = v_caller AND reference_id = v_ref
  ) THEN
    RETURN jsonb_build_object('already_awarded', true);
  END IF;

  IF v_xp > 0 THEN
    PERFORM award_xp(v_caller, v_xp, 'achievement', v_ref);
  END IF;
  IF v_coins > 0 THEN
    PERFORM award_coins(v_caller, v_coins, 'earn', 'Achievement: ' || v_name, v_ref);
  END IF;

  RETURN jsonb_build_object('xp_awarded', v_xp, 'coins_awarded', v_coins);
END;
$$;

REVOKE ALL ON FUNCTION public.award_achievement_rewards(text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.award_achievement_rewards(text) TO authenticated;


-- 6. Remove the now-redundant trigger (it's the source of the
--    double-XP-on-checkin bug -- award_checkin_rewards/
--    checkin_team_for_user now own the full, correct amount).
DROP TRIGGER IF EXISTS xp_on_checkin ON public.daily_team_checkins;
DROP FUNCTION IF EXISTS public.trigger_xp_on_checkin();

-- 7. Remove the forgery-enabling RLS policy now that the only
--    legitimate cross-user check-in path is checkin_team_for_user
--    (validated against a real workouts row).
DROP POLICY IF EXISTS "Users can create check-ins for themselves or friends on shared " ON public.daily_team_checkins;

-- 8. Remove client INSERT on coin_transactions -- all coin awards
--    now flow through award_coins() (postgres-owned). Clients
--    only need SELECT to view their history (unchanged).
DROP POLICY IF EXISTS "Users can insert own transactions" ON public.coin_transactions;

-- 9. The core fix: revoke direct client write access to the
--    economy columns. RLS row-level policy (auth.uid()=id) still
--    permits updating other profile columns normally.
REVOKE UPDATE (xp, level, coin_balance) ON public.user_profiles FROM authenticated, anon;
