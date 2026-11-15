-- Rollback for 20261115142635_coach_max_schedule_job.sql.
-- Stops the 5-minute job and drops its function. Rows the job already inserted stay: they are ordinary schedule
-- rows. After this, rows come from the hourly coach-max-cron Edge Function, and from the client on builds that
-- still insert them.
-- Order: if the INSERT revoke (file 2 of P-5) is ever live, roll that back first, or accept that rows then come
-- from the hourly Edge Function alone (a user who joins mid-day waits up to an hour for a row; no streak is affected).
-- Safe to run twice and on a database that never had the job.
-- After running it: supabase migration repair --status reverted 20261115142635 is NOT the next step (CLAUDE.md:
-- never revert existing versions); ask the owner how the history should record it.
SELECT cron.unschedule(jobname) FROM cron.job WHERE jobname = 'coach-max-schedule-rows';
DROP FUNCTION IF EXISTS public.schedule_coach_max_today();
