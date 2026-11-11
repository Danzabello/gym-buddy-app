-- ROLLBACK for supabase/migrations/20261106120000_notification_inbox_delete.sql
-- NOT a migration: lives in docs/ so `supabase db push` never runs it.
-- Drops the delete policy and revokes the delete grant. Rows users already deleted do not come back. Run as postgres.
BEGIN;
DROP POLICY "Users delete own inbox" ON public.notification_inbox;
REVOKE DELETE ON TABLE public.notification_inbox FROM authenticated;
COMMIT;
