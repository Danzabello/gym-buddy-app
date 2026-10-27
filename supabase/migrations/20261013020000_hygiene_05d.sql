-- Hygiene 05d. Report: docs/hygiene/05d_report.md. Rollback: docs/rollback_20261013020000.sql

-- check_in_coach_max_with_buddy: no caller in Dart, edge functions, SQL bodies, triggers or cron since b99b0b2.
-- Kept for service_role/postgres; closed to clients.
REVOKE EXECUTE ON FUNCTION public.check_in_coach_max_with_buddy(uuid) FROM PUBLIC, anon, authenticated;

-- purchase_shop_item: lock the caller's user_profiles row before the balance check. Logic otherwise unchanged.
CREATE OR REPLACE FUNCTION public.purchase_shop_item(p_shop_item_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_caller uuid := auth.uid();
  v_cost integer;
  v_name text;
  v_unlock_level integer;
  v_unlock_achievement_id text;
  v_level integer;
  v_balance integer;
  v_already_owned boolean;
BEGIN
  IF v_caller IS NULL THEN
    RAISE EXCEPTION 'unauthenticated';
  END IF;

  -- Serialise purchases per user: concurrent calls wait here, then see the committed balance.
  PERFORM 1 FROM user_profiles WHERE id = v_caller FOR UPDATE;

  SELECT cost, name, unlock_level, unlock_achievement_id
  INTO v_cost, v_name, v_unlock_level, v_unlock_achievement_id
  FROM shop_items WHERE id = p_shop_item_id AND is_available = true;

  IF v_cost IS NULL THEN
    RAISE EXCEPTION 'item_not_found_or_unavailable';
  END IF;

  SELECT EXISTS(
    SELECT 1 FROM user_inventory WHERE user_id = v_caller AND shop_item_id = p_shop_item_id
  ) INTO v_already_owned;

  IF v_already_owned THEN
    RETURN jsonb_build_object('success', false, 'reason', 'already_owned');
  END IF;

  SELECT COALESCE(level, 1), coin_balance INTO v_level, v_balance
  FROM user_profiles WHERE id = v_caller;

  -- An item with neither gate set behaves exactly as before: purchasable
  -- on coins alone (no live row currently has that combination, but the
  -- checks are written to allow for it rather than assume it).
  IF v_unlock_level IS NOT NULL AND COALESCE(v_level, 1) < v_unlock_level THEN
    RETURN jsonb_build_object('success', false, 'reason', 'level_locked', 'required_level', v_unlock_level, 'current_level', v_level);
  END IF;

  IF v_unlock_achievement_id IS NOT NULL AND NOT EXISTS (
    SELECT 1 FROM user_achievements
    WHERE user_id = v_caller AND achievement_id = v_unlock_achievement_id AND unlocked_at IS NOT NULL
  ) THEN
    RETURN jsonb_build_object('success', false, 'reason', 'achievement_locked', 'required_achievement', v_unlock_achievement_id);
  END IF;

  IF COALESCE(v_balance, 0) < v_cost THEN
    RETURN jsonb_build_object('success', false, 'reason', 'insufficient_funds', 'balance', v_balance, 'cost', v_cost);
  END IF;

  PERFORM award_coins(v_caller, -v_cost, 'shop_purchase', 'Purchased: ' || v_name, p_shop_item_id::text);

  INSERT INTO user_inventory (user_id, shop_item_id) VALUES (v_caller, p_shop_item_id);

  RETURN jsonb_build_object('success', true, 'new_balance', v_balance - v_cost);
END;
$function$;

REVOKE EXECUTE ON FUNCTION public.purchase_shop_item(uuid) FROM PUBLIC, anon;
GRANT  EXECUTE ON FUNCTION public.purchase_shop_item(uuid) TO authenticated;

-- coin_balance can never go negative. Only negative writer is award_coins(-cost) from purchase_shop_item,
-- which checks the balance first. VALIDATE only if no row violates.
ALTER TABLE public.user_profiles ADD CONSTRAINT user_profiles_coin_balance_nonneg CHECK (coin_balance >= 0) NOT VALID;
DO $$
DECLARE v_bad int;
BEGIN
  SELECT count(*) INTO v_bad FROM public.user_profiles WHERE coin_balance < 0;
  IF v_bad > 0 THEN
    RAISE EXCEPTION 'user_profiles has % rows with coin_balance < 0; not validating', v_bad;
  END IF;
END $$;
ALTER TABLE public.user_profiles VALIDATE CONSTRAINT user_profiles_coin_balance_nonneg;

-- rest_tokens_available: no client or server reader/writer. UPDATE is granted per column (no table-level UPDATE),
-- so a column REVOKE is effective. INSERT on the column is left as is.
REVOKE UPDATE (rest_tokens_available) ON public.user_profiles FROM authenticated;
