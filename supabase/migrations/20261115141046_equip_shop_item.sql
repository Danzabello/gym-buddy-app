-- B6. DI-11: equip in one statement. CoinService.equipItem sent one UPDATE per owned item in the category and
-- then one more, so a dropped connection could leave nothing equipped.
-- Prepared 2026-11-12, revised 2026-11-14 (data-layer pass). Applied 2026-11-15 with the owner's go-ahead.
-- New function only. SECURITY INVOKER: it runs under the caller's existing rights (SELECT and UPDATE (equipped) on
-- user_inventory, own rows by RLS; SELECT on available shop_items), so it can do nothing the client cannot already do.
-- No grant changes.
-- Returns false when the caller does not own the item (or the item is no longer available: shop_items RLS hides it,
-- as it does from the client today). No level check: level is enforced when the item is bought (purchase_shop_item).
-- Starter avatars (lion, wolf, bear) are not inventory items: they are worn through user_profiles.avatar_id and
-- never reach this function.
-- 2026-11-14 changes: names schema-qualified.
-- The UPDATE writes every owned row of the category, changed or not, on purpose: two calls at once for the same
-- user then lock the same rows, the second waits, re-reads each row and rewrites all of them, so the last call
-- wins and exactly one item is equipped. Writing only the rows whose flag changes would let both calls finish
-- with their own item equipped. Do not add an "only if changed" filter.
-- The client (CoinService.equipItem) needs this function live before the build that calls it ships.
-- Rollback: dev/rollback_20261115141046.sql (rehearsed before the apply: run twice inside a transaction that aborts).

CREATE FUNCTION public.equip_shop_item(p_shop_item_id uuid)
RETURNS boolean
LANGUAGE plpgsql
SET search_path = public
AS $$
DECLARE
  v_uid uuid := auth.uid();
  v_category text;
BEGIN
  SELECT si.category INTO v_category
  FROM public.user_inventory ui
  JOIN public.shop_items si ON si.id = ui.shop_item_id
  WHERE ui.user_id = v_uid AND ui.shop_item_id = p_shop_item_id;

  IF v_category IS NULL THEN
    RETURN false;
  END IF;

  UPDATE public.user_inventory ui
  SET equipped = (ui.shop_item_id = p_shop_item_id)
  FROM public.shop_items si
  WHERE si.id = ui.shop_item_id
    AND ui.user_id = v_uid
    AND si.category = v_category;

  RETURN true;
END;
$$;

REVOKE EXECUTE ON FUNCTION public.equip_shop_item(uuid) FROM PUBLIC, anon;
GRANT  EXECUTE ON FUNCTION public.equip_shop_item(uuid) TO authenticated;
