-- SEC-A: active_checkin_sessions. The four "or buddy" policies keyed on
-- linked_workout_id (nothing writes or reads it; w.user_id = w.user_id is
-- always true) let any signed-in user INSERT a session for an unrelated user
-- by pointing linked_workout_id at their own workout; process_stale_sessions
-- then credited that user a workout they never did. The own-row policies for
-- every command stay. No client reads another user's session.
DROP POLICY "Users can create sessions for themselves or workout buddies" ON public.active_checkin_sessions;
DROP POLICY "Users can delete their own sessions or linked buddy sessions" ON public.active_checkin_sessions;
DROP POLICY "Users can update their own sessions or linked buddy sessions" ON public.active_checkin_sessions;
DROP POLICY "Users can view their own sessions or workout buddy sessions" ON public.active_checkin_sessions;
REVOKE ALL ON public.active_checkin_sessions FROM anon;

-- A client may link its own session only to a workout it is in. A forged
-- workout_id let process_stale_sessions credit (and complete) an unrelated
-- pair's workout. Checked in the existing client-role trigger rather than in
-- the INSERT and UPDATE policies: one place covers insert, update and upsert,
-- and an UPDATE that leaves workout_id unchanged is not re-checked.
CREATE OR REPLACE FUNCTION public._pin_client_session_start()
RETURNS trigger
LANGUAGE plpgsql
SET search_path = public
AS $$
BEGIN
  IF current_user NOT IN ('authenticated', 'anon') THEN
    RETURN NEW;
  END IF;

  IF NEW.workout_id IS NOT NULL
     AND (TG_OP = 'INSERT' OR NEW.workout_id IS DISTINCT FROM OLD.workout_id)
     AND NOT EXISTS (SELECT 1 FROM workouts w
                     WHERE w.id = NEW.workout_id AND auth.uid() IN (w.user_id, w.buddy_id)) THEN
    RAISE EXCEPTION 'workout_not_yours' USING ERRCODE = '42501';
  END IF;

  IF NEW.workout_id IS NOT NULL AND NEW.started_at = (
    SELECT w.workout_started_at FROM workouts w
    WHERE w.id = NEW.workout_id AND auth.uid() IN (w.user_id, w.buddy_id)
  ) THEN
    RETURN NEW;
  END IF;

  NEW.started_at := CASE WHEN TG_OP = 'INSERT' THEN now() ELSE OLD.started_at END;
  RETURN NEW;
END;
$$;
