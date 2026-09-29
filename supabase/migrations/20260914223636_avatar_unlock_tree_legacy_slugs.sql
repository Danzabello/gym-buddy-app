-- shop_items.asset_id was decorative/unused elsewhere in the app (confirmed:
-- ShopItem.assetId is parsed but never read anywhere in the Flutter codebase).
-- Repurposing it to carry the bare legacy avatar_id slug each tree node equips
-- to on Select — the exact string every hardcoded emoji-lookup map in the app
-- (avatar_catalog.dart, user_avatar.dart, home_screen.dart, etc.) expects.

-- Bison -> Buffalo: the legacy slug/name the rest of the app already uses.
UPDATE public.shop_items
SET name = 'Buffalo', asset_id = 'buffalo'
WHERE unlock_path = 'coop' AND unlock_tier = 1;

UPDATE public.shop_items SET asset_id = 'wolf'    WHERE unlock_path = 'level'   AND unlock_tier = 1;
UPDATE public.shop_items SET asset_id = 'lion'    WHERE unlock_path = 'level'   AND unlock_tier = 2;
UPDATE public.shop_items SET asset_id = 'eagle'   WHERE unlock_path = 'workout' AND unlock_tier = 1;
UPDATE public.shop_items SET asset_id = 'gorilla' WHERE unlock_path = 'workout' AND unlock_tier = 2;
UPDATE public.shop_items SET asset_id = 'robot'   WHERE unlock_path = 'special' AND unlock_tier = 1;

-- Mammoth and Seasonal Creature have no legacy slug anywhere in the app yet —
-- NULL asset_id is the explicit "not equippable yet" signal the client checks
-- before showing a Select button, rather than writing an avatar_id that no
-- emoji-lookup map recognizes.
UPDATE public.shop_items SET asset_id = NULL WHERE unlock_path = 'coop'    AND unlock_tier = 2;
UPDATE public.shop_items SET asset_id = NULL WHERE unlock_path = 'special' AND unlock_tier = 2;
