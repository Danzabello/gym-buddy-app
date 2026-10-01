-- ROLLBACK for supabase/migrations/20261001202006_live24_process_stale_sessions.sql
-- NOT a migration: lives in docs/ so `supabase db push` never runs it.
-- Unschedules the process-stale-sessions cron job and drops the session
-- lifecycle functions. Open sessions then go back to never being closed
-- server-side (UX-3 / B-1). Run as postgres, before rollback_20261001170947.
BEGIN;
SELECT cron.unschedule('process-stale-sessions');
DROP FUNCTION public.process_stale_sessions(timestamptz);
DROP FUNCTION public._server_checkin(uuid, date);
COMMIT;
