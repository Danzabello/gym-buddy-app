-- ROLLBACK for supabase/migrations/20261001170947_live24_auto_complete_flags_and_input_guards.sql
-- NOT a migration: lives in docs/ so `supabase db push` never runs it.
-- Roll back 20261001170948 (process_stale_sessions) FIRST: it uses these columns.
-- Drops the auto_completed / notice / push-dedup columns (their data is lost),
-- the client guards and the daily cap, and re-grants client DELETE on
-- coach_max_schedule. Re-opens LIVE-24 (forged has_checked_in, client-chosen
-- durations and timestamps, unlimited completions per day). Run as postgres.
BEGIN;
DROP TRIGGER guard_client_auto_complete_flags ON public.workouts;
DROP TRIGGER guard_client_auto_complete_flags ON public.workout_logs;
DROP TRIGGER clamp_client_workout_writes ON public.workouts;
DROP TRIGGER enforce_workout_daily_cap ON public.workouts;
DROP TRIGGER clamp_client_coach_max_schedule ON public.coach_max_schedule;

DROP FUNCTION public._guard_client_auto_complete_flags();
DROP FUNCTION public._clamp_client_workout_writes();
DROP FUNCTION public._enforce_workout_daily_cap();
DROP FUNCTION public._clamp_client_coach_max_schedule();

ALTER TABLE public.workouts
  DROP COLUMN auto_completed,
  DROP COLUMN auto_completed_notice_seen_at;
ALTER TABLE public.workout_logs
  DROP COLUMN auto_completed,
  DROP COLUMN auto_completed_notice_seen_at;
ALTER TABLE public.active_checkin_sessions
  DROP COLUMN goal_notified_at,
  DROP COLUMN reminder_notified_at;

GRANT DELETE ON public.coach_max_schedule TO authenticated;
COMMIT;
