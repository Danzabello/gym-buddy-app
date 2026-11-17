-- Prompt 53, migration 2 of 2: _apply_checkin_rewards (R2, R3, R6). Credit logic.
-- Diffed against the live body (md5 47185fcbc9c873ef46ebdce0bdde70f6, read 2026-11-17). Every change:
--   R6 check-in XP 10 -> 20 base, 5 -> 10 partner (v_xp, v_coop_xp, teammate base XP). Coins unchanged.
--   R3 daily XP cap 1000 -> 300 (v_daily_cap_xp). Coin cap stays 100.
--   R2 milestones leave the capped amounts: the two lines that added v_milestone_xp and v_milestone_coins into v_xp and
--      v_coins are gone. A milestone is paid as its own rows (type and XP description 'streak_milestone', same reference),
--      so the cap queries, which read only daily_checkin and partner_bonus, never see it. Coins are limited by a separate
--      300-coin ceiling per credit day (v_milestone_cap_coins, counted from the user's own streak_milestone rows).
--      Caller: paid right after the capped awards and BEFORE the level read, so did_level_up sees a level gained from it.
--      Teammate: base no longer carries the milestone; it is paid by its own branch, deduped on the teammate's
--      streak_milestone XP row for this reference (the row is written even when the ceiling leaves 0 coins).
--   Return: xp_awarded and coins_awarded are still the totals the caller received (capped part plus milestone).
-- Unchanged: the L4 advisory lock first, the early return on an existing XP row, the cap windows, every other line.
-- L3 (_lock_credit) already holds a cap lock per non-bot member of the streak, caller and teammate alike, so the new
-- ceiling is protected by the same lock as the 100-coin cap; no lock is added or reordered.
-- ACL restated: postgres and service_role only (G0.1 pins it). Rollback: dev/rollback_20261117110000.sql.
CREATE OR REPLACE FUNCTION public._apply_checkin_rewards(p_user_id uuid, p_streak_id uuid, p_check_in_date date)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_ref text := p_streak_id::text || ':' || p_check_in_date::text;
  v_current_streak integer;
  v_xp integer := 20;
  v_coins integer := 10;
  v_coop_xp integer := 10;
  v_coop_coins integer := 5;
  v_milestone_xp integer := 0;
  v_milestone_coins integer := 0;
  v_reasons jsonb := '[]'::jsonb;
  v_partner_checked_in boolean := false;
  v_teammate record;
  v_coach_max_id uuid := '00000000-0000-0000-0000-000000000001';
  v_old_level integer;
  v_new_level integer;
  v_daily_cap_xp constant integer := 300;
  v_daily_cap_coins constant integer := 100;
  v_milestone_cap_coins constant integer := 300;
  v_already_xp integer;
  v_already_coins integer;
  v_already_ms_coins integer;
  v_ms_pay integer := 0;
  v_capped boolean := false;
BEGIN
  -- One payout run per (streak, day) at a time, so the existence checks
  -- below cannot race a concurrent run for a teammate.
  PERFORM pg_advisory_xact_lock(hashtext('checkin_rewards:' || v_ref));

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

  -- Daily cap for the primary user, counted by credit day: the date after the
  -- last colon of reference_id (streak:day), not the day the row was created (CAP-2).
  SELECT COALESCE(SUM(amount), 0) INTO v_already_xp
  FROM xp_transactions
  WHERE user_id = p_user_id
    AND transaction_type = 'xp_award' AND description IN ('daily_checkin', 'partner_bonus')
    AND substring(reference_id from '[^:]*$') = p_check_in_date::text;

  SELECT COALESCE(SUM(amount), 0) INTO v_already_coins
  FROM coin_transactions
  WHERE user_id = p_user_id
    AND transaction_type IN ('daily_checkin', 'partner_bonus')
    AND substring(reference_id from '[^:]*$') = p_check_in_date::text;

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

  -- Milestone, outside the daily caps, under its own coin ceiling for the credit day. Paid before the level read below.
  IF v_milestone_xp > 0 THEN
    SELECT COALESCE(SUM(amount), 0) INTO v_already_ms_coins
    FROM coin_transactions
    WHERE user_id = p_user_id
      AND transaction_type = 'streak_milestone'
      AND substring(reference_id from '[^:]*$') = p_check_in_date::text;
    v_ms_pay := LEAST(v_milestone_coins, GREATEST(0, v_milestone_cap_coins - v_already_ms_coins));
    PERFORM award_xp(p_user_id, v_milestone_xp, 'streak_milestone', v_ref);
    PERFORM award_coins(p_user_id, v_ms_pay, 'streak_milestone', 'Streak milestone', v_ref);
  END IF;

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
        -- Owed-checks: each entitlement deduped by its own kind + reference_id
        -- (XP rows carry the kind in description, coin rows in transaction_type).
        v_t_owed_base boolean;
        v_t_owed_coop boolean;
        v_t_owed_ms boolean;
        v_t_already_xp integer;
        v_t_already_coins integer;
        v_t_already_ms_coins integer;
        v_t_base_xp integer := 0;
        v_t_base_coins integer := 0;
        v_t_coop_xp integer := 0;
        v_t_coop_coins integer := 0;
        v_t_room_xp integer;
        v_t_room_coins integer;
        v_t_ms_pay integer;
      BEGIN
        v_t_owed_base := NOT EXISTS (
          SELECT 1 FROM xp_transactions
          WHERE user_id = v_teammate.user_id
            AND transaction_type = 'xp_award' AND description = 'daily_checkin'
            AND reference_id = v_ref
        );
        v_t_owed_coop := NOT EXISTS (
          SELECT 1 FROM coin_transactions
          WHERE user_id = v_teammate.user_id
            AND transaction_type = 'partner_bonus'
            AND reference_id = v_ref
        );
        v_t_owed_ms := v_milestone_xp > 0 AND NOT EXISTS (
          SELECT 1 FROM xp_transactions
          WHERE user_id = v_teammate.user_id
            AND transaction_type = 'xp_award' AND description = 'streak_milestone'
            AND reference_id = v_ref
        );

        IF v_t_owed_base OR v_t_owed_coop OR v_t_owed_ms THEN
          -- 20 XP / 10 coins base matches the primary's v_xp/v_coins initialisers;
          -- the milestone is paid by its own branch below, not folded into base.
          IF v_t_owed_base THEN
            v_t_base_xp := 20;
            v_t_base_coins := 10;
          END IF;
          IF v_t_owed_coop THEN
            v_t_coop_xp := v_coop_xp;
            v_t_coop_coins := v_coop_coins;
          END IF;

          -- Teammate's cap window: the same credit day (CAP-2).
          SELECT COALESCE(SUM(amount), 0) INTO v_t_already_xp
          FROM xp_transactions
          WHERE user_id = v_teammate.user_id
            AND transaction_type = 'xp_award' AND description IN ('daily_checkin', 'partner_bonus')
            AND substring(reference_id from '[^:]*$') = p_check_in_date::text;

          SELECT COALESCE(SUM(amount), 0) INTO v_t_already_coins
          FROM coin_transactions
          WHERE user_id = v_teammate.user_id
            AND transaction_type IN ('daily_checkin', 'partner_bonus')
            AND substring(reference_id from '[^:]*$') = p_check_in_date::text;

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
          IF v_t_owed_ms THEN
            SELECT COALESCE(SUM(amount), 0) INTO v_t_already_ms_coins
            FROM coin_transactions
            WHERE user_id = v_teammate.user_id
              AND transaction_type = 'streak_milestone'
              AND substring(reference_id from '[^:]*$') = p_check_in_date::text;
            v_t_ms_pay := LEAST(v_milestone_coins, GREATEST(0, v_milestone_cap_coins - v_t_already_ms_coins));
            PERFORM award_xp(v_teammate.user_id, v_milestone_xp, 'streak_milestone', v_ref);
            PERFORM award_coins(v_teammate.user_id, v_t_ms_pay, 'streak_milestone', 'Streak milestone', v_ref);
          END IF;
        END IF;
      END;
    END LOOP;
  END IF;

  RETURN jsonb_build_object(
    'xp_awarded', v_xp + v_milestone_xp,
    'coins_awarded', v_coins + v_ms_pay,
    'current_streak', v_current_streak,
    'reasons', v_reasons,
    'old_level', v_old_level,
    'new_level', v_new_level,
    'did_level_up', v_new_level > v_old_level,
    'daily_cap_reached', v_capped
  );
END;
$function$;

REVOKE EXECUTE ON FUNCTION public._apply_checkin_rewards(uuid, uuid, date) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public._apply_checkin_rewards(uuid, uuid, date) TO service_role;
