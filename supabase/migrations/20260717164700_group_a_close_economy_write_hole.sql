-- GROUP A (audit LIVE-1, LIVE-5): close the economy write hole.

-- LIVE-1: repo migration 20260621151208 contains this REVOKE but it was
-- never applied to live (LIVE-6). Re-issued here so the hole is closed
-- regardless of migration-history reconciliation. Idempotent.
REVOKE UPDATE (xp, level, coin_balance, is_bot)
  ON public.user_profiles FROM authenticated, anon;

-- Same family: column-level INSERT on the economy columns plus the
-- "insert own profile" policy would let a crafted client seed its profile
-- at signup with arbitrary xp/coins. The onboarding upsert sends none of
-- these columns, so this is safe for the real flow.
REVOKE INSERT (xp, level, coin_balance, is_bot)
  ON public.user_profiles FROM authenticated, anon;

-- LIVE-5: award_achievement_rewards trusted any user_achievements row with
-- unlocked_at set, but the user_achievements RLS policy (ALL, auth.uid() =
-- user_id, no separate WITH CHECK) lets a client INSERT its own
-- pre-unlocked row — so unlocked_at proves nothing. Every achievement
-- except feeling_lucky is server-verifiable: verify_achievement_progress
-- re-derives real progress from the underlying tables and pays out
-- atomically at the moment of the genuine unlock, and never pays when the
-- row is already unlocked. Route everything except feeling_lucky through
-- it; this function's own payout path now only serves feeling_lucky
-- (client-triggered flavour achievement, 25 XP / 10 coins, capped to one
-- payout by the xp_transactions reference check).
--
-- Side effect (intended): this also closes the re-mint hole on the
-- coin-only level_* achievements (xp_reward = 0), where the
-- xp_transactions idempotency check never matched and every call paid the
-- coin reward again (level_99 = 5000 coins per call).
CREATE OR REPLACE FUNCTION public.award_achievement_rewards(p_achievement_id text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
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

  -- A user_achievements row is client-writable, so it can't gate a payout.
  -- For everything except feeling_lucky, defer to the server-side
  -- re-derivation: it unlocks + pays only on a real progress transition,
  -- and pays nothing for rows that are already (or fraudulently) unlocked.
  IF p_achievement_id <> 'feeling_lucky' THEN
    RETURN verify_achievement_progress(p_achievement_id);
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
$function$;
