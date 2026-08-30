-- create_invite_team had no dedupe: calling it twice for the same accepted
-- invite (client retry after a lost response, etc.) created a second
-- buddy_teams row, a second team_streaks row, and re-ran the friendship
-- INSERT (a no-op there thanks to its own NOT EXISTS guard, but everything
-- else duplicated). The invite_bonus coin award already had its own
-- reference_id guard and was never affected.
--
-- invites has no team_id column to link back to (checked live -- id, code,
-- inviter_id, invitee_email, status, created_at, accepted_at, accepted_by
-- only), so "already handled" is detected the only way the schema supports:
-- a team that already has both p_inviter_id and p_invitee_id as members.
-- This also covers the pair already being buddies via the normal
-- FriendService flow (which independently creates a team) before this
-- invite was accepted -- either way, one team per pair is correct.
--
-- Guard clause only, added right after the existing no_accepted_invite
-- check; the rest of the function (including the coin-bonus block) is
-- untouched.
--
-- Verified live via a BEGIN/ROLLBACK synthetic test against two real
-- accounts: calling create_invite_team twice for the same accepted invite
-- now returns the SAME team id both times, and afterward there is exactly
-- one team_members pairing, one team_streaks row, one friendship row, and
-- (unchanged from before) exactly one invite_bonus coin_transactions row
-- per user. Rolled back and re-checked clean: zero residual rows.

CREATE OR REPLACE FUNCTION public.create_invite_team(p_inviter_id uuid, p_invitee_id uuid)
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_team_id UUID;
  v_invite_id UUID;
  v_now TIMESTAMPTZ := NOW();
BEGIN
  IF auth.uid() IS NULL OR auth.uid() <> p_invitee_id THEN
    RAISE EXCEPTION 'not_authorized';
  END IF;

  SELECT id INTO v_invite_id
  FROM invites
  WHERE inviter_id = p_inviter_id
    AND accepted_by = p_invitee_id
    AND status = 'accepted'
  ORDER BY accepted_at DESC NULLS LAST
  LIMIT 1;

  IF v_invite_id IS NULL THEN
    RAISE EXCEPTION 'no_accepted_invite';
  END IF;

  -- Idempotency: invites has no team_id column to link back to, so "already
  -- handled" is detected the only way the schema supports -- a team that
  -- already has both of them as members. Covers a replayed call for this
  -- same invite, and also the pair already being buddies via the normal
  -- FriendService flow (which also creates a team) before this invite was
  -- accepted. Either way, one team per pair is correct: return it instead of
  -- creating a second team_streak, a duplicate friendship, or a duplicate
  -- coin award.
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

  -- Buddy-invite coin bonus: +20 to each side, once per invite. Reference is
  -- the invite's own id (not the team id) so a duplicate call for the same
  -- invite -- this function has no guard of its own against being called
  -- twice for one accepted invite, and would happily insert a second team --
  -- still cannot double-award. Matches the reference_id idempotency pattern
  -- award_coins callers use elsewhere (_apply_checkin_rewards, partner_bonus).
  IF NOT EXISTS (
    SELECT 1 FROM coin_transactions
    WHERE transaction_type = 'invite_bonus'
      AND reference_id = v_invite_id::text
  ) THEN
    PERFORM award_coins(p_inviter_id, 20, 'invite_bonus', 'Buddy invite accepted', v_invite_id::text);
    PERFORM award_coins(p_invitee_id, 20, 'invite_bonus', 'Joined via buddy invite', v_invite_id::text);
  END IF;

  RETURN v_team_id;
END;
$function$;
