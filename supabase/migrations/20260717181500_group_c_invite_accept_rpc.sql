-- LIVE-12 (found while verifying Group B): the invites accept + code-lookup
-- RLS was unscoped. Any authenticated user could read every invite row and
-- accept ANY pending invite by id (setting accepted_by = themselves) without
-- knowing the code — an invite-hijack / unsolicited-pairing vector.
--
-- Fix: move acceptance into a SECURITY DEFINER RPC that keys off the secret
-- code (the only key the client legitimately holds), and remove the direct
-- client write + the permissive code-lookup read.

-- ── accept_invite: server-side, code-scoped acceptance ─────────────────────
-- search_path pinned at creation (Group D hardening, built in from the start).
CREATE OR REPLACE FUNCTION public.accept_invite(p_code text)
 RETURNS uuid                       -- returns inviter_id (what the client uses to form the team)
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path = public
AS $function$
DECLARE
  v_caller  uuid := auth.uid();
  v_inviter uuid;
  v_status  text;
  v_code    text := upper(p_code);   -- codes are stored uppercase (create_invite uppercases)
BEGIN
  IF v_caller IS NULL THEN
    RAISE EXCEPTION 'unauthenticated';
  END IF;

  -- Lock the row so two concurrent accepts can't both win.
  SELECT inviter_id, status INTO v_inviter, v_status
  FROM invites
  WHERE code = v_code
  FOR UPDATE;

  IF v_inviter IS NULL THEN
    RAISE EXCEPTION 'invite_not_found';
  END IF;

  IF v_inviter = v_caller THEN
    RAISE EXCEPTION 'cannot_accept_own_invite';
  END IF;

  IF v_status = 'accepted' THEN
    RAISE EXCEPTION 'invite_already_accepted';
  ELSIF v_status = 'expired' THEN
    RAISE EXCEPTION 'invite_expired';
  ELSIF v_status <> 'pending' THEN
    RAISE EXCEPTION 'invite_not_acceptable';
  END IF;

  UPDATE invites
  SET status = 'accepted', accepted_by = v_caller, accepted_at = now()
  WHERE code = v_code AND status = 'pending';

  RETURN v_inviter;
END;
$function$;

-- New functions get PUBLIC EXECUTE by default; strip PUBLIC + anon, grant
-- authenticated only (same trap guarded against in Group B).
REVOKE EXECUTE ON FUNCTION public.accept_invite(text) FROM PUBLIC, anon;
GRANT  EXECUTE ON FUNCTION public.accept_invite(text) TO authenticated;

-- ── Tighten invites to an RPC-only write model + owner-scoped reads ─────────
-- Drop the permissive code-lookup SELECT policy (reads now happen inside the
-- SECURITY DEFINER RPC, which bypasses RLS). The scoped "Users can view own
-- invites" policy (inviter_id = auth.uid() OR accepted_by = auth.uid())
-- remains and is now the only SELECT path for clients.
DROP POLICY IF EXISTS "Authenticated users can look up invite by code" ON public.invites;

-- Drop the now-dead accept UPDATE policy and revoke the underlying UPDATE
-- privilege so no client can write invites directly. accept_invite (definer)
-- is the only write path. (Revoking the privilege is what actually closes it;
-- dropping the policy prevents a future re-GRANT from silently reopening it.)
DROP POLICY IF EXISTS "Authenticated users can accept invites" ON public.invites;
REVOKE UPDATE ON public.invites FROM authenticated, anon;
