-- ROLLBACK for supabase/migrations/20261001124928_pin_client_checkin_date.sql
-- NOT a migration: lives in docs/ on purpose so `supabase db push` never runs it.
--
-- Restores the pre-fix state captured 2026-10-01: no BEFORE INSERT trigger,
-- authenticated has table-level UPDATE, and the client UPDATE policy below.
-- Re-opens LIVE-22 (client-chosen check-in dates); only run to unblock a regression.
--
-- Run as postgres (SQL editor or `supabase db query`).
BEGIN;

DROP TRIGGER IF EXISTS pin_client_checkin_date ON public.daily_team_checkins;
DROP FUNCTION IF EXISTS public._pin_client_checkin_date();

GRANT UPDATE ON public.daily_team_checkins TO authenticated;
CREATE POLICY "Users can update their own check-ins" ON public.daily_team_checkins
  FOR UPDATE TO public
  USING (user_id = auth.uid())
  WITH CHECK (user_id = auth.uid());

COMMIT;
