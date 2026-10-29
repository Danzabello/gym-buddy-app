-- Rollback for 20261029160000_credit_lock_order. Restores the five bodies dumped from live on 2026-10-29
-- (docs/hygiene/07_backup/, md5 in gen_07.py) with their grants, then drops _lock_credit.
-- Pre-change ACLs (all SET search_path=public):
--   finish_checkin_session, check_in_coach_max: {postgres=X/postgres,authenticated=X/postgres,service_role=X/postgres}
--   _credit_checkin, _recompute_team_streak, reconcile_stale_streaks: {postgres=X/postgres,service_role=X/postgres}

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
REVOKE EXECUTE ON FUNCTION public._credit_checkin(uuid, timestamptz, boolean, timestamptz, uuid) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public._credit_checkin(uuid, timestamptz, boolean, timestamptz, uuid) TO service_role;

CREATE OR REPLACE FUNCTION public._recompute_team_streak(p_streak_id uuid, p_check_in_date date)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_team_id uuid;
  v_current_streak integer;
  v_longest_streak integer;
  v_total_workouts integer;
  v_best_streak integer;
  v_last_workout_date date;
  v_member_ids uuid[];
  v_new_streak integer;
  v_new_longest integer;
  v_coach_max_id uuid := '00000000-0000-0000-0000-000000000001';
  v_days_diff integer;
  v_day_complete boolean;
  v_someone_worked_out boolean;
  v_gap_is_valid boolean;
  v_check_date date;
  v_everyone_on_break boolean;
  i integer;
BEGIN
  SELECT team_id, current_streak, longest_streak, total_workouts, best_streak, last_workout_date
  INTO v_team_id, v_current_streak, v_longest_streak, v_total_workouts, v_best_streak, v_last_workout_date
  FROM team_streaks WHERE id = p_streak_id;

  IF v_team_id IS NULL THEN
    RAISE EXCEPTION 'invalid_streak';
  END IF;

  v_current_streak := COALESCE(v_current_streak, 0);
  v_longest_streak := COALESCE(v_longest_streak, 0);
  v_total_workouts := COALESCE(v_total_workouts, 0);
  v_best_streak := COALESCE(v_best_streak, 0);

  SELECT array_agg(user_id) INTO v_member_ids
  FROM team_members WHERE team_id = v_team_id AND user_id <> v_coach_max_id;

  IF v_member_ids IS NULL THEN
    RETURN jsonb_build_object('updated', false, 'reason', 'no_members', 'current_streak', v_current_streak);
  END IF;

  -- ── AND-gate ──────────────────────────────────────────────────────────
  -- (1) every member has a check-in for D or an uncancelled break on D
  SELECT NOT EXISTS (
    SELECT 1 FROM unnest(v_member_ids) AS uid
    WHERE NOT EXISTS (
        SELECT 1 FROM daily_team_checkins dtc
        WHERE dtc.team_streak_id = p_streak_id
          AND dtc.user_id = uid
          AND dtc.check_in_date = p_check_in_date
      )
      AND NOT EXISTS (
        SELECT 1 FROM break_day_usage bdu
        WHERE bdu.user_id = uid
          AND bdu.break_date = p_check_in_date
          AND bdu.cancelled_at IS NULL
      )
  ) INTO v_day_complete;

  -- (2) at least one genuine workout: a member checked in while NOT on break
  SELECT EXISTS (
    SELECT 1 FROM daily_team_checkins dtc
    WHERE dtc.team_streak_id = p_streak_id
      AND dtc.check_in_date = p_check_in_date
      AND dtc.user_id = ANY(v_member_ids)
      AND NOT EXISTS (
        SELECT 1 FROM break_day_usage bdu
        WHERE bdu.user_id = dtc.user_id
          AND bdu.break_date = p_check_in_date
          AND bdu.cancelled_at IS NULL
      )
  ) INTO v_someone_worked_out;

  IF NOT v_day_complete OR NOT v_someone_worked_out THEN
    -- Row untouched: last_workout_date must not advance on an incomplete day.
    RETURN jsonb_build_object('updated', false, 'reason', 'day_incomplete', 'current_streak', v_current_streak);
  END IF;

  -- ── Branch skeleton (label D is fully complete from here on) ──────────
  v_new_streak := v_current_streak;
  v_new_longest := v_longest_streak;

  IF v_last_workout_date IS NULL OR v_last_workout_date = p_check_in_date THEN
    IF v_last_workout_date = p_check_in_date AND v_current_streak > 0 THEN
      RETURN jsonb_build_object('updated', false, 'reason', 'already_today', 'current_streak', v_current_streak);
    END IF;
    v_new_streak := 1;
    v_new_longest := CASE WHEN v_current_streak > 0 THEN v_longest_streak ELSE 1 END;
  ELSE
    v_days_diff := p_check_in_date - v_last_workout_date;

    IF v_days_diff = 1 THEN
      v_new_streak := v_current_streak + 1;
      IF v_new_streak > v_longest_streak THEN v_new_longest := v_new_streak; END IF;

    ELSIF v_days_diff > 1 THEN
      IF v_current_streak = 0 THEN
        v_new_streak := 1;
        v_new_longest := CASE WHEN v_longest_streak > 0 THEN v_longest_streak ELSE 1 END;
      ELSE
        v_gap_is_valid := true;
        FOR i IN 1..(v_days_diff - 1) LOOP
          v_check_date := v_last_workout_date + i;
          SELECT NOT EXISTS (
            SELECT 1 FROM unnest(v_member_ids) AS uid
            WHERE NOT EXISTS (
              SELECT 1 FROM break_day_usage bdu
              WHERE bdu.user_id = uid AND bdu.break_date = v_check_date AND bdu.cancelled_at IS NULL
            )
          ) INTO v_everyone_on_break;

          IF NOT v_everyone_on_break THEN
            v_gap_is_valid := false;
            EXIT;
          END IF;
        END LOOP;

        IF v_gap_is_valid THEN
          v_new_streak := v_current_streak + 1;
          IF v_new_streak > v_longest_streak THEN v_new_longest := v_new_streak; END IF;
        ELSE
          -- Approved: gapped-but-mutually-complete day starts a fresh streak.
          v_new_streak := 1;
          PERFORM public._record_streak_loss(v_team_id, v_current_streak, ARRAY(
            SELECT uid FROM unnest(v_member_ids) AS uid
            WHERE EXISTS (
              SELECT 1 FROM generate_series((v_last_workout_date + 1)::timestamp,
                                            (p_check_in_date - 1)::timestamp, interval '1 day') AS g(day)
              WHERE NOT EXISTS (SELECT 1 FROM daily_team_checkins dtc
                                WHERE dtc.team_streak_id = p_streak_id AND dtc.user_id = uid
                                  AND dtc.check_in_date = g.day::date)
                AND NOT EXISTS (SELECT 1 FROM break_day_usage bdu
                                WHERE bdu.user_id = uid AND bdu.break_date = g.day::date
                                  AND bdu.cancelled_at IS NULL))));
        END IF;
      END IF;
    ELSE
      RETURN jsonb_build_object('updated', false, 'reason', 'same_day_or_past', 'current_streak', v_current_streak);
    END IF;
  END IF;

  UPDATE team_streaks SET
    current_streak = v_new_streak,
    longest_streak = v_new_longest,
    total_workouts = v_total_workouts + 1,
    best_streak = GREATEST(v_best_streak, v_new_streak),
    last_workout_date = p_check_in_date,
    last_interaction_at = now(),
    updated_at = now()
  WHERE id = p_streak_id;

  RETURN jsonb_build_object(
    'updated', true,
    'old_streak', v_current_streak,
    'new_streak', v_new_streak,
    'longest_streak', v_new_longest,
    'old_best_streak', v_best_streak,
    'new_best_streak', GREATEST(v_best_streak, v_new_streak)
  );
