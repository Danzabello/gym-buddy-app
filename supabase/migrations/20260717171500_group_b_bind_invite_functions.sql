-- GROUP B (audit LIVE-2, LIVE-8): bind the invite RPCs to the caller and
-- strip anon/PUBLIC EXECUTE.
--
-- Both functions are SECURITY DEFINER and were callable by anyone: their
-- ACL held a PUBLIC EXECUTE grant (=X) in addition to explicit anon/
-- authenticated grants, and neither checked auth.uid() against its params.
-- So anon (or any authenticated user) could forge invite codes and buddy
-- teams for arbitrary UUIDs.
--
-- Guard conditions are derived from the REAL call paths, not the function
-- names:
--   * create_invite is called by the inviter (InviteService.createInvite
--     passes p_inviter_id = auth.uid()).
--   * create_invite_team is called by the INVITEE during onboarding
--     (_createBuddyTeam passes p_invitee_id = auth.uid(), p_inviter_id =
--     the other party). The audit's suggested auth.uid() = p_inviter_id
--     would break the real flow, so the caller is bound to p_invitee_id and
--     the pairing must correspond to a real accepted invite from that
--     inviter to that invitee (invites.status = 'accepted', set by
--     InviteService.acceptInvite before this RPC runs).

-- ── create_invite: caller must be the inviter ──────────────────────────────
CREATE OR REPLACE FUNCTION public.create_invite(p_inviter_id uuid)
 RETURNS text
 LANGUAGE plpgsql
 SECURITY DEFINER
AS $function$
DECLARE
  v_code TEXT;
  v_attempts INT := 0;
BEGIN
  IF auth.uid() IS NULL OR auth.uid() <> p_inviter_id THEN
    RAISE EXCEPTION 'not_authorized';
  END IF;

  -- Generate a unique 8-char code, retry on collision
  LOOP
    v_code := upper(substr(md5(random()::text || clock_timestamp()::text), 1, 8));

    BEGIN
      INSERT INTO invites (inviter_id, code)
      VALUES (p_inviter_id, v_code);
      RETURN v_code;
    EXCEPTION WHEN unique_violation THEN
      v_attempts := v_attempts + 1;
      IF v_attempts >= 5 THEN
        RAISE EXCEPTION 'Could not generate unique invite code';
      END IF;
    END;
  END LOOP;
END;
$function$;

-- ── create_invite_team: caller must be the invitee of a real accepted invite ─
CREATE OR REPLACE FUNCTION public.create_invite_team(p_inviter_id uuid, p_invitee_id uuid)
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
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

  RETURN v_team_id;
END;
$function$;

-- ── Lock EXECUTE to authenticated (+ service_role) only ────────────────────
-- PUBLIC holds EXECUTE by default; revoking anon alone would be a no-op
-- (same grant-layer trap as Group A's table-level ACL). Revoke PUBLIC and
-- anon, then re-grant authenticated explicitly to be certain.
REVOKE EXECUTE ON FUNCTION public.create_invite(uuid) FROM PUBLIC, anon;
REVOKE EXECUTE ON FUNCTION public.create_invite_team(uuid, uuid) FROM PUBLIC, anon;

GRANT EXECUTE ON FUNCTION public.create_invite(uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public.create_invite_team(uuid, uuid) TO authenticated;
