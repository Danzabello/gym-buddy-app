-- 05e RACE-2 seed (committed). testtest1 baseline: coin_balance 0, 0 user_inventory rows, 0 coin_transactions rows.
-- Direct UPDATE as postgres; no credit function, no ledger row. Aborts if the baseline has changed.
DO $$
BEGIN
  IF (SELECT coin_balance FROM public.user_profiles WHERE id = 'cf4946f5-f921-4e81-bbf4-88d574e8baf5') <> 0
     OR EXISTS (SELECT 1 FROM public.user_inventory WHERE user_id = 'cf4946f5-f921-4e81-bbf4-88d574e8baf5')
     OR EXISTS (SELECT 1 FROM public.coin_transactions WHERE user_id = 'cf4946f5-f921-4e81-bbf4-88d574e8baf5') THEN
    RAISE EXCEPTION 'testtest1 baseline changed; not seeding';
  END IF;
END $$;
UPDATE public.user_profiles SET coin_balance = 150 WHERE id = 'cf4946f5-f921-4e81-bbf4-88d574e8baf5';
SELECT coin_balance FROM public.user_profiles WHERE id = 'cf4946f5-f921-4e81-bbf4-88d574e8baf5';
