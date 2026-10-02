-- Streak events M1: the server owns active_checkin_sessions.started_at.
-- Rule 1 (credit the local day a workout STARTED) and the reconcile grace
-- both read started_at, so a client must not be able to back-date it.
-- Client writes keep their started_at only when it equals the server-set
-- workout_started_at of a linked workout the caller is in (buddy timers
-- anchor to it: setBuddyReady, _startWorkout, _adoptLiveBuddyWorkoutSession).
-- Otherwise: INSERT -> now(), UPDATE -> unchanged (resume never moves it).
-- Old clients keep working; the value is overwritten silently.
CREATE OR REPLACE FUNCTION public._pin_client_session_start()
RETURNS trigger
LANGUAGE plpgsql
SET search_path = public
AS $$
BEGIN
  IF current_user NOT IN ('authenticated', 'anon') THEN
    RETURN NEW;
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

CREATE TRIGGER pin_client_session_start
  BEFORE INSERT OR UPDATE ON public.active_checkin_sessions
  FOR EACH ROW EXECUTE FUNCTION public._pin_client_session_start();
