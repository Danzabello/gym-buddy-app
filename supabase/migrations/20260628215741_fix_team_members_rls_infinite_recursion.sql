-- Pre-existing bug, unrelated to tonight's other work: team_members'
-- INSERT policy ("Team creators can add members") directly subqueries
-- buddy_teams, whose own SELECT policy directly subqueries team_members
-- back -- an unresolvable RLS cycle (Postgres error 42P17). This has
-- likely silently broken Coach Max team creation for every new signup.
--
-- Fix: route the cross-table check through a SECURITY DEFINER function,
-- which bypasses RLS for its own internal lookup -- the same pattern
-- already used by get_user_team_ids() to safely break this exact class
-- of cycle.
CREATE OR REPLACE FUNCTION public.user_created_team(p_team_id uuid)
RETURNS boolean
LANGUAGE sql
SECURITY DEFINER
SET search_path = public
STABLE
AS $$
  SELECT EXISTS(
    SELECT 1 FROM buddy_teams WHERE id = p_team_id AND created_by = auth.uid()
  );
$$;

REVOKE ALL ON FUNCTION public.user_created_team(uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.user_created_team(uuid) TO authenticated;

DROP POLICY IF EXISTS "Team creators can add members" ON public.team_members;
CREATE POLICY "Team creators can add members" ON public.team_members
  FOR INSERT TO authenticated
  WITH CHECK (public.user_created_team(team_id));