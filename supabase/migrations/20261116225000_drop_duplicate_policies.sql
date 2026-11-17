-- M5 (DB audit DB-6): drop three permissive policies that add nothing (RLS change, ASK FIRST, by name):
--   notification_log "Service role manages logs": FOR ALL TO public USING (auth.role() = 'service_role'). The only
--     role that carries that claim is service_role, which has BYPASSRLS, so the policy never grants a row; for every
--     other role it is false. It is also the last auth_rls_initplan row after 20261116223000.
--   friend_nicknames "Users see only nicknames they set": SELECT, (user_id = auth.uid()); its twin "Users can view own
--     nicknames" is (auth.uid() = user_id), same roles, no WITH CHECK on either.
--   buddy_teams "Users can update their own teams": UPDATE, (created_by = auth.uid()); its twin "Users can update teams
--     they created" has the same text, same roles, no WITH CHECK on either.
-- The three other overlapping pairs (own row OR partner row on break_day_usage, buddy_teams SELECT, user_inventory)
-- are intended and stay. Ships after 20261116223000; the guard stops it if a twin's text is not what was checked.
SET LOCAL lock_timeout = '3s';
DO $guard$
BEGIN
  IF (SELECT count(*) FROM pg_policies WHERE schemaname = 'public' AND roles = '{public}' AND with_check IS NULL AND (
        (tablename = 'friend_nicknames' AND policyname = 'Users can view own nicknames' AND cmd = 'SELECT'
           AND qual IN ('(auth.uid() = user_id)', '(( SELECT auth.uid() AS uid) = user_id)'))
     OR (tablename = 'buddy_teams' AND policyname = 'Users can update teams they created' AND cmd = 'UPDATE'
           AND qual IN ('(created_by = auth.uid())', '(created_by = ( SELECT auth.uid() AS uid))')))) <> 2 THEN
    RAISE EXCEPTION 'drop_duplicate_policies: a kept twin is missing or changed, nothing dropped';
  END IF;
END
$guard$;
DROP POLICY "Service role manages logs" ON public.notification_log;
DROP POLICY "Users see only nicknames they set" ON public.friend_nicknames;
DROP POLICY "Users can update their own teams" ON public.buddy_teams;
