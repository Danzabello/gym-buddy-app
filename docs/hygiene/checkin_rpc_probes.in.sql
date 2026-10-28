-- Single server check-in RPC probes (template; gen_checkin_rpc.py writes checkin_rpc_probes.sql with Migration A inline).
-- One transaction: helpers; phase 1 runs the OLD bodies on the equivalence fixtures (each captured, then rolled
-- back); Migration A; phase 2 runs the NEW bodies on the same fixtures plus every probe; RAISE, then ROLLBACK.
-- Nothing persists. Credit functions only run in here. Test accounts only, matched by id.
-- _send_push is stubbed for the whole transaction to record calls instead of posting.
BEGIN;

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

CREATE FUNCTION pg_temp.ua() RETURNS uuid LANGUAGE sql AS $$ SELECT '5e67f64d-16e3-4b09-9b00-ddc49df8c3f6'::uuid $$; -- rokitest1
CREATE FUNCTION pg_temp.uc() RETURNS uuid LANGUAGE sql AS $$ SELECT 'cf4946f5-f921-4e81-bbf4-88d574e8baf5'::uuid $$; -- testtest1
CREATE FUNCTION pg_temp.o1() RETURNS uuid LANGUAGE sql AS $$ SELECT '81f83cdb-e09b-4f1f-8045-afa0d3d2181e'::uuid $$; -- onboard_check1
CREATE FUNCTION pg_temp.o2() RETURNS uuid LANGUAGE sql AS $$ SELECT 'bc85514c-02f2-4340-90f2-d95e3f62af26'::uuid $$; -- onboard_check2
CREATE FUNCTION pg_temp.o3() RETURNS uuid LANGUAGE sql AS $$ SELECT 'f0f43430-80aa-4c38-8f87-c11226bef86f'::uuid $$; -- onboard_check3
CREATE FUNCTION pg_temp.o4() RETURNS uuid LANGUAGE sql AS $$ SELECT 'ae240bb6-e629-401e-9fb6-feb1ed21cee9'::uuid $$; -- onboard_check4
CREATE FUNCTION pg_temp.o6() RETURNS uuid LANGUAGE sql AS $$ SELECT '30d543f1-bb06-41c4-8522-396ed948ba35'::uuid $$; -- onboard_check6
CREATE FUNCTION pg_temp.cmx() RETURNS uuid LANGUAGE sql AS $$ SELECT '00000000-0000-0000-0000-000000000001'::uuid $$;
CREATE FUNCTION pg_temp.all_u() RETURNS uuid[] LANGUAGE sql AS $$
  SELECT ARRAY[pg_temp.ua(), pg_temp.uc(), pg_temp.o1(), pg_temp.o2(), pg_temp.o3(), pg_temp.o4(), pg_temp.o6()] $$;

-- Run SQL as a user (JWT claims + role), return its text result or 'ERR:<message>'.
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
    r := 'ERR:' || SQLERRM;
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

-- Session started 20 minutes ago (active_checkin_sessions.started_at; no workout, workout_started_at untouched).
CREATE FUNCTION pg_temp.sess(p_u uuid) RETURNS void LANGUAGE sql AS $$
  INSERT INTO active_checkin_sessions (user_id, started_at, workout_type, planned_duration)
  VALUES (p_u, now() - interval '20 minutes', 'Strength', 30) $$;
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

-- Stable labels so fixture teams created in different runs compare equal.
CREATE FUNCTION pg_temp.nm(p uuid) RETURNS text LANGUAGE sql AS $$
  SELECT coalesce((SELECT username FROM user_profiles WHERE id = p), left(p::text, 8)) $$;
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
    'push', (SELECT coalesce(jsonb_agg(jsonb_build_array(pg_temp.nm(recipient), pg_temp.lblt(ref::uuid), pg_temp.nm(sender)) ORDER BY ts), '[]')
             FROM pg_temp.push_log WHERE key = 'buddy_checked_in')) $$;

CREATE FUNCTION pg_temp.ok(p_t text, p_ok boolean, p_info text DEFAULT '') RETURNS text LANGUAGE sql AS $$
  SELECT CASE WHEN coalesce(p_ok, false) THEN 'PASS ' ELSE 'FAIL ' END || p_t
         || CASE WHEN coalesce(p_info, '') <> '' THEN ' -> ' || p_info ELSE '' END $$;
