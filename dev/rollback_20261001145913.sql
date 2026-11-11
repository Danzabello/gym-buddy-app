-- ROLLBACK for supabase/migrations/20261001145913_revoke_client_team_inserts.sql
-- NOT a migration: lives in docs/ so `supabase db push` never runs it.
-- Restores the INSERT grants and the four INSERT policies exactly as they
-- were on live on 2026-10-01 (re-opens LIVE-19/23/25). Run as postgres.
BEGIN;
GRANT INSERT ON public.buddy_teams, public.team_members, public.team_streaks TO authenticated;

CREATE POLICY "Authenticated users can create teams" ON public.buddy_teams
  FOR INSERT TO public WITH CHECK (auth.uid() IS NOT NULL);
CREATE POLICY "Team creators can add members" ON public.team_members
  FOR INSERT TO authenticated WITH CHECK (user_created_team(team_id));
CREATE POLICY "Users can insert themselves" ON public.team_members
  FOR INSERT TO authenticated WITH CHECK (auth.uid() = user_id);
CREATE POLICY "Users can insert streaks for their teams" ON public.team_streaks
  FOR INSERT TO public WITH CHECK (team_id IN (SELECT team_members.team_id FROM team_members WHERE team_members.user_id = auth.uid()));
COMMIT;
