-- B5. SB-5 / P-3 / P-7: one call for "who is on a break today" instead of one is_on_break_today call per buddy
-- (lib/home/dashboard_page.dart and lib/widgets/friends_page_modern.dart looped until the data-layer pass).
-- Prepared 2026-11-12, revised 2026-11-14 (data-layer pass). Applied 2026-11-15 with the owner's go-ahead.
-- New function only. SECURITY INVOKER like is_on_break_today, which it calls for each id, so it shows exactly
-- what the per-buddy call shows today (break_day_usage RLS and safe_user_tz still decide).
-- 2026-11-14 changes: NULLs and duplicates in the array are dropped, and only the first 200 non-NULL elements are
-- answered (the client sends a user's buddies or friends; the largest live list is 5). Past 200 a caller gets no
-- row, which the client reads as "not on a break", the same as a failed call today. The cap is a LIMIT on the
-- unnested rows, not an array slice, so a multi-dimensional array cannot get round it (review gate 1, finding 3).
-- The client (BreakDayService.usersOnBreakToday) needs this function live before the build that calls it ships.
-- Rollback: dev/rollback_20261115140911.sql (rehearsed before the apply: run twice inside a transaction that aborts).

CREATE FUNCTION public.are_on_break_today(p_user_ids uuid[])
RETURNS TABLE (user_id uuid, on_break boolean)
LANGUAGE sql
STABLE
SET search_path = public
AS $$
  SELECT u.id, public.is_on_break_today(u.id)
  FROM (SELECT DISTINCT c.id
        FROM (SELECT t.id FROM unnest(p_user_ids) AS t(id) WHERE t.id IS NOT NULL LIMIT 200) AS c) AS u;
$$;

REVOKE EXECUTE ON FUNCTION public.are_on_break_today(uuid[]) FROM PUBLIC, anon;
GRANT  EXECUTE ON FUNCTION public.are_on_break_today(uuid[]) TO authenticated;
