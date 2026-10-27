-- Rollback for 20261013020000_hygiene_05d. Restores the definitions and grants captured before the change.
-- Pre-change ACLs:
--   check_in_coach_max_with_buddy(uuid): {postgres=X/postgres,authenticated=X/postgres,service_role=X/postgres}
--   purchase_shop_item(uuid):            {postgres=X/postgres,authenticated=X/postgres,service_role=X/postgres}
--   user_profiles.rest_tokens_available: {authenticated=aw/postgres} (column-level INSERT, UPDATE)
--   user_profiles constraints: user_profiles_age_min_16, user_profiles_pkey, user_profiles_username_key

GRANT EXECUTE ON FUNCTION public.check_in_coach_max_with_buddy(uuid) TO authenticated;

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

ALTER TABLE public.user_profiles DROP CONSTRAINT IF EXISTS user_profiles_coin_balance_nonneg;

GRANT UPDATE (rest_tokens_available) ON public.user_profiles TO authenticated;
