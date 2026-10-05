-- ROLLBACK for supabase/migrations/20261002224500_auto_complete_credits_ready_partner.sql
-- NOT a migration: lives in docs/ so `supabase db push` never runs it.
-- Restores process_stale_sessions as of M3 (prosrc md5
-- 2feb1ced5796c0a44486b78f6b845f55) and drops _auto_credit: session-less
-- participants are no longer credited, orphans close without credit again.
-- Run as postgres.
BEGIN;
CREATE OR REPLACE FUNCTION public.process_stale_sessions(p_now timestamptz DEFAULT now())
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_key text;
  v_ids uuid[];
  v_sid uuid;
  s record;
  c record;
  v_credit uuid[];
  v_close boolean;
  v_any boolean;
  v_day date;
  v_kind text;
  v_title text;
  v_body text;
  v_pushed integer := 0;
  v_paid integer := 0;
  v_unpaid integer := 0;
  v_stale integer := 0;
  v_orphans integer := 0;
BEGIN
  SELECT decrypted_secret INTO v_key
  FROM vault.decrypted_secrets WHERE name = 'service_role_key' LIMIT 1;

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
    SELECT a.id, a.user_id, a.workout_id, a.goal_notified_at, a.reminder_notified_at,
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

    -- Before 3h30: push #1 at the goal, push #2 an hour later, never more.
    IF p_now < s.start_at + interval '210 minutes' THEN
      IF s.goal_notified_at IS NULL THEN
        UPDATE active_checkin_sessions SET goal_notified_at = p_now WHERE id = s.id;
        v_kind := 'goal';
        v_title := 'Workout complete';
        v_body := 'Workout complete. Log back into the app to confirm.';
      ELSIF s.reminder_notified_at IS NULL AND p_now >= s.goal_notified_at + interval '1 hour' THEN
        UPDATE active_checkin_sessions SET reminder_notified_at = p_now WHERE id = s.id;
        v_kind := 'reminder';
        v_title := 'Workout waiting';
        v_body := 'Your workout is still waiting. Open the app to confirm it.';
      ELSE
        CONTINUE;
      END IF;
      -- No token: skip silently (03b's in-app notice is the fallback).
      IF v_key IS NOT NULL AND EXISTS (SELECT 1 FROM device_tokens WHERE user_id = s.user_id) THEN
        PERFORM net.http_post(
          url := 'https://jwpbunulswiihkzpjopy.supabase.co/functions/v1/send-notification',
          headers := jsonb_build_object('Content-Type', 'application/json', 'Authorization', 'Bearer ' || v_key),
          body := jsonb_build_object(
            'user_id', s.user_id, 'title', v_title, 'body', v_body,
            'type', 'workout_overtime', 'reference_id', s.id::text,
            'batch_key', 'session_' || v_kind || '_' || s.id::text));
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
    FOR c IN
      SELECT id, user_id, workout_emoji FROM active_checkin_sessions
      WHERE id = ANY(v_credit) ORDER BY id FOR UPDATE
    LOOP
      v_day := (s.start_at AT TIME ZONE public.safe_user_tz(c.user_id))::date;  -- Rule 1: start day
      IF NOT EXISTS (
        SELECT 1 FROM workout_logs
        WHERE user_id = c.user_id AND auto_completed AND workout_date = v_day
      ) THEN
        PERFORM public._server_checkin(c.user_id, v_day);
        INSERT INTO workout_logs (user_id, workout_date, workout_time, workout_name, workout_category,
                                  workout_emoji, planned_duration_minutes, actual_duration_minutes, auto_completed)
        VALUES (c.user_id, v_day, s.start_at + make_interval(mins => s.goal), s.wtype,
                COALESCE((SELECT category FROM workout_templates WHERE name = s.wtype LIMIT 1), 'other'),
                COALESCE(c.workout_emoji, '💪'), s.goal, s.goal, true);
        v_any := true;
        v_paid := v_paid + 1;
      ELSE
        v_unpaid := v_unpaid + 1;
      END IF;
      DELETE FROM active_checkin_sessions WHERE id = c.id;
    END LOOP;

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

  -- In-progress workouts nobody holds a session for (never opened the
  -- timer, or abandoned): closed without credit at 3h30.
  UPDATE workouts w SET status = 'cancelled', auto_completed = true, updated_at = p_now
  WHERE w.status = 'in_progress'
    AND w.workout_started_at <= p_now - interval '210 minutes'
    AND NOT EXISTS (SELECT 1 FROM active_checkin_sessions a WHERE a.workout_id = w.id);
  GET DIAGNOSTICS v_orphans = ROW_COUNT;

  RETURN jsonb_build_object('pushed', v_pushed, 'paid', v_paid, 'unpaid', v_unpaid,
                            'stale_closed', v_stale, 'orphans_closed', v_orphans);
END;
$$;

REVOKE EXECUTE ON FUNCTION public.process_stale_sessions(timestamptz) FROM PUBLIC, anon, authenticated;
DROP FUNCTION public._auto_credit(uuid, timestamptz, integer, text, text);
COMMIT;
