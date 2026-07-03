-- STEP 3, migration #4 of the per-user timezone rework (Option B).
--
-- Fixes the pre-existing reward asymmetry in the mutual check-in flow: the
-- LAST member to check in triggered award_checkin_rewards and received
-- base 10/10 (+ milestone when applicable) + 5/5 co-op, while the FIRST
-- member's own earlier call was gated out and they only ever received the
-- retroactive 5/5 partner_bonus top-up — never their base or milestone.
--
-- The retro teammate loop now grants each teammate their FULL missing
-- entitlement, each part separately deduped by its (transaction_type,
-- reference_id) pair:
--   * base 10/10 + milestone(7/30/100) -> one 'daily_checkin' txn,
--     owed iff no xp 'daily_checkin' txn with this reference_id exists
--     (matches how the primary's own award is recorded);
--   * co-op 5/5 -> 'partner_bonus' txn, owed iff missing (current check,
--     unchanged).
-- A teammate owing neither is skipped. Amounts still run through the daily
-- cap in the TEAMMATE's own local-tz window (tz3_2). Milestone amounts are
-- hoisted into v_milestone_xp/coins so primary and teammates share one value
-- computed from the same v_current_streak in the same call.
--
-- award_checkin_rewards (the wrapper) is intentionally untouched: it is pure
-- validation + delegate, with no timezone math (verified against live source).
--
-- Everything else — primary dedup, co-op detection, cap constants, per-user
-- tz cap windows from tz3_2, level-up detection, return shape — is preserved.

CREATE OR REPLACE FUNCTION public._apply_checkin_rewards(p_user_id uuid, p_streak_id uuid, p_check_in_date date)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_ref text := p_streak_id::text || ':' || p_check_in_date::text;
  v_current_streak integer;
  v_xp integer := 10;
  v_coins integer := 10;
  v_coop_xp integer := 5;
  v_coop_coins integer := 5;
  v_milestone_xp integer := 0;
  v_milestone_coins integer := 0;
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
  v_user_tz text := public.safe_user_tz(p_user_id);
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

  -- Milestone amounts hoisted so the retro teammate loop can reuse them
  -- (same v_current_streak, same call -> symmetric by construction).
  IF v_current_streak = 7 THEN
    v_milestone_xp := 50; v_milestone_coins := 50;
    v_reasons := v_reasons || jsonb_build_array('milestone_7');
  ELSIF v_current_streak = 30 THEN
    v_milestone_xp := 50; v_milestone_coins := 100;
    v_reasons := v_reasons || jsonb_build_array('milestone_30');
  ELSIF v_current_streak = 100 THEN
    v_milestone_xp := 50; v_milestone_coins := 250;
    v_reasons := v_reasons || jsonb_build_array('milestone_100');
  END IF;
  v_xp := v_xp + v_milestone_xp;
  v_coins := v_coins + v_milestone_coins;

  -- Daily cap check for the primary user, in THEIR OWN local day (tz3_2)
  SELECT COALESCE(SUM(amount), 0) INTO v_already_xp
  FROM xp_transactions
  WHERE user_id = p_user_id
    AND transaction_type IN ('daily_checkin', 'partner_bonus')
    AND (created_at AT TIME ZONE v_user_tz)::date = p_check_in_date;

  SELECT COALESCE(SUM(amount), 0) INTO v_already_coins
  FROM coin_transactions
  WHERE user_id = p_user_id
    AND transaction_type IN ('daily_checkin', 'partner_bonus')
    AND (created_at AT TIME ZONE v_user_tz)::date = p_check_in_date;

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
      DECLARE
        -- Owed-checks: each entitlement deduped by its own
        -- (transaction_type, reference_id) pair.
        v_t_owed_base boolean;
        v_t_owed_coop boolean;
        v_t_already_xp integer;
        v_t_already_coins integer;
        v_t_base_xp integer := 0;
        v_t_base_coins integer := 0;
        v_t_coop_xp integer := 0;
        v_t_coop_coins integer := 0;
        v_t_room_xp integer;
        v_t_room_coins integer;
        -- Teammate's cap window is measured in the TEAMMATE's own local day.
        v_t_tz text := public.safe_user_tz(v_teammate.user_id);
      BEGIN
        v_t_owed_base := NOT EXISTS (
          SELECT 1 FROM xp_transactions
          WHERE user_id = v_teammate.user_id
            AND transaction_type = 'daily_checkin'
            AND reference_id = v_ref
        );
        v_t_owed_coop := NOT EXISTS (
          SELECT 1 FROM coin_transactions
          WHERE user_id = v_teammate.user_id
            AND transaction_type = 'partner_bonus'
            AND reference_id = v_ref
        );

        IF v_t_owed_base OR v_t_owed_coop THEN
          -- 10/10 base matches the primary's v_xp/v_coins initialisers;
          -- milestone shares the hoisted amounts from this same call.
          IF v_t_owed_base THEN
            v_t_base_xp := 10 + v_milestone_xp;
            v_t_base_coins := 10 + v_milestone_coins;
          END IF;
          IF v_t_owed_coop THEN
            v_t_coop_xp := v_coop_xp;
            v_t_coop_coins := v_coop_coins;
          END IF;

          SELECT COALESCE(SUM(amount), 0) INTO v_t_already_xp
          FROM xp_transactions
          WHERE user_id = v_teammate.user_id
            AND transaction_type IN ('daily_checkin', 'partner_bonus')
            AND (created_at AT TIME ZONE v_t_tz)::date = p_check_in_date;

          SELECT COALESCE(SUM(amount), 0) INTO v_t_already_coins
          FROM coin_transactions
          WHERE user_id = v_teammate.user_id
            AND transaction_type IN ('daily_checkin', 'partner_bonus')
            AND (created_at AT TIME ZONE v_t_tz)::date = p_check_in_date;

          -- Cap the combined owed amount: base takes the remaining room
          -- first, co-op whatever is left after that.
          v_t_room_xp := GREATEST(0, v_daily_cap_xp - v_t_already_xp);
          v_t_room_coins := GREATEST(0, v_daily_cap_coins - v_t_already_coins);
          v_t_base_xp := LEAST(v_t_base_xp, v_t_room_xp);
          v_t_base_coins := LEAST(v_t_base_coins, v_t_room_coins);
          v_t_coop_xp := LEAST(v_t_coop_xp, v_t_room_xp - v_t_base_xp);
          v_t_coop_coins := LEAST(v_t_coop_coins, v_t_room_coins - v_t_base_coins);

          -- Award each owed part even when capped to 0: the ref-tagged txn
          -- is what marks the entitlement as covered for future dedup.
          IF v_t_owed_base THEN
            PERFORM award_xp(v_teammate.user_id, v_t_base_xp, 'daily_checkin', v_ref);
            PERFORM award_coins(v_teammate.user_id, v_t_base_coins, 'daily_checkin', 'Daily check-in rewards', v_ref);
          END IF;
          IF v_t_owed_coop THEN
            PERFORM award_xp(v_teammate.user_id, v_t_coop_xp, 'partner_bonus', v_ref);
            PERFORM award_coins(v_teammate.user_id, v_t_coop_coins, 'partner_bonus', 'Partner checked in too!', v_ref);
          END IF;
        END IF;
      END;
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
$function$;
