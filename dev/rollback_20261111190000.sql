-- ROLLBACK for supabase/migrations/20261111190000_stale_accounts.sql
-- NOT a migration: lives in docs/ so `supabase db push` never runs it.
-- Removes the daily job, the two functions and the run log. Accounts the job already deleted do not come back.
-- The Edge Function is separate: supabase functions delete stale-accounts-cron. Run as postgres.
BEGIN;
DO $$
BEGIN
  IF EXISTS (SELECT 1 FROM cron.job WHERE jobname = 'stale-accounts-daily') THEN
    PERFORM cron.unschedule('stale-accounts-daily');
  END IF;
END $$;
DROP FUNCTION public.stale_account_preview(integer, integer);
DROP FUNCTION public.stale_account_candidates(integer);
DROP TABLE public.stale_account_runs;
COMMIT;
