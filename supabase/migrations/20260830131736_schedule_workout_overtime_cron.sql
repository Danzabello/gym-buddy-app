-- Schedules the workout-overtime-cron edge function every 5 minutes, same
-- pattern as coach-max-hourly (20260701120500): pg_cron -> net.http_post,
-- bearer token read from the vault at fire time rather than baked into the
-- job definition.
--
-- 5 minutes keeps the 15-minute-overtime and 30-minute-renag thresholds
-- tight without over-polling: worst-case latency on either threshold is
-- under 5 minutes.

SELECT cron.schedule(
  'workout-overtime-every-5min',
  '*/5 * * * *',
  $job$
  SELECT net.http_post(
    url := 'https://jwpbunulswiihkzpjopy.supabase.co/functions/v1/workout-overtime-cron',
    headers := jsonb_build_object(
      'Content-Type', 'application/json',
      'Authorization', 'Bearer ' || (SELECT decrypted_secret FROM vault.decrypted_secrets WHERE name = 'service_role_key' LIMIT 1)
    ),
    body := '{}'::jsonb
  );
  $job$
);