CREATE FUNCTION pg_temp.is(p_t text, p_got text, p_want text) RETURNS text LANGUAGE sql AS $$
  SELECT pg_temp.ok(p_t, p_got IS NOT DISTINCT FROM p_want,
                    'got ' || coalesce(p_got, 'NULL') || CASE WHEN p_got IS DISTINCT FROM p_want THEN ', want ' || coalesce(p_want, 'NULL') ELSE '' END) $$;

-- ═════════ equivalence fixtures (run by the old bodies in phase 1, by the new bodies in phase 2) ═════════

-- EQ1 normal finish: rokitest1, solo session, Finish.
CREATE FUNCTION pg_temp.fx_eq1() RETURNS jsonb LANGUAGE plpgsql AS $f$
DECLARE r jsonb;
BEGIN
  PERFORM pg_temp.sess(pg_temp.ua());
  r := pg_temp.fin(pg_temp.ua());
  RETURN jsonb_build_object('ret', pg_temp.strip(r), 'teams', pg_temp.tms(r), 'snap', pg_temp.snap(ARRAY[pg_temp.ua()]));
END $f$;

-- EQ2 partner credit: shared team rokitest1 + onboard_check1, a completed workout both readied (started now(),
-- not backdated; 30 min recorded). onboard_check1 finishes; rokitest1 is credited as the ready partner (M6a).
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

-- EQ4 CAP-2, the intended difference: onboard_check2 already has 95 coins / 995 xp of daily_checkin payouts
-- for YESTERDAY's credit, created today (a Finish after midnight). Rewards for today, then for yesterday.
CREATE FUNCTION pg_temp.fx_eq4() RETURNS jsonb LANGUAGE plpgsql AS $f$
DECLARE s uuid := pg_temp.cms(pg_temp.o2()); t date := pg_temp.day(pg_temp.o2()); r1 jsonb; r2 jsonb;
BEGIN
  PERFORM pg_temp.capfx(pg_temp.o2(), 'fx:' || (t - 1), 95, 995);
  r1 := public._apply_checkin_rewards(pg_temp.o2(), s, t);
  r2 := public._apply_checkin_rewards(pg_temp.o2(), s, t - 1);
  RETURN jsonb_build_object('today', r1, 'yesterday', r2, 'snap', pg_temp.snap(ARRAY[pg_temp.o2()]));
END $f$;

-- ═════════ phase 1: old bodies ═════════
DO $p1$
DECLARE fk text; v jsonb; d text;
BEGIN
  IF EXISTS (SELECT 1 FROM daily_team_checkins WHERE user_id = ANY(pg_temp.all_u()) AND check_in_date >= current_date - 2)
     OR EXISTS (SELECT 1 FROM active_checkin_sessions WHERE user_id = ANY(pg_temp.all_u()))
     OR EXISTS (SELECT 1 FROM friendships WHERE user_id = ANY(pg_temp.all_u()) AND friend_id = ANY(pg_temp.all_u()))
     OR EXISTS (SELECT 1 FROM invites WHERE inviter_id = ANY(pg_temp.all_u()) OR accepted_by = ANY(pg_temp.all_u()))
     OR to_regprocedure('public._server_checkin(uuid,date)') IS NULL THEN
    RAISE EXCEPTION 'fixture precondition failed';
  END IF;
  FOREACH fk IN ARRAY ARRAY['eq1', 'eq2', 'eq3', 'eq4'] LOOP
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

-- ═════════ Migration A ═════════
-- @@MIGRATION_A@@

-- ═════════ phase 2: new bodies ═════════
DO $probe$
DECLARE
  r text[] := ARRAY[]::text[];
  fk text; v jsonb; o jsonb; j jsonb; j2 jsonb; n text; ok boolean;
  a uuid; b uuid; c uuid; e uuid; f uuid; s uuid; s1 uuid; s2 uuid; t date; tz text; tm timestamptz;
  i1 uuid; i2 uuid; i3 uuid; np integer; ca integer; cb integer; xa integer; xb integer; k integer;
