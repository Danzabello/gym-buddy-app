-- ROLLBACK for supabase/migrations/20261002181833_pin_client_session_start.sql
-- NOT a migration: lives in docs/ so `supabase db push` never runs it.
-- Clients can again write any active_checkin_sessions.started_at (Rule 1 and
-- the reconcile grace would trust a back-dated start). Run as postgres.
BEGIN;
DROP TRIGGER pin_client_session_start ON public.active_checkin_sessions;
DROP FUNCTION public._pin_client_session_start();
COMMIT;
