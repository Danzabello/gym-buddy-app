-- AUTO-COMPLETE-LIMIT (prompt 35). The 3h30 auto check-in stays as a safety net but a user gets only 3 in a
-- row: auto_checkin_counts holds each user's run of consecutive paid auto check-ins (no row = 0, nothing is
-- backfilled). _auto_credit refuses a 4th (no credit, no workout_logs row; the caller still closes the session,
-- a shared workout nobody was paid for closes as cancelled), counts one only when _credit_checkin really
-- inserted a check-in row for the user (teams non-empty), and on reaching 3 sends one Coach Max push
-- (type coach_max_motivational -> notif_coach_max, channel gym_buddy_coach_max, not urgent). The user's own
-- Complete Check-In (finish_checkin_session, past its gates) deletes the row. Push 3 (session_reminder2) no
-- longer mentions the auto check-in. The counter is never shown. process_stale_sessions is unchanged.
-- Lock order: the counter read is lock-free, every counter write is L5 and comes after _credit_checkin (L2/L3).
-- Rollback: docs/rollback_20261105220000.sql.

CREATE TABLE public.auto_checkin_counts (
  user_id     uuid        PRIMARY KEY REFERENCES public.user_profiles(id) ON DELETE CASCADE,
  consecutive smallint    NOT NULL CHECK (consecutive BETWEEN 1 AND 3),
  updated_at  timestamptz NOT NULL DEFAULT now()
);
ALTER TABLE public.auto_checkin_counts ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON TABLE public.auto_checkin_counts FROM anon, authenticated;
GRANT SELECT, INSERT, UPDATE, DELETE ON TABLE public.auto_checkin_counts TO service_role;
COMMENT ON TABLE public.auto_checkin_counts IS 'Consecutive paid auto check-ins per user (max 3). Written only by _auto_credit and finish_checkin_session; no client access. Never shown in the app.';

INSERT INTO public.push_templates (key, variant, title, body) VALUES
  ('coach_max_auto_limit', 1, 'Coach Max', 'That''s three auto check-ins in a row. I''m done covering for you. Next time, you check in yourself.'),
  ('coach_max_auto_limit', 2, 'Coach Max', 'Three in a row. I covered for you, now it''s your turn. Check in yourself from now on.'),
  ('coach_max_auto_limit', 3, 'Coach Max', 'I''m not your alarm clock. Three auto check-ins is all you get. Check in yourself next time.');

UPDATE public.push_templates
SET title = 'Final reminder', body = 'This is the final reminder. Open the app and tap Complete Check-In.'
WHERE key = 'session_reminder2' AND variant = 1;

CREATE OR REPLACE FUNCTION public._auto_credit(p_user uuid, p_start timestamp with time zone, p_goal integer, p_type text, p_emoji text)
 RETURNS boolean
 LANGUAGE plpgsql
 SET search_path TO 'public'
AS $function$
DECLARE
  v_day date := public._credit_day(p_user, p_start);
  v_n integer;
  v_rc jsonb;
BEGIN
  IF EXISTS (SELECT 1 FROM workout_logs
             WHERE user_id = p_user AND auto_completed AND workout_date = v_day) THEN
    RETURN false;
  END IF;

  -- AUTO-LIMIT: 3 auto check-ins in a row, then none. L5 read, no lock: a concurrent reset or count is
  -- one valid serial order either way. Refused = false, so the caller closes the session unpaid.
  SELECT consecutive INTO v_n FROM auto_checkin_counts WHERE user_id = p_user;
  IF COALESCE(v_n, 0) >= 3 THEN
    RETURN false;
  END IF;

  v_rc := public._credit_checkin(p_user, p_start);
  INSERT INTO workout_logs (user_id, workout_date, workout_time, workout_name, workout_category,
                            workout_emoji, planned_duration_minutes, actual_duration_minutes, auto_completed)
  VALUES (p_user, v_day, p_start + make_interval(mins => p_goal), p_type,
          COALESCE((SELECT category FROM workout_templates WHERE name = p_type LIMIT 1), 'other'),
          COALESCE(p_emoji, '💪'), p_goal, p_goal, true);

  -- Counts only a check-in row _credit_checkin really inserted for this user (teams lists new rows only).
  IF jsonb_array_length(v_rc->'teams') > 0 THEN
    -- L5 row write, after the credit.
    INSERT INTO auto_checkin_counts AS c (user_id, consecutive) VALUES (p_user, 1)
    ON CONFLICT (user_id) DO UPDATE SET consecutive = LEAST(c.consecutive + 1, 3), updated_at = now()
    RETURNING c.consecutive INTO v_n;
    IF v_n = 3 THEN
      -- The one Coach Max warning, on reaching 3. A failed push must not roll back the credit.
      BEGIN
        PERFORM public._send_push(p_user, 'coach_max_auto_limit', '{}'::jsonb, 'emerald', 'coach_max', 'coach_max_motivational',
                                  p_user::text, 'coach_max_limit_' || p_user::text, false, '00000000-0000-0000-0000-000000000001'::uuid);
      EXCEPTION WHEN OTHERS THEN
        RAISE WARNING '_auto_credit: coach_max_auto_limit push failed for %: %', p_user, SQLERRM;
      END;
    END IF;
  END IF;
  RETURN true;
END;
$function$;
REVOKE EXECUTE ON FUNCTION public._auto_credit(uuid, timestamp with time zone, integer, text, text) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public._auto_credit(uuid, timestamp with time zone, integer, text, text) TO service_role;

-- finish_checkin_session: the live body (20261029160000) plus one L5 DELETE after _credit_checkin.
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

  -- L0: the shared workout row before the session row, so two buddies finishing together serialise.
  IF p_workout_id IS NOT NULL THEN
    PERFORM 1 FROM workouts WHERE id = p_workout_id AND v_uid IN (user_id, buddy_id) FOR NO KEY UPDATE;
  END IF;

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

  IF v_wk_ok THEN  -- L2+L3: caller and the M6a partner below, in one ordered pass
    PERFORM public._lock_credit(ARRAY[v_uid, v_wk.user_id, v_wk.buddy_id], true);
  ELSE  -- L2+L3
    PERFORM public._lock_credit(ARRAY[v_uid], true);
  END IF;
  PERFORM public._credit_checkin(v_uid, v_start);
  -- AUTO-LIMIT (prompt 35), L5 row write after the credits: the user's own Complete Check-In, past the
  -- eligibility gates above, restarts their 3-auto-check-in allowance. Only here: not the M6a partner
  -- credit below, not check_in_coach_max, not submit_checkin.
  DELETE FROM auto_checkin_counts WHERE user_id = v_uid;
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
