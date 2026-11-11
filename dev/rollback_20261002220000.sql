-- ROLLBACK for supabase/migrations/20261002220000_pending_notice.sql
-- NOT a migration: lives in docs/ so `supabase db push` never runs it.
-- Drops the notice RPCs (the app must not call them after this). Run as postgres.
BEGIN;
DROP FUNCTION public.mark_notice_seen(uuid[]);
DROP FUNCTION public.get_pending_notice();
COMMIT;