END;
$function$;
REVOKE EXECUTE ON FUNCTION public._recompute_team_streak(uuid, date) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public._recompute_team_streak(uuid, date) TO service_role;

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
REVOKE EXECUTE ON FUNCTION public.finish_checkin_session(uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.finish_checkin_session(uuid) TO authenticated, service_role;

CREATE OR REPLACE FUNCTION public.check_in_coach_max(p_user_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_caller uuid := auth.uid();
  v_coach_max_id uuid := '00000000-0000-0000-0000-000000000001';
  v_streak_id uuid;
  v_today date;
  v_scheduled_time time;
  v_local_now time;
BEGIN
  IF v_caller IS NULL OR v_caller <> p_user_id THEN
    RAISE EXCEPTION 'forbidden';
  END IF;

  SELECT ts.id INTO v_streak_id
  FROM team_streaks ts
  JOIN team_members tm ON tm.team_id = ts.team_id
  JOIN buddy_teams bt ON bt.id = ts.team_id
  WHERE tm.user_id = p_user_id AND bt.is_coach_max_team = true AND ts.is_active = true
  LIMIT 1;

  IF v_streak_id IS NULL THEN
    RETURN jsonb_build_object('checked_in', false, 'reason', 'no_coach_max_team');
  END IF;

  v_today := (now() AT TIME ZONE safe_user_tz(p_user_id))::date;

  IF EXISTS (
    SELECT 1 FROM daily_team_checkins
    WHERE team_streak_id = v_streak_id AND user_id = v_coach_max_id AND check_in_date = v_today
  ) THEN
    RETURN jsonb_build_object('checked_in', true, 'already_done', true);
  END IF;

  SELECT scheduled_time INTO v_scheduled_time
  FROM coach_max_schedule
  WHERE user_id = p_user_id AND scheduled_date = v_today;

  IF NOT FOUND THEN
    RETURN jsonb_build_object('checked_in', false, 'reason', 'no_schedule_today');
  END IF;

  v_local_now := (now() AT TIME ZONE safe_user_tz(p_user_id))::time;

  IF v_scheduled_time > v_local_now THEN
    RETURN jsonb_build_object('checked_in', false, 'reason', 'not_due_yet',
                               'scheduled_time', v_scheduled_time);
  END IF;

  RETURN public._finish_coach_max_checkin(v_streak_id, p_user_id, v_today);
END;
$function$;
REVOKE EXECUTE ON FUNCTION public.check_in_coach_max(uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.check_in_coach_max(uuid) TO authenticated, service_role;

CREATE OR REPLACE FUNCTION public.reconcile_stale_streaks()
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_streak record;
  v_utc_today date := (now() AT TIME ZONE 'utc')::date;
  v_member_ids uuid[];
  v_member uuid;
  v_m_yesterday date;
  v_broken boolean;
  v_missers uuid[];
  v_reset_count integer := 0;
BEGIN
  FOR v_streak IN
    SELECT id, team_id, current_streak, last_workout_date
    FROM team_streaks
    WHERE is_active = true AND current_streak > 0
      AND (last_workout_date IS NULL OR last_workout_date < v_utc_today)
  LOOP
    SELECT array_agg(user_id) INTO v_member_ids
    FROM team_members
    WHERE team_id = v_streak.team_id
      AND user_id <> '00000000-0000-0000-0000-000000000001';

    IF v_streak.last_workout_date IS NULL THEN
      -- Active streak count with no completed day on record: inconsistent,
      -- reset (unchanged from the current function).
      UPDATE team_streaks SET current_streak = 0, updated_at = now() WHERE id = v_streak.id;
      v_reset_count := v_reset_count + 1;
      CONTINUE;
    END IF;

    IF v_member_ids IS NULL THEN
      CONTINUE; -- memberless: nothing to judge (matches current behavior)
    END IF;

    v_broken := false;
    v_missers := '{}';

    FOREACH v_member IN ARRAY v_member_ids LOOP
      -- This member's own fully-elapsed yesterday.
      v_m_yesterday := (now() AT TIME ZONE public.safe_user_tz(v_member))::date - 1;

      IF v_streak.last_workout_date + 1 <= v_m_yesterday THEN
        IF EXISTS (
          SELECT 1
          FROM generate_series(
                 (v_streak.last_workout_date + 1)::timestamp,
                 v_m_yesterday::timestamp,
                 interval '1 day') AS g(day)
          WHERE NOT EXISTS (
              SELECT 1 FROM daily_team_checkins dtc
              WHERE dtc.team_streak_id = v_streak.id
                AND dtc.user_id = v_member
                AND dtc.check_in_date = g.day::date
            )
            AND NOT EXISTS (
              SELECT 1 FROM break_day_usage bdu
              WHERE bdu.user_id = v_member
                AND bdu.break_date = g.day::date
                AND bdu.cancelled_at IS NULL
            )
            -- Grace (Rule 1): a workout that started on this member's
            -- yesterday and is still running will be credited to that day.
            AND NOT (g.day::date = v_m_yesterday AND (
              EXISTS (
                SELECT 1 FROM active_checkin_sessions s
                WHERE s.user_id = v_member
                  AND s.started_at >= now() - interval '220 minutes'
                  AND (s.started_at AT TIME ZONE public.safe_user_tz(v_member))::date = g.day::date
              )
              OR EXISTS (
                SELECT 1 FROM workouts w
                WHERE w.status = 'in_progress'
                  AND w.workout_started_at >= now() - interval '220 minutes'
                  AND (w.workout_started_at AT TIME ZONE public.safe_user_tz(v_member))::date = g.day::date
                  AND ((w.user_id = v_member AND w.creator_ready AND NOT w.creator_cancelled)
                    OR (w.buddy_id = v_member AND w.buddy_ready AND NOT w.buddy_cancelled))
              )
            ))
        ) THEN
          v_broken := true;  -- STRICT: one member's definitive miss is enough
          v_missers := v_missers || v_member;  -- keep going: record every misser
        END IF;
      END IF;
    END LOOP;

    IF v_broken THEN
      UPDATE team_streaks SET current_streak = 0, updated_at = now() WHERE id = v_streak.id;
      v_reset_count := v_reset_count + 1;
      PERFORM public._record_streak_loss(v_streak.team_id, v_streak.current_streak, v_missers);
    END IF;
  END LOOP;

  RETURN jsonb_build_object('reset_count', v_reset_count);
END;
$function$;
REVOKE EXECUTE ON FUNCTION public.reconcile_stale_streaks() FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.reconcile_stale_streaks() TO service_role;

DROP FUNCTION public._lock_credit(uuid[], boolean, uuid);
