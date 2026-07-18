-- GROUP D (audit LIVE-7): search_path hardening.
--
-- Pin search_path on the remaining SECURITY DEFINER functions that still
-- lacked it (create_invite_team got it in 20260717193000; accept_invite was
-- created with it). Without a fixed search_path, a SECURITY DEFINER function
-- resolves unqualified names using the caller's search_path -- a
-- privilege-escalation vector.
ALTER FUNCTION public.create_invite(uuid)   SET search_path = public;
ALTER FUNCTION public.delete_own_account()  SET search_path = public;

-- NOTE: the proposed "ALTER DEFAULT PRIVILEGES ... REVOKE EXECUTE ON FUNCTIONS
-- FROM PUBLIC, anon" was dropped. Verified on live (PG17.6): even with the
-- REVOKE targeting the correct role (current_user = session_user = defaclrole
-- = postgres, confirmed by OID match), a newly-created function still came back
-- PUBLIC- and anon-executable -- the hardwired PUBLIC EXECUTE default on
-- functions is not suppressed here. So function EXECUTE must be locked down
-- per-function, not via default privileges. See CLAUDE.md.
