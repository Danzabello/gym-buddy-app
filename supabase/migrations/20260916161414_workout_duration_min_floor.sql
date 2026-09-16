-- S-12 fix: no server-side floor existed on logged workout duration, so a
-- direct write (the release-reachable "Test (1 min)" chip, or any raw API
-- call) could record an arbitrarily short "completed" workout.
--
-- Minimum picked from the app's own data, not guessed: 15 minutes is the
-- lowest value the app can legitimately produce today --
--   - workout_templates.default_duration_minutes bottoms out at 15
--     (Tabata Training / hiit, Stretching / yoga -- both real, intentionally
--     brief workout types)
--   - the Feeling Lucky randomiser's duration pool is [15, 30, 45, 60]
--     (workout_selection_modal.dart), and is NOT clamped by the app's own
--     20-minute custom-duration-dialog floor (_minCategoryDuration), so 15
--     is a value the client can and does legitimately send today.
-- No real path in the app can currently produce anything below 15.
--
-- Applied NOT VALID: there are 17 existing workouts rows and 10 existing
-- workout_logs rows below this floor (durations 0-14, all status=
-- 'completed', dev/QA test-chip artifacts from before this fix) -- this
-- enforces the floor on every write from here on without touching or
-- rejecting that pre-existing data.
ALTER TABLE public.workout_logs
  ADD CONSTRAINT workout_logs_min_duration_check
  CHECK (actual_duration_minutes IS NULL OR actual_duration_minutes >= 15)
  NOT VALID;

ALTER TABLE public.workouts
  ADD CONSTRAINT workouts_min_duration_check
  CHECK (actual_duration_minutes IS NULL OR actual_duration_minutes >= 15)
  NOT VALID;
