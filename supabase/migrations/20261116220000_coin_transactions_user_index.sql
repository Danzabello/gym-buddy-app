-- M2 (DB audit DB-2): coin_transactions has no index that leads with user_id (the only one is partial, on
-- achievement rows), so every coin read and every profile-delete cascade scans the whole table. Every app read is
-- user_id = me plus created_at (history page, week totals, partner-bonus check, realtime filter).
-- Same shape as the sibling idx_xp_transactions_user_id (user_id, created_at DESC).
-- Plain CREATE INDEX: CONCURRENTLY cannot run in the CLI's one-transaction file, and the table is small (SHARE lock
-- for milliseconds; a concurrent coin insert waits that long). No policy, grant, function or lock-order change.
CREATE INDEX idx_coin_transactions_user_created ON public.coin_transactions (user_id, created_at DESC);