BEGIN
  -- ── C: permissions and catalog (permission probes first, before any privileged call) ──
  n := pg_temp.u(NULL, 'SELECT public.submit_checkin()::text', 'anon');
  r := r || pg_temp.ok('C1 anon cannot execute submit_checkin', n LIKE 'ERR:permission denied for function submit_checkin%', n);
  n := pg_temp.u(pg_temp.ua(), format('SELECT public._credit_checkin(%L, now())::text', pg_temp.ua()));
  r := r || pg_temp.ok('C2 authenticated cannot execute _credit_checkin', n LIKE 'ERR:permission denied for function _credit_checkin%', n);
  n := pg_temp.u(pg_temp.ua(), format('SELECT public._credit_day(%L, now())::text', pg_temp.ua()));
  r := r || pg_temp.ok('C3 authenticated cannot execute _credit_day', n LIKE 'ERR:permission denied for function _credit_day%', n);
  SELECT has_function_privilege('authenticated', p.oid, 'EXECUTE') AND NOT has_function_privilege('anon', p.oid, 'EXECUTE')
         AND p.proacl::text NOT LIKE '{=%' AND p.proacl::text NOT LIKE '%,=%' AND p.prosecdef AND p.proconfig = '{search_path=public}'
  INTO ok FROM pg_proc p WHERE p.oid = 'public.submit_checkin()'::regprocedure;
  r := r || pg_temp.ok('C4 submit_checkin: EXECUTE authenticated only (not PUBLIC/anon), SECURITY DEFINER, search_path=public', ok,
                       (SELECT proacl::text FROM pg_proc WHERE oid = 'public.submit_checkin()'::regprocedure));
  SELECT string_agg(p.oid::regprocedure::text || ' ' || p.proacl::text || ' ' || p.proconfig::text || ' secdef=' || p.prosecdef, '; ' ORDER BY p.proname),
         bool_and(p.proconfig = '{search_path=public}' AND p.proacl::text = CASE
           WHEN p.proname IN ('finish_checkin_session', 'create_invite_team') THEN '{postgres=X/postgres,authenticated=X/postgres,service_role=X/postgres}'
           WHEN p.proname = 'submit_checkin' THEN p.proacl::text
           ELSE '{postgres=X/postgres,service_role=X/postgres}' END)
  INTO n, ok FROM pg_proc p
  WHERE p.pronamespace = 'public'::regnamespace AND p.proname IN ('_credit_day', '_credit_checkin', 'finish_checkin_session', '_auto_credit',
        '_apply_checkin_rewards', 'submit_checkin', 'notify_buddy_checkin', 'create_invite_team', '_fulfil_invite_reward');
  r := r || pg_temp.ok('C5 ACLs and search_path of every new/replaced function', ok, n);
  r := r || pg_temp.ok('C6 _server_checkin dropped', to_regprocedure('public._server_checkin(uuid,date)') IS NULL);
  r := r || pg_temp.ok('C7 process_stale_sessions body unchanged, COMMENT points at _credit_day',
                       md5(pg_get_functiondef('public.process_stale_sessions(timestamptz)'::regprocedure)) = '929c250cf1b7e98ad9c9d593d786ba32'
                       AND obj_description('public.process_stale_sessions(timestamptz)'::regprocedure, 'pg_proc') LIKE '%_credit_day%');

  -- ── E: equivalence, new bodies on the phase-1 fixtures ──
  FOREACH fk IN ARRAY ARRAY['eq1', 'eq2', 'eq3', 'eq4'] LOOP
    BEGIN
      EXECUTE format('SELECT pg_temp.fx_%s()', fk) INTO v;
      RAISE EXCEPTION 'capture' USING ERRCODE = 'P0099', DETAIL = v::text;
    EXCEPTION WHEN SQLSTATE 'P0099' THEN
      GET STACKED DIAGNOSTICS n = PG_EXCEPTION_DETAIL;
      v := n::jsonb;
    END;
    SELECT x.v INTO o FROM eq_old x WHERE x.k = fk;
    IF fk <> 'eq4' THEN
      r := r || pg_temp.ok(format('E.%s new = old: return, check-in rows, streaks, xp/coin rows, profiles, logs, pushes', fk), v = o,
                           format('md5 old %s new %s', md5(o::text), md5(v::text)));
      r := r || ('     ' || fk || ' new: ' || v::text);
      IF v <> o THEN r := r || ('     ' || fk || ' old: ' || o::text); END IF;
    ELSE
      r := r || pg_temp.is('E.eq4 CAP-2 intended difference, today''s cap (old counts the created-today yesterday payout)',
                           format('old %s/%s new %s/%s', o#>>'{today,coins_awarded}', o#>>'{today,xp_awarded}', v#>>'{today,coins_awarded}', v#>>'{today,xp_awarded}'),
                           'old 5/5 new 10/10');
      r := r || pg_temp.is('E.eq4 CAP-2 intended difference, yesterday''s cap (new counts it by its yesterday suffix)',
                           format('old %s/%s new %s/%s', o#>>'{yesterday,coins_awarded}', o#>>'{yesterday,xp_awarded}', v#>>'{yesterday,coins_awarded}', v#>>'{yesterday,xp_awarded}'),
                           'old 10/10 new 5/5');
      r := r || pg_temp.ok('E.eq4 nothing else differs (rows, streaks, logs, pushes)',
                           (v#>'{snap,rows}') = (o#>'{snap,rows}') AND (v#>'{snap,streaks}') = (o#>'{snap,streaks}')
                           AND (v#>'{snap,logs}') = (o#>'{snap,logs}') AND (v#>'{snap,push}') = (o#>'{snap,push}'));
    END IF;
  END LOOP;

  -- ── Q1: friend check-in (FS-2/DI-9), copy time, push suppression, real Finish after a copy, idempotency ──
  BEGIN
    a := pg_temp.ua(); b := pg_temp.o3(); t := pg_temp.day(b); tm := now() - interval '3 hours';
    -- onboard_check3's real check-in, 3 hours ago, on its Coach Max team (fixture row; postgres insert).
    INSERT INTO daily_team_checkins (team_streak_id, user_id, check_in_date, check_in_time) VALUES (pg_temp.cms(b), b, t, tm);
    s := pg_temp.bt(a, b);  -- rokitest1 accepts the friendship: create_buddy_team
    np := pg_temp.npush(); cb := pg_temp.coins(b); xb := pg_temp.xp(b);
    j := pg_temp.sub(a);
    r := r || pg_temp.is('Q1.1 submit_checkin as rokitest1 (no row today): reason', j->>'reason', 'not_checked_in_today');
    r := r || pg_temp.ok('Q1.2 credited false, xp 0, coins 0', j->>'credited' = 'false' AND j->>'xp' = '0' AND j->>'coins' = '0', j::text);
    r := r || pg_temp.is('Q1.3 partner row created on the new team with the partner''s local date',
                         (SELECT check_in_date::text FROM daily_team_checkins WHERE team_streak_id = s AND user_id = b), t::text);
    SELECT check_in_time INTO tm FROM daily_team_checkins WHERE team_streak_id = s AND user_id = b;
    r := r || pg_temp.ok('Q1.4 copy check_in_time = source earliest time, not now() (pin trigger did not fire under the definer)',
                         tm = (SELECT min(check_in_time) FROM daily_team_checkins WHERE user_id = b AND check_in_date = t AND team_streak_id <> s)
                         AND tm <> now(), format('copy %s, now %s', tm, now()));
    r := r || pg_temp.ok('Q1.5 caller not copied (no real row today)', NOT EXISTS (SELECT 1 FROM daily_team_checkins WHERE user_id = a AND check_in_date = pg_temp.day(a)));
    r := r || pg_temp.is('Q1.6 the copy sent no push', (pg_temp.npush() - np)::text, '0');
    r := r || pg_temp.is('Q1.7 the copy paid nothing (partner coins/xp delta)', (pg_temp.coins(b) - cb) || '/' || (pg_temp.xp(b) - xb), '0/0');
    r := r || pg_temp.is('Q1.8 flag cleared when submit_checkin returns', coalesce(current_setting('app.checkin_copy', true), '<null>'), '');
    r := r || pg_temp.is('Q1.9 new team not advanced yet (caller missing): streak/total', (SELECT current_streak || '/' || total_workouts FROM team_streaks WHERE id = s), '0/0');
    PERFORM pg_temp.sess(a);
    np := pg_temp.npush(); ca := pg_temp.coins(a); cb := pg_temp.coins(b);
    j := pg_temp.fin(a);
    r := r || pg_temp.ok('Q1.10 a real Finish after the copy, same transaction, still pushes rokitest1 -> onboard_check3 on the new team',
                         EXISTS (SELECT 1 FROM pg_temp.push_log WHERE key = 'buddy_checked_in' AND recipient = b AND sender = a
                                 AND ref = (SELECT team_id::text FROM team_streaks WHERE id = s)),
                         (pg_temp.npush() - np) || ' buddy_checked_in pushes from this Finish');
    r := r || pg_temp.is('Q1.11 Finish completes the new team''s day: streak/total', (SELECT current_streak || '/' || total_workouts FROM team_streaks WHERE id = s), '1/1');
    r := r || pg_temp.is('Q1.12 Finish pays as before: rokitest1 +25 (Coach Max 10, team 15), onboard_check3 retro share +15',
                         (pg_temp.coins(a) - ca) || '/' || (pg_temp.coins(b) - cb), '25/15');
    np := pg_temp.npush(); ca := pg_temp.coins(a); cb := pg_temp.coins(b);
    k := (SELECT count(*) FROM daily_team_checkins WHERE user_id IN (a, b));
    j := pg_temp.sub(a);
    r := r || pg_temp.is('Q1.13 second submit_checkin the same day: reason', j->>'reason', 'already_checked_in');
    r := r || pg_temp.is('Q1.14 second call: rows, coins, pushes unchanged',
                         ((SELECT count(*) FROM daily_team_checkins WHERE user_id IN (a, b)) - k) || '/' || (pg_temp.coins(a) - ca) || '/' || (pg_temp.coins(b) - cb) || '/' || (pg_temp.npush() - np),
                         '0/0/0/0');
    j2 := pg_temp.fin(a);
    r := r || pg_temp.is('Q1.15 second Finish the same day: result, coins delta', (j2->>'result') || '/' || (pg_temp.coins(a) - ca), 'nothing_to_finish/0');
    r := r || pg_temp.ok('Q1.16 submit_checkin return shape', j ?& ARRAY['credited', 'reason', 'credit_date', 'streak', 'xp', 'coins', 'teams'] AND NOT j ? 'milestones_unlocked', j::text);
    RAISE EXCEPTION 'undo' USING ERRCODE = 'P0098';
  EXCEPTION WHEN SQLSTATE 'P0098' THEN NULL;
            WHEN OTHERS THEN r := r || ('FAIL Q1 crashed: ' || SQLERRM);
  END;

  -- ── Q2: UTC versus local date (FS-1), member with no real row today not copied ──
  BEGIN
    c := pg_temp.uc(); e := pg_temp.o6(); f := pg_temp.o4();
    tz := CASE WHEN extract(hour FROM now() AT TIME ZONE 'UTC') >= 10 THEN 'Pacific/Kiritimati' ELSE 'Pacific/Pago_Pago' END;
    UPDATE user_profiles SET timezone = tz WHERE id = e;
    r := r || pg_temp.ok('Q2.0 fixture: onboard_check6 local date differs from the UTC date', pg_temp.day(e) <> (now() AT TIME ZONE 'UTC')::date,
                         format('%s %s vs UTC %s', tz, pg_temp.day(e), (now() AT TIME ZONE 'UTC')::date));
    PERFORM pg_temp.sess(e);
    j := pg_temp.fin(e);
    r := r || pg_temp.is('Q2.1 Finish credit_date = the member''s local date', j->>'credit_date', pg_temp.day(e)::text);
    INSERT INTO daily_team_checkins (team_streak_id, user_id, check_in_date, check_in_time)
    VALUES (pg_temp.cms(f), f, pg_temp.day(f) - 1, now() - interval '1 day');  -- onboard_check4: a row yesterday only
    s1 := pg_temp.bt(c, e);
    s2 := pg_temp.bt(c, f);
    j := pg_temp.sub(c);
    r := r || pg_temp.is('Q2.2 submit_checkin as testtest1 (no row today): reason', j->>'reason', 'not_checked_in_today');
    r := r || pg_temp.is('Q2.3 onboard_check6 copied with its own local date, not the UTC date',
                         (SELECT check_in_date::text FROM daily_team_checkins WHERE team_streak_id = s1 AND user_id = e), pg_temp.day(e)::text);
    r := r || pg_temp.ok('Q2.4 onboard_check4 (no real row today, only yesterday) not copied anywhere',
                         NOT EXISTS (SELECT 1 FROM daily_team_checkins WHERE user_id = f AND (team_streak_id = s2 OR check_in_date >= pg_temp.day(f))));
    r := r || pg_temp.ok('Q2.5 testtest1 not copied', NOT EXISTS (SELECT 1 FROM daily_team_checkins WHERE user_id = c AND team_streak_id IN (s1, s2)));
    RAISE EXCEPTION 'undo' USING ERRCODE = 'P0098';
  EXCEPTION WHEN SQLSTATE 'P0098' THEN NULL;
            WHEN OTHERS THEN r := r || ('FAIL Q2 crashed: ' || SQLERRM);
  END;

  -- ── Q3: copies of the caller and the partner complete a new team's day, pay nothing, push nothing ──
  BEGIN
    a := pg_temp.ua(); f := pg_temp.o4();
    PERFORM pg_temp.sess(a); j := pg_temp.fin(a);
    PERFORM pg_temp.sess(f); j := pg_temp.fin(f);
    s := pg_temp.bt(a, f);
    np := pg_temp.npush(); ca := pg_temp.coins(a); cb := pg_temp.coins(f); xa := pg_temp.xp(a); xb := pg_temp.xp(f);
    j := pg_temp.sub(a);
    r := r || pg_temp.ok('Q3.1 reason credited, credited true, xp 0, coins 0',
                         j->>'reason' = 'credited' AND j->>'credited' = 'true' AND j->>'xp' = '0' AND j->>'coins' = '0', j::text);
    r := r || pg_temp.is('Q3.2 both members copied onto the new team', (SELECT count(*)::text FROM daily_team_checkins WHERE team_streak_id = s), '2');
    r := r || pg_temp.is('Q3.3 copies complete the day: streak/total, return marks the team updated',
                         (SELECT current_streak || '/' || total_workouts FROM team_streaks WHERE id = s) || '/' ||
                         (SELECT te->>'updated' FROM jsonb_array_elements(j->'teams') te WHERE (te->>'streak_id')::uuid = s), '1/1/true');
    r := r || pg_temp.is('Q3.4 copies paid nothing: coins and xp deltas',
                         (pg_temp.coins(a) - ca) || '/' || (pg_temp.coins(f) - cb) || '/' || (pg_temp.xp(a) - xa) || '/' || (pg_temp.xp(f) - xb), '0/0/0/0');
    r := r || pg_temp.is('Q3.5 copies pushed nothing', (pg_temp.npush() - np)::text, '0');
    r := r || pg_temp.ok('Q3.6 each copy keeps its member''s earliest real check_in_time',
                         NOT EXISTS (SELECT 1 FROM daily_team_checkins d WHERE d.team_streak_id = s AND d.check_in_time <>
                                     (SELECT min(x.check_in_time) FROM daily_team_checkins x WHERE x.user_id = d.user_id AND x.check_in_date = d.check_in_date AND x.team_streak_id <> s)));
    RAISE EXCEPTION 'undo' USING ERRCODE = 'P0098';
  EXCEPTION WHEN SQLSTATE 'P0098' THEN NULL;
            WHEN OTHERS THEN r := r || ('FAIL Q3 crashed: ' || SQLERRM);
  END;

  -- ── CAP: daily cap by credit day (exact reference_id suffix) ──
  b := pg_temp.o2(); s := pg_temp.cms(b); t := pg_temp.day(b);
  BEGIN
    PERFORM pg_temp.capfx(b, 'fx:' || (t - 1), 95, 995);
    j := public._apply_checkin_rewards(b, s, t - 1);
    r := r || pg_temp.is('CAP.1 yesterday''s cap counts yesterday-suffixed payouts: coins/xp/capped',
                         (j->>'coins_awarded') || '/' || (j->>'xp_awarded') || '/' || (j->>'daily_cap_reached'), '5/5/true');
    RAISE EXCEPTION 'undo' USING ERRCODE = 'P0098';
  EXCEPTION WHEN SQLSTATE 'P0098' THEN NULL; WHEN OTHERS THEN r := r || ('FAIL CAP.1 crashed: ' || SQLERRM);
  END;
  BEGIN
    PERFORM pg_temp.capfx(b, 'fx:' || t, 95, 995);
    j := public._apply_checkin_rewards(b, s, t);
    r := r || pg_temp.is('CAP.2 today''s cap counts today-suffixed payouts: coins/xp/capped',
                         (j->>'coins_awarded') || '/' || (j->>'xp_awarded') || '/' || (j->>'daily_cap_reached'), '5/5/true');
    RAISE EXCEPTION 'undo' USING ERRCODE = 'P0098';
  EXCEPTION WHEN SQLSTATE 'P0098' THEN NULL; WHEN OTHERS THEN r := r || ('FAIL CAP.2 crashed: ' || SQLERRM);
  END;
  BEGIN
    PERFORM pg_temp.capfx(b, 'legacy-no-suffix', 95, 995);
    PERFORM pg_temp.capfx(b, NULL, 95, 995);
    PERFORM pg_temp.capfx(b, 'fx:' || t || 'x', 95, 995);
    j := public._apply_checkin_rewards(b, s, t);
    r := r || pg_temp.is('CAP.3 legacy reference (no suffix, NULL, or a near-miss suffix) is not counted: coins/xp/capped',
                         (j->>'coins_awarded') || '/' || (j->>'xp_awarded') || '/' || (j->>'daily_cap_reached'), '10/10/false');
    RAISE EXCEPTION 'undo' USING ERRCODE = 'P0098';
  EXCEPTION WHEN SQLSTATE 'P0098' THEN NULL; WHEN OTHERS THEN r := r || ('FAIL CAP.3 crashed: ' || SQLERRM);
  END;
  BEGIN
    -- A payout created today for a workout that started yesterday at 23:50 (Finish after midnight).
    PERFORM pg_temp.capfx(b, 'fx:' || (t - 1), 95, 995);
    j := public._apply_checkin_rewards(b, s, t);
    j2 := public._apply_checkin_rewards(b, s, t - 1);
    r := r || pg_temp.is('CAP.4 straddling midnight: counts for yesterday (capped), not for today: today/yesterday coins',
                         (j->>'coins_awarded') || '/' || (j2->>'coins_awarded'), '10/5');
    RAISE EXCEPTION 'undo' USING ERRCODE = 'P0098';
  EXCEPTION WHEN SQLSTATE 'P0098' THEN NULL; WHEN OTHERS THEN r := r || ('FAIL CAP.4 crashed: ' || SQLERRM);
  END;
  FOREACH n IN ARRAY ARRAY['today', 'yesterday'] LOOP
    BEGIN
      f := pg_temp.o4();
      s1 := pg_temp.team(b, f);
      INSERT INTO daily_team_checkins (team_streak_id, user_id, check_in_date, check_in_time) VALUES (s1, b, t, now()), (s1, f, t, now());
      PERFORM pg_temp.capfx(f, 'fx:' || CASE WHEN n = 'today' THEN t ELSE t - 1 END, 95, 0);
      cb := pg_temp.coins(f);
      j := public._apply_checkin_rewards(b, s1, t);
      r := r || pg_temp.is(format('CAP.5 teammate cap by credit day, teammate has 95 coins suffixed %s: teammate paid (10 base + 5 co-op, capped)', n),
                           (pg_temp.coins(f) - cb)::text, CASE WHEN n = 'today' THEN '5' ELSE '15' END);
      RAISE EXCEPTION 'undo' USING ERRCODE = 'P0098';
    EXCEPTION WHEN SQLSTATE 'P0098' THEN NULL; WHEN OTHERS THEN r := r || ('FAIL CAP.5 crashed: ' || SQLERRM);
    END;
  END LOOP;

  -- ── F3: invitee bonus once per account, on the first credited row ──
  BEGIN
    a := pg_temp.ua(); c := pg_temp.uc(); e := pg_temp.o1(); b := pg_temp.o2();
    INSERT INTO invites (inviter_id, status, created_at, accepted_at, accepted_by)
    VALUES (c, 'accepted', (SELECT created_at FROM auth.users WHERE id = e) - interval '1 minute', now(), e) RETURNING id INTO i1;
    n := pg_temp.u(e, format('SELECT public.create_invite_team(%L, %L)::text', c, e));
    r := r || pg_temp.ok('F3.1 create_invite_team for a new invitee pays nothing at join', n NOT LIKE 'ERR:%' AND pg_temp.nbonus(e) = '0/0', n || ' bonus ' || pg_temp.nbonus(e));
    PERFORM pg_temp.sess(e); j := pg_temp.fin(e);
    r := r || pg_temp.is('F3.2 first credited day pays once (Finish wrote 2 rows): count/amount/reference = the invite',
                         pg_temp.nbonus(e) || '/' || (SELECT max(reference_id) FROM coin_transactions WHERE user_id = e AND transaction_type = 'invite_bonus'),
                         '1/20/' || i1);
    INSERT INTO daily_team_checkins (team_streak_id, user_id, check_in_date, check_in_time)
    VALUES (pg_temp.cms(e), e, pg_temp.day(e) - 1, now() - interval '1 day');
    r := r || pg_temp.is('F3.3 a credited row on another day pays nothing more', pg_temp.nbonus(e), '1/20');
    INSERT INTO invites (inviter_id, status, created_at, accepted_at, accepted_by)
    VALUES (b, 'accepted', (SELECT created_at FROM auth.users WHERE id = e) - interval '1 minute', now(), e) RETURNING id INTO i2;
    n := pg_temp.u(e, format('SELECT public.create_invite_team(%L, %L)::text', b, e));
    j := pg_temp.sub(e);
    r := r || pg_temp.is('F3.4 second inviter, then a copied row lands: still one bonus (copy reason, bonus)', (j->>'reason') || ' ' || pg_temp.nbonus(e), 'credited 1/20');
    INSERT INTO invites (inviter_id, status, accepted_at, accepted_by) VALUES (c, 'accepted', now(), a) RETURNING id INTO i3;
    n := pg_temp.u(a, format('SELECT public.create_invite_team(%L, %L)::text', c, a));
    PERFORM pg_temp.sess(a); j := pg_temp.fin(a);
    r := r || pg_temp.is('F3.5 an existing account (created before the invite) is never paid', pg_temp.nbonus(a), '0/0');
    r := r || ('     inviter rewards (unchanged rule, >= 2 distinct check-in days): testtest1 '
               || (SELECT count(*) FROM coin_transactions WHERE user_id = c AND transaction_type = 'invite_reward') || ', onboard_check2 '
               || (SELECT count(*) FROM coin_transactions WHERE user_id = b AND transaction_type = 'invite_reward'));
    RAISE EXCEPTION 'undo' USING ERRCODE = 'P0098';
  EXCEPTION WHEN SQLSTATE 'P0098' THEN NULL;
            WHEN OTHERS THEN r := r || ('FAIL F3 crashed: ' || SQLERRM);
  END;

  -- ── B: Migration B simulated (REVOKE inside this transaction) ──
  BEGIN
    e := pg_temp.o6();
    n := pg_temp.u(e, format('INSERT INTO public.daily_team_checkins (team_streak_id, user_id, check_in_date, check_in_time) '
                             'VALUES (%L, %L, %L, %L) RETURNING check_in_date || ''|'' || (check_in_time = now())',
                             pg_temp.cms(e), e, '2020-01-01', '2020-01-01 10:00+00'));
    r := r || pg_temp.is('B.1 before B the installed build''s direct insert still works and is pinned (date|time = now())', n, pg_temp.day(e) || '|true');
    REVOKE INSERT ON public.daily_team_checkins FROM authenticated;
    r := r || pg_temp.ok('B.2 after REVOKE: no table or column INSERT left for authenticated',
                         NOT has_any_column_privilege('authenticated', 'public.daily_team_checkins', 'INSERT'));
    n := pg_temp.u(pg_temp.o3(), format('INSERT INTO public.daily_team_checkins (team_streak_id, user_id) VALUES (%L, %L) RETURNING 1',
                                        pg_temp.cms(pg_temp.o3()), pg_temp.o3()));
    r := r || pg_temp.ok('B.3 direct insert denied', n LIKE 'ERR:permission denied for table daily_team_checkins%', n);
    j := pg_temp.sub(e);
    r := r || pg_temp.is('B.4 submit_checkin still works after the REVOKE (definer)', j->>'reason', 'already_checked_in');
    RAISE EXCEPTION 'undo' USING ERRCODE = 'P0098';
  EXCEPTION WHEN SQLSTATE 'P0098' THEN NULL;
            WHEN OTHERS THEN r := r || ('FAIL B crashed: ' || SQLERRM);
  END;

  RAISE EXCEPTION E'PROBE_RESULTS\n%', array_to_string(r, E'\n');
END
$probe$;
ROLLBACK;
