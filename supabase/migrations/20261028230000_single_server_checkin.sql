-- Single server check-in RPC. Design: docs/hygiene/checkin_rpc_design.md. Report: docs/hygiene/checkin_rpc_report.md.
-- Rollback: docs/rollback_20261028230000.sql. Additive: the installed build's direct inserts keep working until Migration B.

-- The one credit-day formula (Q7).
CREATE OR REPLACE FUNCTION public._credit_day(p_user_id uuid, p_at timestamp with time zone)
 RETURNS date
 LANGUAGE sql
 STABLE
 SET search_path TO 'public'
AS $function$
  -- The credit-day formula: the user's local date at p_at. Every credit path
  -- takes its day from here. process_stale_sessions repeats this formula
  -- inline in its "already credited?" guards (see its COMMENT): keep them equal.
  SELECT (p_at AT TIME ZONE public.safe_user_tz(p_user_id))::date;
$function$;

-- The one internal credit path, replacing _server_checkin (same loop and body).
-- p_at: the moment the credit belongs to; the day comes only from _credit_day.
-- p_time: stored check_in_time (a copy keeps its source's time). p_pay = false
-- skips rewards (copies pay nothing). p_streak_id limits it to one team.
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
$function$;

-- finish_checkin_session: credit day and credits through the shared functions. Body otherwise unchanged.
CREATE OR REPLACE FUNCTION public.finish_checkin_session(p_workout_id uuid DEFAULT NULL::uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_uid uuid := auth.uid();
  v_tz text;
  v_start timestamptz;
  v_day date;
  v_level_before integer;
  v_level_after integer;
  v_on_break boolean;
  v_before jsonb;
  v_teams jsonb;
  v_checked_in integer;
  v_wk record;
  v_partner uuid;
  v_pday date;
  v_partner_before integer;
  v_partner_n integer := 0;
  v_sess_ok boolean := false;
  v_wk_ok boolean := false;
  v_sess_early boolean := false;
BEGIN
  IF v_uid IS NULL THEN
    RAISE EXCEPTION 'unauthenticated';
  END IF;
  v_tz := public.safe_user_tz(v_uid);

  -- FIN-1: credit only (a) an eligible own session or (b) an eligible
  -- workout participation; anything else is a no-op that writes nothing.
  -- (a) own session: start pinned by the server, at least 15 minutes and at
  --     most 3h30 ago, and not tied to a workout the caller left or cancelled.
  --     Under 15 minutes it is too_early.
  SELECT COALESCE(w.workout_started_at, s.started_at),
         COALESCE(w.workout_started_at, s.started_at) BETWEEN now() - interval '210 minutes' AND now()
           AND NOT COALESCE(CASE WHEN v_uid = w.user_id THEN w.creator_cancelled ELSE w.buddy_cancelled END, false)
  INTO v_start, v_sess_ok
  FROM active_checkin_sessions s
  LEFT JOIN workouts w ON w.id = s.workout_id AND v_uid IN (w.user_id, w.buddy_id)
  WHERE s.user_id = v_uid
  FOR UPDATE OF s;
  v_sess_early := COALESCE(v_sess_ok AND v_start > now() - interval '15 minutes', false);
  v_sess_ok := COALESCE(v_sess_ok AND NOT v_sess_early, false);

  -- (b) participant of a started workout who has not left or cancelled, past
  --     the 15-minute floor: in progress and started within 3h30, or completed
  --     (by a person, not the cron) within 3h40 of its start (M3 grace),
  --     whenever Finish arrives; start day inside the reward window
  --     [today-1, today].
  IF p_workout_id IS NOT NULL THEN
    SELECT * INTO v_wk FROM workouts
    WHERE id = p_workout_id AND v_uid IN (user_id, buddy_id)
      AND workout_started_at <= now()
      AND (workout_started_at AT TIME ZONE v_tz)::date >= (now() AT TIME ZONE v_tz)::date - 1
      AND CASE WHEN status = 'completed'
               THEN workout_completed_at <= workout_started_at + interval '220 minutes'
                    AND NOT COALESCE(auto_completed, false)
               ELSE workout_started_at >= now() - interval '210 minutes' END
      AND status IN ('in_progress', 'completed')
      AND NOT COALESCE(CASE WHEN v_uid = user_id THEN creator_cancelled ELSE buddy_cancelled END, false)
      AND CASE WHEN status = 'completed' THEN COALESCE(actual_duration_minutes, 0) >= 15
               ELSE now() - workout_started_at >= interval '15 minutes' END;
    v_wk_ok := FOUND;
  END IF;

  IF NOT (v_sess_ok OR v_wk_ok) THEN
    RETURN jsonb_build_object(
      'result', CASE WHEN v_sess_early THEN 'too_early' ELSE 'nothing_to_finish' END,
      'credit_date', (now() AT TIME ZONE v_tz)::date,
      'checked_in', 0, 'break_cancelled', false, 'did_level_up', false,
      'new_level', COALESCE((SELECT level FROM user_profiles WHERE id = v_uid), 1),
      'teams', '[]'::jsonb, 'partner_checked_in', 0);
  END IF;

  IF NOT v_sess_ok THEN
    v_start := v_wk.workout_started_at;
  END IF;
  v_day := public._credit_day(v_uid, v_start);

  SELECT level INTO v_level_before FROM user_profiles WHERE id = v_uid;
  v_on_break := EXISTS (SELECT 1 FROM break_day_usage
                        WHERE user_id = v_uid AND break_date = v_day AND cancelled_at IS NULL);
  SELECT jsonb_object_agg(ts.id, jsonb_build_object(
           'total', ts.total_workouts, 'best', ts.best_streak,
           'in', EXISTS (SELECT 1 FROM daily_team_checkins d
                         WHERE d.team_streak_id = ts.id AND d.user_id = v_uid AND d.check_in_date = v_day)))
  INTO v_before
  FROM team_streaks ts JOIN team_members tm ON tm.team_id = ts.team_id
  WHERE tm.user_id = v_uid AND ts.is_active = true;

  PERFORM public._credit_checkin(v_uid, v_start);
  DELETE FROM active_checkin_sessions WHERE user_id = v_uid;

  -- M6a (owner rule 2026-10-02): in a buddy workout, the other participant
  -- who confirmed ready and has not cancelled is "in", session or not. Only
  -- when the caller is a participant and the workout started at most 3h30
  -- ago; credited to the partner's own local start day; idempotent through
  -- UNIQUE per team/user/day. Runs before the caller's results are read, so
  -- a shared streak the partner completes shows as advanced to the caller.
  -- FIN-1: only through a finisher eligible under (b) above, so a leaver
  -- never triggers it; v_wk is that workout (started, inside its window).
  IF v_wk_ok THEN
    IF v_wk.buddy_id IS NOT NULL AND v_wk.buddy_id <> v_wk.user_id THEN
      v_partner := CASE WHEN v_uid = v_wk.user_id THEN v_wk.buddy_id ELSE v_wk.user_id END;
      IF (v_partner = v_wk.user_id AND v_wk.creator_ready AND NOT v_wk.creator_cancelled)
         OR (v_partner = v_wk.buddy_id AND v_wk.buddy_ready AND NOT v_wk.buddy_cancelled) THEN
        v_pday := public._credit_day(v_partner, v_wk.workout_started_at);
        SELECT count(*) INTO v_partner_before FROM daily_team_checkins
        WHERE user_id = v_partner AND check_in_date = v_pday;
        PERFORM public._credit_checkin(v_partner, v_wk.workout_started_at);
        DELETE FROM active_checkin_sessions WHERE user_id = v_partner AND workout_id = p_workout_id;
        SELECT count(*) - v_partner_before INTO v_partner_n FROM daily_team_checkins
        WHERE user_id = v_partner AND check_in_date = v_pday;
      END IF;
    END IF;
  END IF;

  SELECT level INTO v_level_after FROM user_profiles WHERE id = v_uid;
  SELECT COALESCE(jsonb_agg(jsonb_build_object(
           'streak_id', ts.id, 'team_id', ts.team_id, 'is_coach_max_team', bt.is_coach_max_team,
           'updated', ts.total_workouts IS DISTINCT FROM (v_before->ts.id::text->>'total')::integer,
           'new_streak', ts.current_streak,
           'old_best_streak', COALESCE((v_before->ts.id::text->>'best')::integer, 0),
           'new_best_streak', ts.best_streak)), '[]'::jsonb),
         count(*) FILTER (WHERE NOT COALESCE((v_before->ts.id::text->>'in')::boolean, false)
                            AND EXISTS (SELECT 1 FROM daily_team_checkins d
                                        WHERE d.team_streak_id = ts.id AND d.user_id = v_uid AND d.check_in_date = v_day))
  INTO v_teams, v_checked_in
  FROM team_streaks ts
  JOIN team_members tm ON tm.team_id = ts.team_id
  JOIN buddy_teams bt ON bt.id = ts.team_id
  WHERE tm.user_id = v_uid AND ts.is_active = true;

  RETURN jsonb_build_object(
    'credit_date', v_day,
    'checked_in', v_checked_in,
    'break_cancelled', v_on_break AND NOT EXISTS (SELECT 1 FROM break_day_usage
                         WHERE user_id = v_uid AND break_date = v_day AND cancelled_at IS NULL),
    'did_level_up', COALESCE(v_level_after, 1) > COALESCE(v_level_before, 1),
    'new_level', COALESCE(v_level_after, 1),
    'teams', v_teams,
    'partner_checked_in', v_partner_n);
END;
$function$;

-- _auto_credit (process_stale_sessions' credit step): same.
CREATE OR REPLACE FUNCTION public._auto_credit(p_user uuid, p_start timestamp with time zone, p_goal integer, p_type text, p_emoji text)
 RETURNS boolean
 LANGUAGE plpgsql
 SET search_path TO 'public'
AS $function$
DECLARE
  v_day date := public._credit_day(p_user, p_start);
BEGIN
  IF EXISTS (SELECT 1 FROM workout_logs
             WHERE user_id = p_user AND auto_completed AND workout_date = v_day) THEN
    RETURN false;
  END IF;
  PERFORM public._credit_checkin(p_user, p_start);
  INSERT INTO workout_logs (user_id, workout_date, workout_time, workout_name, workout_category,
                            workout_emoji, planned_duration_minutes, actual_duration_minutes, auto_completed)
  VALUES (p_user, v_day, p_start + make_interval(mins => p_goal), p_type,
          COALESCE((SELECT category FROM workout_templates WHERE name = p_type LIMIT 1), 'other'),
          COALESCE(p_emoji, '💪'), p_goal, p_goal, true);
  RETURN true;
END;
$function$;

DROP FUNCTION public._server_checkin(uuid, date);

COMMENT ON FUNCTION public.process_stale_sessions(timestamp with time zone) IS 'Its inline (start AT TIME ZONE safe_user_tz(u))::date "already credited?" guards must stay equal to public._credit_day(), the credit-day formula _auto_credit uses.';

-- CAP-2: the daily cap counts payouts by credit day (reference_id suffix), not by creation day.
CREATE OR REPLACE FUNCTION public._apply_checkin_rewards(p_user_id uuid, p_streak_id uuid, p_check_in_date date)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_ref text := p_streak_id::text || ':' || p_check_in_date::text;
  v_current_streak integer;
  v_xp integer := 10;
  v_coins integer := 10;
  v_coop_xp integer := 5;
  v_coop_coins integer := 5;
  v_milestone_xp integer := 0;
  v_milestone_coins integer := 0;
  v_reasons jsonb := '[]'::jsonb;
  v_partner_checked_in boolean := false;
  v_teammate record;
  v_coach_max_id uuid := '00000000-0000-0000-0000-000000000001';
  v_old_level integer;
  v_new_level integer;
  v_daily_cap_xp constant integer := 1000;
  v_daily_cap_coins constant integer := 100;
  v_already_xp integer;
  v_already_coins integer;
  v_capped boolean := false;
BEGIN
  -- One payout run per (streak, day) at a time, so the existence checks
  -- below cannot race a concurrent run for a teammate.
  PERFORM pg_advisory_xact_lock(hashtext('checkin_rewards:' || v_ref));

  IF EXISTS (
    SELECT 1 FROM xp_transactions
    WHERE user_id = p_user_id AND reference_id = v_ref
  ) THEN
    RETURN jsonb_build_object('already_awarded', true);
  END IF;

  SELECT level INTO v_old_level FROM user_profiles WHERE id = p_user_id;
  v_old_level := COALESCE(v_old_level, 1);

  SELECT current_streak INTO v_current_streak FROM team_streaks WHERE id = p_streak_id;
  v_current_streak := COALESCE(v_current_streak, 1);

  SELECT EXISTS (
    SELECT 1 FROM daily_team_checkins
    WHERE team_streak_id = p_streak_id
      AND check_in_date = p_check_in_date
      AND user_id <> p_user_id
      AND user_id <> v_coach_max_id
  ) INTO v_partner_checked_in;

  IF v_partner_checked_in THEN
    v_xp := v_xp + v_coop_xp;
    v_coins := v_coins + v_coop_coins;
    v_reasons := v_reasons || jsonb_build_array('coop_bonus');
  END IF;

  -- Milestone amounts hoisted so the retro teammate loop can reuse them
  -- (same v_current_streak, same call -> symmetric by construction).
  IF v_current_streak = 7 THEN
    v_milestone_xp := 50; v_milestone_coins := 50;
    v_reasons := v_reasons || jsonb_build_array('milestone_7');
  ELSIF v_current_streak = 30 THEN
    v_milestone_xp := 50; v_milestone_coins := 100;
    v_reasons := v_reasons || jsonb_build_array('milestone_30');
  ELSIF v_current_streak = 100 THEN
    v_milestone_xp := 50; v_milestone_coins := 250;
    v_reasons := v_reasons || jsonb_build_array('milestone_100');
  END IF;
  v_xp := v_xp + v_milestone_xp;
  v_coins := v_coins + v_milestone_coins;

  -- Daily cap for the primary user, counted by credit day: the date after the
  -- last colon of reference_id (streak:day), not the day the row was created (CAP-2).
  SELECT COALESCE(SUM(amount), 0) INTO v_already_xp
  FROM xp_transactions
  WHERE user_id = p_user_id
    AND transaction_type = 'xp_award' AND description IN ('daily_checkin', 'partner_bonus')
    AND substring(reference_id from '[^:]*$') = p_check_in_date::text;

  SELECT COALESCE(SUM(amount), 0) INTO v_already_coins
  FROM coin_transactions
  WHERE user_id = p_user_id
    AND transaction_type IN ('daily_checkin', 'partner_bonus')
    AND substring(reference_id from '[^:]*$') = p_check_in_date::text;

  IF v_already_xp + v_xp > v_daily_cap_xp THEN
    v_xp := GREATEST(0, v_daily_cap_xp - v_already_xp);
    v_capped := true;
  END IF;
  IF v_already_coins + v_coins > v_daily_cap_coins THEN
    v_coins := GREATEST(0, v_daily_cap_coins - v_already_coins);
    v_capped := true;
  END IF;

  PERFORM award_xp(p_user_id, v_xp, 'daily_checkin', v_ref);
  PERFORM award_coins(p_user_id, v_coins, 'daily_checkin', 'Daily check-in rewards', v_ref);

  SELECT level INTO v_new_level FROM user_profiles WHERE id = p_user_id;

  IF v_partner_checked_in THEN
    FOR v_teammate IN
      SELECT DISTINCT dtc.user_id
      FROM daily_team_checkins dtc
      WHERE dtc.team_streak_id = p_streak_id
        AND dtc.check_in_date = p_check_in_date
        AND dtc.user_id <> p_user_id
        AND dtc.user_id <> v_coach_max_id
    LOOP
      DECLARE
        -- Owed-checks: each entitlement deduped by its own kind + reference_id
        -- (XP rows carry the kind in description, coin rows in transaction_type).
        v_t_owed_base boolean;
        v_t_owed_coop boolean;
        v_t_already_xp integer;
        v_t_already_coins integer;
        v_t_base_xp integer := 0;
        v_t_base_coins integer := 0;
        v_t_coop_xp integer := 0;
        v_t_coop_coins integer := 0;
        v_t_room_xp integer;
        v_t_room_coins integer;
      BEGIN
        v_t_owed_base := NOT EXISTS (
          SELECT 1 FROM xp_transactions
          WHERE user_id = v_teammate.user_id
            AND transaction_type = 'xp_award' AND description = 'daily_checkin'
            AND reference_id = v_ref
        );
        v_t_owed_coop := NOT EXISTS (
          SELECT 1 FROM coin_transactions
          WHERE user_id = v_teammate.user_id
            AND transaction_type = 'partner_bonus'
            AND reference_id = v_ref
        );

        IF v_t_owed_base OR v_t_owed_coop THEN
          -- 10/10 base matches the primary's v_xp/v_coins initialisers;
          -- milestone shares the hoisted amounts from this same call.
          IF v_t_owed_base THEN
            v_t_base_xp := 10 + v_milestone_xp;
            v_t_base_coins := 10 + v_milestone_coins;
          END IF;
          IF v_t_owed_coop THEN
            v_t_coop_xp := v_coop_xp;
            v_t_coop_coins := v_coop_coins;
          END IF;

          -- Teammate's cap window: the same credit day (CAP-2).
          SELECT COALESCE(SUM(amount), 0) INTO v_t_already_xp
          FROM xp_transactions
          WHERE user_id = v_teammate.user_id
            AND transaction_type = 'xp_award' AND description IN ('daily_checkin', 'partner_bonus')
            AND substring(reference_id from '[^:]*$') = p_check_in_date::text;

          SELECT COALESCE(SUM(amount), 0) INTO v_t_already_coins
          FROM coin_transactions
          WHERE user_id = v_teammate.user_id
            AND transaction_type IN ('daily_checkin', 'partner_bonus')
            AND substring(reference_id from '[^:]*$') = p_check_in_date::text;

          -- Cap the combined owed amount: base takes the remaining room
          -- first, co-op whatever is left after that.
          v_t_room_xp := GREATEST(0, v_daily_cap_xp - v_t_already_xp);
          v_t_room_coins := GREATEST(0, v_daily_cap_coins - v_t_already_coins);
          v_t_base_xp := LEAST(v_t_base_xp, v_t_room_xp);
          v_t_base_coins := LEAST(v_t_base_coins, v_t_room_coins);
          v_t_coop_xp := LEAST(v_t_coop_xp, v_t_room_xp - v_t_base_xp);
          v_t_coop_coins := LEAST(v_t_coop_coins, v_t_room_coins - v_t_base_coins);

          -- Award each owed part even when capped to 0: the ref-tagged txn
          -- is what marks the entitlement as covered for future dedup.
          IF v_t_owed_base THEN
            PERFORM award_xp(v_teammate.user_id, v_t_base_xp, 'daily_checkin', v_ref);
            PERFORM award_coins(v_teammate.user_id, v_t_base_coins, 'daily_checkin', 'Daily check-in rewards', v_ref);
          END IF;
          IF v_t_owed_coop THEN
            PERFORM award_xp(v_teammate.user_id, v_t_coop_xp, 'partner_bonus', v_ref);
            PERFORM award_coins(v_teammate.user_id, v_t_coop_coins, 'partner_bonus', 'Partner checked in too!', v_ref);
          END IF;
        END IF;
      END;
    END LOOP;
  END IF;

  RETURN jsonb_build_object(
    'xp_awarded', v_xp,
    'coins_awarded', v_coins,
    'current_streak', v_current_streak,
    'reasons', v_reasons,
    'old_level', v_old_level,
    'new_level', v_new_level,
    'did_level_up', v_new_level > v_old_level,
    'daily_cap_reached', v_capped
  );
END;
$function$;

-- submit_checkin: copies members' real check-ins for their local today onto shared teams. Never a first check-in.
CREATE OR REPLACE FUNCTION public.submit_checkin()
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_uid uuid := auth.uid();
  v_coach_max_id constant uuid := '00000000-0000-0000-0000-000000000001';
  v_day date;
  v_before jsonb;
  v_mine_before integer;
  v_mine integer;
  v_xp integer := 0;
  v_coins integer := 0;
  v_r jsonb;
  c record;
BEGIN
  IF v_uid IS NULL THEN
    RAISE EXCEPTION 'unauthenticated';
  END IF;
  v_day := public._credit_day(v_uid, now());

  SELECT jsonb_object_agg(ts.id, ts.total_workouts) INTO v_before
  FROM team_streaks ts JOIN team_members tm ON tm.team_id = ts.team_id
  WHERE tm.user_id = v_uid AND ts.is_active = true;

  IF v_before IS NULL THEN
    RETURN jsonb_build_object('credited', false, 'reason', 'no_teams', 'credit_date', v_day,
                              'streak', 0, 'xp', 0, 'coins', 0, 'teams', '[]'::jsonb);
  END IF;

  SELECT count(*) INTO v_mine_before FROM daily_team_checkins
  WHERE user_id = v_uid AND check_in_date = v_day;

  -- Copy each member's real check-in for their own local today onto every
  -- shared active team that lacks it. Nobody gets a first check-in here (that
  -- stays behind finish_checkin_session), Coach Max is never copied, a copy
  -- keeps its source's earliest check_in_time, and copies pay nothing.
  FOR c IN
    SELECT ts.id AS streak_id, m.user_id, src.t
    FROM team_streaks ts
    JOIN team_members me ON me.team_id = ts.team_id AND me.user_id = v_uid
    JOIN team_members m ON m.team_id = ts.team_id AND m.user_id <> v_coach_max_id
    CROSS JOIN LATERAL (SELECT public._credit_day(m.user_id, now()) AS day) d
    CROSS JOIN LATERAL (
      SELECT min(x.check_in_time) AS t FROM daily_team_checkins x
      WHERE x.user_id = m.user_id AND x.check_in_date = d.day
    ) src
    WHERE ts.is_active = true
      AND src.t IS NOT NULL
      AND NOT EXISTS (
        SELECT 1 FROM daily_team_checkins y
        WHERE y.team_streak_id = ts.id AND y.user_id = m.user_id AND y.check_in_date = d.day
      )
    ORDER BY ts.id, m.user_id
  LOOP
    -- A copy is not a new check-in: notify_buddy_checkin sends no push for it.
    PERFORM set_config('app.checkin_copy', '1', true);
    v_r := public._credit_checkin(c.user_id, now(), false, c.t, c.streak_id);
    PERFORM set_config('app.checkin_copy', '', true);
    IF c.user_id = v_uid THEN
      v_xp := v_xp + (v_r->>'xp')::integer;
      v_coins := v_coins + (v_r->>'coins')::integer;
    END IF;
  END LOOP;

  SELECT count(*) INTO v_mine FROM daily_team_checkins
  WHERE user_id = v_uid AND check_in_date = v_day;

  RETURN (
    SELECT jsonb_build_object(
      'credited', v_mine > v_mine_before,
      'reason', CASE WHEN v_mine > v_mine_before THEN 'credited'
                     WHEN v_mine_before > 0 THEN 'already_checked_in'
                     ELSE 'not_checked_in_today' END,
      'credit_date', v_day,
      'streak', COALESCE(max(ts.current_streak), 0),
      'xp', v_xp,
      'coins', v_coins,
      'teams', COALESCE(jsonb_agg(jsonb_build_object(
                 'streak_id', ts.id, 'team_id', ts.team_id,
                 'updated', ts.total_workouts IS DISTINCT FROM (v_before->>ts.id::text)::integer,
                 'new_streak', ts.current_streak) ORDER BY ts.id), '[]'::jsonb))
    FROM team_streaks ts JOIN team_members tm ON tm.team_id = ts.team_id
    WHERE tm.user_id = v_uid AND ts.is_active = true);
END;
$function$;

-- notify_buddy_checkin: no push for a copy (transaction-local flag set by submit_checkin only).
CREATE OR REPLACE FUNCTION public.notify_buddy_checkin()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_other_user_id uuid;
  v_team_id uuid;
BEGIN
  -- Copies written by submit_checkin are not new check-ins: no push.
  IF current_setting('app.checkin_copy', true) = '1' THEN
    RETURN NEW;
  END IF;

  SELECT team_id INTO v_team_id FROM team_streaks WHERE id = NEW.team_streak_id;
  IF v_team_id IS NULL THEN
    RETURN NEW;
  END IF;

  SELECT tm.user_id INTO v_other_user_id
  FROM team_members tm
  WHERE tm.team_id = v_team_id
    AND tm.user_id != NEW.user_id
  LIMIT 1;

  PERFORM public._send_push(v_other_user_id, 'buddy_checked_in', '{}'::jsonb, 'emerald', 'streaks',
                            'buddy_checked_in', v_team_id::text, 'streak_' || v_team_id, false, NEW.user_id);
  RETURN NEW;
END;
$function$;

-- F3: create_invite_team no longer pays the invitee at join ...
CREATE OR REPLACE FUNCTION public.create_invite_team(p_inviter_id uuid, p_invitee_id uuid)
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_team_id UUID;
  v_invite_id UUID;
  v_now TIMESTAMPTZ := NOW();
BEGIN
  IF auth.uid() IS NULL OR auth.uid() <> p_invitee_id THEN
    RAISE EXCEPTION 'not_authorized';
  END IF;

  SELECT id INTO v_invite_id
  FROM invites
  WHERE inviter_id = p_inviter_id
    AND accepted_by = p_invitee_id
    AND status = 'accepted'
  ORDER BY accepted_at DESC NULLS LAST
  LIMIT 1;

  IF v_invite_id IS NULL THEN
    RAISE EXCEPTION 'no_accepted_invite';
  END IF;

  SELECT tm1.team_id INTO v_team_id
  FROM team_members tm1
  JOIN team_members tm2 ON tm2.team_id = tm1.team_id AND tm2.user_id = p_invitee_id
  WHERE tm1.user_id = p_inviter_id
  LIMIT 1;

  IF v_team_id IS NOT NULL THEN
    RETURN v_team_id;
  END IF;

  INSERT INTO buddy_teams (team_name, team_emoji, is_coach_max_team, max_members, created_by, created_at, updated_at)
  VALUES ('Gym Buddies', '💪', false, 2, p_inviter_id, v_now, v_now)
  RETURNING id INTO v_team_id;

  INSERT INTO team_members (team_id, user_id, role, joined_at, created_at)
  VALUES
    (v_team_id, p_inviter_id, 'member', v_now, v_now),
    (v_team_id, p_invitee_id, 'member', v_now, v_now);

  INSERT INTO team_streaks (team_id, current_streak, longest_streak, is_active, created_at, updated_at)
  VALUES (v_team_id, 0, 0, true, v_now, v_now);

  INSERT INTO friendships (user_id, friend_id, status)
  SELECT p_inviter_id, p_invitee_id, 'accepted'
  WHERE NOT EXISTS (
    SELECT 1 FROM friendships
    WHERE (user_id = p_inviter_id AND friend_id = p_invitee_id)
       OR (user_id = p_invitee_id AND friend_id = p_inviter_id)
  );

  -- The invitee's welcome bonus is paid on their first credited day by
  -- _fulfil_invite_reward, once per account (F3), no longer here.

  RETURN v_team_id;
END;
$function$;

-- ... _fulfil_invite_reward pays it once per account, on the first credited row.
CREATE OR REPLACE FUNCTION public._fulfil_invite_reward()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_invite  RECORD;
  v_days    INT;
  v_friends INT;
  v_amount  INT;
  v_bonus   BOOLEAN := false;
BEGIN
  FOR v_invite IN
    SELECT i.id, i.inviter_id, i.created_at
    FROM invites i
    WHERE i.accepted_by = NEW.user_id
      AND i.status = 'accepted'
    FOR UPDATE
  LOOP
    -- F3: the invitee's own 20-coin welcome bonus, once per account for life,
    -- paid on its first credited row after joining through an invite. The
    -- FOR UPDATE above serialises concurrent rows for the same invitee.
    IF NOT v_bonus
       AND NOT EXISTS (
         SELECT 1 FROM coin_transactions
         WHERE user_id = NEW.user_id AND transaction_type = 'invite_bonus'
       )
       AND EXISTS (
         SELECT 1 FROM auth.users u
         WHERE u.id = NEW.user_id AND u.created_at > v_invite.created_at
       ) THEN
      BEGIN
        PERFORM award_coins(NEW.user_id, 20, 'invite_bonus', 'Joined via buddy invite', v_invite.id::text);
      EXCEPTION WHEN OTHERS THEN
        -- Never block the check-in. No invite_bonus row, so the next row retries.
        RAISE WARNING 'invite_bonus failed for %: %', NEW.user_id, SQLERRM;
      END;
      v_bonus := true;
    END IF;

    IF EXISTS (
      SELECT 1 FROM coin_transactions
      WHERE transaction_type = 'invite_reward'
        AND reference_id = v_invite.id::text
    ) THEN
      CONTINUE;
    END IF;

    IF NOT EXISTS (
      SELECT 1 FROM auth.users u
      WHERE u.id = NEW.user_id
        AND u.created_at > v_invite.created_at
    ) THEN
      CONTINUE;
    END IF;

    SELECT COUNT(DISTINCT check_in_date) INTO v_days
    FROM daily_team_checkins
    WHERE user_id = NEW.user_id;

    IF v_days < 2 THEN
      CONTINUE;
    END IF;

    SELECT COUNT(*) INTO v_friends
    FROM friendships
    WHERE status = 'accepted'
      AND (user_id = v_invite.inviter_id OR friend_id = v_invite.inviter_id);

    v_amount := CASE
      WHEN v_friends < 30 THEN 20
      WHEN v_friends < 60 THEN 10
      WHEN v_friends < 90 THEN 5
      ELSE 2
    END;

    BEGIN
      PERFORM award_coins(
        v_invite.inviter_id, v_amount, 'invite_reward',
        'Buddy invite paid off', v_invite.id::text
      );
    EXCEPTION WHEN OTHERS THEN
      INSERT INTO invite_reward_dead_letters (invite_id, inviter_id, amount, error_message)
      VALUES (v_invite.id, v_invite.inviter_id, v_amount, SQLERRM);
    END;
  END LOOP;

  RETURN NULL;
END;
$function$;

REVOKE EXECUTE ON FUNCTION public._credit_day(uuid, timestamp with time zone) FROM PUBLIC, anon, authenticated;
GRANT  EXECUTE ON FUNCTION public._credit_day(uuid, timestamp with time zone) TO service_role;
REVOKE EXECUTE ON FUNCTION public._credit_checkin(uuid, timestamp with time zone, boolean, timestamp with time zone, uuid) FROM PUBLIC, anon, authenticated;
GRANT  EXECUTE ON FUNCTION public._credit_checkin(uuid, timestamp with time zone, boolean, timestamp with time zone, uuid) TO service_role;
REVOKE EXECUTE ON FUNCTION public._apply_checkin_rewards(uuid, uuid, date) FROM PUBLIC, anon, authenticated;
REVOKE EXECUTE ON FUNCTION public.submit_checkin() FROM PUBLIC, anon;
GRANT  EXECUTE ON FUNCTION public.submit_checkin() TO authenticated;
REVOKE EXECUTE ON FUNCTION public.finish_checkin_session(uuid) FROM PUBLIC, anon;
GRANT  EXECUTE ON FUNCTION public.finish_checkin_session(uuid) TO authenticated;
REVOKE EXECUTE ON FUNCTION public.create_invite_team(uuid, uuid) FROM PUBLIC, anon;
GRANT  EXECUTE ON FUNCTION public.create_invite_team(uuid, uuid) TO authenticated;
