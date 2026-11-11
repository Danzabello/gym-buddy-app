-- ROLLBACK for supabase/migrations/20261111200000_purge_invite_lookup_attempts.sql
-- NOT a migration: lives in docs/ so `supabase db push` never runs it.
-- Unschedules the purge job. Rows already deleted do not come back; invite-redirect goes back to pruning only on each request, which means the
-- privacy policy's "deleted 10 to 11 minutes after the request" is no longer true (change the policy before or with this). Run as postgres.
BEGIN;
DO $$
BEGIN
  IF EXISTS (SELECT 1 FROM cron.job WHERE jobname = 'purge-invite-lookup-attempts') THEN
    PERFORM cron.unschedule('purge-invite-lookup-attempts');
  END IF;
END $$;
COMMIT;
