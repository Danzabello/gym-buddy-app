-- ROLLBACK for supabase/migrations/20261001122846_revoke_get_user_team_ids_uuid.sql
-- NOT a migration: lives in docs/ on purpose so `supabase db push` never runs it.
-- Restores the live ACL captured 2026-10-01: {=X, postgres, anon, authenticated, service_role}.
-- Re-opens the LIVE-25 hole; only run to unblock a regression.
GRANT EXECUTE ON FUNCTION public.get_user_team_ids(uuid) TO PUBLIC, anon, authenticated;
