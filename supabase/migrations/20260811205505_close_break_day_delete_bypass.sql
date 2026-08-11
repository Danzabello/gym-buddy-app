-- Close the weekly break-day cap bypass.
--
-- declare_break_day() enforces the cap by counting live rows:
--
--   SELECT count(*) ... FROM break_day_usage
--    WHERE user_id = v_uid AND break_date BETWEEN ... AND cancelled_at IS NULL
--
-- That count is correct, server-computed and race-safe (advisory lock), but it
-- is derived from rows the user could delete. break_day_usage granted
-- anon/authenticated full CRUD (arwdDxtm) AND carried a permissive
-- "Users can delete their own break days" policy, so a plain client-side
-- DELETE succeeded. Measured before this migration: seed 3 break days at a cap
-- of 3, declare -> limit_reached; DELETE one row from the client -> 1 row
-- removed; declare -> success. Four days off in a capped week, repeatable
-- indefinitely.
--
-- Deleting a spent break day is also invisible to streak integrity: both
-- recompute_team_streak and reconcile_stale_streaks only ever scan forward
-- from last_workout_date, so a row the streak has already passed is never
-- re-examined. The bypass costs the user nothing.
--
-- Nothing legitimate deletes from this table: no Dart call site, no DB
-- function, no trigger. The sanctioned revoke path is cancelBreakDay()'s
-- UPDATE of cancelled_at, which is already correctly constrained by
-- "Users can cancel their own break days" (WITH CHECK cancelled_at IS NOT
-- NULL -- cancel only, no un-cancel, no user_id reassignment) and is left
-- untouched here. Soft-cancel is the right model: it frees the slot while
-- preserving the row that recompute_team_streak reads.

-- ── 1. Remove the DELETE capability ─────────────────────────────────────────
-- The REVOKE is what actually closes the hole. The policy is dropped as well,
-- following the same reasoning recorded in 20260717181500 for the invites
-- accept policy: a permissive policy left pointing at a revoked grant is not
-- inert documentation, it is a loaded gun. Any future blanket re-GRANT (a
-- "GRANT ALL ON ALL TABLES" during some later fix) would silently re-open the
-- bypass with no second barrier. With the policy gone, a re-grant alone is not
-- enough to exploit it -- RLS would still deny for want of a DELETE policy,
-- which is exactly how invites failed soft rather than open.
REVOKE DELETE ON public.break_day_usage FROM anon, authenticated;
DROP POLICY IF EXISTS "Users can delete their own break days" ON public.break_day_usage;

-- ── 2. is_on_break_today: grant hygiene ─────────────────────────────────────
-- Not an active leak: the function is STABLE SQL and NOT SECURITY DEFINER, so
-- it runs as the caller and RLS on break_day_usage still applies -- an anon
-- caller resolves to false for everyone. But it carried a bare PUBLIC EXECUTE
-- (acl "=X/postgres"), against the standing rule that every client-facing
-- function states its grants explicitly. Both callers
-- (friends_page_modern.dart:135, home_screen.dart:2335) run inside HomeScreen,
-- which AuthWrapper only reaches post-authentication, and both already swallow
-- RPC errors into "no badge", so this cannot break an unauthenticated path.
REVOKE EXECUTE ON FUNCTION public.is_on_break_today(uuid) FROM PUBLIC, anon;
GRANT  EXECUTE ON FUNCTION public.is_on_break_today(uuid) TO authenticated;
