-- Publishes coin_transactions to Realtime (Postgres Changes) so the open
-- dashboard header shows coins live, including credits made by someone
-- else's action (the invite reward paid to the inviter) or in the database.
-- RLS ("Users see own transactions", auth.uid() = user_id) scopes each
-- subscriber to their own rows, and Realtime enforces RLS per subscriber, so
-- no extra filtering is needed here to keep this scoped rather than global.
-- user_profiles is deliberately NOT published: it holds private columns and
-- the client re-reads the numbers through get_my_profile instead.
--
-- Rollback: ALTER PUBLICATION supabase_realtime DROP TABLE public.coin_transactions;
--
-- The future COIN-TX-ANON migration may revoke anon and any extra grants on
-- this table, but must keep SELECT for authenticated, or Realtime stops
-- delivering these rows.
--
-- No new table or function, so no grants to add. Guarded so a re-run is safe.
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1
    FROM pg_publication_tables
    WHERE pubname = 'supabase_realtime'
      AND schemaname = 'public'
      AND tablename = 'coin_transactions'
  ) THEN
    ALTER PUBLICATION supabase_realtime ADD TABLE public.coin_transactions;
  END IF;
END
$$;
