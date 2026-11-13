-- Rollback for 20261113231708_revoke_rest_tokens_insert.sql
GRANT INSERT (rest_tokens_available) ON public.user_profiles TO authenticated;
