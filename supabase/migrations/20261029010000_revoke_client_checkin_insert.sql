-- Single server check-in RPC, migration B. Report: docs/hygiene/checkin_rpc_report.md.
-- Rollback: docs/rollback_20261029010000.sql. Applied after the device check of the build that no longer inserts.
-- Every check-in row is now written by the server (finish_checkin_session, process_stale_sessions,
-- submit_checkin, Coach Max), so clients lose INSERT on daily_team_checkins (A-3 / F1).
-- Before: {postgres=arwdDxtm/postgres,anon=r/postgres,authenticated=ar/postgres,service_role=arwdDxtm/postgres}, no column ACLs.
REVOKE INSERT ON public.daily_team_checkins FROM authenticated;
