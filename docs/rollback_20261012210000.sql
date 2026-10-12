-- ROLLBACK for supabase/migrations/20261012210000_profile_visibility.sql
-- NOT a migration: lives in docs/ so `supabase db push` never runs it.
-- Restores the pre-LIVE-10 state exactly (all columns readable by any signed-in
-- user, anon table grants, both SELECT policies, the two INVOKER functions).
-- Run as postgres. The client on fix/profile-visibility calls get_my_profile and
-- get_teammate_timezones, so roll the app back first or those reads fail.
BEGIN;
GRANT SELECT, REFERENCES, TRIGGER ON public.user_profiles TO anon;
GRANT SELECT ON public.user_profiles TO authenticated;
REVOKE SELECT (id, username, display_name, avatar_id, avatar_border, fitness_level,
               looking_for_buddy, workout_days_per_week, created_at)
  ON public.user_profiles FROM authenticated;  -- column grants (table grant above covers them)

DROP POLICY "Signed-in users can view profiles" ON public.user_profiles;
CREATE POLICY "Users can view own profile" ON public.user_profiles
  FOR SELECT USING (auth.uid() = id);
CREATE POLICY "Users can view other profiles" ON public.user_profiles
  FOR SELECT USING (auth.uid() IS NOT NULL);

DROP FUNCTION public.get_my_profile();
DROP FUNCTION public.get_teammate_timezones(uuid[]);

CREATE OR REPLACE FUNCTION public.get_workouts_awaiting_creator_join(creator_id uuid)
 RETURNS TABLE(workout_id uuid, workout_type text, buddy_name text, planned_duration_minutes integer, started_at timestamp with time zone, join_window_end timestamp with time zone, time_remaining_seconds integer, popup_already_shown boolean)
 LANGUAGE plpgsql
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
  ORDER BY dtc.check_in_time;
END;
$function$;
ALTER FUNCTION public.get_team_checkin_order(uuid, date) RESET search_path;
GRANT EXECUTE ON FUNCTION public.get_team_checkin_order(uuid, date) TO PUBLIC, anon, authenticated;
COMMIT;
