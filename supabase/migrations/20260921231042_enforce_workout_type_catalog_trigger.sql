-- LIVE-15 close-out (workouts.workout_type). workout_type was free text with no
-- CHECK, and verify_achievement_progress' mixed_bag achievement counts
-- DISTINCT workout_type over the caller's completed workouts, so a client
-- could inflate it with made-up type names.
--
-- The catalog is the 8 names the app's two schedule sheets offer (identical
-- lists in schedule_workout_sheet.dart and quick_schedule_sheet.dart). This is a
-- trigger, not a CHECK, for the same reason as the duration triggers: 16 legacy
-- rows fall outside the catalog (12 'Buddy Workout', 3 'Check-in', 1 'Weights',
-- all Oct-Dec 2025, none producible by current code), and a NOT VALID CHECK
-- would make them un-updatable -- including by the buddy_id ON DELETE SET NULL
-- action, i.e. it would reopen the account-deletion bug fixed in ba28371.
-- UPDATE OF workout_type only fires when an UPDATE names the column, so FK
-- actions and unrelated edits leave legacy rows alone.
--
-- 'Buddy Workout' is deliberately NOT allowlisted: its only writer
-- (WorkoutInviteService.acceptInvite) is dead code -- WorkoutInvitesCard is
-- never instantiated and nothing calls sendInvite.
CREATE OR REPLACE FUNCTION public._enforce_workout_type_catalog()
RETURNS trigger
LANGUAGE plpgsql
SET search_path = public
AS $$
BEGIN
  IF NEW.workout_type NOT IN (
    'Strength', 'Cardio', 'HIIT', 'Leg Day', 'Upper Body', 'Full Body',
    'Yoga', 'Other'
  ) THEN
    RAISE EXCEPTION 'invalid workout_type: %', NEW.workout_type;
  END IF;
  RETURN NEW;
END;
$$;

CREATE TRIGGER enforce_workout_type_catalog
BEFORE INSERT OR UPDATE OF workout_type ON public.workouts
FOR EACH ROW
EXECUTE FUNCTION public._enforce_workout_type_catalog();
