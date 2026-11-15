-- Rollback for 20261115141046_equip_shop_item.sql.
-- Drops the one function the migration added. Nothing is lost: it stores no data, and user_inventory.equipped keeps
-- whatever was equipped. A build that calls it cannot change the equipped item until it is back.
-- Safe to run twice and on a database that never had the function.
-- After running it: supabase migration repair --status reverted 20261115141046 is NOT the next step (CLAUDE.md:
-- never revert existing versions); ask the owner how the history should record it.
DROP FUNCTION IF EXISTS public.equip_shop_item(uuid);
