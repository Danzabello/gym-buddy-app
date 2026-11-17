-- Rollback for 20261116225000_drop_duplicate_policies.sql: recreates the three policies with their 2026-11-16 text,
-- wrapped as 20261116223000 would have left the two auth.uid() ones (it ships first). If 20261116223000 is not
-- applied, use the bare auth.uid() form instead: (user_id = auth.uid()) and (created_by = auth.uid()).
SET LOCAL lock_timeout = '3s';
CREATE POLICY "Service role manages logs" ON public.notification_log AS PERMISSIVE FOR ALL TO public
  USING (auth.role() = 'service_role'::text);
CREATE POLICY "Users see only nicknames they set" ON public.friend_nicknames AS PERMISSIVE FOR SELECT TO public
  USING (user_id = (SELECT auth.uid()));
CREATE POLICY "Users can update their own teams" ON public.buddy_teams AS PERMISSIVE FOR UPDATE TO public
  USING (created_by = (SELECT auth.uid()));
