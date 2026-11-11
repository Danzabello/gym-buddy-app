CREATE OR REPLACE FUNCTION public._server_checkin(p_user_id uuid, p_day date)
 RETURNS void
 LANGUAGE plpgsql
 SET search_path TO 'public'
AS $function$
DECLARE
  t record;
  v_coach_max_id constant uuid := '00000000-0000-0000-0000-000000000001';
BEGIN
  -- Same as BreakDayService.cancelBreakDay: working out cancels today's break.
  UPDATE break_day_usage SET cancelled_at = now()
  WHERE user_id = p_user_id AND break_date = p_day AND cancelled_at IS NULL;

  FOR t IN
    SELECT ts.id, bt.is_coach_max_team
    FROM team_streaks ts
    JOIN team_members tm ON tm.team_id = ts.team_id
    JOIN buddy_teams bt ON bt.id = ts.team_id
    WHERE tm.user_id = p_user_id AND ts.is_active = true
  LOOP
    INSERT INTO daily_team_checkins (team_streak_id, user_id, check_in_date, check_in_time)
    VALUES (t.id, p_user_id, p_day, now())
    ON CONFLICT (team_streak_id, user_id, check_in_date) DO NOTHING;
    CONTINUE WHEN NOT FOUND;

    IF (public._recompute_team_streak(t.id, p_day)->>'updated')::boolean THEN
      PERFORM public._apply_checkin_rewards(p_user_id, t.id, p_day);
    END IF;

    IF t.is_coach_max_team AND NOT EXISTS (
      SELECT 1 FROM daily_team_checkins
      WHERE team_streak_id = t.id AND user_id = v_coach_max_id AND check_in_date = p_day
    ) THEN
      PERFORM public._finish_coach_max_checkin(t.id, p_user_id, p_day);
    END IF;
  END LOOP;
END;
$function$
