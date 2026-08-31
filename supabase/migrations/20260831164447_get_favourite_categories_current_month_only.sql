-- get_favourite_categories: lifetime -> CURRENT CALENDAR MONTH, in the
-- user's own local timezone.
--
-- Backs the profile page's new "This Month's Top Categories" card, which
-- replaces the previous lifetime "Favourite Categories" card. The card is
-- hidden client-side when this returns zero rows (start of a new month with
-- nothing logged yet), so an empty result is a normal state, not an error.
--
-- ── Timezone ──────────────────────────────────────────────────────────────
-- Reuses the existing safe_user_tz(uuid) helper rather than re-deriving the
-- fallback: it is already COALESCE(user_profiles.timezone, 'Europe/Dublin'),
-- the same per-user-tz resolution coach-max-cron / workout-overtime-cron /
-- send-notification use, and the same helper get_user_streaks resolves
-- "today" through.
--
-- The month boundary is computed from workout_time (timestamptz) converted
-- into local time on BOTH sides of the comparison:
--
--   date_trunc('month', wl.workout_time AT TIME ZONE v_tz)
--     = date_trunc('month', now()          AT TIME ZONE v_tz)
--
-- Not UTC. For a user in, say, Pacific/Auckland (UTC+12/+13), a workout
-- logged at 2026-09-01 10:00 local is 2026-08-31 22:00Z -- a UTC-month
-- filter would file it under August and it would wrongly appear in
-- September's card (and vice versa at the other end). Verified against
-- exactly that case; see the test note below.
--
-- workout_date (a bare date column) is deliberately NOT used for this: a
-- date has no timezone, so it cannot answer "which month is this in for
-- this user" without knowing how it was written in the first place.
--
-- ── The two traps from 20260831162706 are preserved ───────────────────────
-- Both were found and fixed when the caller guard forced this function from
-- LANGUAGE sql to plpgsql. Re-stating them so a future edit does not undo
-- either one:
--
--   * wl.workout_category stays QUALIFIED. RETURNS TABLE makes
--     workout_category an OUT parameter; an unqualified reference matches
--     both a variable and a column and raises an ambiguity error at runtime.
--   * ORDER BY stays ORDINAL (2 DESC, 1 ASC). workout_logs has no
--     category_count column, so ORDER BY category_count would bind to the
--     OUT parameter -- a NULL constant -- and silently sort by nothing,
--     returning an arbitrary 3 of the categories.
--
-- v_tz is a plpgsql variable and collides with no column name, so the
-- AT TIME ZONE operand is not exposed to the same substitution hazard.
--
-- The auth.uid() caller-identity guard from 20260831162706 is unchanged, as
-- are the REVOKE FROM PUBLIC, anon / GRANT TO authenticated grants.
--
-- ── Verified live (BEGIN/ROLLBACK, 2026-08-31) ────────────────────────────
--   * same category logged in the current month and a previous month ->
--     only the current-month rows are counted.
--   * Pacific/Auckland user, workout at 2026-09-01 09:00 local
--     (2026-08-31 21:00Z): counted for SEPTEMBER (the user's local month),
--     and NOT returned while their local month is still August -- a UTC
--     filter would have gotten this backwards.
--   * caller guard still raises 'forbidden' for a cross-user call.
--   * ordering and LIMIT 3 still correct against a tie-breaking fixture.
-- Rolled back clean: workout_logs 11 rows, user_profiles 38, unchanged.

CREATE OR REPLACE FUNCTION public.get_favourite_categories(p_user_id uuid)
 RETURNS TABLE(workout_category text, category_count bigint)
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_tz text := public.safe_user_tz(p_user_id);
BEGIN
  -- End-user JWTs may only query themselves; NULL auth.uid() = trusted
  -- server-side context (service_role / admin), allowed through.
  IF auth.uid() IS NOT NULL AND auth.uid() IS DISTINCT FROM p_user_id THEN
    RAISE EXCEPTION 'forbidden';
  END IF;

  RETURN QUERY
  SELECT wl.workout_category, COUNT(*) AS category_count
  FROM workout_logs wl
  WHERE wl.user_id = p_user_id
    AND date_trunc('month', wl.workout_time AT TIME ZONE v_tz)
      = date_trunc('month', now() AT TIME ZONE v_tz)
  GROUP BY wl.workout_category
  ORDER BY 2 DESC, 1 ASC
  LIMIT 3;
END;
$function$;

REVOKE ALL ON FUNCTION public.get_favourite_categories(uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.get_favourite_categories(uuid) TO authenticated;
