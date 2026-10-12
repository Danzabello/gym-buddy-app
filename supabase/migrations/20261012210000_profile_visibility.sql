-- LIVE-10: other users' profile rows expose only the discovery columns.
--
-- Column-level SELECT is an allowlist: a column added later is private by
-- default. Column grants bind the owner too, so the owner reads their own full
-- row through get_my_profile(). Rows stay visible to signed-in users (that is
-- what keeps PostgREST embedded selects working); private columns do not.
-- Writes are unchanged (the column INSERT/UPDATE grants are untouched).
-- Rollback: docs/rollback_20261012210000.sql

-- 1. Table: drop table-level SELECT (the column REVOKE trap: a column revoke is
--    a no-op while the table-level grant stands), then grant the allowlist.
REVOKE ALL ON public.user_profiles FROM anon;
REVOKE SELECT ON public.user_profiles FROM authenticated;
GRANT SELECT (id, username, display_name, avatar_id, avatar_border, fitness_level,
              looking_for_buddy, workout_days_per_week, created_at)
  ON public.user_profiles TO authenticated;

-- One SELECT policy instead of two (the own-row one is subsumed).
DROP POLICY "Users can view own profile" ON public.user_profiles;
DROP POLICY "Users can view other profiles" ON public.user_profiles;
CREATE POLICY "Signed-in users can view profiles" ON public.user_profiles
  FOR SELECT TO authenticated USING ((SELECT auth.uid()) IS NOT NULL);

-- 2. Own row, all columns.
CREATE FUNCTION public.get_my_profile()
RETURNS SETOF public.user_profiles
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public
AS $$ SELECT * FROM user_profiles WHERE id = auth.uid() $$;
REVOKE EXECUTE ON FUNCTION public.get_my_profile() FROM PUBLIC, anon;
GRANT  EXECUTE ON FUNCTION public.get_my_profile() TO authenticated;

-- 3. Teammates' timezones (shared team only; anyone else gets no row).
CREATE FUNCTION public.get_teammate_timezones(p_user_ids uuid[])
RETURNS TABLE(user_id uuid, timezone text)
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public
AS $$
  SELECT up.id, up.timezone
  FROM user_profiles up
  WHERE up.id = ANY(p_user_ids)
    AND EXISTS (SELECT 1 FROM team_members me
                JOIN team_members them ON them.team_id = me.team_id
                WHERE me.user_id = auth.uid() AND them.user_id = up.id)
$$;
REVOKE EXECUTE ON FUNCTION public.get_teammate_timezones(uuid[]) FROM PUBLIC, anon;
GRANT  EXECUTE ON FUNCTION public.get_teammate_timezones(uuid[]) TO authenticated;

-- 4. The two INVOKER readers become DEFINER. Each keeps the bound its INVOKER
--    version got from RLS, so it returns no more than before: the caller's own
--    workouts only (20260929211000), and only check-ins the
--    daily_team_checkins SELECT policy shows the caller.
CREATE OR REPLACE FUNCTION public.get_workouts_awaiting_creator_join(creator_id uuid)
 RETURNS TABLE(workout_id uuid, workout_type text, buddy_name text, planned_duration_minutes integer, started_at timestamp with time zone, join_window_end timestamp with time zone, time_remaining_seconds integer, popup_already_shown boolean)
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
BEGIN
  RETURN QUERY
  SELECT
    w.id as workout_id,
    w.workout_type,
    up.display_name as buddy_name,
    w.planned_duration_minutes,
    w.workout_started_at as started_at,
    -- Join window = started_at + (planned_duration / 4)
    w.workout_started_at + (w.planned_duration_minutes * INTERVAL '1 minute' / 4) as join_window_end,
    -- Time remaining in seconds
    EXTRACT(EPOCH FROM (
      (w.workout_started_at + (w.planned_duration_minutes * INTERVAL '1 minute' / 4)) - NOW()
    ))::INTEGER as time_remaining_seconds,
    COALESCE(w.creator_popup_shown, FALSE) as popup_already_shown
  FROM workouts w
  LEFT JOIN user_profiles up ON up.id = w.buddy_id
  WHERE w.user_id = creator_id
    AND creator_id = auth.uid()  -- caller's own workouts only
    AND w.status = 'in_progress'
    AND w.started_by_user_id = w.buddy_id  -- Buddy started it
    AND (w.creator_joined IS NULL OR w.creator_joined = FALSE)  -- Creator hasn't joined
    AND w.workout_started_at IS NOT NULL;
END;
$function$;
REVOKE EXECUTE ON FUNCTION public.get_workouts_awaiting_creator_join(uuid) FROM PUBLIC, anon;
GRANT  EXECUTE ON FUNCTION public.get_workouts_awaiting_creator_join(uuid) TO authenticated;

CREATE OR REPLACE FUNCTION public.get_team_checkin_order(p_team_streak_id uuid, p_check_date date)
 RETURNS TABLE(user_id uuid, display_name text, check_in_time timestamp with time zone, check_order integer)
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
BEGIN
  RETURN QUERY
  SELECT
    dtc.user_id,
    up.display_name,
    dtc.check_in_time,
    ROW_NUMBER() OVER (ORDER BY dtc.check_in_time)::INTEGER as check_order
  FROM daily_team_checkins dtc
  JOIN user_profiles up ON dtc.user_id = up.id
  WHERE dtc.team_streak_id = p_team_streak_id
    AND dtc.check_in_date = p_check_date
    -- same rows the daily_team_checkins SELECT policy shows the caller
    AND (dtc.user_id = auth.uid()
         OR EXISTS (SELECT 1 FROM team_streaks ts
                    JOIN team_members tm ON tm.team_id = ts.team_id
                    WHERE ts.id = dtc.team_streak_id AND tm.user_id = auth.uid())
         OR EXISTS (SELECT 1 FROM friendships f
                    WHERE f.status = 'accepted'
                      AND ((f.user_id = auth.uid() AND f.friend_id = dtc.user_id)
                        OR (f.friend_id = auth.uid() AND f.user_id = dtc.user_id))))
  ORDER BY dtc.check_in_time;
END;
$function$;
REVOKE EXECUTE ON FUNCTION public.get_team_checkin_order(uuid, date) FROM PUBLIC, anon;
GRANT  EXECUTE ON FUNCTION public.get_team_checkin_order(uuid, date) TO authenticated;
