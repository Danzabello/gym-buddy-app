-- Consistency fix: an invited buddy should be a real buddy everywhere, not
-- just in the streak wheel.
--
-- The Gym Buddies list (FriendsPageModern) is built from friendships
-- (FriendService.getFriends), while the dashboard streak wheel is built from
-- team_streaks. The normal buddy flow (FriendService.acceptFriendRequest)
-- creates BOTH a friendship and a team, so those buddies show up in both. The
-- invite flow (accept_invite -> create_invite_team) only created the team, so
-- an invited buddy appeared in the wheel but was missing from the list.
--
-- Fix: create_invite_team now also creates an accepted friendship between the
-- two, mirroring the normal flow. Idempotent and direction-agnostic. Also pins
-- search_path = public (the Group D hardening item for this SECURITY DEFINER
-- function, handled here since we're editing it anyway).

CREATE OR REPLACE FUNCTION public.create_invite_team(p_inviter_id uuid, p_invitee_id uuid)
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path = public
AS $function$
DECLARE
  v_team_id UUID;
  v_now TIMESTAMPTZ := NOW();
BEGIN
  IF auth.uid() IS NULL OR auth.uid() <> p_invitee_id THEN
    RAISE EXCEPTION 'not_authorized';
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM invites
    WHERE inviter_id = p_inviter_id
      AND accepted_by = p_invitee_id
      AND status = 'accepted'
  ) THEN
    RAISE EXCEPTION 'no_accepted_invite';
  END IF;

  INSERT INTO buddy_teams (team_name, team_emoji, is_coach_max_team, max_members, created_by, created_at, updated_at)
  VALUES ('Gym Buddies', '💪', false, 2, p_inviter_id, v_now, v_now)
  RETURNING id INTO v_team_id;

  INSERT INTO team_members (team_id, user_id, role, joined_at, created_at)
  VALUES
    (v_team_id, p_inviter_id, 'member', v_now, v_now),
    (v_team_id, p_invitee_id, 'member', v_now, v_now);

  INSERT INTO team_streaks (team_id, current_streak, longest_streak, is_active, created_at, updated_at)
  VALUES (v_team_id, 0, 0, true, v_now, v_now);

  -- Mirror the normal buddy flow: an invited buddy is also a friend, so they
  -- appear in the Gym Buddies list. Skip if a friendship already exists in
  -- either direction (unique key is directional on (user_id, friend_id)).
  INSERT INTO friendships (user_id, friend_id, status)
  SELECT p_inviter_id, p_invitee_id, 'accepted'
  WHERE NOT EXISTS (
    SELECT 1 FROM friendships
    WHERE (user_id = p_inviter_id AND friend_id = p_invitee_id)
       OR (user_id = p_invitee_id AND friend_id = p_inviter_id)
  );

  RETURN v_team_id;
END;
$function$;
