-- INVITE-IP purge (prompt 45). invite_lookup_attempts holds the IP address of each invite-link lookup, for the invite-redirect rate limit
-- (20 requests per 10 minutes). The function prunes rows older than 10 minutes only when the next lookup arrives, so the last visitor's address
-- could stay for as long as nobody opened another invite link. The privacy policy says these records are deleted 10 to 11 minutes after the
-- request, so this adds a job that makes that true: every minute, delete rows older than 10 minutes. Nothing else changes: the function still
-- prunes on each request, the table keeps its RLS and no client grants.
-- ponytail: no index on attempted_at alone, a sequential scan of a table this small every minute is cheaper than a second index to maintain.
-- Rollback: dev/rollback_20261111200000.sql.

SELECT cron.schedule('purge-invite-lookup-attempts', '* * * * *',
  $$DELETE FROM public.invite_lookup_attempts WHERE attempted_at < now() - interval '10 minutes'$$);
