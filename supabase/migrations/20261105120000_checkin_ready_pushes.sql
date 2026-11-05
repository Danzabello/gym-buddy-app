-- CHECKIN-READY-PUSH (prompt 34). A solo dashboard check-in sends no push when
-- its timer unlocks Check In: 20261008200000 removed the net.http_post of pushes
-- #8/#9 from process_stale_sessions and nothing replaced it (workout-overtime-cron
-- only reads in-progress workouts rows). Restores them, through _send_push:
--   stage 1 at the goal, stage 2 thirty minutes after stage 1, stage 3 an hour
--   after stage 2, while the session is open and before the 3h30 auto check-in.
-- Scope: not for a session of an in-progress workout the user is still in (the
-- overtime cron's). Type checkin_ready (notif_workouts), channel
-- gym_buddy_high_importance, not urgent (quiet hours apply), tag session_<id>,
-- batch_key session_goal_<id> / session_reminder_<id> / session_reminder2_<id>.
-- The cron runs every minute so stage 1 lands within about a minute.
-- The credit, auto-complete and close logic is the live body, unchanged.
-- Rollback: docs/rollback_20261105120000.sql.

ALTER TABLE public.active_checkin_sessions ADD COLUMN reminder2_notified_at timestamptz;

INSERT INTO public.push_templates (key, variant, title, body) VALUES
  ('session_goal', 1, 'Timer''s done', 'Your check-in is unlocked. Open the app and tap Complete Check-In.'),
  ('session_reminder', 1, 'Still waiting on you', 'Your workout isn''t counted until you check in. It takes one tap.'),
  ('session_reminder2', 1, 'Last reminder', 'Tap Complete Check-In now. If you skip it, it''s counted automatically 3½ hours after you started.');

CREATE OR REPLACE FUNCTION public.process_stale_sessions(p_now timestamp with time zone DEFAULT now())
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_ids uuid[];
  v_sid uuid;
  s record;
  c record;
  v_credit uuid[];
  v_close boolean;
  v_any boolean;
  v_day date;
  v_kind text;
  v_color text;
  v_pushed integer := 0;
  v_paid integer := 0;
  v_unpaid integer := 0;
  v_stale integer := 0;
  v_orphans integer := 0;
  v_done uuid[];
  v_p uuid;
  o record;
BEGIN
  -- Lock every session whose goal is reached; an overlapping run skips them.
  SELECT array_agg(id) INTO v_ids FROM (
    SELECT a.id
    FROM active_checkin_sessions a
    LEFT JOIN workouts w ON w.id = a.workout_id
    WHERE COALESCE(w.workout_started_at, a.started_at)
          + make_interval(mins => LEAST(GREATEST(COALESCE(w.planned_duration_minutes, a.planned_duration, 30), 15), 210))
          <= p_now
    ORDER BY a.started_at
    FOR UPDATE OF a SKIP LOCKED
  ) due;

  FOREACH v_sid IN ARRAY COALESCE(v_ids, '{}'::uuid[]) LOOP
    SELECT a.id, a.user_id, a.workout_id, a.goal_notified_at, a.reminder_notified_at, a.reminder2_notified_at,
           COALESCE(w.workout_started_at, a.started_at) AS start_at,
           LEAST(GREATEST(COALESCE(w.planned_duration_minutes, a.planned_duration, 30), 15), 210) AS goal,
           COALESCE(w.workout_type, a.workout_type, 'Workout') AS wtype,
           w.status AS w_status,
           (w.id IS NOT NULL AND (
              (a.user_id = w.user_id AND NOT COALESCE(w.creator_cancelled, false))
              OR (a.user_id = w.buddy_id AND NOT COALESCE(w.buddy_cancelled, false)))) AS in_workout
    INTO s
    FROM active_checkin_sessions a
    LEFT JOIN workouts w ON w.id = a.workout_id
    WHERE a.id = v_sid;
    CONTINUE WHEN NOT FOUND;  -- already credited with its workout partner

    -- Abandoned long before this job could see it: close, no push, no credit.
    IF s.start_at < p_now - interval '24 hours' THEN
      DELETE FROM active_checkin_sessions WHERE id = s.id;
      v_stale := v_stale + 1;
      CONTINUE;
    END IF;

    -- Before 3h30: stage 1 at the goal, stage 2 thirty minutes after stage 1,
    -- stage 3 an hour after stage 2, never more, one stage per session per run.
    -- A session of an in-progress workout it is still part of belongs to
    -- workout-overtime-cron (still_going, before_auto): no push from here,
    -- and no stamp, so nothing is claimed that was not sent.
    IF p_now < s.start_at + interval '210 minutes' THEN
      CONTINUE WHEN s.in_workout AND s.w_status = 'in_progress';
      IF s.goal_notified_at IS NULL THEN
        UPDATE active_checkin_sessions SET goal_notified_at = p_now WHERE id = s.id;
        v_kind := 'session_goal';
        v_color := 'emerald';
      ELSIF s.reminder_notified_at IS NULL AND p_now >= s.goal_notified_at + interval '30 minutes' THEN
        UPDATE active_checkin_sessions SET reminder_notified_at = p_now WHERE id = s.id;
        v_kind := 'session_reminder';
        v_color := 'orange';
      ELSIF s.reminder_notified_at IS NOT NULL AND s.reminder2_notified_at IS NULL
            AND p_now >= s.reminder_notified_at + interval '1 hour' THEN
        UPDATE active_checkin_sessions SET reminder2_notified_at = p_now WHERE id = s.id;
        v_kind := 'session_reminder2';
        v_color := 'amber';
      ELSE
        CONTINUE;
      END IF;
      -- Copy comes from push_templates; _send_push skips a user with no device
      -- token (03b's in-app notice is the fallback). The stamp above is the
      -- claim, so a run that finds it set never sends the stage twice.
      IF public._send_push(s.user_id, v_kind, '{}'::jsonb, v_color, 'high_importance',
                           'checkin_ready', s.id::text, 'session_' || s.id::text, false, NULL) THEN
        v_pushed := v_pushed + 1;
      END IF;
      CONTINUE;
    END IF;

    -- 3h30: auto-complete. In a shared workout still in progress, credit
    -- everyone still in it first: closing the row fires
    -- cleanup_workout_sessions, which (as postgres) deletes all its sessions.
    v_close := s.in_workout AND s.w_status = 'in_progress';
    IF v_close THEN
      SELECT array_agg(a.id) INTO v_credit
      FROM active_checkin_sessions a
      JOIN workouts w ON w.id = a.workout_id
      WHERE a.workout_id = s.workout_id
        AND ((a.user_id = w.user_id AND NOT COALESCE(w.creator_cancelled, false))
          OR (a.user_id = w.buddy_id AND NOT COALESCE(w.buddy_cancelled, false)));
    ELSE
      v_credit := ARRAY[s.id];
    END IF;

    v_any := false;
    v_done := '{}';
    FOR c IN
      SELECT id, user_id, workout_emoji FROM active_checkin_sessions
      WHERE id = ANY(v_credit) ORDER BY id FOR UPDATE
    LOOP
      IF public._auto_credit(c.user_id, s.start_at, s.goal, s.wtype, c.workout_emoji) THEN
        v_any := true;
        v_paid := v_paid + 1;
      ELSE
        v_unpaid := v_unpaid + 1;
      END IF;
      v_done := v_done || c.user_id;
      DELETE FROM active_checkin_sessions WHERE id = c.id;
    END LOOP;

    -- M6b (owner rule 2026-10-02): a participant who confirmed ready and has
    -- not cancelled is in without a session too, unless already credited
    -- for their start day (e.g. a manual Finish credited them).
    IF v_close THEN
      FOR v_p IN
        SELECT x.u FROM workouts w2,
          LATERAL (VALUES (w2.user_id, w2.creator_ready AND NOT w2.creator_cancelled),
                          (w2.buddy_id, w2.buddy_ready AND NOT w2.buddy_cancelled)) AS x(u, ok)
        WHERE w2.id = s.workout_id AND x.u IS NOT NULL AND x.ok AND x.u <> ALL(v_done)
          AND NOT EXISTS (SELECT 1 FROM daily_team_checkins d
                          WHERE d.user_id = x.u
                            AND d.check_in_date = (s.start_at AT TIME ZONE public.safe_user_tz(x.u))::date)
      LOOP
        IF public._auto_credit(v_p, s.start_at, s.goal, s.wtype, NULL) THEN
          v_any := true;
          v_paid := v_paid + 1;
        ELSE
          v_unpaid := v_unpaid + 1;
        END IF;
      END LOOP;
    END IF;

    -- Close the shared row once: completed with the goal duration if anyone
    -- was paid, else (or over the daily cap) cancelled. Both flagged.
    IF v_close THEN
      BEGIN
        UPDATE workouts SET
          status = CASE WHEN v_any THEN 'completed' ELSE 'cancelled' END,
          actual_duration_minutes = CASE WHEN v_any THEN s.goal ELSE actual_duration_minutes END,
          workout_completed_at = CASE WHEN v_any THEN s.start_at + make_interval(mins => s.goal)
                                      ELSE workout_completed_at END,
          auto_completed = true,
          updated_at = p_now
        WHERE id = s.workout_id AND status = 'in_progress';
      EXCEPTION WHEN raise_exception THEN  -- daily_workout_limit_reached
        UPDATE workouts SET status = 'cancelled', auto_completed = true, updated_at = p_now
        WHERE id = s.workout_id AND status = 'in_progress';
      END;
    END IF;
  END LOOP;

  -- In-progress workouts nobody holds a session for, at 3h30: ready,
  -- not-cancelled participants are credited (M6b; started in the last 24h,
  -- not already credited for their start day), then the row is closed:
  -- completed if anyone was paid, else (or over the daily cap) cancelled.
  FOR o IN
    SELECT w.id, w.user_id, w.buddy_id, w.workout_started_at, w.workout_type,
           w.creator_ready AND NOT w.creator_cancelled AS creator_in,
           w.buddy_ready AND NOT w.buddy_cancelled AS buddy_in,
           LEAST(GREATEST(COALESCE(w.planned_duration_minutes, 30), 15), 210) AS goal
    FROM workouts w
    WHERE w.status = 'in_progress'
      AND w.workout_started_at <= p_now - interval '210 minutes'
      AND NOT EXISTS (SELECT 1 FROM active_checkin_sessions a WHERE a.workout_id = w.id)
    FOR UPDATE OF w SKIP LOCKED
  LOOP
    v_any := false;
    IF o.workout_started_at >= p_now - interval '24 hours' THEN
      FOR v_p IN
        SELECT x.u FROM (VALUES (o.user_id, o.creator_in), (o.buddy_id, o.buddy_in)) AS x(u, ok)
        WHERE x.u IS NOT NULL AND x.ok
          AND NOT EXISTS (SELECT 1 FROM daily_team_checkins d
                          WHERE d.user_id = x.u
                            AND d.check_in_date = (o.workout_started_at AT TIME ZONE public.safe_user_tz(x.u))::date)
      LOOP
        IF public._auto_credit(v_p, o.workout_started_at, o.goal, o.workout_type, NULL) THEN
          v_any := true;
          v_paid := v_paid + 1;
        ELSE
          v_unpaid := v_unpaid + 1;
        END IF;
      END LOOP;
    END IF;
    BEGIN
      UPDATE workouts SET
        status = CASE WHEN v_any THEN 'completed' ELSE 'cancelled' END,
        actual_duration_minutes = CASE WHEN v_any THEN o.goal ELSE actual_duration_minutes END,
        workout_completed_at = CASE WHEN v_any THEN o.workout_started_at + make_interval(mins => o.goal)
                                    ELSE workout_completed_at END,
        auto_completed = true,
        updated_at = p_now
      WHERE id = o.id AND status = 'in_progress';
    EXCEPTION WHEN raise_exception THEN  -- daily_workout_limit_reached
      UPDATE workouts SET status = 'cancelled', auto_completed = true, updated_at = p_now
      WHERE id = o.id AND status = 'in_progress';
    END;
    v_orphans := v_orphans + 1;
  END LOOP;

  RETURN jsonb_build_object('pushed', v_pushed, 'paid', v_paid, 'unpaid', v_unpaid,
                            'stale_closed', v_stale, 'orphans_closed', v_orphans);
END;
$function$

;
REVOKE EXECUTE ON FUNCTION public.process_stale_sessions(timestamp with time zone) FROM PUBLIC, anon, authenticated;

-- Every minute (was every 5). cron.schedule upserts by job name; same command.
SELECT cron.schedule('process-stale-sessions', '* * * * *', 'SELECT public.process_stale_sessions();');
