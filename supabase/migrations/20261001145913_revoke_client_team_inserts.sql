-- LIVE-23 / LIVE-25 / LIVE-19 (M2): the client may no longer create teams,
-- join teams or forge team_streaks rows. Teams are created only by
-- create_buddy_team / ensure_coach_max_team / create_invite_team (SECURITY
-- DEFINER, owned by postgres, so unaffected by these revokes).
-- SELECT policies, get_user_team_ids() and user_created_team are untouched.

DROP POLICY "Authenticated users can create teams" ON public.buddy_teams;
DROP POLICY "Team creators can add members" ON public.team_members;
DROP POLICY "Users can insert themselves" ON public.team_members;
DROP POLICY "Users can insert streaks for their teams" ON public.team_streaks;

REVOKE INSERT ON public.buddy_teams, public.team_members, public.team_streaks FROM authenticated;
