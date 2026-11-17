-- M3 (DB audit DB-3, DB-4; tracker B4, prepared 2026-11-12 as 20261113103000, held): wrap every bare auth.uid()
-- in a public policy as (SELECT auth.uid()), so Postgres evaluates it once per statement (an InitPlan) and can use
-- idx_team_members_user inside the policy subqueries, instead of re-evaluating it per row.
-- RLS change (ASK FIRST): rewrites the USING / WITH CHECK text of 54 policies on 24 tables (live 2026-11-16).
-- Roles, commands, permissive flags and conditions are unchanged: only the call is wrapped. The second block fails
-- the migration if a bare call is left, and the whole file is one transaction, so nothing half-applies.
-- Locks: ALTER POLICY takes ACCESS EXCLUSIVE on each of the 24 tables, in table-name order, until COMMIT. That is
-- outside the L0 to L5 credit order: a concurrent check-in can wait, or one side can lose a 40P01. lock_timeout makes
-- the migration give up after 3 s instead of queueing traffic behind it; rerun it between cron ticks.
-- Rollback: dev/rollback_20261116223000.sql (54 explicit ALTER POLICY statements with the 2026-11-16 text). Do not
-- use a reverse regex: it would also unwrap policies that were wrapped before this migration (notification_inbox).
SET LOCAL lock_timeout = '3s';

DO $initplan$
DECLARE
  p record;
  q text;
  c text;
BEGIN
  FOR p IN
    SELECT schemaname, tablename, policyname, qual, with_check
    FROM pg_policies
    WHERE schemaname = 'public'
      AND (coalesce(qual, '') ~ '(?<!SELECT )auth\.uid\(\)' OR coalesce(with_check, '') ~ '(?<!SELECT )auth\.uid\(\)')
    ORDER BY tablename, policyname
  LOOP
    q := regexp_replace(p.qual,       '(?<!SELECT )auth\.uid\(\)', '(SELECT auth.uid())', 'g');
    c := regexp_replace(p.with_check, '(?<!SELECT )auth\.uid\(\)', '(SELECT auth.uid())', 'g');
    EXECUTE format('ALTER POLICY %I ON %I.%I', p.policyname, p.schemaname, p.tablename)
      || CASE WHEN q IS NOT NULL THEN ' USING (' || q || ')' ELSE '' END
      || CASE WHEN c IS NOT NULL THEN ' WITH CHECK (' || c || ')' ELSE '' END;
  END LOOP;
END
$initplan$;

DO $verify$
BEGIN
  IF EXISTS (
    SELECT 1 FROM pg_policies
    WHERE schemaname = 'public'
      AND (coalesce(qual, '') ~ '(?<!SELECT )auth\.uid\(\)' OR coalesce(with_check, '') ~ '(?<!SELECT )auth\.uid\(\)')
  ) THEN
    RAISE EXCEPTION 'rls_initplan: a bare auth.uid() is left in a public policy';
  END IF;
END
$verify$;
