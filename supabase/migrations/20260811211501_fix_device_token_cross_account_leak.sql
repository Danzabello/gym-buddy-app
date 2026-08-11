-- Fix the cross-account FCM device-token leak.
--
-- device_tokens was UNIQUE (user_id, token). A second account signing in on
-- the same handset presents the same FCM token, does not conflict, and gets
-- its own row -- so one physical device belonged to two accounts at once.
-- send-notification selects every token row for a user_id and sends to all of
-- them, so a push addressed to account A was delivered to a handset now held
-- by account B. Confirmed in production, not theoretical: token 56347980...
-- was live on both rokitest (from 2026-07-20) and newtestaccount2 (from
-- 2026-07-27), both rows being refreshed on the same day.
--
-- Nothing on the client could repair this. The "Users manage own tokens"
-- policy scopes every operation to auth.uid() = user_id, so the arriving
-- account is structurally unable to delete the previous owner's row. Hence
-- the SECURITY DEFINER RPC below -- same shape as declare_break_day and
-- accept_invite: definer owns the write, RLS keeps clients in their lane.

-- ── 1. Dedupe before the constraint can be tightened ────────────────────────
-- Keep the most recently refreshed row per token; that is the account that
-- most recently used the handset. Verified against live before applying:
-- exactly one row is removed (rokitest's, updated 17:17, losing to
-- newtestaccount2's 17:41 on the same token). Single-owner tokens are
-- untouched, including the profile-less 2026-03 row, which is out of scope.
DELETE FROM public.device_tokens dt
USING (
  SELECT id,
         row_number() OVER (PARTITION BY token
                            ORDER BY updated_at DESC, created_at DESC) AS rn
  FROM public.device_tokens
) ranked
WHERE dt.id = ranked.id
  AND ranked.rn > 1;

-- ── 2. One token belongs to exactly one account ─────────────────────────────
-- This is the structural fix. With UNIQUE (token), a cross-account insert can
-- no longer duplicate -- worst case it errors, which fails safe.
ALTER TABLE public.device_tokens
  DROP CONSTRAINT device_tokens_user_id_token_key;

ALTER TABLE public.device_tokens
  ADD CONSTRAINT device_tokens_token_key UNIQUE (token);

-- ── 3. Registration goes through a definer RPC ──────────────────────────────
CREATE OR REPLACE FUNCTION public.register_device_token(
  p_token    text,
  p_platform text DEFAULT 'android'
)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path = public
AS $function$
DECLARE
  v_uid uuid := auth.uid();
BEGIN
  IF v_uid IS NULL THEN
    RAISE EXCEPTION 'unauthenticated';
  END IF;

  -- Trust boundary: p_token is client-supplied. FCM registration tokens run
  -- ~150-200 chars; the bound only stops absurd payloads being stored.
  IF p_token IS NULL OR btrim(p_token) = '' OR length(p_token) > 4096 THEN
    RAISE EXCEPTION 'invalid_token';
  END IF;

  -- One registration at a time per token: app start and onTokenRefresh can
  -- fire together. Same guard declare_break_day uses.
  PERFORM pg_advisory_xact_lock(hashtext('device_token:' || p_token));

  -- Release the handset from any other account. This is the whole reason the
  -- function is SECURITY DEFINER -- a client cannot reach another user's row.
  DELETE FROM device_tokens
   WHERE token = p_token
     AND user_id <> v_uid;

  INSERT INTO device_tokens (user_id, token, platform, updated_at)
  VALUES (v_uid, p_token, coalesce(p_platform, 'android'), now())
  ON CONFLICT (token) DO UPDATE
    SET user_id    = excluded.user_id,
        platform   = excluded.platform,
        updated_at = now();
END;
$function$;

-- New functions in public are PUBLIC-executable by default on this instance;
-- state the grants explicitly (CLAUDE.md).
REVOKE EXECUTE ON FUNCTION public.register_device_token(text, text) FROM PUBLIC, anon;
GRANT  EXECUTE ON FUNCTION public.register_device_token(text, text) TO authenticated;

-- ── 4. RLS policy deliberately unchanged ────────────────────────────────────
-- "Users manage own tokens" (ALL, auth.uid() = user_id) still correctly scopes
-- a client's SELECT/UPDATE/DELETE to its own rows, and removeToken()'s
-- delete-by-(user_id, token) keeps working against it. The RPC bypasses it as
-- definer, by design.
