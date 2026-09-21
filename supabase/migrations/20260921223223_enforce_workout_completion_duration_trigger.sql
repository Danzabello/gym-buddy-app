-- LIVE-15 close-out (workouts): a completed workout must carry a real
-- duration, or a client can set status='completed' with actual_duration_minutes
-- NULL/short and count toward workout achievements while bypassing S-12's floor.
--
-- Replaces workouts_min_duration_check (S-12, CHECK ... NOT VALID) with a
-- trigger rather than a stricter CHECK, for two reasons found in investigation:
--  1. A CHECK treats a NULL result as passing, so
--     (status <> 'completed' OR actual_duration_minutes >= 15) accepts
--     status='completed' with a NULL duration -- the exact case to block.
--  2. NOT VALID grandfathering leaves 20 legacy rows that fail the check, and
--     every later UPDATE of such a row re-evaluates it -- including the
--     ON DELETE SET NULL update an FK action issues. Verified live: deleting
--     a buddy's account failed with 23514 on workouts_min_duration_check.
-- UPDATE OF status, actual_duration_minutes only fires when an UPDATE names
-- one of those columns, so FK SET NULL updates (buddy_id, started_by_user_id,
-- cancel_requested_by) leave legacy rows alone while any client attempt to
-- complete a workout, or to change a completed workout's duration, is checked.
--
-- Every workouts read in verify_achievement_progress filters
-- status = 'completed' (including its only duration use, > 90), so dropping the
-- CHECK's coverage of non-completed rows loosens nothing reward-relevant.
ALTER TABLE public.workouts DROP CONSTRAINT workouts_min_duration_check;

CREATE OR REPLACE FUNCTION public._enforce_workout_completion_duration()
RETURNS trigger
LANGUAGE plpgsql
SET search_path = public
AS $$
BEGIN
  IF NEW.status = 'completed'
     AND (NEW.actual_duration_minutes IS NULL OR NEW.actual_duration_minutes < 15)
  THEN
    RAISE EXCEPTION 'workout completion requires actual_duration_minutes >= 15 (got %)',
      NEW.actual_duration_minutes;
  END IF;
  RETURN NEW;
END;
$$;

CREATE TRIGGER enforce_workout_completion_duration
BEFORE INSERT OR UPDATE OF status, actual_duration_minutes ON public.workouts
FOR EACH ROW
EXECUTE FUNCTION public._enforce_workout_completion_duration();
