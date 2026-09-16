-- LIVE-13 fix: shop purchase gates were client-trusted, and
-- user_inventory was directly client-writable beyond what equipping
-- needs.
--
-- purchase_shop_item already SELECTed shop_items.cost and .name but
-- never fetched or checked unlock_level / unlock_achievement_id, so
-- any item -- including 0-cost achievement-gated cosmetics like Crown
-- Gold Ring -- could be bought by anyone regardless of level or
-- achievement progress. Separately, user_inventory had a client INSERT
-- policy (bypassing this RPC entirely) and an UPDATE policy with no
-- column restriction, so a client could also swap shop_item_id on an
-- owned row to "upgrade" a cheap item into an expensive one.
--
-- Fix, in the one shared function every purchase goes through, plus
-- locking user_inventory down to what the app actually needs:
--   - equipItem (coin_service.dart) only ever SETs the `equipped`
--     column on an existing row matched by (user_id, shop_item_id) --
--     it never writes shop_item_id. So: no client INSERT, no client
--     DELETE, and UPDATE restricted at the column-grant level to
--     `equipped` only. The existing row-level "own rows only" policy
--     is kept (renamed for clarity); the column grant is what actually
--     blocks a shop_item_id swap, since RLS policies don't have a
--     per-column WITH CHECK.
--   - All legitimate writes (INSERT on purchase, UPDATE on equip) now
--     either happen inside this SECURITY DEFINER function (running as
--     its owner) or are limited to the one column equip needs.

-- ── 1. Lock down user_inventory to what the app actually needs ─────────
drop policy if exists "Users can buy items" on public.user_inventory;
drop policy if exists "Users can equip items" on public.user_inventory;

create policy "Users can update own inventory equip state" on public.user_inventory
  for update to authenticated
  using (auth.uid() = user_id)
  with check (auth.uid() = user_id);

revoke all on public.user_inventory from anon;
revoke all on public.user_inventory from authenticated;
grant select on public.user_inventory to authenticated;
grant update (equipped) on public.user_inventory to authenticated;

-- ── 2. Enforce unlock_level / unlock_achievement_id server-side ────────
create or replace function public.purchase_shop_item(p_shop_item_id uuid)
 returns jsonb
 language plpgsql
 security definer
 set search_path to 'public'
as $function$
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

revoke execute on function public.purchase_shop_item(uuid) from public, anon;
grant execute on function public.purchase_shop_item(uuid) to authenticated;
