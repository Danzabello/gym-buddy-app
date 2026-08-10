-- Hardening for accept_invite (follow-up to the invite-redirect work).
--
-- Four changes, all on the authenticated redemption path:
--
-- 1. 7-day TTL, matching invite-redirect. The redirect started rejecting aged
--    invites in the browser, but the Android App Link bypasses that function
--    entirely, so a stored code could still redeem a months-old invite here.
--    Checked at read time from created_at; no row is ever written to
--    status='expired'.
--
-- 2. Oracle collapse. invite_not_found / invite_already_accepted /
--    invite_expired / invite_not_acceptable each told an authenticated caller
--    which case they had hit, so anyone could confirm whether a code existed.
--    All four collapse into a single NULL return -- deliberately not an
--    exception, because RAISE would roll back the metering row written by
--    change 3 below (see the note in the function body). unauthenticated and
--    cannot_accept_own_invite stay distinct: neither tells the caller anything
--    about codes they do not already own.
--
--    invite_not_acceptable was unreachable anyway -- the status CHECK allows
--    only pending|accepted|expired, and all three were handled above it.
--
-- 3. Rate limiting, 20 attempts per 10 minutes per auth.uid(). Same
--    self-pruning shape as invite_lookup_attempts, keyed by user rather than
--    IP because this path always has a JWT. Fails open, matching the Edge
--    Function: a broken limiter must not block every invite redemption.
--
-- 4. REVOKE DELETE ON invites. anon and authenticated held a table-level
--    DELETE grant; only the absence of an RLS DELETE policy stopped it, so it
--    failed soft at 0 rows rather than being denied. Nothing reads or writes
--    invites from the client except a SELECT in InviteService.getSentInvites,
--    and no DB function deletes from it.

-- ── 3. Rate-limit ledger ────────────────────────────────────────────────────
-- No grants to anon/authenticated: accept_invite is SECURITY DEFINER owned by
-- postgres, so its body touches this table as the owner and needs no grant of
-- its own. That differs from invite_lookup_attempts, which is reached by the
-- Edge Function's service_role client -- both bypass RLS, but for different
-- reasons (ownership here, BYPASSRLS there).
--
-- No FK on user_id: rows live ~10 minutes, and a FK to user_profiles would
-- make metering fail for a caller whose profile row does not exist yet.
create table public.invite_accept_attempts (
  id           bigserial   primary key,
  user_id      uuid        not null,
  attempted_at timestamptz not null default now()
);

create index invite_accept_attempts_user_time_idx
  on public.invite_accept_attempts (user_id, attempted_at desc);

alter table public.invite_accept_attempts enable row level security;
revoke all on table public.invite_accept_attempts from anon, authenticated;

-- ── 1 + 2. accept_invite: TTL + single generic failure ──────────────────────
CREATE OR REPLACE FUNCTION public.accept_invite(p_code text)
 RETURNS uuid                       -- returns inviter_id (what the client uses to form the team)
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path = public
AS $function$
DECLARE
  v_caller   uuid        := auth.uid();
  v_inviter  uuid;
  v_status   text;
  v_created  timestamptz;
  v_attempts int         := 0;
  v_code     text        := upper(p_code);   -- codes are stored uppercase (create_invite uppercases)
BEGIN
  IF v_caller IS NULL THEN
    RAISE EXCEPTION 'unauthenticated';
  END IF;

  -- Meter per caller. Prune first so the table only ever holds one window's
  -- worth of rows, which is why this needs no cron sweep. Wrapped so that a
  -- limiter failure cannot take invite redemption down with it; the RAISE
  -- lives outside the block so it is not swallowed by its own handler.
  BEGIN
    DELETE FROM invite_accept_attempts
     WHERE attempted_at < now() - interval '10 minutes';

    SELECT count(*) INTO v_attempts
      FROM invite_accept_attempts
     WHERE user_id = v_caller
       AND attempted_at >= now() - interval '10 minutes';

    IF v_attempts < 20 THEN
      INSERT INTO invite_accept_attempts (user_id) VALUES (v_caller);
    END IF;
  EXCEPTION WHEN OTHERS THEN
    v_attempts := 0;   -- limiter unavailable: fail open
  END;

  IF v_attempts >= 20 THEN
    RAISE EXCEPTION 'too_many_attempts';
  END IF;

  -- Lock the row so two concurrent accepts can't both win.
  SELECT inviter_id, status, created_at
    INTO v_inviter, v_status, v_created
    FROM invites
   WHERE code = v_code
     FOR UPDATE;

  -- Everything that depends on the code itself leaves through this one door:
  -- no such code, already accepted, any non-pending status, or older than the
  -- 7-day TTL. Do not split these apart again -- the split is what let a
  -- caller confirm which codes exist.
  --
  -- It returns NULL rather than raising, and that is load-bearing: RAISE
  -- aborts the call's subtransaction, which would roll back the metering row
  -- inserted above. Since failed attempts are precisely what needs metering,
  -- raising here would leave brute-force traffic uncounted (measured: 24 calls
  -- produced 2 ledger rows). NULL commits, so the meter holds. The client is
  -- unaffected -- InviteService casts the result to String? and already maps
  -- both null and a thrown error to the same "skip pairing" path.
  IF v_inviter IS NULL
     OR v_status <> 'pending'
     OR v_created < now() - interval '7 days' THEN
    RETURN NULL;
  END IF;

  -- Checked after the validity test on purpose: a caller learns only about an
  -- invite that is both live and their own, which they already knew about.
  IF v_inviter = v_caller THEN
    RAISE EXCEPTION 'cannot_accept_own_invite';
  END IF;

  UPDATE invites
  SET status = 'accepted', accepted_by = v_caller, accepted_at = now()
  WHERE code = v_code AND status = 'pending';

  RETURN v_inviter;
END;
$function$;

-- CREATE OR REPLACE keeps the existing ACL, but re-assert it per the standing
-- rule that every client-facing SECURITY DEFINER function states its grants.
REVOKE EXECUTE ON FUNCTION public.accept_invite(text) FROM PUBLIC, anon;
GRANT  EXECUTE ON FUNCTION public.accept_invite(text) TO authenticated;

-- ── 4. Close the DELETE grant ───────────────────────────────────────────────
REVOKE DELETE ON public.invites FROM anon, authenticated;
