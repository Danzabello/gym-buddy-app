-- Coach Max impersonation: two INSERT policies check WHAT is being inserted
-- but never WHO is inserting it.
--
--   daily_team_checkins  "Coach Max can check in"
--     PUBLIC, WITH CHECK (user_id = '00000000-...-0001')
--   team_members         "System can insert Coach Max"
--     PUBLIC, WITH CHECK (user_id = '00000000-...-0001')
--
-- Neither references auth.uid(), and anon holds the table-level INSERT grant,
-- so this is an UNAUTHENTICATED write. Confirmed live in rolled-back probes --
-- all four succeeded, both as `authenticated` against teams the caller does not
-- belong to, and as `anon` with no JWT at all:
--   * Coach Max check-in inserted into a foreign team's active streak
--   * Coach Max inserted as a member of a foreign team
--
-- NOT scoped to service_role, despite the policy names: three live client paths
-- legitimately insert Coach Max rows, and onboarding is one of them.
--   * CoachMaxService._addTeamMembers  -> team_members (every new user)
--   * CoachMaxService.checkInCoachMax  -> daily_team_checkins
--   * TeamStreakService._checkInCoachMax -> daily_team_checkins
-- A service_role-only policy would break Coach Max team creation for every
-- signup. service_role has rolbypassrls = true, so coach-max-cron is unaffected
-- by any policy here either way.
--
-- Fix binds each insert to the caller's OWN team instead.

-- ---------------------------------------------------------------------------
-- 1. team_members -- drop as redundant.
--
-- "Team creators can add members" (role authenticated, WITH CHECK
-- user_created_team(team_id)) already covers the legitimate path:
-- CoachMaxService._createCoachMaxTeam inserts buddy_teams with
-- created_by = userId, and user_created_team() is
-- EXISTS(SELECT 1 FROM buddy_teams WHERE id = p_team_id AND created_by =
-- auth.uid()), so the creator can add Coach Max to the team they just made.
-- No replacement policy is needed.
-- ---------------------------------------------------------------------------
DROP POLICY IF EXISTS "System can insert Coach Max" ON public.team_members;

-- ---------------------------------------------------------------------------
-- 2. daily_team_checkins -- replace with a team-scoped equivalent.
--
-- The sibling policy "Users can create check-ins for their teams" requires
-- user_id = auth.uid(), so it does NOT cover Coach Max's row -- dropping
-- without a replacement would break Coach Max check-ins. The replacement keeps
-- the same team-membership subquery that policy uses, and restricts the row to
-- Coach Max, for a caller who is a member of that streak's team.
--
-- Scoped TO authenticated, which alone closes the anon path.
-- ---------------------------------------------------------------------------
DROP POLICY IF EXISTS "Coach Max can check in" ON public.daily_team_checkins;

CREATE POLICY "Coach Max check-in for own team"
  ON public.daily_team_checkins
  FOR INSERT
  TO authenticated
  WITH CHECK (
    user_id = '00000000-0000-0000-0000-000000000001'::uuid
    AND team_streak_id IN (
      SELECT ts.id
      FROM team_streaks ts
      JOIN team_members tm ON tm.team_id = ts.team_id
      WHERE tm.user_id = auth.uid()
    )
  );

-- ---------------------------------------------------------------------------
-- 3. Defence in depth: anon never needs to write either table -- both flows
-- require auth.uid(). Revoking closes the unauthenticated path at the grant
-- layer as well as the policy layer.
-- ---------------------------------------------------------------------------
REVOKE INSERT ON public.daily_team_checkins FROM PUBLIC, anon;
REVOKE INSERT ON public.team_members        FROM PUBLIC, anon;

-- Residual, deliberately not addressed here: a member can still trigger Coach
-- Max's check-in early within their OWN team, bypassing the random scheduled
-- time coach-max-cron picks. That is what the client already does
-- (TeamStreakService._checkInCoachMax fires immediately after the user checks
-- in), so it is existing intended behaviour, not a new gap. The client and the
-- cron are two competing mechanisms for the same row; reconciling them is a
-- separate piece of work.
