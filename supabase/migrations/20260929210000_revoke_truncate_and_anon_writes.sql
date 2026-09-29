-- Tighten table-level grants on the public schema (defence in depth; no
-- intended runtime behaviour change).
--
--   1. Revoke TRUNCATE from anon and authenticated on every public table.
--      RLS does not apply to TRUNCATE, so the grant is the only barrier, and
--      nothing in the app, the Edge Functions or the database ever truncates.
--   2. Revoke INSERT, UPDATE and DELETE from anon on every public table.
--      No policy lets anon write (every write policy depends on auth.uid() or
--      auth.role() = 'service_role'), so these grants were inert; they are only
--      a loaded gun if a permissive policy or a blanket re-GRANT ever appears
--      (the same reasoning as 20260811205505_close_break_day_delete_bypass).
--
-- Deliberately NOT touched: authenticated's INSERT / UPDATE / DELETE (the app
-- writes as authenticated; trimming those is a separate, per-table change),
-- column-level grants, service_role, postgres, and any function grants.
--
-- Pre-checks done against the live project (2026-09-29, read-only):
--   * SECURITY INVOKER functions that write to public tables: exactly one,
--     cleanup_workout_sessions() (DELETE FROM active_checkin_sessions, fired by
--     trigger on workouts). It runs as whoever updates the workout, which is
--     always authenticated; anon cannot update workouts. authenticated keeps
--     DELETE, so it is unaffected.
--   * Triggers on public tables that write: _fulfil_invite_reward and
--     _grant_achievement_shop_items, both SECURITY DEFINER (run as owner), so
--     unaffected by any role's grants.
--   * No triggers exist on auth.users.
--   * Edge Functions write only with the service_role key (invite-redirect,
--     coach-max-cron, send-notification, workout-overtime-cron, delete-account);
--     delete-account uses the anon key only to identify the caller.
--   * Signed-out flows use auth.signUp / signIn, the search_usernames RPC
--     (SECURITY DEFINER) and invite-redirect (service_role); none writes to a
--     public table as anon.
-- Rollback (exact reverse of the live grants): docs/rollback_grants_20260929210000.sql

REVOKE TRUNCATE ON ALL TABLES IN SCHEMA public FROM anon, authenticated;
REVOKE INSERT, UPDATE, DELETE ON ALL TABLES IN SCHEMA public FROM anon;

-- Self-check: abort (and roll the whole migration back) if anything is left.
DO $$
DECLARE
  n integer;
BEGIN
  SELECT count(*) INTO n
  FROM pg_class c
  JOIN pg_namespace ns ON ns.oid = c.relnamespace AND ns.nspname = 'public'
  CROSS JOIN LATERAL aclexplode(c.relacl) a
  JOIN pg_roles r ON r.oid = a.grantee
  WHERE c.relkind IN ('r', 'p', 'v', 'm', 'f')
    AND (
      (r.rolname IN ('anon', 'authenticated') AND a.privilege_type = 'TRUNCATE')
      OR (r.rolname = 'anon' AND a.privilege_type IN ('INSERT', 'UPDATE', 'DELETE'))
    );
  IF n > 0 THEN
    RAISE EXCEPTION 'grant revoke incomplete: % privilege(s) remain', n;
  END IF;
END $$;
