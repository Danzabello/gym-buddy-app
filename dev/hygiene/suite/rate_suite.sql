-- Rate-limit suite (prompt 13, SEARCH-RATE): the search_usernames meter and the friendships insert meter.
-- Run with docs/hygiene/suite/run.sh. One transaction: the migration under test is inlined at @@MIGRATION@@
-- (run.sh --with), then every group runs in its own sub-block that is rolled back. Fixture profiles are created
-- inside the transaction (fresh ids, never a real account). The block ends in RAISE: nothing persists.
-- _send_push is stubbed (no HTTP). Meter-table grants are in grants_fresh.sql.
BEGIN;
-- @@MIGRATION@@

CREATE TEMP TABLE push_log (ts timestamptz DEFAULT clock_timestamp(), recipient uuid, key text, ref text, sender uuid);
GRANT ALL ON push_log TO PUBLIC;
CREATE OR REPLACE FUNCTION public._send_push(p_user uuid, p_key text, p_vars jsonb, p_kind text, p_channel text, p_type text,
                                             p_ref text, p_tag text, p_urgent boolean DEFAULT false, p_sender uuid DEFAULT NULL::uuid)
 RETURNS boolean LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public' AS $f$
BEGIN
  INSERT INTO pg_temp.push_log (recipient, key, ref, sender) VALUES (p_user, p_key, p_ref, p_sender);
  RETURN true;
END $f$;

-- Fixture profiles f(0)..f(29).
CREATE TEMP TABLE fx (n int PRIMARY KEY, id uuid NOT NULL DEFAULT gen_random_uuid());
INSERT INTO fx (n) SELECT generate_series(0, 29);
INSERT INTO user_profiles (id, age, username, display_name)
SELECT id, 30, 'zzrate_' || n || '_' || left(replace(id::text, '-', ''), 8), 'rate probe ' || n FROM fx;
GRANT SELECT ON fx TO PUBLIC;
CREATE FUNCTION pg_temp.f(p_n int) RETURNS uuid LANGUAGE sql AS $$ SELECT id FROM pg_temp.fx WHERE n = p_n $$;

-- Run SQL as a user (JWT claims + role), return its text result or 'ERR:<sqlstate> <message>'.
CREATE FUNCTION pg_temp.u(p_uid uuid, p_sql text, p_role text DEFAULT 'authenticated')
RETURNS text LANGUAGE plpgsql AS $f$
DECLARE r text;
BEGIN
  PERFORM set_config('request.jwt.claims',
    CASE WHEN p_uid IS NULL THEN json_build_object('role', p_role)::text
         ELSE json_build_object('sub', p_uid, 'role', p_role)::text END, true);
  BEGIN
    EXECUTE format('SET LOCAL ROLE %I', p_role);
    EXECUTE p_sql INTO r;
    RESET ROLE;
  EXCEPTION WHEN OTHERS THEN
    r := 'ERR:' || SQLSTATE || ' ' || SQLERRM;
  END;
  RESET ROLE;
  PERFORM set_config('request.jwt.claims', '', true);
  RETURN r;
END $f$;
CREATE FUNCTION pg_temp.ok(p_t text, p_ok boolean, p_info text DEFAULT '') RETURNS text LANGUAGE sql AS $$
  SELECT CASE WHEN coalesce(p_ok, false) THEN 'PASS ' ELSE 'FAIL ' END || p_t
         || CASE WHEN coalesce(p_info, '') <> '' THEN ' -> ' || p_info ELSE '' END $$;
CREATE FUNCTION pg_temp.is(p_t text, p_got text, p_want text) RETURNS text LANGUAGE sql AS $$
  SELECT pg_temp.ok(p_t, p_got IS NOT DISTINCT FROM p_want,
                    'got ' || coalesce(p_got, 'NULL') || CASE WHEN p_got IS DISTINCT FROM p_want THEN ', want ' || coalesce(p_want, 'NULL') ELSE '' END) $$;

-- search_usernames as p_u: the number of rows returned, or ERR.
CREATE FUNCTION pg_temp.srch(p_u uuid, p_q text DEFAULT 'zzrate') RETURNS text LANGUAGE sql AS $$
  SELECT pg_temp.u(p_u, format('SELECT count(*)::text FROM public.search_usernames(%L)', p_q)) $$;
CREATE FUNCTION pg_temp.nsrch(p_u uuid) RETURNS int LANGUAGE sql AS $$
  SELECT count(*)::int FROM username_search_attempts WHERE user_id = p_u $$;
