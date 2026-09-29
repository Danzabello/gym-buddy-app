-- Wolf/Lion shop_items rows are no longer part of the Level path (superseded
-- by Shark/Tiger under the new forest-layout Wolf hub). unlock_path/
-- unlock_tier exist only for the tree feature, so clearing them just makes
-- the DB match reality — no legacy behavior reads these columns on these
-- rows (the Wolf/Lion hub equip slugs are hardcoded in the Flutter widget,
-- entirely independent of these shop_items rows).
UPDATE public.shop_items
SET unlock_path = NULL, unlock_tier = NULL
WHERE id IN ('447e6731-e218-4f0c-87b4-bb8a5db941a5', '7f4536a9-1abf-4a4d-b6d9-5256b61d1ec2');
