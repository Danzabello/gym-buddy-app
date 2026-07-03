-- STEP 1 of the per-user timezone rework (Option B: each user's check-in is
-- dated in THEIR OWN local zone; a streak day completes when both members have
-- a row for that date label, each computed in their own tz).
--
-- This migration only adds the storage + resolver. No existing "today" logic
-- changes yet (that lands in later, per-RPC migrations).
--
-- NOTE: there is deliberately NO per-team timezone. Under Option B dating is
-- per-user, so buddy_teams needs nothing here.

-- 1. Per-user IANA timezone (e.g. 'Europe/Dublin', 'America/New_York').
--    NOT NULL DEFAULT the agreed fallback: existing rows become valid
--    immediately, and the client overwrites this with the real device tz on
--    the next launch. A constant default is a metadata-only add (no rewrite).
ALTER TABLE public.user_profiles
  ADD COLUMN IF NOT EXISTS timezone text NOT NULL DEFAULT 'Europe/Dublin';

-- 2. Write-time validation: coerce NULL or unknown IANA names to the fallback.
--    pg_timezone_names is the live IANA set, so this tracks tzdata updates.
--    The trigger fires only when `timezone` is actually written, so ordinary
--    profile updates (coins, level, etc.) don't pay for it.
CREATE OR REPLACE FUNCTION public.validate_user_timezone()
RETURNS trigger
LANGUAGE plpgsql
AS $$
BEGIN
  IF NEW.timezone IS NULL
     OR NOT EXISTS (SELECT 1 FROM pg_timezone_names WHERE name = NEW.timezone) THEN
    NEW.timezone := 'Europe/Dublin';
  END IF;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_validate_user_timezone ON public.user_profiles;
CREATE TRIGGER trg_validate_user_timezone
  BEFORE INSERT OR UPDATE OF timezone ON public.user_profiles
  FOR EACH ROW EXECUTE FUNCTION public.validate_user_timezone();

-- 3. The single resolver every server-side path will use to answer "what is
--    THIS user's local today": (now() AT TIME ZONE safe_user_tz(uid))::date.
--    Trusts the trigger-validated column (no per-call pg_timezone_names scan)
--    and only falls back for a missing row / NULL, so callers never null-check.
CREATE OR REPLACE FUNCTION public.safe_user_tz(p_user_id uuid)
RETURNS text
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT COALESCE(
    (SELECT up.timezone FROM user_profiles up WHERE up.id = p_user_id),
    'Europe/Dublin'
  );
$$;

-- Resolver is an internal primitive: the SECURITY DEFINER streak/economy/cron
-- functions call it as the table owner regardless of grants; only service_role
-- needs direct access.
REVOKE ALL ON FUNCTION public.safe_user_tz(uuid) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.safe_user_tz(uuid) TO service_role;
