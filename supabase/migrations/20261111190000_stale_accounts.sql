-- STALE-ACCOUNTS (prompt 44). Accounts that never finished setting up are deleted 30 days after they were created or
-- last signed in, whichever is later, so dead sign-ups and their email addresses do not sit in the database.
--
-- Unfinished: no user_profiles row, or a row with onboarding_completed = false. A NULL flag counts as finished, a
-- finished account is never matched, and neither is Coach Max (00000000-0000-0000-0000-000000000001). An unfinished
-- account that a Join on the buddy step already paired (it has a team_members row) is listed but never deleted: the
-- inviter's team and streak would be left behind. The clock is auth.users.created_at and auth.users.last_sign_in_at.
--
-- This migration only reads. The delete is done by the stale-accounts-cron Edge Function, with the same two steps as
-- delete-account (the user_profiles row, then auth.admin.deleteUser): a SQL function cannot delete from auth.users.
--   stale_account_candidates(p_days)   every unfinished account idle for more than p_days, with a paired flag
--   stale_account_preview(p_days, p_cap)  the same rows with what the next run would do; deletes and writes nothing
--   stale_account_runs                 one row per run of the function: counts only, no email, no id
-- The daily job is created switched OFF. Switch it on or off with cron.alter_job(...) (docs/hygiene/44_stale_accounts_probe.sql
-- shows the statements). Everything here is service_role only; nothing is reachable from the app.
-- Rollback: docs/rollback_20261111190000.sql.

CREATE TABLE public.stale_account_runs (
  id          uuid        PRIMARY KEY DEFAULT gen_random_uuid(),
  ran_at      timestamptz NOT NULL DEFAULT now(),
  mode        text        NOT NULL CHECK (mode IN ('run', 'dry_run')),
  cap         integer     NOT NULL,
  candidates  integer     NOT NULL,  -- eligible accounts when the run started (paired ones not counted)
  deleted     integer     NOT NULL DEFAULT 0,
  failed      integer     NOT NULL DEFAULT 0,
  skipped     integer     NOT NULL DEFAULT 0,  -- looked at again just before the delete and left alone
  note        text
);
ALTER TABLE public.stale_account_runs ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON TABLE public.stale_account_runs FROM PUBLIC, anon, authenticated;
GRANT ALL ON TABLE public.stale_account_runs TO service_role;
COMMENT ON TABLE public.stale_account_runs IS 'One row per run of the stale-accounts-cron Edge Function. Counts only: no email, no user id.';

CREATE OR REPLACE FUNCTION public.stale_account_candidates(p_days integer DEFAULT 30)
 RETURNS TABLE(user_id uuid, created_at timestamptz, last_sign_in_at timestamptz, idle_since timestamptz, days_idle integer,
               has_profile boolean, onboarding_completed boolean, provider text, email_masked text, paired boolean)
 LANGUAGE sql
 STABLE
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  SELECT u.id, u.created_at, u.last_sign_in_at, i.idle_since,
         floor(extract(epoch FROM now() - i.idle_since) / 86400)::integer,
         p.id IS NOT NULL,
         p.onboarding_completed,
         coalesce(u.raw_app_meta_data ->> 'provider', 'unknown'),
         CASE WHEN u.email IS NULL OR u.email = '' THEN NULL
              ELSE left(u.email, 1) || '***@' || split_part(u.email, '@', 2) END,
         EXISTS (SELECT 1 FROM public.team_members tm WHERE tm.user_id = u.id)
  FROM auth.users u
  LEFT JOIN public.user_profiles p ON p.id = u.id
  CROSS JOIN LATERAL (SELECT greatest(u.created_at, coalesce(u.last_sign_in_at, u.created_at)) AS idle_since) i
  WHERE u.id <> '00000000-0000-0000-0000-000000000001'::uuid
    AND (p.id IS NULL OR p.onboarding_completed = false)
    AND i.idle_since < now() - make_interval(days => p_days)
  ORDER BY i.idle_since, u.id;
$function$;

CREATE OR REPLACE FUNCTION public.stale_account_preview(p_days integer DEFAULT 30, p_cap integer DEFAULT 25)
 RETURNS TABLE(action text, user_id uuid, created_at timestamptz, last_sign_in_at timestamptz, days_idle integer,
               has_profile boolean, onboarding_completed boolean, provider text, email_masked text)
 LANGUAGE sql
 STABLE
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  SELECT CASE WHEN c.paired THEN 'skip: paired'
              WHEN row_number() OVER (PARTITION BY c.paired ORDER BY c.idle_since, c.user_id) <= p_cap THEN 'delete (next run)'
              ELSE 'delete (later run)' END,
         c.user_id, c.created_at, c.last_sign_in_at, c.days_idle, c.has_profile, c.onboarding_completed, c.provider, c.email_masked
  FROM public.stale_account_candidates(p_days) c
  ORDER BY c.paired, c.idle_since, c.user_id;
$function$;

REVOKE EXECUTE ON FUNCTION public.stale_account_candidates(integer) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.stale_account_candidates(integer) TO service_role;
REVOKE EXECUTE ON FUNCTION public.stale_account_preview(integer, integer) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.stale_account_preview(integer, integer) TO service_role;
COMMENT ON FUNCTION public.stale_account_candidates(integer) IS 'Unfinished accounts idle for more than p_days (later of created_at and last_sign_in_at). Never Coach Max, never a finished account, a NULL onboarding flag counts as finished. paired accounts are flagged: the Edge Function never deletes them.';
COMMENT ON FUNCTION public.stale_account_preview(integer, integer) IS 'What the next stale-accounts-cron run would do, masked emails, deletes and writes nothing.';

-- Daily at 03:47 UTC (clear of coach-max-hourly at :00, purge-cron-run-details 03:17, purge-notification-inbox 03:23).
-- Created OFF: nothing runs until cron.alter_job(..., active := true).
SELECT cron.schedule(
  'stale-accounts-daily',
  '47 3 * * *',
  $job$
  SELECT net.http_post(
    url := 'https://jwpbunulswiihkzpjopy.supabase.co/functions/v1/stale-accounts-cron',
    headers := jsonb_build_object(
      'Content-Type', 'application/json',
      'Authorization', 'Bearer ' || (SELECT decrypted_secret FROM vault.decrypted_secrets WHERE name = 'service_role_key' LIMIT 1)
    ),
    body := '{"cap":25}'::jsonb
  );
  $job$
);
SELECT cron.alter_job((SELECT jobid FROM cron.job WHERE jobname = 'stale-accounts-daily'), active := false);
