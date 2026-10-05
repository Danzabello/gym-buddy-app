-- Realtime "Allow public access" is OFF, so only private channels may join.
-- The dashboard's dashboard_checkins channel (postgres_changes on
-- daily_team_checkins INSERTs) is now private: true. Joining a private
-- channel requires a SELECT policy on realtime.messages for the join's
-- authorization row (extension broadcast/presence, per the Realtime
-- Authorization docs). Read-only, this one topic, signed-in users only; no
-- INSERT policy, so nobody can broadcast or track presence on it. Which
-- check-ins each user receives is still decided by daily_team_checkins RLS.
CREATE POLICY "authenticated can join dashboard_checkins"
  ON realtime.messages
  FOR SELECT
  TO authenticated
  USING (
    (SELECT realtime.topic()) = 'dashboard_checkins'
    AND realtime.messages.topic = 'dashboard_checkins'
    AND realtime.messages.extension IN ('broadcast', 'presence')
  );
