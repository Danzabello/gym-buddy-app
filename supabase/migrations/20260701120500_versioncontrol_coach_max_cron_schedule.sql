-- Version-control the hourly Coach Max cron job.
--
-- This job (jobname 'coach-max-hourly') was originally created ad-hoc and was
-- the last scheduled job not captured in migrations. It POSTs to the
-- coach-max-cron edge function every hour; that function then fires each
-- user's Coach Max check-in once their randomly-drawn 07:00-17:00
-- Europe/Dublin time-of-day has passed.
--
-- Hourly is sufficient: the firing window is 10h wide, so the worst-case
-- latency between a drawn time and its trigger is ~1h. To tighten that, change
-- the schedule to '*/15 * * * *'.
--
-- cron.schedule() upserts by job name, so this reproduces the existing live
-- job verbatim and is a no-op against current state — it just brings the job
-- under version control. Requires the pg_cron + pg_net extensions and the
-- 'service_role_key' secret in Vault (all already present).

SELECT cron.schedule(
  'coach-max-hourly',
  '0 * * * *',
  $job$
  SELECT net.http_post(
    url := 'https://jwpbunulswiihkzpjopy.supabase.co/functions/v1/coach-max-cron',
    headers := jsonb_build_object(
      'Content-Type', 'application/json',
      'Authorization', 'Bearer ' || (SELECT decrypted_secret FROM vault.decrypted_secrets WHERE name = 'service_role_key' LIMIT 1)
    ),
    body := '{}'::jsonb
  );
  $job$
);
