-- NOTIF-INBOX delete rule (prompt 40). A user can delete their own notification_inbox rows from the app. A delete that
-- reaches another user's row affects zero rows and raises no error, so the client must ask for the deleted rows back.
-- Nothing else changes: no INSERT or UPDATE for authenticated, nothing for anon, RLS stays on, service_role keeps ALL.
-- Rollback: dev/rollback_20261106120000.sql.

GRANT DELETE ON TABLE public.notification_inbox TO authenticated;
CREATE POLICY "Users delete own inbox" ON public.notification_inbox
  FOR DELETE TO authenticated USING (user_id = (SELECT auth.uid()));
