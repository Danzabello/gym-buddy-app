-- Exclude solo (1-member) teams from get_user_streaks.
--
-- Two buddy_teams rows carry exactly one member — the owner, with no buddy —
-- and both have an active streak, so they were returned to the client like any
-- real team. That inflated every count (Profile read "7 Streaks" / "6 active
-- streaks" against 5 real buddies) and, worse, a solo team has no "other"
-- member: the client's _getDisplayName falls back to `members.first`, which is
-- the signed-in user, so a solo team surfacing into the top 4 of the buddy
-- wheel would render the user's own name and avatar back at them in a
-- friends-only context. It sat 6th by luck, not by design.
--
-- This filters them out of the read path only. No rows are touched or deleted,
-- so it is fully reversible: re-running the previous definition restores the
-- old behaviour, and the underlying teams stay intact for whatever cleanup or
-- repair is decided separately.
--
-- Coach Max teams are unaffected — they carry 2 members (Coach Max + user).

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
      -- A team needs someone other than the viewer in it to be a buddy team.
      AND EXISTS (
        SELECT 1 FROM team_members tm3
        WHERE tm3.team_id = bt.id
          AND tm3.user_id <> p_user_id
      )
  ) team_data;

  RETURN result;
END;
$function$;

-- Re-asserted per CLAUDE.md: new/replaced client-facing SECURITY DEFINER
-- functions must state their grants explicitly rather than rely on defaults.
REVOKE EXECUTE ON FUNCTION public.get_user_streaks(uuid) FROM PUBLIC, anon;
GRANT  EXECUTE ON FUNCTION public.get_user_streaks(uuid) TO authenticated;
