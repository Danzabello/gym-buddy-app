-- ROLLBACK for supabase/migrations/20261002182226_finish_checkin_session.sql
-- NOT a migration: lives in docs/ so `supabase db push` never runs it.
-- Drops the Finish RPC. Roll the app back first: a build that calls
-- finish_checkin_session cannot check in without it. Run as postgres.
BEGIN;
DROP FUNCTION public.finish_checkin_session(uuid);
COMMIT;
