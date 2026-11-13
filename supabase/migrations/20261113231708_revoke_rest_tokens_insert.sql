-- user_profiles.rest_tokens_available: no client write (hygiene 05d left the INSERT grant in place).
-- Grant change: REVOKE INSERT on column rest_tokens_available of public.user_profiles from authenticated.
-- The INSERT grants on user_profiles are column-level (no table-level INSERT), so this column revoke takes
-- effect and leaves the other columns alone. Nothing in lib/ or supabase/functions/ names the column and no
-- server function reads it.
-- Rollback: dev/rollback_20261113231708.sql

REVOKE INSERT (rest_tokens_available) ON public.user_profiles FROM authenticated;
