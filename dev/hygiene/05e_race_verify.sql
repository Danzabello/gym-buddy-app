-- 05e RACE-2 verify (read-only). Expected: one purchase won, balance = 150 - winning cost >= 0, 1 inventory row, 1 shop_purchase row.
WITH b AS (SELECT coin_balance FROM public.user_profiles WHERE id = 'cf4946f5-f921-4e81-bbf4-88d574e8baf5'),
     inv AS (SELECT count(*) n, string_agg(shop_item_id::text, ',') items FROM public.user_inventory WHERE user_id = 'cf4946f5-f921-4e81-bbf4-88d574e8baf5'),
     tx AS (SELECT count(*) n, coalesce(sum(amount), 0) s, string_agg(transaction_type || ':' || amount || ':' || reference_id, ',') d FROM public.coin_transactions WHERE user_id = 'cf4946f5-f921-4e81-bbf4-88d574e8baf5')
SELECT b.coin_balance, inv.n AS inventory_rows, inv.items, tx.n AS ledger_rows, tx.s AS ledger_sum, tx.d AS ledger,
       (inv.n = 1 AND tx.n = 1 AND b.coin_balance >= 0 AND b.coin_balance = 150 + tx.s
        AND tx.d LIKE 'shop_purchase:%' AND split_part(tx.d, ':', 3) = inv.items) AS pass
FROM b, inv, tx;
