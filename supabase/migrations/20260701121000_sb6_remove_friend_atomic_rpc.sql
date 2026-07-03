-- SB-6 / DI-3: atomic friend removal.
--
-- Replaces friend_service.removeFriend's 5 sequential, non-transactional client
-- .delete() calls (check-ins -> streak -> members -> team -> friendship), where
-- each of steps 2-5 swallowed its own error and continued, so a mid-sequence
-- failure could orphan rows (dangling team_members/streaks/check-ins, or a
-- team that outlived its friendship).
--
-- This SECURITY DEFINER function performs the whole teardown inside the single
-- implicit transaction of the function body: any error rolls back every delete,
-- so the operation is all-or-nothing.
--
-- Because SECURITY DEFINER runs as the function owner and bypasses RLS, the
-- function does its own authorization: the caller must be authenticated and
-- must actually be in a friendship with p_friend_id before anything is touched.
-- All deletes are scoped to teams the caller is a member of and to the caller's
-- own friendship rows, so a caller can never affect data they aren't part of.

CREATE OR REPLACE FUNCTION public.remove_friend(p_friend_id uuid)
RETURNS boolean
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_caller   uuid := auth.uid();
  v_team_ids uuid[];
BEGIN
  IF v_caller IS NULL THEN
    RAISE EXCEPTION 'not_authenticated';
  END IF;

  IF p_friend_id IS NULL OR p_friend_id = v_caller THEN
    RAISE EXCEPTION 'invalid_friend_id';
  END IF;

  -- Authorization: the caller must actually be friends with p_friend_id.
  IF NOT EXISTS (
    SELECT 1 FROM friendships
    WHERE (user_id = v_caller     AND friend_id = p_friend_id)
       OR (user_id = p_friend_id  AND friend_id = v_caller)
  ) THEN
    RAISE EXCEPTION 'not_friends';
  END IF;

  -- Every shared, non-Coach-Max team the two users are both members of
  -- (normally exactly one). Only these teams are torn down.
  SELECT array_agg(bt.id) INTO v_team_ids
  FROM buddy_teams bt
  WHERE bt.is_coach_max_team = false
    AND EXISTS (SELECT 1 FROM team_members tm WHERE tm.team_id = bt.id AND tm.user_id = v_caller)
    AND EXISTS (SELECT 1 FROM team_members tm WHERE tm.team_id = bt.id AND tm.user_id = p_friend_id);

  -- All deletes below share the function's single transaction — any failure
  -- rolls the whole thing back (this is the fix for the old non-atomic path).
  IF v_team_ids IS NOT NULL THEN
    DELETE FROM daily_team_checkins
    WHERE team_streak_id IN (
      SELECT id FROM team_streaks WHERE team_id = ANY(v_team_ids)
    );

    DELETE FROM team_streaks WHERE team_id = ANY(v_team_ids);
    DELETE FROM team_members WHERE team_id = ANY(v_team_ids);
    DELETE FROM buddy_teams  WHERE id = ANY(v_team_ids);
  END IF;

  DELETE FROM friendships
  WHERE (user_id = v_caller    AND friend_id = p_friend_id)
     OR (user_id = p_friend_id AND friend_id = v_caller);

  RETURN true;
END;
$$;

-- Callable only by authenticated end users (each removing their own friend);
-- service_role retains execute implicitly.
REVOKE ALL ON FUNCTION public.remove_friend(uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.remove_friend(uuid) TO authenticated;
