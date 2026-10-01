-- ROLLBACK for supabase/migrations/20261001122847_lock_workout_templates_writes.sql
-- NOT a migration: lives in docs/ on purpose so `supabase db push` never runs it.
-- Restores authenticated INSERT/UPDATE as captured 2026-10-01 (table-level).
-- Re-opens LIVE-27; only run to unblock a regression.
GRANT INSERT, UPDATE ON public.workout_templates TO authenticated;
