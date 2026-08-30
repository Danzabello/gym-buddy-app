-- Tracking columns for the workout-overtime-cron nag feature: how many
-- "still working out?" pushes a given in_progress workout has received, and
-- when the last one went out, so the cron can cap at 3 and space them 30
-- minutes apart.
ALTER TABLE workouts
  ADD COLUMN overtime_nag_count int4 NOT NULL DEFAULT 0,
  ADD COLUMN last_overtime_nag_at timestamptz;
