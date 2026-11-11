-- Rollback for 20261029010000_revoke_client_checkin_insert. Restores the table-level grant captured before the change:
-- {postgres=arwdDxtm/postgres,anon=r/postgres,authenticated=ar/postgres,service_role=arwdDxtm/postgres}, no column ACLs.
GRANT INSERT ON public.daily_team_checkins TO authenticated;
