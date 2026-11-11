-- ROLLBACK for supabase/migrations/20261005210706_realtime_dashboard_checkins_private.sql
-- NOT a migration: lives in docs/ so `supabase db push` never runs it.
-- With "Allow public access" OFF this stops the dashboard's live check-in
-- feed (private join denied). Run as postgres.
BEGIN;
DROP POLICY "authenticated can join dashboard_checkins" ON realtime.messages;
COMMIT;
