-- recompute_team_streak: service_role only. The app has had no call to it since commit 44cfeea (the one call
-- was a redundant recompute in CoachMaxService; check_in_coach_max recomputes server-side).
-- Grant change: REVOKE EXECUTE on public.recompute_team_streak(uuid, date) from authenticated.
-- service_role keeps it: the coach-max-cron Edge Function calls it with the service-role client.
-- An installed build that still has the old call gets a permission error inside a try/catch that only logs
-- in debug, so nothing breaks for it.
-- dev/hygiene/suite/economy_suite.sql (G0.1) pinned this function as executable by authenticated; it is
-- updated in the same commit.
-- Rollback: dev/rollback_20261114012440.sql

REVOKE EXECUTE ON FUNCTION public.recompute_team_streak(uuid, date) FROM PUBLIC, anon, authenticated;
GRANT  EXECUTE ON FUNCTION public.recompute_team_streak(uuid, date) TO service_role;
