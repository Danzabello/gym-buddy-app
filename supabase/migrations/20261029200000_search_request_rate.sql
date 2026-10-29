-- 20261029200000_search_request_rate: SEARCH-RATE (prompt 13). Not a credit path.
-- A: search_usernames meters each caller, 60 calls / 10 min; over the cap it returns no rows.
-- B: a direct client insert into friendships meters the sender, 20 / hour overall and 2 / 24 h per target;
--    over either cap it raises too_many_requests. Server-side inserts (create_invite_team) are not metered.
-- Both copy accept_invite / invite_accept_attempts: prune first, count, insert a meter row, fail open.
-- Rollback: docs/rollback_20261029200000.sql.

-- ── A. search meter ───────────────────────────────────────────────────────────
CREATE TABLE public.username_search_attempts (
  id           bigserial   PRIMARY KEY,
  user_id      uuid        NOT NULL,
  attempted_at timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX username_search_attempts_user_time_idx
  ON public.username_search_attempts (user_id, attempted_at DESC);
ALTER TABLE public.username_search_attempts ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON TABLE public.username_search_attempts FROM anon, authenticated;
REVOKE ALL ON SEQUENCE public.username_search_attempts_id_seq FROM anon, authenticated;

CREATE OR REPLACE FUNCTION public.search_usernames(q text)
 RETURNS TABLE(id uuid, username text, display_name text, avatar_id text)
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_escaped text;
  v_caller   uuid := auth.uid();
  v_attempts int  := 0;
BEGIN
  IF q IS NULL OR length(q) < 3 THEN
    RETURN;
  END IF;

  -- Meter per caller, same shape as accept_invite: prune first (no cron
  -- sweep), wrapped so a limiter failure fails open. Short queries return
  -- above and cost nothing. Over the cap this RETURNs no rows rather than
  -- raising: a RAISE would roll back the meter rows this call is counted by.
  BEGIN
    DELETE FROM username_search_attempts
     WHERE attempted_at < now() - interval '10 minutes';

    SELECT count(*) INTO v_attempts
      FROM username_search_attempts
     WHERE user_id = v_caller
       AND attempted_at >= now() - interval '10 minutes';

    IF v_attempts < 60 THEN
      INSERT INTO username_search_attempts (user_id) VALUES (v_caller);
    END IF;
  EXCEPTION WHEN OTHERS THEN
    v_attempts := 0;   -- limiter unavailable: fail open
  END;

  IF v_attempts >= 60 THEN
    RETURN;
  END IF;

  -- Escape % and _ so they're treated as literal characters, not SQL LIKE
  -- wildcards (same convention as the client-side escape this replaces).
  v_escaped := replace(replace(replace(q, '\', '\\'), '%', '\%'), '_', '\_');

  RETURN QUERY
  SELECT up.id, up.username, up.display_name, up.avatar_id
  FROM public.user_profiles up
  WHERE up.username IS NOT NULL
    AND up.username ILIKE '%' || v_escaped || '%'
  LIMIT 10;
END;
$function$;
REVOKE EXECUTE ON FUNCTION public.search_usernames(text) FROM PUBLIC, anon;
GRANT  EXECUTE ON FUNCTION public.search_usernames(text) TO authenticated;

-- ── B. friend request meter ───────────────────────────────────────────────────
CREATE TABLE public.friend_request_attempts (
  id           bigserial   PRIMARY KEY,
  user_id      uuid        NOT NULL,
  target_id    uuid        NOT NULL,
  attempted_at timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX friend_request_attempts_user_time_idx
  ON public.friend_request_attempts (user_id, attempted_at DESC);
ALTER TABLE public.friend_request_attempts ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON TABLE public.friend_request_attempts FROM anon, authenticated;
REVOKE ALL ON SEQUENCE public.friend_request_attempts_id_seq FROM anon, authenticated;

-- Fired only by the trigger below, whose WHEN (current_user = 'authenticated') is evaluated as the inserting role,
-- before this definer body runs: a direct client insert passes it, an insert inside a SECURITY DEFINER function
-- (current_user = its owner) or by service_role does not. Trigger functions need no EXECUTE grant to fire.
CREATE FUNCTION public._meter_friend_request()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_caller uuid := auth.uid();   -- not NEW.user_id: RLS WITH CHECK runs after BEFORE triggers
  v_hour   int  := 0;
  v_target int  := 0;
BEGIN
  -- Prune, count, meter; wrapped so a limiter failure fails open, with the
  -- RAISE outside so its own handler cannot swallow it. Raising is fine here:
  -- only inserts that land need metering, and a failed insert rolls back its
  -- meter row along with the friendship row.
  BEGIN
    DELETE FROM friend_request_attempts
     WHERE attempted_at < now() - interval '24 hours';

    SELECT count(*) FILTER (WHERE attempted_at >= now() - interval '1 hour'),
           count(*) FILTER (WHERE target_id = NEW.friend_id)
      INTO v_hour, v_target
      FROM friend_request_attempts
     WHERE user_id = v_caller
       AND attempted_at >= now() - interval '24 hours';

    IF v_hour < 20 AND v_target < 2 THEN
      INSERT INTO friend_request_attempts (user_id, target_id) VALUES (v_caller, NEW.friend_id);
    END IF;
  EXCEPTION WHEN OTHERS THEN
    v_hour := 0; v_target := 0;   -- limiter unavailable: fail open
  END;

  IF v_hour >= 20 OR v_target >= 2 THEN
    RAISE EXCEPTION 'too_many_requests';   -- one message for both caps
  END IF;

  RETURN NEW;
END;
$function$;
REVOKE EXECUTE ON FUNCTION public._meter_friend_request() FROM PUBLIC, anon, authenticated;

CREATE TRIGGER meter_friend_request
  BEFORE INSERT ON public.friendships
  FOR EACH ROW WHEN (current_user = 'authenticated')
  EXECUTE FUNCTION public._meter_friend_request();