-- Direct client friend request a -> b (the app's insert): 'pending', or ERR.
CREATE FUNCTION pg_temp.req(a uuid, b uuid) RETURNS text LANGUAGE sql AS $$
  SELECT pg_temp.u(a, format('INSERT INTO public.friendships (user_id, friend_id, status) VALUES (%L, %L, ''pending'') RETURNING status', a, b)) $$;
CREATE FUNCTION pg_temp.unreq(a uuid, b uuid) RETURNS text LANGUAGE sql AS $$
  SELECT pg_temp.u(a, format('WITH d AS (DELETE FROM public.friendships WHERE user_id = %L AND friend_id = %L RETURNING 1) SELECT count(*)::text FROM d', a, b)) $$;
CREATE FUNCTION pg_temp.nreq(p_u uuid) RETURNS int LANGUAGE sql AS $$
  SELECT count(*)::int FROM friend_request_attempts WHERE user_id = p_u $$;

DO $suite$
DECLARE
  r text[] := ARRAY[]::text[];
  a uuid; b uuid; n text; m text; k int; code text;
BEGIN
  -- ── S search_usernames: 60 / 10 min per caller ──
  BEGIN
    a := pg_temp.f(0); b := pg_temp.f(1);
    k := 0;
    FOR i IN 1..60 LOOP
      n := pg_temp.srch(a);
      IF n ~ '^[0-9]+$' AND n::int > 0 THEN k := k + 1; END IF;
    END LOOP;
    r := r || pg_temp.is('S1 60 calls in the window all return results', k::text, '60');
    r := r || pg_temp.is('S2 the 61st returns empty, not an error', pg_temp.srch(a), '0');
    r := r || pg_temp.is('S3 the meter rows are committed (60 kept after the over-cap call, none for it)', pg_temp.nsrch(a)::text, '60');
    n := pg_temp.srch(b);
    r := r || pg_temp.ok('S4 another user is unaffected (results, one meter row)', n ~ '^[1-9]' AND pg_temp.nsrch(b) = 1, n || ' / ' || pg_temp.nsrch(b));
    n := pg_temp.srch(b, 'zz') || '/' || pg_temp.srch(b, '') || '/' || coalesce(pg_temp.srch(b, NULL), 'null');
    r := r || pg_temp.is('S5 short queries return nothing and are not metered', n || ' meter ' || pg_temp.nsrch(b), '0/0/0 meter 1');
    INSERT INTO username_search_attempts (user_id, attempted_at) VALUES (pg_temp.f(2), now() - interval '11 minutes');
    PERFORM pg_temp.srch(b);
    r := r || pg_temp.is('S6 a write prunes rows older than the window', pg_temp.nsrch(pg_temp.f(2))::text, '0');
    BEGIN
      DROP TABLE username_search_attempts;
      n := pg_temp.srch(pg_temp.f(3));
      RAISE EXCEPTION 'undo' USING ERRCODE = 'P0097';
    EXCEPTION WHEN SQLSTATE 'P0097' THEN NULL;
    END;
    r := r || pg_temp.ok('S7 limiter unavailable (table gone): search fails open', n ~ '^[1-9]', n);
    RAISE EXCEPTION 'undo' USING ERRCODE = 'P0098';
  EXCEPTION WHEN SQLSTATE 'P0098' THEN NULL;
            WHEN OTHERS THEN r := r || ('FAIL S crashed: ' || SQLERRM);
  END;

  -- ── R1 20 / hour overall; invite pairing still works at the cap and is not counted ──
  BEGIN
    a := pg_temp.f(4);
    k := 0;
    FOR i IN 5..24 LOOP
      IF pg_temp.req(a, pg_temp.f(i)) = 'pending' THEN k := k + 1; END IF;
    END LOOP;
    r := r || pg_temp.is('R1.1 20 requests to 20 different targets succeed', k::text, '20');
    m := pg_temp.req(a, pg_temp.f(25));
    r := r || pg_temp.is('R1.2 the 21st fails with too_many_requests', m, 'ERR:P0001 too_many_requests');
    r := r || pg_temp.is('R1.3 the 21st left no friendship row, the meter holds 20',
                         (SELECT count(*) FROM friendships WHERE user_id = a AND friend_id = pg_temp.f(25)) || ' / ' || pg_temp.nreq(a), '0 / 20');
    r := r || pg_temp.is('R1.4 each landed request still pushed once', (SELECT count(*) FROM pg_temp.push_log WHERE key = 'friend_request' AND sender = a)::text, '20');
    -- a (at the cap) redeems an invite from f(29) the way the app does: accept_invite, then create_invite_team.
    b := pg_temp.f(29);
    code := upper('ZR' || left(md5(random()::text), 6));
    INSERT INTO invites (code, inviter_id, status) VALUES (code, b, 'pending');
    n := pg_temp.u(a, format('SELECT public.accept_invite(%L)::text', code));
    r := r || pg_temp.is('R1.5 accept_invite at the request cap', n, b::text);
    n := pg_temp.u(a, format('SELECT public.create_invite_team(%L, %L)::text', b, a));
    r := r || pg_temp.ok('R1.6 create_invite_team at the request cap: team made, accepted friendship inserted',
                         n !~ '^ERR' AND EXISTS (SELECT 1 FROM friendships WHERE user_id = b AND friend_id = a AND status = 'accepted'), n);
    r := r || pg_temp.is('R1.7 pairing is not metered (invitee still 20, inviter 0)', pg_temp.nreq(a) || ' / ' || pg_temp.nreq(b), '20 / 0');
    RAISE EXCEPTION 'undo' USING ERRCODE = 'P0098';
  EXCEPTION WHEN SQLSTATE 'P0098' THEN NULL;
            WHEN OTHERS THEN r := r || ('FAIL R1 crashed: ' || SQLERRM);
  END;

  -- ── R2 2 / 24 h to the same target, across delete and re-insert ──
  BEGIN
    a := pg_temp.f(1); b := pg_temp.f(2);
    n := pg_temp.req(a, b) || ' ' || pg_temp.unreq(a, b) || ' ' || pg_temp.req(a, b) || ' ' || pg_temp.unreq(a, b);
    r := r || pg_temp.is('R2.1 request, delete, request again, delete', n, 'pending 1 pending 1');
    m := pg_temp.req(a, b);
    r := r || pg_temp.is('R2.2 the third request to the same target fails with too_many_requests', m, 'ERR:P0001 too_many_requests');
    r := r || pg_temp.is('R2.3 another target is still fine', pg_temp.req(a, pg_temp.f(3)), 'pending');
    r := r || pg_temp.is('R2.4 the target can still request the sender', pg_temp.req(b, a), 'pending');
    RAISE EXCEPTION 'undo' USING ERRCODE = 'P0098';
  EXCEPTION WHEN SQLSTATE 'P0098' THEN NULL;
            WHEN OTHERS THEN r := r || ('FAIL R2 crashed: ' || SQLERRM);
  END;

  -- ── R3 windows: the hourly cap slides, the per-target cap holds for 24 h, older rows are pruned ──
  BEGIN
    INSERT INTO friend_request_attempts (user_id, target_id, attempted_at)
    SELECT pg_temp.f(26), gen_random_uuid(), now() - interval '61 minutes' FROM generate_series(1, 20);
    r := r || pg_temp.is('R3.1 20 requests 61 minutes ago do not block a new one', pg_temp.req(pg_temp.f(26), pg_temp.f(5)), 'pending');
    INSERT INTO friend_request_attempts (user_id, target_id, attempted_at)
    VALUES (pg_temp.f(27), pg_temp.f(6), now() - interval '23 hours'), (pg_temp.f(27), pg_temp.f(6), now() - interval '23 hours');
    r := r || pg_temp.is('R3.2 two requests to a target 23 hours ago still block it', pg_temp.req(pg_temp.f(27), pg_temp.f(6)), 'ERR:P0001 too_many_requests');
    INSERT INTO friend_request_attempts (user_id, target_id, attempted_at)
    VALUES (pg_temp.f(28), pg_temp.f(6), now() - interval '25 hours'), (pg_temp.f(28), pg_temp.f(6), now() - interval '25 hours');
    n := pg_temp.req(pg_temp.f(28), pg_temp.f(6));
    r := r || pg_temp.is('R3.3 after 24 hours the target is open again and the old rows are pruned',
                         n || ' ' || (SELECT count(*) FROM friend_request_attempts WHERE attempted_at < now() - interval '24 hours'), 'pending 0');
    RAISE EXCEPTION 'undo' USING ERRCODE = 'P0098';
  EXCEPTION WHEN SQLSTATE 'P0098' THEN NULL;
            WHEN OTHERS THEN r := r || ('FAIL R3 crashed: ' || SQLERRM);
  END;

  -- ── R4 only the signed-in client is metered; the limiter fails open ──
  BEGIN
    n := pg_temp.u(NULL, format('INSERT INTO public.friendships (user_id, friend_id, status) VALUES (%L, %L, ''pending'') RETURNING status',
                                pg_temp.f(25), pg_temp.f(0)), 'service_role');
    r := r || pg_temp.is('R4.1 service_role insert lands and is not metered', n || ' ' || pg_temp.nreq(pg_temp.f(25)), 'pending 0');
    INSERT INTO friendships (user_id, friend_id, status) VALUES (pg_temp.f(25), pg_temp.f(1), 'pending');
    r := r || pg_temp.is('R4.2 postgres insert is not metered', pg_temp.nreq(pg_temp.f(25))::text, '0');
    BEGIN
      DROP TABLE friend_request_attempts;
      n := pg_temp.req(pg_temp.f(3), pg_temp.f(4));
      RAISE EXCEPTION 'undo' USING ERRCODE = 'P0097';
    EXCEPTION WHEN SQLSTATE 'P0097' THEN NULL;
    END;
    r := r || pg_temp.is('R4.3 limiter unavailable (table gone): the request fails open', n, 'pending');
    r := r || pg_temp.ok('R4.4 trigger is BEFORE INSERT, gated on current_user = authenticated',
                         (SELECT pg_get_triggerdef(oid) FROM pg_trigger WHERE tgname = 'meter_friend_request' AND tgrelid = 'public.friendships'::regclass)
                         LIKE '%BEFORE INSERT%WHEN ((CURRENT_USER = ''authenticated''::name))%');
    RAISE EXCEPTION 'undo' USING ERRCODE = 'P0098';
  EXCEPTION WHEN SQLSTATE 'P0098' THEN NULL;
            WHEN OTHERS THEN r := r || ('FAIL R4 crashed: ' || SQLERRM);
  END;

  RAISE EXCEPTION E'SUITE_RESULTS\n%', array_to_string(r, E'\n');
END
$suite$;
ROLLBACK;
