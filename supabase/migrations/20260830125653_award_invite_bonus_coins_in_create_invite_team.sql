-- Buddy-invite coin reward: +20 coins to BOTH the inviter and the new
-- joiner, awarded once when an invite is accepted and a buddy team is
-- created.
--
-- Lives inside create_invite_team (SECURITY DEFINER, called by the invitee
-- right after accept_invite during onboarding -- see
-- onboarding_basic_info_new.dart's _createBuddyTeam) rather than a
-- client-side call, per the server-authoritative economy rule from the S2/S3
-- security remediation: no client-trusted coin writes, everything routes
-- through award_coins().
--
-- Idempotency: create_invite_team has no guard of its own against being
-- called twice for the same accepted invite (nothing here flips
-- invites.status away from 'accepted', and the buddy_teams/team_members/
-- team_streaks inserts are unconditional -- a second call would happily
-- create a second team). Rather than take that on, the coin award gets its
-- own guard: reference_id is the invite's own id (fetched once into
-- v_invite_id), and a NOT EXISTS check on coin_transactions before awarding
-- means a duplicate call still cannot double-award, even though it can still
-- double the team. Matches the reference_id idempotency pattern award_coins
-- callers use elsewhere (_apply_checkin_rewards, partner_bonus).
--
-- No new REVOKE/GRANT: this is not a new function, and CREATE OR REPLACE
-- preserves the existing ACL (authenticated only, set by group_b's
-- bind-invite-functions migration).
--
-- Verified live via a BEGIN/ROLLBACK synthetic test against two real
-- accounts: both balances went +20 exactly once despite calling
-- create_invite_team twice for the same invite, then the transaction was
-- rolled back and re-checked clean (0 residual invite_bonus transactions,
-- 0 residual team_members rows for the two test accounts).

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
