-- ROLLBACK for supabase/migrations/20261001145912_team_creation_rpcs.sql
-- NOT a migration: lives in docs/ so `supabase db push` never runs it.
-- Only safe while M2 (20261001145913) is NOT applied: once client INSERT is
-- revoked, these RPCs are the only way the app can create teams.
-- Teams already created through them are left in place. Run as postgres.
BEGIN;
DROP FUNCTION IF EXISTS public.create_buddy_team(uuid);
DROP FUNCTION IF EXISTS public.ensure_coach_max_team();
COMMIT;
