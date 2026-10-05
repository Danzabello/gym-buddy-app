-- ROLLBACK for supabase/migrations/20261005171049_search_usernames_authenticated_only.sql
-- NOT a migration: lives in docs/ so `supabase db push` never runs it.
-- Restores anon EXECUTE on search_usernames (previous ACL:
-- postgres, authenticated, service_role, anon; no PUBLIC). Run as postgres.
BEGIN;
GRANT EXECUTE ON FUNCTION public.search_usernames(text) TO anon;
COMMIT;
