-- Rollback for 20261114012440_revoke_client_recompute.sql
GRANT EXECUTE ON FUNCTION public.recompute_team_streak(uuid, date) TO authenticated;
