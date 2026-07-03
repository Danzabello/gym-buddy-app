-- STEP 3, migration #6b of the per-user timezone rework (hardening follow-up).
--
-- get_user_streaks was EXECUTE-granted to PUBLIC and anon — a SECURITY
-- DEFINER function taking an arbitrary p_user_id, so anyone holding the
-- shipped anon key could pull any user's team names, usernames, avatars and
-- check-in times. Pre-existing exposure (predates version control), spotted
-- during tz3_6 verification.
--
-- Two-layer fix:
--   1. Grants: revoke PUBLIC/anon, keep authenticated (+ service_role).
--   2. Identity check inside the function: an end-user JWT may only query
--      ITSELF (auth.uid() = p_user_id). No-JWT contexts (service_role /
--      postgres admin) pass through — auth.uid() is NULL there, and blocking
--      them would break server-side/maintenance use.
--
-- Function body is otherwise identical to tz3_6 (viewer-tz today_check_ins).

CREATE OR REPLACE FUNCTION public.get_user_streaks(p_user_id uuid)
 RETURNS json
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  result JSON;
  -- The viewer's own local today (was CURRENT_DATE, i.e. UTC).
  v_today date := (now() AT TIME ZONE public.safe_user_tz(p_user_id))::date;
BEGIN
  -- End-user JWTs may only query themselves; NULL auth.uid() = trusted
  -- server-side context (service_role / admin), allowed through.
  IF auth.uid() IS NOT NULL AND auth.uid() IS DISTINCT FROM p_user_id THEN
    RAISE EXCEPTION 'forbidden';
  END IF;

  SELECT json_agg(team_data) INTO result
  FROM (
    SELECT
      bt.id as team_id,
      bt.team_name,
      bt.team_emoji,
      bt.is_coach_max_team,
      ts.id as streak_id,
      ts.current_streak,
      ts.best_streak,
      ts.total_workouts,
      ts.longest_streak,
      ts.last_workout_date,
      ts.last_interaction_at,
      ts.is_favorite,
      (
        SELECT json_agg(m)
        FROM (
          SELECT up.id as user_id, up.display_name, up.avatar_id, up.username
          FROM team_members tm2
          JOIN user_profiles up ON up.id = tm2.user_id
          WHERE tm2.team_id = bt.id
        ) m
      ) as members,
      (
        SELECT json_agg(c)
        FROM (
          SELECT sc.user_id, sc.check_in_time as checked_in_at
          FROM daily_team_checkins sc
          WHERE sc.team_streak_id = ts.id
          AND sc.check_in_date = v_today
        ) c
      ) as today_check_ins
    FROM team_members tm
    JOIN buddy_teams bt ON bt.id = tm.team_id
    LEFT JOIN team_streaks ts ON ts.team_id = bt.id AND ts.is_active = true
    WHERE tm.user_id = p_user_id
  ) team_data;

  RETURN result;
END;
$function$;

REVOKE ALL ON FUNCTION public.get_user_streaks(uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.get_user_streaks(uuid) TO authenticated;
