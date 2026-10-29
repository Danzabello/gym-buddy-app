-- Reward and streak suite (prompt 07). Run with docs/hygiene/suite/run.sh, never by hand against live without reading it.
-- One transaction: helpers; phase 1 runs the CURRENT live bodies on the equivalence fixtures (each captured, then
-- rolled back); the migration under test is inlined at @@MIGRATION@@ (run.sh --with), or nothing; phase 2 runs the
-- equivalence fixtures again plus every group, each group in its own sub-block that is rolled back. The block ends
-- in RAISE, so the whole transaction aborts: nothing persists. _send_push is stubbed (no HTTP).
-- Grants and denied writes are in grants_fresh.sql (own connection, authenticated call first).
BEGIN;

-- ═════════ fixture accounts: test accounts only, matched by id. Swap ids here. ═════════
-- Never: onboard_check5 19c3b618-ae18-4b2e-be52-cbe1de8cacbe (owner's phone), mijotest 6dfac56a (real check-ins).
CREATE TEMP TABLE acct (k text PRIMARY KEY, id uuid NOT NULL, note text);
INSERT INTO acct VALUES
  ('ua', '5e67f64d-16e3-4b09-9b00-ddc49df8c3f6', 'rokitest1'),
  ('uc', 'cf4946f5-f921-4e81-bbf4-88d574e8baf5', 'testtest1'),
  ('o1', '81f83cdb-e09b-4f1f-8045-afa0d3d2181e', 'onboard_check1'),
  ('o2', 'bc85514c-02f2-4340-90f2-d95e3f62af26', 'onboard_check2'),
  ('o3', 'f0f43430-80aa-4c38-8f87-c11226bef86f', 'onboard_check3'),
  ('o4', 'ae240bb6-e629-401e-9fb6-feb1ed21cee9', 'onboard_check4'),
  ('o6', '30d543f1-bb06-41c4-8522-396ed948ba35', 'onboard_check6');
GRANT SELECT ON acct TO PUBLIC;

CREATE TEMP TABLE push_log (ts timestamptz DEFAULT clock_timestamp(), recipient uuid, key text, ref text, sender uuid);
GRANT ALL ON push_log TO PUBLIC;
CREATE TEMP TABLE eq_old (k text PRIMARY KEY, v jsonb);

CREATE OR REPLACE FUNCTION public._send_push(p_user uuid, p_key text, p_vars jsonb, p_kind text, p_channel text, p_type text,
                                             p_ref text, p_tag text, p_urgent boolean DEFAULT false, p_sender uuid DEFAULT NULL::uuid)
 RETURNS boolean LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public' AS $f$
BEGIN
  INSERT INTO pg_temp.push_log (recipient, key, ref, sender) VALUES (p_user, p_key, p_ref, p_sender);
  RETURN true;
END $f$;

CREATE FUNCTION pg_temp.id(p_k text) RETURNS uuid LANGUAGE sql AS $$ SELECT id FROM pg_temp.acct WHERE k = p_k $$;
CREATE FUNCTION pg_temp.ua() RETURNS uuid LANGUAGE sql AS $$ SELECT pg_temp.id('ua') $$;
CREATE FUNCTION pg_temp.uc() RETURNS uuid LANGUAGE sql AS $$ SELECT pg_temp.id('uc') $$;
CREATE FUNCTION pg_temp.o1() RETURNS uuid LANGUAGE sql AS $$ SELECT pg_temp.id('o1') $$;
CREATE FUNCTION pg_temp.o2() RETURNS uuid LANGUAGE sql AS $$ SELECT pg_temp.id('o2') $$;
CREATE FUNCTION pg_temp.o3() RETURNS uuid LANGUAGE sql AS $$ SELECT pg_temp.id('o3') $$;
CREATE FUNCTION pg_temp.o4() RETURNS uuid LANGUAGE sql AS $$ SELECT pg_temp.id('o4') $$;
CREATE FUNCTION pg_temp.o6() RETURNS uuid LANGUAGE sql AS $$ SELECT pg_temp.id('o6') $$;
CREATE FUNCTION pg_temp.cmx() RETURNS uuid LANGUAGE sql AS $$ SELECT '00000000-0000-0000-0000-000000000001'::uuid $$;
CREATE FUNCTION pg_temp.all_u() RETURNS uuid[] LANGUAGE sql AS $$ SELECT array_agg(id) FROM pg_temp.acct $$;

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

CREATE FUNCTION pg_temp.js(r text) RETURNS jsonb LANGUAGE sql AS $$
  SELECT CASE WHEN r IS NULL THEN 'null'::jsonb WHEN r LIKE 'ERR:%' THEN to_jsonb(r) ELSE r::jsonb END $$;
CREATE FUNCTION pg_temp.fin(p_u uuid, w uuid DEFAULT NULL) RETURNS jsonb LANGUAGE sql AS $$
  SELECT pg_temp.js(pg_temp.u(p_u, CASE WHEN w IS NULL THEN 'SELECT public.finish_checkin_session()::text'
                                        ELSE format('SELECT public.finish_checkin_session(%L)::text', w) END)) $$;
CREATE FUNCTION pg_temp.sub(p_u uuid) RETURNS jsonb LANGUAGE sql AS $$
  SELECT pg_temp.js(pg_temp.u(p_u, 'SELECT public.submit_checkin()::text')) $$;

CREATE FUNCTION pg_temp.day(p_u uuid) RETURNS date LANGUAGE sql AS $$
  SELECT (now() AT TIME ZONE coalesce((SELECT timezone FROM user_profiles WHERE id = p_u), 'Europe/Dublin'))::date $$;
CREATE FUNCTION pg_temp.cms(p_u uuid) RETURNS uuid LANGUAGE sql AS $$
  SELECT ts.id FROM team_streaks ts JOIN buddy_teams bt ON bt.id = ts.team_id JOIN team_members tm ON tm.team_id = bt.id
  WHERE tm.user_id = p_u AND bt.is_coach_max_team AND ts.is_active LIMIT 1 $$;
CREATE FUNCTION pg_temp.coins(p_u uuid) RETURNS integer LANGUAGE sql AS $$ SELECT coin_balance FROM user_profiles WHERE id = p_u $$;
CREATE FUNCTION pg_temp.xp(p_u uuid) RETURNS integer LANGUAGE sql AS $$ SELECT xp FROM user_profiles WHERE id = p_u $$;
CREATE FUNCTION pg_temp.npush() RETURNS integer LANGUAGE sql AS $$ SELECT count(*)::int FROM pg_temp.push_log WHERE key = 'buddy_checked_in' $$;
CREATE FUNCTION pg_temp.nbonus(p_u uuid) RETURNS text LANGUAGE sql AS $$
  SELECT count(*) || '/' || coalesce(sum(amount), 0) FROM coin_transactions WHERE user_id = p_u AND transaction_type = 'invite_bonus' $$;
CREATE FUNCTION pg_temp.def(p_fn text) RETURNS text LANGUAGE sql AS $$ SELECT pg_get_functiondef(to_regprocedure(p_fn)) $$;  -- NULL if missing
-- a appears in the body before b (both present).
CREATE FUNCTION pg_temp.before(p_body text, a text, b text) RETURNS boolean LANGUAGE sql AS $$
  SELECT strpos(p_body, a) > 0 AND strpos(p_body, b) > 0 AND strpos(p_body, a) < strpos(p_body, b) $$;
-- L3 cap locks this backend holds for these users.
CREATE FUNCTION pg_temp.capheld(p_users uuid[]) RETURNS integer LANGUAGE sql AS $$
  SELECT count(*)::int FROM pg_locks l
  WHERE l.locktype = 'advisory' AND l.pid = pg_backend_pid() AND l.granted AND l.objsubid = 2
    AND l.classid = (hashtext('checkin_cap')::bigint & 4294967295)::oid
    AND l.objid IN (SELECT (hashtext(x::text)::bigint & 4294967295)::oid FROM unnest(p_users) x) $$;

-- Session started 20 minutes ago (active_checkin_sessions.started_at; no workout, workout_started_at untouched).
CREATE FUNCTION pg_temp.sess(p_u uuid, p_ago interval DEFAULT interval '20 minutes') RETURNS void LANGUAGE sql AS $$
  INSERT INTO active_checkin_sessions (user_id, started_at, workout_type, planned_duration)
  VALUES (p_u, now() - p_ago, 'Strength', 30) $$;
-- Fixture buddy team (postgres), returns the streak id.
CREATE FUNCTION pg_temp.team(a uuid, b uuid) RETURNS uuid LANGUAGE plpgsql AS $f$
DECLARE t uuid; s uuid;
BEGIN
  INSERT INTO buddy_teams (team_name, team_emoji, is_coach_max_team, max_members, created_by)
  VALUES ('probe', '💪', false, 2, a) RETURNING id INTO t;
  INSERT INTO team_members (team_id, user_id, role) VALUES (t, a, 'member'), (t, b, 'member');
  INSERT INTO team_streaks (team_id, current_streak, longest_streak, is_active) VALUES (t, 0, 0, true) RETURNING id INTO s;
  RETURN s;
END $f$;
-- Accepted friendship (fixture), then the real create_buddy_team as a; returns the streak id.
CREATE FUNCTION pg_temp.bt(a uuid, b uuid) RETURNS uuid LANGUAGE plpgsql AS $f$
BEGIN
  INSERT INTO friendships (user_id, friend_id, status) VALUES (a, b, 'accepted');
  RETURN (pg_temp.js(pg_temp.u(a, format('SELECT public.create_buddy_team(%L)::text', b)))->>'streak_id')::uuid;
END $f$;
-- Fixture payout rows for the cap probes.
CREATE FUNCTION pg_temp.capfx(p_u uuid, p_ref text, p_coins integer, p_xp integer) RETURNS void LANGUAGE sql AS $$
  INSERT INTO coin_transactions (user_id, amount, transaction_type, description, reference_id)
  SELECT p_u, p_coins, 'daily_checkin', 'probe fixture', p_ref WHERE p_coins > 0;
  INSERT INTO xp_transactions (user_id, amount, transaction_type, description, reference_id)
  SELECT p_u, p_xp, 'xp_award', 'daily_checkin', p_ref WHERE p_xp > 0 $$;

-- Stable labels so fixture teams created in different phases compare equal.
CREATE FUNCTION pg_temp.nm(p uuid) RETURNS text LANGUAGE sql AS $$
  SELECT coalesce((SELECT note FROM pg_temp.acct WHERE id = p), (SELECT username FROM user_profiles WHERE id = p), left(p::text, 8)) $$;
CREATE FUNCTION pg_temp.lblt(p_team uuid) RETURNS text LANGUAGE sql AS $$
  SELECT CASE WHEN bt.is_coach_max_team THEN 'CM[' ELSE 'T[' END
         || coalesce((SELECT string_agg(pg_temp.nm(tm.user_id), '+' ORDER BY pg_temp.nm(tm.user_id))
                      FROM team_members tm WHERE tm.team_id = bt.id AND tm.user_id <> pg_temp.cmx()), '') || ']'
  FROM buddy_teams bt WHERE bt.id = p_team $$;
CREATE FUNCTION pg_temp.lbl(p_streak uuid) RETURNS text LANGUAGE sql AS $$
  SELECT pg_temp.lblt(team_id) FROM team_streaks WHERE id = p_streak $$;
CREATE FUNCTION pg_temp.ref(r text) RETURNS text LANGUAGE sql AS $$
  SELECT CASE WHEN r ~ '^[0-9a-f-]{36}:' THEN coalesce(pg_temp.lbl(split_part(r, ':', 1)::uuid), '?') || ':' || split_part(r, ':', 2) ELSE r END $$;
CREATE FUNCTION pg_temp.tms(r jsonb) RETURNS jsonb LANGUAGE sql AS $$
  SELECT CASE WHEN jsonb_typeof(r) = 'object' AND r ? 'teams'
    THEN (SELECT coalesce(jsonb_agg(jsonb_build_array(pg_temp.lbl((e->>'streak_id')::uuid), e - 'streak_id' - 'team_id') ORDER BY pg_temp.lbl((e->>'streak_id')::uuid)), '[]')
          FROM jsonb_array_elements(r->'teams') e)
    ELSE r END $$;
CREATE FUNCTION pg_temp.strip(r jsonb) RETURNS jsonb LANGUAGE sql AS $$
  SELECT CASE WHEN jsonb_typeof(r) = 'object' THEN r - 'teams' ELSE r END $$;

-- Everything a credit can change for these users, written in this transaction (created_at = now()).
CREATE FUNCTION pg_temp.snap(p_users uuid[]) RETURNS jsonb LANGUAGE sql AS $$
  WITH tms AS (SELECT DISTINCT ts.id FROM team_streaks ts JOIN team_members tm ON tm.team_id = ts.team_id WHERE tm.user_id = ANY(p_users))
  SELECT jsonb_build_object(
    'rows', (SELECT coalesce(jsonb_agg(x ORDER BY x::text), '[]') FROM (
               SELECT jsonb_build_array(pg_temp.lbl(d.team_streak_id), pg_temp.nm(d.user_id), d.check_in_date, d.check_in_time) x
               FROM daily_team_checkins d WHERE d.team_streak_id IN (SELECT id FROM tms) AND d.created_at = now()) q),
    'streaks', (SELECT coalesce(jsonb_agg(x ORDER BY x::text), '[]') FROM (
               SELECT jsonb_build_array(pg_temp.lbl(ts.id), ts.current_streak, ts.longest_streak, ts.best_streak, ts.total_workouts, ts.last_workout_date) x
               FROM team_streaks ts WHERE ts.id IN (SELECT id FROM tms)) q),
    'xp', (SELECT coalesce(jsonb_agg(x ORDER BY x::text), '[]') FROM (
               SELECT jsonb_build_array(pg_temp.nm(user_id), amount, transaction_type, description, pg_temp.ref(reference_id)) x
               FROM xp_transactions WHERE created_at = now() AND user_id = ANY(p_users)) q),
    'coins', (SELECT coalesce(jsonb_agg(x ORDER BY x::text), '[]') FROM (
               SELECT jsonb_build_array(pg_temp.nm(user_id), amount, transaction_type, description, pg_temp.ref(reference_id)) x
               FROM coin_transactions WHERE created_at = now() AND user_id = ANY(p_users)) q),
    'profiles', (SELECT jsonb_agg(jsonb_build_array(pg_temp.nm(id), xp, coin_balance, level) ORDER BY pg_temp.nm(id))
               FROM user_profiles WHERE id = ANY(p_users)),
    'logs', (SELECT coalesce(jsonb_agg(x ORDER BY x::text), '[]') FROM (
               SELECT jsonb_build_array(pg_temp.nm(user_id), workout_date, workout_time, workout_name, workout_category, workout_emoji,
                                        planned_duration_minutes, actual_duration_minutes, auto_completed) x
               FROM workout_logs WHERE created_at = now() AND user_id = ANY(p_users)) q),
    'breaks_cancelled', (SELECT count(*) FROM break_day_usage WHERE cancelled_at = now() AND user_id = ANY(p_users)),
    'sessions', (SELECT count(*) FROM active_checkin_sessions WHERE user_id = ANY(p_users)),
    'schedule', (SELECT coalesce(jsonb_agg(jsonb_build_array(pg_temp.nm(user_id), scheduled_date, has_checked_in, checked_in_at = now()) ORDER BY user_id), '[]')
                 FROM coach_max_schedule WHERE user_id = ANY(p_users) AND scheduled_date >= current_date - 1),
    'push', (SELECT coalesce(jsonb_agg(jsonb_build_array(pg_temp.nm(recipient), key, coalesce(pg_temp.lblt(ref::uuid), pg_temp.lbl(ref::uuid)), pg_temp.nm(sender)) ORDER BY ts), '[]')
             FROM pg_temp.push_log WHERE recipient = ANY(p_users))) $$;

CREATE FUNCTION pg_temp.ok(p_t text, p_ok boolean, p_info text DEFAULT '') RETURNS text LANGUAGE sql AS $$
  SELECT CASE WHEN coalesce(p_ok, false) THEN 'PASS ' ELSE 'FAIL ' END || p_t
         || CASE WHEN coalesce(p_info, '') <> '' THEN ' -> ' || p_info ELSE '' END $$;
CREATE FUNCTION pg_temp.is(p_t text, p_got text, p_want text) RETURNS text LANGUAGE sql AS $$
  SELECT pg_temp.ok(p_t, p_got IS NOT DISTINCT FROM p_want,
                    'got ' || coalesce(p_got, 'NULL') || CASE WHEN p_got IS DISTINCT FROM p_want THEN ', want ' || coalesce(p_want, 'NULL') ELSE '' END) $$;

-- ═════════ equivalence fixtures (phase 1: bodies before @@MIGRATION@@; phase 2: after) ═════════

-- EQ1 normal finish: rokitest1, solo session, Finish.
CREATE FUNCTION pg_temp.fx_eq1() RETURNS jsonb LANGUAGE plpgsql AS $f$
DECLARE r jsonb;
BEGIN
  PERFORM pg_temp.sess(pg_temp.ua());
  r := pg_temp.fin(pg_temp.ua());
  RETURN jsonb_build_object('ret', pg_temp.strip(r), 'teams', pg_temp.tms(r), 'snap', pg_temp.snap(ARRAY[pg_temp.ua()]));
END $f$;

-- EQ2 partner credit (M6a): shared team rokitest1 + onboard_check1, a completed workout both readied (started now(),
-- not backdated; 30 min recorded). onboard_check1 finishes; rokitest1 is credited as the ready partner.
CREATE FUNCTION pg_temp.fx_eq2() RETURNS jsonb LANGUAGE plpgsql AS $f$
DECLARE r jsonb; w uuid; d timestamp := now() AT TIME ZONE 'Europe/Dublin';
BEGIN
  PERFORM pg_temp.team(pg_temp.ua(), pg_temp.o1());
  INSERT INTO workouts (user_id, buddy_id, workout_type, workout_date, workout_time, planned_duration_minutes, status, buddy_status,
                        workout_started_at, workout_completed_at, actual_duration_minutes, creator_ready, buddy_ready)
  VALUES (pg_temp.ua(), pg_temp.o1(), 'Strength', d::date, d::time, 30, 'completed', 'accepted', now(), now(), 30, true, true)
  RETURNING id INTO w;
  r := pg_temp.fin(pg_temp.o1(), w);
  RETURN jsonb_build_object('ret', pg_temp.strip(r), 'teams', pg_temp.tms(r), 'snap', pg_temp.snap(ARRAY[pg_temp.ua(), pg_temp.o1()]));
END $f$;

-- EQ3 stale auto-complete: _auto_credit for testtest1 (process_stale_sessions' credit step), then its dedup.
CREATE FUNCTION pg_temp.fx_eq3() RETURNS jsonb LANGUAGE plpgsql AS $f$
DECLARE b1 boolean; b2 boolean;
BEGIN
  b1 := public._auto_credit(pg_temp.uc(), now(), 30, 'Strength', NULL);
  b2 := public._auto_credit(pg_temp.uc(), now(), 30, 'Strength', NULL);
  RETURN jsonb_build_object('ret', jsonb_build_array(b1, b2), 'snap', pg_temp.snap(ARRAY[pg_temp.uc()]));
END $f$;

-- EQ4 caps (CAP-2): onboard_check2 has 95 coins / 995 xp of payouts suffixed yesterday. Rewards today, then yesterday.
CREATE FUNCTION pg_temp.fx_eq4() RETURNS jsonb LANGUAGE plpgsql AS $f$
DECLARE s uuid := pg_temp.cms(pg_temp.o2()); t date := pg_temp.day(pg_temp.o2()); r1 jsonb; r2 jsonb;
BEGIN
  PERFORM pg_temp.capfx(pg_temp.o2(), 'fx:' || (t - 1), 95, 995);
  r1 := public._apply_checkin_rewards(pg_temp.o2(), s, t);
  r2 := public._apply_checkin_rewards(pg_temp.o2(), s, t - 1);
  RETURN jsonb_build_object('today', r1, 'yesterday', r2, 'snap', pg_temp.snap(ARRAY[pg_temp.o2()]));
END $f$;

-- EQ5 submit_checkin copy: onboard_check3 has a real row today; rokitest1 accepts, sync copies it.
CREATE FUNCTION pg_temp.fx_eq5() RETURNS jsonb LANGUAGE plpgsql AS $f$
DECLARE r jsonb; b uuid := pg_temp.o3();
BEGIN
  INSERT INTO daily_team_checkins (team_streak_id, user_id, check_in_date, check_in_time)
  VALUES (pg_temp.cms(b), b, pg_temp.day(b), date_trunc('second', now()) - interval '3 hours');
  PERFORM pg_temp.bt(pg_temp.ua(), b);
  r := pg_temp.sub(pg_temp.ua());
  RETURN jsonb_build_object('ret', pg_temp.strip(r), 'teams', pg_temp.tms(r), 'snap', pg_temp.snap(ARRAY[pg_temp.ua(), b]));
END $f$;

-- EQ6 check_in_coach_max then a Finish: onboard_check6, schedule due at 00:00 local today.
CREATE FUNCTION pg_temp.fx_eq6() RETURNS jsonb LANGUAGE plpgsql AS $f$
DECLARE r1 jsonb; r2 jsonb; r3 jsonb; e uuid := pg_temp.o6();
BEGIN
  INSERT INTO coach_max_schedule (user_id, scheduled_date, scheduled_time, has_checked_in)
  VALUES (e, pg_temp.day(e), '00:00', false)
  ON CONFLICT (user_id, scheduled_date) DO UPDATE SET scheduled_time = '00:00', has_checked_in = false, checked_in_at = NULL;
  r1 := pg_temp.js(pg_temp.u(e, format('SELECT public.check_in_coach_max(%L)::text', e)));
  PERFORM pg_temp.sess(e);
  r2 := pg_temp.fin(e);
  r3 := pg_temp.js(pg_temp.u(e, format('SELECT public.check_in_coach_max(%L)::text', e)));
  RETURN jsonb_build_object('cm1', r1 #- '{streak_result,current_streak}', 'fin', pg_temp.strip(r2), 'teams', pg_temp.tms(r2),
                            'cm2', r3, 'snap', pg_temp.snap(ARRAY[e]));
END $f$;

-- EQ7 reconcile_stale_streaks: a broken fixture streak (last day 3 days ago, nobody checked in since) and an intact one
-- (last day yesterday). Only the fixture streaks and their pushes are compared (the call also sees every live streak,
-- inside this rolled-back sub-block).
CREATE FUNCTION pg_temp.fx_eq7() RETURNS jsonb LANGUAGE plpgsql AS $f$
DECLARE s1 uuid; s2 uuid;
BEGIN
  s1 := pg_temp.team(pg_temp.o1(), pg_temp.o2());
  s2 := pg_temp.team(pg_temp.o3(), pg_temp.o4());
  UPDATE team_streaks SET current_streak = 3, longest_streak = 3, best_streak = 3, last_workout_date = pg_temp.day(pg_temp.o1()) - 3 WHERE id = s1;
  UPDATE team_streaks SET current_streak = 2, longest_streak = 2, best_streak = 2, last_workout_date = pg_temp.day(pg_temp.o3()) - 1 WHERE id = s2;
  PERFORM public.reconcile_stale_streaks();
  RETURN jsonb_build_object(
    'streaks', (SELECT jsonb_agg(jsonb_build_array(pg_temp.lbl(id), current_streak, longest_streak, last_workout_date - pg_temp.day(pg_temp.o1())) ORDER BY pg_temp.lbl(id))
                FROM team_streaks WHERE id IN (s1, s2)),
    'losses', (SELECT count(*) FROM streak_events WHERE team_id IN (SELECT team_id FROM team_streaks WHERE id IN (s1, s2))),
    'push', (SELECT coalesce(jsonb_agg(jsonb_build_array(pg_temp.nm(recipient), key) ORDER BY pg_temp.nm(recipient), key), '[]')
             FROM pg_temp.push_log WHERE ref IN (s1::text, s2::text)));
END $f$;

-- ═════════ phase 1 ═════════
DO $p1$
DECLARE fk text; v jsonb; d text;
BEGIN
  IF EXISTS (SELECT 1 FROM daily_team_checkins WHERE user_id = ANY(pg_temp.all_u()) AND check_in_date >= current_date - 2)
     OR EXISTS (SELECT 1 FROM active_checkin_sessions WHERE user_id = ANY(pg_temp.all_u()))
     OR EXISTS (SELECT 1 FROM friendships WHERE user_id = ANY(pg_temp.all_u()) AND friend_id = ANY(pg_temp.all_u()))
     OR EXISTS (SELECT 1 FROM invites WHERE inviter_id = ANY(pg_temp.all_u()) OR accepted_by = ANY(pg_temp.all_u()))
     OR EXISTS (SELECT 1 FROM pg_temp.acct WHERE pg_temp.cms(id) IS NULL)
     OR EXISTS (SELECT 1 FROM pg_temp.acct WHERE id IN ('19c3b618-ae18-4b2e-be52-cbe1de8cacbe', '6dfac56a-74a1-4a60-b7fa-e200338350f3')) THEN
    RAISE EXCEPTION 'fixture precondition failed';
  END IF;
  FOREACH fk IN ARRAY ARRAY['eq1', 'eq2', 'eq3', 'eq4', 'eq5', 'eq6', 'eq7'] LOOP
    BEGIN
      EXECUTE format('SELECT pg_temp.fx_%s()', fk) INTO v;
      RAISE EXCEPTION 'capture' USING ERRCODE = 'P0099', DETAIL = v::text;
    EXCEPTION WHEN SQLSTATE 'P0099' THEN
      GET STACKED DIAGNOSTICS d = PG_EXCEPTION_DETAIL;
      INSERT INTO eq_old VALUES (fk, d::jsonb);
    END;
  END LOOP;
END
$p1$;

-- ═════════ migration under test (run.sh --with), else nothing ═════════
-- @@MIGRATION@@

-- ═════════ phase 2 ═════════
DO $suite$
DECLARE
  r text[] := ARRAY[]::text[];
  fk text; v jsonb; o jsonb; j jsonb; j2 jsonb; n text; ok boolean; body text;
  a uuid; b uuid; c uuid; e uuid; f uuid; s uuid; s1 uuid; s2 uuid; t date; tz text; tm timestamptz; w uuid;
  i1 uuid; i2 uuid; i3 uuid; np integer; ca integer; cb integer; xa integer; xb integer; k integer;
BEGIN
  -- ── G0 catalog: ACL, SECURITY DEFINER, search_path, pinned bodies, lock order in the bodies ──
  SELECT string_agg(p.oid::regprocedure::text || ' ' || p.proacl::text || ' ' || coalesce(p.proconfig::text, '-') || ' secdef=' || p.prosecdef, '; ' ORDER BY p.oid::regprocedure::text),
         bool_and(p.proconfig = '{search_path=public}' AND p.proacl::text = CASE
           WHEN p.proname IN ('finish_checkin_session', 'create_invite_team', 'check_in_coach_max', 'recompute_team_streak',
                              'submit_checkin', 'purchase_shop_item', 'verify_achievement_progress')
             THEN '{postgres=X/postgres,authenticated=X/postgres,service_role=X/postgres}'
           ELSE '{postgres=X/postgres,service_role=X/postgres}' END
           AND p.prosecdef = (p.proname NOT IN ('_credit_checkin', '_credit_day', '_auto_credit', '_lock_credit')))
  INTO n, ok FROM pg_proc p
  WHERE p.pronamespace = 'public'::regnamespace AND p.proname IN (
    '_lock_credit', '_credit_checkin', '_credit_day', '_recompute_team_streak', 'recompute_team_streak', 'finish_checkin_session',
    '_auto_credit', 'process_stale_sessions', 'check_in_coach_max', 'reconcile_stale_streaks', '_apply_checkin_rewards',
    'submit_checkin', 'create_invite_team', '_fulfil_invite_reward', 'purchase_shop_item', 'verify_achievement_progress');
  r := r || pg_temp.ok('G0.1 ACL, SECURITY DEFINER and search_path of every credit-path function', ok AND n LIKE '%_lock_credit%', n);
  r := r || pg_temp.is('G0.2 unchanged bodies pinned: _apply_checkin_rewards, process_stale_sessions, submit_checkin, purchase_shop_item',
                       md5(pg_temp.def('public._apply_checkin_rewards(uuid,uuid,date)')) || ' ' || md5(pg_temp.def('public.process_stale_sessions(timestamptz)'))
                       || ' ' || md5(pg_temp.def('public.submit_checkin()')) || ' ' || md5(pg_temp.def('public.purchase_shop_item(uuid)')),
                       '47185fcbc9c873ef46ebdce0bdde70f6 929c250cf1b7e98ad9c9d593d786ba32 acc63cafafd56afa8a0ebd7503510739 0f67d03bef591fd4c107bb2bb8d05ef2');
  r := r || pg_temp.ok('G0.3 process_stale_sessions COMMENT points at _credit_day',
                       obj_description('public.process_stale_sessions(timestamptz)'::regprocedure, 'pg_proc') LIKE '%_credit_day%');
  body := pg_temp.def('public._lock_credit(uuid[],boolean,uuid)');
  r := r || pg_temp.ok('G0.4 lock order _lock_credit: L2 streak rows (ORDER BY ts.id FOR NO KEY UPDATE) before L3 cap locks',
                       pg_temp.before(body, 'ORDER BY ts.id', 'FOR NO KEY UPDATE') AND pg_temp.before(body, 'FOR NO KEY UPDATE', 'pg_advisory_xact_lock(hashtext(''checkin_cap''), v_k)')
                       AND pg_temp.before(body, 'SELECT DISTINCT hashtext(tm.user_id::text)', 'ORDER BY 1'));
  body := pg_temp.def('public._credit_checkin(uuid,timestamptz,boolean,timestamptz,uuid)');
  r := r || pg_temp.ok('G0.5 lock order _credit_checkin: _lock_credit before any write',
                       pg_temp.before(body, 'public._lock_credit(ARRAY[p_user_id], p_pay, p_streak_id)', 'UPDATE break_day_usage')
                       AND pg_temp.before(body, 'public._lock_credit(', 'INSERT INTO daily_team_checkins'));
  body := pg_temp.def('public.finish_checkin_session(uuid)');
  r := r || pg_temp.ok('G0.6 lock order finish_checkin_session: L0 workout, then L1 session, then L2+L3 for caller and partner, then credits',
                       pg_temp.before(body, 'FROM workouts WHERE id = p_workout_id AND v_uid IN (user_id, buddy_id) FOR NO KEY UPDATE', 'FOR UPDATE OF s')
                       AND pg_temp.before(body, 'FOR UPDATE OF s', 'public._lock_credit(ARRAY[v_uid, v_wk.user_id, v_wk.buddy_id], true)')
                       AND pg_temp.before(body, 'public._lock_credit(ARRAY[v_uid], true)', 'PERFORM public._credit_checkin(v_uid, v_start)'));
  body := pg_temp.def('public._recompute_team_streak(uuid,date)');
  r := r || pg_temp.ok('G0.7 lock order _recompute_team_streak: first read of the streak row is FOR NO KEY UPDATE',
                       pg_temp.before(body, 'FROM team_streaks WHERE id = p_streak_id' || chr(10) || '  FOR NO KEY UPDATE', 'IF v_team_id IS NULL'));
  body := pg_temp.def('public.check_in_coach_max(uuid)');
  r := r || pg_temp.ok('G0.8 lock order check_in_coach_max: L2 before the bot row check and _finish_coach_max_checkin',
                       pg_temp.before(body, 'FROM team_streaks WHERE id = v_streak_id FOR NO KEY UPDATE', 'WHERE team_streak_id = v_streak_id AND user_id = v_coach_max_id')
                       AND pg_temp.before(body, 'FOR NO KEY UPDATE', '_finish_coach_max_checkin'));
  body := pg_temp.def('public.reconcile_stale_streaks()');
  r := r || pg_temp.ok('G0.9 lock order reconcile_stale_streaks: loop ORDER BY id FOR NO KEY UPDATE',
                       pg_temp.before(body, 'ORDER BY id' || chr(10) || '    FOR NO KEY UPDATE', 'LOOP'));

  -- ── G1 _credit_checkin (the L3 checks first: no paying credit has run in this phase yet) ──
  BEGIN
    s := pg_temp.team(pg_temp.o3(), pg_temp.o4());
    j := public._credit_checkin(pg_temp.o3(), now(), false, now(), s);
    r := r || pg_temp.is('G1.1 p_pay=false takes no L3 cap lock', pg_temp.capheld(ARRAY[pg_temp.o3(), pg_temp.o4()])::text, '0');
    s := pg_temp.team(pg_temp.o1(), pg_temp.o2());
    j := public._credit_checkin(pg_temp.o1(), now(), true, now(), s);
    r := r || pg_temp.is('G1.2 a paying credit holds L3 for every non-bot member of the locked streak (both, held to commit)',
                         pg_temp.capheld(ARRAY[pg_temp.o1(), pg_temp.o2()])::text, '2');
    r := r || pg_temp.is('G1.3 no L3 for the Coach Max bot', pg_temp.capheld(ARRAY[pg_temp.cmx()])::text, '0');
    r := r || pg_temp.ok('G1.4 p_streak_id limits the credit to that team (no row on the Coach Max team)',
                         NOT EXISTS (SELECT 1 FROM daily_team_checkins WHERE user_id = pg_temp.o1() AND team_streak_id = pg_temp.cms(pg_temp.o1()) AND check_in_date = pg_temp.day(pg_temp.o1())),
                         j::text);
    r := r || pg_temp.ok('G1.5 return shape credit_date/teams/xp/coins, day incomplete (partner missing), paid 0',
                         j ?& ARRAY['credit_date', 'teams', 'xp', 'coins'] AND j#>>'{teams,0,updated}' = 'false' AND j->>'coins' = '0', j::text);
    j := public._credit_checkin(pg_temp.o2(), now(), true, now(), s);
    r := r || pg_temp.is('G1.6 teammate completes the day: updated/new_streak/xp/coins', (j#>>'{teams,0,updated}') || '/' || (j#>>'{teams,0,new_streak}') || '/' || (j->>'xp') || '/' || (j->>'coins'), 'true/1/15/15');
    k := (SELECT count(*) FROM daily_team_checkins WHERE team_streak_id = s);
    j := public._credit_checkin(pg_temp.o2(), now(), true, now(), s);
    r := r || pg_temp.is('G1.7 second call: no new row, teams [] , paid 0', ((SELECT count(*) FROM daily_team_checkins WHERE team_streak_id = s) - k) || '/' || (j->'teams')::text || '/' || (j->>'coins'), '0/[]/0');
    r := r || pg_temp.is('G1.8 stored check_in_time = p_time', (SELECT (check_in_time = now())::text FROM daily_team_checkins WHERE team_streak_id = s AND user_id = pg_temp.o1()), 'true');
    RAISE EXCEPTION 'undo' USING ERRCODE = 'P0098';
  EXCEPTION WHEN SQLSTATE 'P0098' THEN NULL;
            WHEN OTHERS THEN r := r || ('FAIL G1 crashed: ' || SQLERRM);
  END;

  -- ── G10 equivalence: the phase-2 bodies on the phase-1 fixtures ──
  FOREACH fk IN ARRAY ARRAY['eq1', 'eq2', 'eq3', 'eq4', 'eq5', 'eq6', 'eq7'] LOOP
    BEGIN
      EXECUTE format('SELECT pg_temp.fx_%s()', fk) INTO v;
      RAISE EXCEPTION 'capture' USING ERRCODE = 'P0099', DETAIL = v::text;
    EXCEPTION WHEN SQLSTATE 'P0099' THEN
      GET STACKED DIAGNOSTICS n = PG_EXCEPTION_DETAIL;
      v := n::jsonb;
    END;
    SELECT x.v INTO o FROM eq_old x WHERE x.k = fk;
    r := r || pg_temp.ok(format('G10.%s new = old', fk), v = o, format('md5 old %s new %s', md5(o::text), md5(v::text)));
    r := r || ('     ' || fk || ': ' || v::text);
    IF v IS DISTINCT FROM o THEN r := r || ('     ' || fk || ' old: ' || coalesce(o::text, 'NULL')); END IF;
  END LOOP;

  -- ── G2 submit_checkin (copy condition, local day, copy time, no push, no pay, idempotency) + G3 Finish after a copy ──
  BEGIN
    a := pg_temp.ua(); b := pg_temp.o3(); t := pg_temp.day(b); tm := now() - interval '3 hours';
    INSERT INTO daily_team_checkins (team_streak_id, user_id, check_in_date, check_in_time) VALUES (pg_temp.cms(b), b, t, tm);
    s := pg_temp.bt(a, b);
    np := pg_temp.npush(); cb := pg_temp.coins(b); xb := pg_temp.xp(b);
    j := pg_temp.sub(a);
    r := r || pg_temp.is('G2.1 submit_checkin as rokitest1 (no row today): reason', j->>'reason', 'not_checked_in_today');
    r := r || pg_temp.ok('G2.2 credited false, xp 0, coins 0', j->>'credited' = 'false' AND j->>'xp' = '0' AND j->>'coins' = '0', j::text);
    r := r || pg_temp.is('G2.3 partner row created on the new team with the partner''s local date',
                         (SELECT check_in_date::text FROM daily_team_checkins WHERE team_streak_id = s AND user_id = b), t::text);
    SELECT check_in_time INTO tm FROM daily_team_checkins WHERE team_streak_id = s AND user_id = b;
    r := r || pg_temp.ok('G2.4 copy check_in_time = source earliest time, not now()',
                         tm = (SELECT min(check_in_time) FROM daily_team_checkins WHERE user_id = b AND check_in_date = t AND team_streak_id <> s)
                         AND tm <> now(), format('copy %s, now %s', tm, now()));
    r := r || pg_temp.ok('G2.5 caller not copied (no real row today)', NOT EXISTS (SELECT 1 FROM daily_team_checkins WHERE user_id = a AND check_in_date = pg_temp.day(a)));
    r := r || pg_temp.is('G2.6 the copy sent no push', (pg_temp.npush() - np)::text, '0');
    r := r || pg_temp.is('G2.7 the copy paid nothing (partner coins/xp delta)', (pg_temp.coins(b) - cb) || '/' || (pg_temp.xp(b) - xb), '0/0');
    r := r || pg_temp.is('G2.8 copy flag cleared when submit_checkin returns', coalesce(current_setting('app.checkin_copy', true), '<null>'), '');
    r := r || pg_temp.is('G2.9 new team not advanced yet (caller missing): streak/total', (SELECT current_streak || '/' || total_workouts FROM team_streaks WHERE id = s), '0/0');
    PERFORM pg_temp.sess(a);
    np := pg_temp.npush(); ca := pg_temp.coins(a); cb := pg_temp.coins(b);
    j := pg_temp.fin(a);
    r := r || pg_temp.ok('G3.1 a real Finish after the copy still pushes rokitest1 -> onboard_check3 on the new team',
                         EXISTS (SELECT 1 FROM pg_temp.push_log WHERE key = 'buddy_checked_in' AND recipient = b AND sender = a
                                 AND ref = (SELECT team_id::text FROM team_streaks WHERE id = s)));
    r := r || pg_temp.is('G3.2 Finish completes the new team''s day: streak/total', (SELECT current_streak || '/' || total_workouts FROM team_streaks WHERE id = s), '1/1');
    r := r || pg_temp.is('G3.3 Finish pays: rokitest1 +25 (Coach Max 10, team 15), onboard_check3 retro share +15',
                         (pg_temp.coins(a) - ca) || '/' || (pg_temp.coins(b) - cb), '25/15');
    np := pg_temp.npush(); ca := pg_temp.coins(a); cb := pg_temp.coins(b);
    k := (SELECT count(*) FROM daily_team_checkins WHERE user_id IN (a, b));
    j := pg_temp.sub(a);
    r := r || pg_temp.is('G2.10 second submit_checkin the same day: reason', j->>'reason', 'already_checked_in');
    r := r || pg_temp.is('G2.11 second call: rows, coins, pushes unchanged',
                         ((SELECT count(*) FROM daily_team_checkins WHERE user_id IN (a, b)) - k) || '/' || (pg_temp.coins(a) - ca) || '/' || (pg_temp.coins(b) - cb) || '/' || (pg_temp.npush() - np),
                         '0/0/0/0');
    j2 := pg_temp.fin(a);
    r := r || pg_temp.is('G3.4 second Finish the same day: result, coins delta', (j2->>'result') || '/' || (pg_temp.coins(a) - ca), 'nothing_to_finish/0');
    r := r || pg_temp.ok('G2.12 submit_checkin return shape', j ?& ARRAY['credited', 'reason', 'credit_date', 'streak', 'xp', 'coins', 'teams'] AND NOT j ? 'milestones_unlocked', j::text);
    RAISE EXCEPTION 'undo' USING ERRCODE = 'P0098';
  EXCEPTION WHEN SQLSTATE 'P0098' THEN NULL;
            WHEN OTHERS THEN r := r || ('FAIL G2 crashed: ' || SQLERRM);
  END;

  -- ── G2 local day versus UTC (FS-1); a member with no real row today is not copied ──
  BEGIN
    c := pg_temp.uc(); e := pg_temp.o6(); f := pg_temp.o4();
    tz := CASE WHEN extract(hour FROM now() AT TIME ZONE 'UTC') >= 10 THEN 'Pacific/Kiritimati' ELSE 'Pacific/Pago_Pago' END;
    UPDATE user_profiles SET timezone = tz WHERE id = e;
    r := r || pg_temp.ok('G2.13 fixture: onboard_check6 local date differs from the UTC date', pg_temp.day(e) <> (now() AT TIME ZONE 'UTC')::date,
                         format('%s %s vs UTC %s', tz, pg_temp.day(e), (now() AT TIME ZONE 'UTC')::date));
    PERFORM pg_temp.sess(e);
    j := pg_temp.fin(e);
    r := r || pg_temp.is('G3.5 Finish credit_date = the member''s local date', j->>'credit_date', pg_temp.day(e)::text);
    INSERT INTO daily_team_checkins (team_streak_id, user_id, check_in_date, check_in_time)
    VALUES (pg_temp.cms(f), f, pg_temp.day(f) - 1, now() - interval '1 day');
    s1 := pg_temp.bt(c, e);
    s2 := pg_temp.bt(c, f);
    j := pg_temp.sub(c);
    r := r || pg_temp.is('G2.14 submit_checkin as testtest1 (no row today): reason', j->>'reason', 'not_checked_in_today');
    r := r || pg_temp.is('G2.15 onboard_check6 copied with its own local date, not the UTC date',
                         (SELECT check_in_date::text FROM daily_team_checkins WHERE team_streak_id = s1 AND user_id = e), pg_temp.day(e)::text);
    r := r || pg_temp.ok('G2.16 onboard_check4 (only yesterday) not copied anywhere',
                         NOT EXISTS (SELECT 1 FROM daily_team_checkins WHERE user_id = f AND (team_streak_id = s2 OR check_in_date >= pg_temp.day(f))));
    r := r || pg_temp.ok('G2.17 testtest1 not copied', NOT EXISTS (SELECT 1 FROM daily_team_checkins WHERE user_id = c AND team_streak_id IN (s1, s2)));
    RAISE EXCEPTION 'undo' USING ERRCODE = 'P0098';
  EXCEPTION WHEN SQLSTATE 'P0098' THEN NULL;
            WHEN OTHERS THEN r := r || ('FAIL G2 local-day crashed: ' || SQLERRM);
  END;

  -- ── G2 copies of the caller and the partner complete a new team's day, pay nothing, push nothing ──
  BEGIN
    a := pg_temp.ua(); f := pg_temp.o4();
    PERFORM pg_temp.sess(a); j := pg_temp.fin(a);
    PERFORM pg_temp.sess(f); j := pg_temp.fin(f);
    s := pg_temp.bt(a, f);
    np := pg_temp.npush(); ca := pg_temp.coins(a); cb := pg_temp.coins(f); xa := pg_temp.xp(a); xb := pg_temp.xp(f);
    j := pg_temp.sub(a);
    r := r || pg_temp.ok('G2.18 reason credited, credited true, xp 0, coins 0',
                         j->>'reason' = 'credited' AND j->>'credited' = 'true' AND j->>'xp' = '0' AND j->>'coins' = '0', j::text);
    r := r || pg_temp.is('G2.19 both members copied onto the new team', (SELECT count(*)::text FROM daily_team_checkins WHERE team_streak_id = s), '2');
    r := r || pg_temp.is('G2.20 copies complete the day: streak/total, return marks the team updated',
                         (SELECT current_streak || '/' || total_workouts FROM team_streaks WHERE id = s) || '/' ||
                         (SELECT te->>'updated' FROM jsonb_array_elements(j->'teams') te WHERE (te->>'streak_id')::uuid = s), '1/1/true');
    r := r || pg_temp.is('G2.21 copies paid nothing: coins and xp deltas',
                         (pg_temp.coins(a) - ca) || '/' || (pg_temp.coins(f) - cb) || '/' || (pg_temp.xp(a) - xa) || '/' || (pg_temp.xp(f) - xb), '0/0/0/0');
    r := r || pg_temp.is('G2.22 copies pushed nothing', (pg_temp.npush() - np)::text, '0');
    r := r || pg_temp.ok('G2.23 each copy keeps its member''s earliest real check_in_time',
                         NOT EXISTS (SELECT 1 FROM daily_team_checkins d WHERE d.team_streak_id = s AND d.check_in_time <>
                                     (SELECT min(x.check_in_time) FROM daily_team_checkins x WHERE x.user_id = d.user_id AND x.check_in_date = d.check_in_date AND x.team_streak_id <> s)));
    RAISE EXCEPTION 'undo' USING ERRCODE = 'P0098';
  EXCEPTION WHEN SQLSTATE 'P0098' THEN NULL;
            WHEN OTHERS THEN r := r || ('FAIL G2 copies crashed: ' || SQLERRM);
  END;

  -- ── G3 finish_checkin_session FIN-1 gate and L0 ──
  BEGIN
    j := pg_temp.fin(pg_temp.o2());
    r := r || pg_temp.is('G3.6 no session, no workout: nothing_to_finish, credits nothing', (j->>'result') || '/' || (j->>'checked_in'), 'nothing_to_finish/0');
    PERFORM pg_temp.sess(pg_temp.o2(), interval '5 minutes');
    j := pg_temp.fin(pg_temp.o2());
    r := r || pg_temp.is('G3.7 session under 15 minutes: too_early, session kept', (j->>'result') || '/' || (SELECT count(*) FROM active_checkin_sessions WHERE user_id = pg_temp.o2()), 'too_early/1');
    INSERT INTO workouts (user_id, workout_type, workout_date, workout_time, planned_duration_minutes, status, workout_started_at, creator_ready)
    VALUES (pg_temp.uc(), 'Strength', current_date, '10:00', 30, 'in_progress', now(), true) RETURNING id INTO w;
    j := pg_temp.fin(pg_temp.o4(), w);
    r := r || pg_temp.is('G3.8 someone else''s workout id: no error, nothing_to_finish (L0 only locks a participant''s workout)', j->>'result', 'nothing_to_finish');
    r := r || pg_temp.ok('G3.9 return shape (installed build parses it)',
                         j ?& ARRAY['result', 'credit_date', 'checked_in', 'break_cancelled', 'did_level_up', 'new_level', 'teams', 'partner_checked_in'], j::text);
    RAISE EXCEPTION 'undo' USING ERRCODE = 'P0098';
  EXCEPTION WHEN SQLSTATE 'P0098' THEN NULL;
            WHEN OTHERS THEN r := r || ('FAIL G3 crashed: ' || SQLERRM);
  END;

  -- ── G5 _apply_checkin_rewards: CAP-1 dedup, CAP-2 caps by credit day ──
  b := pg_temp.o2(); s := pg_temp.cms(b); t := pg_temp.day(b);
  BEGIN
    j := public._apply_checkin_rewards(b, s, t);
    j2 := public._apply_checkin_rewards(b, s, t);
    r := r || pg_temp.is('G5.1 base payout 10/10, then CAP-1 dedup on the same streak:day', (j->>'coins_awarded') || '/' || (j->>'xp_awarded') || '/' || (j2->>'already_awarded'), '10/10/true');
    RAISE EXCEPTION 'undo' USING ERRCODE = 'P0098';
  EXCEPTION WHEN SQLSTATE 'P0098' THEN NULL; WHEN OTHERS THEN r := r || ('FAIL G5.1 crashed: ' || SQLERRM);
  END;
  BEGIN
    PERFORM pg_temp.capfx(b, 'fx:' || (t - 1), 95, 995);
    j := public._apply_checkin_rewards(b, s, t - 1);
    r := r || pg_temp.is('G5.2 yesterday''s cap counts yesterday-suffixed payouts: coins/xp/capped',
                         (j->>'coins_awarded') || '/' || (j->>'xp_awarded') || '/' || (j->>'daily_cap_reached'), '5/5/true');
    RAISE EXCEPTION 'undo' USING ERRCODE = 'P0098';
  EXCEPTION WHEN SQLSTATE 'P0098' THEN NULL; WHEN OTHERS THEN r := r || ('FAIL G5.2 crashed: ' || SQLERRM);
  END;
  BEGIN
    PERFORM pg_temp.capfx(b, 'fx:' || t, 95, 995);
    j := public._apply_checkin_rewards(b, s, t);
    r := r || pg_temp.is('G5.3 today''s cap counts today-suffixed payouts: coins/xp/capped',
                         (j->>'coins_awarded') || '/' || (j->>'xp_awarded') || '/' || (j->>'daily_cap_reached'), '5/5/true');
    RAISE EXCEPTION 'undo' USING ERRCODE = 'P0098';
  EXCEPTION WHEN SQLSTATE 'P0098' THEN NULL; WHEN OTHERS THEN r := r || ('FAIL G5.3 crashed: ' || SQLERRM);
  END;
  BEGIN
    PERFORM pg_temp.capfx(b, 'legacy-no-suffix', 95, 995);
    PERFORM pg_temp.capfx(b, NULL, 95, 995);
    PERFORM pg_temp.capfx(b, 'fx:' || t || 'x', 95, 995);
    j := public._apply_checkin_rewards(b, s, t);
    r := r || pg_temp.is('G5.4 legacy reference (no suffix, NULL, near-miss suffix) is not counted: coins/xp/capped',
                         (j->>'coins_awarded') || '/' || (j->>'xp_awarded') || '/' || (j->>'daily_cap_reached'), '10/10/false');
    RAISE EXCEPTION 'undo' USING ERRCODE = 'P0098';
  EXCEPTION WHEN SQLSTATE 'P0098' THEN NULL; WHEN OTHERS THEN r := r || ('FAIL G5.4 crashed: ' || SQLERRM);
  END;
  BEGIN
    PERFORM pg_temp.capfx(b, 'fx:' || (t - 1), 95, 995);
    j := public._apply_checkin_rewards(b, s, t);
    j2 := public._apply_checkin_rewards(b, s, t - 1);
    r := r || pg_temp.is('G5.5 straddling midnight: counts for yesterday (capped), not for today: today/yesterday coins',
                         (j->>'coins_awarded') || '/' || (j2->>'coins_awarded'), '10/5');
    RAISE EXCEPTION 'undo' USING ERRCODE = 'P0098';
  EXCEPTION WHEN SQLSTATE 'P0098' THEN NULL; WHEN OTHERS THEN r := r || ('FAIL G5.5 crashed: ' || SQLERRM);
  END;
  FOREACH n IN ARRAY ARRAY['today', 'yesterday'] LOOP
    BEGIN
      f := pg_temp.o4();
      s1 := pg_temp.team(b, f);
      INSERT INTO daily_team_checkins (team_streak_id, user_id, check_in_date, check_in_time) VALUES (s1, b, t, now()), (s1, f, t, now());
      PERFORM pg_temp.capfx(f, 'fx:' || CASE WHEN n = 'today' THEN t ELSE t - 1 END, 95, 0);
      cb := pg_temp.coins(f);
      j := public._apply_checkin_rewards(b, s1, t);
      r := r || pg_temp.is(format('G5.6 teammate cap by credit day, teammate has 95 coins suffixed %s: teammate paid (10 base + 5 co-op, capped)', n),
                           (pg_temp.coins(f) - cb)::text, CASE WHEN n = 'today' THEN '5' ELSE '15' END);
      RAISE EXCEPTION 'undo' USING ERRCODE = 'P0098';
    EXCEPTION WHEN SQLSTATE 'P0098' THEN NULL; WHEN OTHERS THEN r := r || ('FAIL G5.6 crashed: ' || SQLERRM);
    END;
  END LOOP;

  -- ── G4 _auto_credit / process_stale_sessions (body pinned in G0.2) ──
  BEGIN
    n := public._auto_credit(pg_temp.uc(), now(), 30, 'Strength', NULL) || '/' || public._auto_credit(pg_temp.uc(), now(), 30, 'Strength', NULL);
    r := r || pg_temp.is('G4.1 _auto_credit credits once, then dedups (workout_logs.auto_completed)',
                         n || '/' || (SELECT count(*) FROM workout_logs WHERE user_id = pg_temp.uc() AND auto_completed AND created_at = now()), 'true/false/1');
    RAISE EXCEPTION 'undo' USING ERRCODE = 'P0098';
  EXCEPTION WHEN SQLSTATE 'P0098' THEN NULL; WHEN OTHERS THEN r := r || ('FAIL G4 crashed: ' || SQLERRM);
  END;

  -- ── G6 F3: invitee bonus once per account, on the first credited row ──
  BEGIN
    a := pg_temp.ua(); c := pg_temp.uc(); e := pg_temp.o1(); b := pg_temp.o2();
    INSERT INTO invites (inviter_id, status, created_at, accepted_at, accepted_by)
    VALUES (c, 'accepted', (SELECT created_at FROM auth.users WHERE id = e) - interval '1 minute', now(), e) RETURNING id INTO i1;
    n := pg_temp.u(e, format('SELECT public.create_invite_team(%L, %L)::text', c, e));
    r := r || pg_temp.ok('G6.1 create_invite_team for a new invitee pays nothing at join', n NOT LIKE 'ERR:%' AND pg_temp.nbonus(e) = '0/0', n || ' bonus ' || pg_temp.nbonus(e));
    PERFORM pg_temp.sess(e); j := pg_temp.fin(e);
    r := r || pg_temp.is('G6.2 first credited day pays once (Finish wrote 2 rows): count/amount/reference = the invite',
                         pg_temp.nbonus(e) || '/' || (SELECT max(reference_id) FROM coin_transactions WHERE user_id = e AND transaction_type = 'invite_bonus'),
                         '1/20/' || i1);
    INSERT INTO daily_team_checkins (team_streak_id, user_id, check_in_date, check_in_time)
    VALUES (pg_temp.cms(e), e, pg_temp.day(e) - 1, now() - interval '1 day');
    r := r || pg_temp.is('G6.3 a credited row on another day pays nothing more', pg_temp.nbonus(e), '1/20');
    r := r || pg_temp.is('G6.4 inviter reward needs >= 2 distinct check-in days (invitee now has 2)',
                         (SELECT count(*)::text FROM coin_transactions WHERE user_id = c AND transaction_type = 'invite_reward'), '1');
    INSERT INTO invites (inviter_id, status, created_at, accepted_at, accepted_by)
    VALUES (b, 'accepted', (SELECT created_at FROM auth.users WHERE id = e) - interval '1 minute', now(), e) RETURNING id INTO i2;
    n := pg_temp.u(e, format('SELECT public.create_invite_team(%L, %L)::text', b, e));
    j := pg_temp.sub(e);
    r := r || pg_temp.is('G6.5 second inviter, then a copied row lands: still one bonus (copy reason, bonus)', (j->>'reason') || ' ' || pg_temp.nbonus(e), 'credited 1/20');
    INSERT INTO invites (inviter_id, status, accepted_at, accepted_by) VALUES (c, 'accepted', now(), a) RETURNING id INTO i3;
    n := pg_temp.u(a, format('SELECT public.create_invite_team(%L, %L)::text', c, a));
    PERFORM pg_temp.sess(a); j := pg_temp.fin(a);
    r := r || pg_temp.is('G6.6 an existing account (created before the invite) is never paid', pg_temp.nbonus(a), '0/0');
    RAISE EXCEPTION 'undo' USING ERRCODE = 'P0098';
  EXCEPTION WHEN SQLSTATE 'P0098' THEN NULL;
            WHEN OTHERS THEN r := r || ('FAIL G6 crashed: ' || SQLERRM);
  END;

  -- ── G7 purchase_shop_item (Star Streak 150 coins, unlock level 1) ──
  BEGIN
    c := pg_temp.uc();
    UPDATE user_profiles SET coin_balance = 100 WHERE id = c;
    j := pg_temp.js(pg_temp.u(c, 'SELECT public.purchase_shop_item(''78594031-1074-46ed-b80b-a1cbcb7043b0'')::text'));
    r := r || pg_temp.is('G7.1 insufficient funds refused, balance unchanged', (j->>'reason') || '/' || pg_temp.coins(c), 'insufficient_funds/100');
    UPDATE user_profiles SET coin_balance = 150 WHERE id = c;
    j := pg_temp.js(pg_temp.u(c, 'SELECT public.purchase_shop_item(''78594031-1074-46ed-b80b-a1cbcb7043b0'')::text'));
    r := r || pg_temp.is('G7.2 exact balance buys it: success/new_balance/ledger/inventory',
                         (j->>'success') || '/' || (j->>'new_balance') || '/'
                         || (SELECT sum(amount) FROM coin_transactions WHERE user_id = c AND transaction_type = 'shop_purchase' AND created_at = now()) || '/'
                         || (SELECT count(*) FROM user_inventory WHERE user_id = c AND shop_item_id = '78594031-1074-46ed-b80b-a1cbcb7043b0'),
                         'true/0/-150/1');
    j := pg_temp.js(pg_temp.u(c, 'SELECT public.purchase_shop_item(''78594031-1074-46ed-b80b-a1cbcb7043b0'')::text'));
    r := r || pg_temp.ok('G7.3 second purchase of the same item refused', coalesce(j->>'success', 'false') = 'false' AND pg_temp.coins(c) = 0, j::text);
    r := r || pg_temp.ok('G7.4 purchase locks the buyer row (FOR UPDATE in the body)', pg_temp.def('public.purchase_shop_item(uuid)') LIKE '%FOR UPDATE%');
    BEGIN
      UPDATE user_profiles SET coin_balance = -1 WHERE id = c;
      n := 'no error';
    EXCEPTION WHEN OTHERS THEN n := SQLSTATE || ' ' || SQLERRM;
    END;
    r := r || pg_temp.ok('G7.5 coin_balance cannot go negative (CHECK)', n LIKE '23514%', n);
    RAISE EXCEPTION 'undo' USING ERRCODE = 'P0098';
  EXCEPTION WHEN SQLSTATE 'P0098' THEN NULL;
            WHEN OTHERS THEN r := r || ('FAIL G7 crashed: ' || SQLERRM);
  END;

  -- ── G8 verify_achievement_progress replay (first_flame: best_streak >= 1, 50 xp / 20 coins) ──
  BEGIN
    b := pg_temp.o2();
    DELETE FROM user_achievements WHERE user_id = b AND achievement_id = 'first_flame';
    ca := pg_temp.coins(b); xa := pg_temp.xp(b);
    j := pg_temp.js(pg_temp.u(b, 'SELECT public.verify_achievement_progress(''first_flame'')::text'));
    r := r || pg_temp.ok('G8.1 no streak yet: not unlocked, nothing paid',
                         NOT EXISTS (SELECT 1 FROM user_achievements WHERE user_id = b AND achievement_id = 'first_flame' AND unlocked_at IS NOT NULL)
                         AND pg_temp.coins(b) = ca AND pg_temp.xp(b) = xa, j::text);
    s := pg_temp.team(b, pg_temp.o1());
    j := public._credit_checkin(pg_temp.o1(), now(), true, now(), s);
    j := public._credit_checkin(b, now(), true, now(), s);
    ca := pg_temp.coins(b); xa := pg_temp.xp(b);
    j := pg_temp.js(pg_temp.u(b, 'SELECT public.verify_achievement_progress(''first_flame'')::text'));
    r := r || pg_temp.is('G8.2 after a credited day: unlocked once, paid 20 coins / 50 xp',
                         (SELECT count(*) FROM user_achievements WHERE user_id = b AND achievement_id = 'first_flame' AND unlocked_at IS NOT NULL) || '/'
                         || (pg_temp.coins(b) - ca) || '/' || (pg_temp.xp(b) - xa), '1/20/50');
    ca := pg_temp.coins(b); xa := pg_temp.xp(b);
    j := pg_temp.js(pg_temp.u(b, 'SELECT public.verify_achievement_progress(''first_flame'')::text'));
    r := r || pg_temp.is('G8.3 replay: already_unlocked, nothing paid', (j->>'already_unlocked') || '/' || (pg_temp.coins(b) - ca) || '/' || (pg_temp.xp(b) - xa), 'true/0/0');
    RAISE EXCEPTION 'undo' USING ERRCODE = 'P0098';
  EXCEPTION WHEN SQLSTATE 'P0098' THEN NULL;
            WHEN OTHERS THEN r := r || ('FAIL G8 crashed: ' || SQLERRM);
  END;

  RAISE EXCEPTION E'SUITE_RESULTS\n%', array_to_string(r, E'\n');
END
$suite$;
ROLLBACK;
