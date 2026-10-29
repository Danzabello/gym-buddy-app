CREATE OR REPLACE FUNCTION public._credit_checkin(p_user_id uuid, p_at timestamp with time zone, p_pay boolean DEFAULT true, p_time timestamp with time zone DEFAULT now(), p_streak_id uuid DEFAULT NULL::uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SET search_path TO 'public'
AS $function$
DECLARE
  t record;
  v_coach_max_id constant uuid := '00000000-0000-0000-0000-000000000001';
  v_day date := public._credit_day(p_user_id, p_at);
  v_rc jsonb;
  v_rw jsonb;
  v_teams jsonb := '[]'::jsonb;
  v_xp integer := 0;
  v_coins integer := 0;
BEGIN
  -- Same as BreakDayService.cancelBreakDay: working out cancels today's break.
  UPDATE break_day_usage SET cancelled_at = now()
  WHERE user_id = p_user_id AND break_date = v_day AND cancelled_at IS NULL;

  FOR t IN
    SELECT ts.id, ts.team_id, bt.is_coach_max_team
    FROM team_streaks ts
    JOIN team_members tm ON tm.team_id = ts.team_id
    JOIN buddy_teams bt ON bt.id = ts.team_id
    WHERE tm.user_id = p_user_id AND ts.is_active = true
      AND (p_streak_id IS NULL OR ts.id = p_streak_id)
  LOOP
    INSERT INTO daily_team_checkins (team_streak_id, user_id, check_in_date, check_in_time)
    VALUES (t.id, p_user_id, v_day, p_time)
    ON CONFLICT (team_streak_id, user_id, check_in_date) DO NOTHING;
    CONTINUE WHEN NOT FOUND;

    v_rc := public._recompute_team_streak(t.id, v_day);
    IF (v_rc->>'updated')::boolean AND p_pay THEN
      v_rw := public._apply_checkin_rewards(p_user_id, t.id, v_day);
      v_xp := v_xp + COALESCE((v_rw->>'xp_awarded')::integer, 0);
      v_coins := v_coins + COALESCE((v_rw->>'coins_awarded')::integer, 0);
    END IF;

    IF t.is_coach_max_team AND NOT EXISTS (
      SELECT 1 FROM daily_team_checkins
      WHERE team_streak_id = t.id AND user_id = v_coach_max_id AND check_in_date = v_day
    ) THEN
      PERFORM public._finish_coach_max_checkin(t.id, p_user_id, v_day);
    END IF;

    v_teams := v_teams || jsonb_build_object(
      'streak_id', t.id, 'team_id', t.team_id,
      'updated', COALESCE((v_rc->>'updated')::boolean, false),
      'new_streak', (SELECT current_streak FROM team_streaks WHERE id = t.id));
  END LOOP;

  RETURN jsonb_build_object('credit_date', v_day, 'teams', v_teams, 'xp', v_xp, 'coins', v_coins);
END;
$function$
