CREATE OR REPLACE FUNCTION public.create_invite_team(p_inviter_id uuid, p_invitee_id uuid)
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_team_id UUID;
  v_invite_id UUID;
  v_invite_created TIMESTAMPTZ;
  v_invitee_is_new BOOLEAN;
  v_now TIMESTAMPTZ := NOW();
BEGIN
  IF auth.uid() IS NULL OR auth.uid() <> p_invitee_id THEN
    RAISE EXCEPTION 'not_authorized';
  END IF;

  SELECT id, created_at INTO v_invite_id, v_invite_created
  FROM invites
  WHERE inviter_id = p_inviter_id
    AND accepted_by = p_invitee_id
    AND status = 'accepted'
  ORDER BY accepted_at DESC NULLS LAST
  LIMIT 1;

  IF v_invite_id IS NULL THEN
    RAISE EXCEPTION 'no_accepted_invite';
  END IF;

  SELECT tm1.team_id INTO v_team_id
  FROM team_members tm1
  JOIN team_members tm2 ON tm2.team_id = tm1.team_id AND tm2.user_id = p_invitee_id
  WHERE tm1.user_id = p_inviter_id
  LIMIT 1;

  IF v_team_id IS NOT NULL THEN
    RETURN v_team_id;
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

  INSERT INTO friendships (user_id, friend_id, status)
  SELECT p_inviter_id, p_invitee_id, 'accepted'
  WHERE NOT EXISTS (
    SELECT 1 FROM friendships
    WHERE (user_id = p_inviter_id AND friend_id = p_invitee_id)
       OR (user_id = p_invitee_id AND friend_id = p_inviter_id)
  );

  SELECT (u.created_at > v_invite_created) INTO v_invitee_is_new
  FROM auth.users u WHERE u.id = p_invitee_id;

  IF COALESCE(v_invitee_is_new, false) THEN
    IF NOT EXISTS (
      SELECT 1 FROM coin_transactions
      WHERE transaction_type = 'invite_bonus'
        AND reference_id = v_invite_id::text
        AND user_id = p_invitee_id
    ) THEN
      PERFORM award_coins(p_invitee_id, 20, 'invite_bonus', 'Joined via buddy invite', v_invite_id::text);
    END IF;
  END IF;

  RETURN v_team_id;
END;
$function$
