-- LIVE-15 close-out (workout_logs): mirrors enforce_workout_completion_duration
-- on workouts. workout_logs has an owner INSERT policy and an owner UPDATE
-- policy with no column restriction, so a client can write or rewrite a log
-- row with any duration, bypassing S-12's floor.
--
-- Replaces workout_logs_min_duration_check (S-12, CHECK ... NOT VALID) with a
-- trigger, for the same reason as workouts: NOT VALID leaves the 10 legacy
-- short rows failing the check, and every later UPDATE of one re-evaluates it,
-- including the ON DELETE SET NULL update an FK action issues. Verified live:
-- deleting the buddy account f7c1ef63 failed with 23514 on
-- workout_logs_min_duration_check (workout_logs_buddy_id_fkey is SET NULL).
--
-- Differences from the workouts trigger:
--  * workout_logs has no status/completion column -- every row is a record of a
--    completed workout -- so the rule is on actual_duration_minutes alone and
--    the trigger is BEFORE INSERT OR UPDATE OF actual_duration_minutes.
--  * S-12's CHECK let NULL through; this rejects it, matching workouts. Safe for
--    the app: logWorkout takes a required int, its only caller
--    (checkInAllTeams) guards durationMinutes != null, and no NULL rows exist.
-- FK SET NULL updates only name buddy_id / template_id, so they never fire it
-- and legacy rows stay untouched.
ALTER TABLE public.workout_logs DROP CONSTRAINT workout_logs_min_duration_check;

CREATE OR REPLACE FUNCTION public._enforce_workout_log_duration()
RETURNS trigger
LANGUAGE plpgsql
SET search_path = public
AS $$
BEGIN
  IF NEW.actual_duration_minutes IS NULL OR NEW.actual_duration_minutes < 15 THEN
    RAISE EXCEPTION 'workout log requires actual_duration_minutes >= 15 (got %)',
      NEW.actual_duration_minutes;
  END IF;
  RETURN NEW;
END;
$$;

CREATE TRIGGER enforce_workout_log_duration
BEFORE INSERT OR UPDATE OF actual_duration_minutes ON public.workout_logs
FOR EACH ROW
EXECUTE FUNCTION public._enforce_workout_log_duration();
