-- LIVE-25 part 1: get_user_team_ids(uuid) is SECURITY DEFINER with no caller check,
-- executable by anon. No client, function, policy or trigger uses the uuid overload
-- (the team_members_select policy uses the no-arg overload, left untouched).
-- service_role keeps EXECUTE.
REVOKE EXECUTE ON FUNCTION public.get_user_team_ids(uuid) FROM PUBLIC, anon, authenticated;
