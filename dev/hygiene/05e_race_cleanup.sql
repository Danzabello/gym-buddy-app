-- 05e RACE-2 cleanup (committed), as postgres. Baseline had no user_inventory or coin_transactions rows for testtest1,
-- so every such row now present was written by the race. Deletes only the two probe items' rows, restores coin_balance 0,
-- then aborts the whole cleanup unless testtest1 is back to the baseline shape.
BEGIN;
DELETE FROM public.user_inventory WHERE user_id = 'cf4946f5-f921-4e81-bbf4-88d574e8baf5' AND shop_item_id IN ('78594031-1074-46ed-b80b-a1cbcb7043b0', '9eeca178-1353-406d-8671-54e59bdcf26d');
DELETE FROM public.coin_transactions WHERE user_id = 'cf4946f5-f921-4e81-bbf4-88d574e8baf5' AND transaction_type = 'shop_purchase' AND reference_id IN ('78594031-1074-46ed-b80b-a1cbcb7043b0', '9eeca178-1353-406d-8671-54e59bdcf26d');
UPDATE public.user_profiles SET coin_balance = 0 WHERE id = 'cf4946f5-f921-4e81-bbf4-88d574e8baf5';
DO $$
BEGIN
  IF (SELECT coin_balance FROM public.user_profiles WHERE id = 'cf4946f5-f921-4e81-bbf4-88d574e8baf5') <> 0
     OR EXISTS (SELECT 1 FROM public.user_inventory WHERE user_id = 'cf4946f5-f921-4e81-bbf4-88d574e8baf5')
     OR EXISTS (SELECT 1 FROM public.coin_transactions WHERE user_id = 'cf4946f5-f921-4e81-bbf4-88d574e8baf5') THEN
    RAISE EXCEPTION 'cleanup did not return testtest1 to baseline; rolled back';
  END IF;
END $$;
COMMIT;
