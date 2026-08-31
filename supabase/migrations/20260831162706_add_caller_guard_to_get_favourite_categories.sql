-- get_favourite_categories was missing the caller-identity guard.
--
-- It is SECURITY DEFINER, granted to authenticated, and takes p_user_id as a
-- parameter with no check that the caller IS that user -- so any authenticated
-- user could read anyone else's workout-category breakdown by passing their
-- UUID. Same IDOR shape as the invite enumeration closed in Group C, lower
-- severity (aggregate stats, not credentials).
--
-- Its own header claimed to mirror get_user_streaks' shape, but that is
-- exactly the guard it had omitted. Added verbatim, including the comment,
-- at the top of the body before any query runs:
--
--   IF auth.uid() IS NOT NULL AND auth.uid() IS DISTINCT FROM p_user_id THEN
--     RAISE EXCEPTION 'forbidden';
--   END IF;
--
-- NULL auth.uid() stays allowed, matching get_user_streaks: that is trusted
-- server-side context (service_role / admin), not an end-user JWT.
--
-- ── One unavoidable consequence: LANGUAGE sql -> plpgsql ───────────────────
-- A LANGUAGE sql function cannot host an IF/RAISE, so the guard is impossible
-- without the language change. The query itself is unchanged in meaning, but
-- two mechanical edits were forced by plpgsql's variable substitution, and
-- both are load-bearing:
--
--   * The table is aliased `wl` and the column qualified wl.workout_category.
--     RETURNS TABLE makes workout_category an OUT parameter, so an unqualified
--     reference matches both a variable and a column -- ambiguous, and under
--     the default #variable_conflict error it raises at runtime.
--   * ORDER BY uses ordinals (2 DESC, 1 ASC) rather than the alias names.
--     workout_logs has no category_count column, so `ORDER BY category_count`
--     would have bound to the OUT parameter -- a NULL constant -- and sorted
--     by nothing at all, silently. Ordinals cannot bind to a variable.
--     Semantically identical: column 2 is the count, column 1 the category.
--
-- Verified live via BEGIN/ROLLBACK with two synthetic users:
--   * A calling get_favourite_categories(B) now raises 'forbidden' (was:
--     returned B's rows).
--   * B calling it for themselves returns their own 3 categories, correctly
--     ordered by count desc then name asc -- confirming the ordinal ORDER BY
--     still sorts, and the LIMIT 3 still truncates.
--   * NULL auth.uid() (server-side context) still allowed through.
-- Rolled back and re-checked clean: workout_logs 11 rows and user_profiles 38
-- unchanged, zero residual test rows.

CREATE OR REPLACE FUNCTION public.get_favourite_categories(p_user_id uuid)
 RETURNS TABLE(workout_category text, category_count bigint)
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
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
  GROUP BY wl.workout_category
  ORDER BY 2 DESC, 1 ASC
  LIMIT 3;
END;
$function$;

REVOKE ALL ON FUNCTION public.get_favourite_categories(uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.get_favourite_categories(uuid) TO authenticated;
