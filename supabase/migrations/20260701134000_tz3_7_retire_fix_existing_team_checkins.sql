-- STEP 3, migration #7 of the per-user timezone rework: retire
-- fix_existing_team_checkins.
--
-- A pre-version-control, one-off repair utility with ZERO callers (verified:
-- no references in the Flutter client, Edge Functions, or cron jobs). It
-- copied a member's today-check-in from any other team into the given team
-- and then DIRECTLY set current_streak = 1 — bypassing recompute_team_streak
-- and violating the single-writer architecture (recompute completes days,
-- reconcile_stale_streaks breaks streaks; nothing else writes streak counts).
-- It was also UTC-dated (CURRENT_DATE) and EXECUTE-granted to PUBLIC/anon.
--
-- Its legitimate use case (team created after a member already checked in)
-- is handled by the live paths: friend_service's backfill,
-- checkin_team_for_user, and recompute_team_streak.

DROP FUNCTION IF EXISTS public.fix_existing_team_checkins(uuid);
