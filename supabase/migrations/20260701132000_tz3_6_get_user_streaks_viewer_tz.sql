-- STEP 3, migration #6 of the per-user timezone rework (Option B).
--
-- get_user_streaks feeds the dashboard. Its today_check_ins bucket previously
-- keyed on CURRENT_DATE (the DB session timezone = UTC), which drifts from
-- the per-user check_in_date labels. "Today" is now resolved in the VIEWING
-- user's own timezone (approved: viewer-relative display) — p_user_id is the
-- viewer; the client always calls this with the signed-in user's id.
--
-- Expected Option-B nuance, by design: during the offset window a partner in
-- another timezone may have checked in on THEIR today, which is a different
-- label than the viewer's today — that check-in won't show in the viewer's
-- today_check_ins until the labels line up. Matches the approved
-- viewer-relative semantics.
--
-- Also adds SET search_path = public, matching every other SECURITY DEFINER
-- function in this project (the original predated that hardening pattern).
-- Query shape, joins, and output structure are otherwise unchanged.

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
