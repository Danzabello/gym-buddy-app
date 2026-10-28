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
-- Single server check-in RPC. Design: docs/hygiene/checkin_rpc_design.md. Report: docs/hygiene/checkin_rpc_report.md.
-- Rollback: docs/rollback_20261028230000.sql. Additive: the installed build's direct inserts keep working until Migration B.

-- The one credit-day formula (Q7).
CREATE OR REPLACE FUNCTION public._credit_day(p_user_id uuid, p_at timestamp with time zone)
 RETURNS date
 LANGUAGE sql
 STABLE
 SET search_path TO 'public'
AS $function$
  -- The credit-day formula: the user's local date at p_at. Every credit path
  -- takes its day from here. process_stale_sessions repeats this formula
  -- inline in its "already credited?" guards (see its COMMENT): keep them equal.
  SELECT (p_at AT TIME ZONE public.safe_user_tz(p_user_id))::date;
$function$;

-- The one internal credit path, replacing _server_checkin (same loop and body).
-- p_at: the moment the credit belongs to; the day comes only from _credit_day.
-- p_time: stored check_in_time (a copy keeps its source's time). p_pay = false
-- skips rewards (copies pay nothing). p_streak_id limits it to one team.
CREATE OR REPLACE FUNCTION public._credit_checkin(p_user_id uuid, p_at timestamp with time zone, p_pay boolean DEFAULT true, p_time timestamp with time zone DEFAULT now(), p_streak_id uuid DEFAULT NULL::uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SET search_path TO 'public'
AS $function$
DECLARE
  t record;
  v_coach_max_id constant uuid := '00000000-0000-0000-0000-000000000001';
  v_day date := public._credit_day(p_user_id, p_at);
  v_rc jsonb;
  v_rw jsonb;
  v_teams jsonb := '[]'::jsonb;
  v_xp integer := 0;
  v_coins integer := 0;
BEGIN
  -- Same as BreakDayService.cancelBreakDay: working out cancels today's break.
  UPDATE break_day_usage SET cancelled_at = now()
  WHERE user_id = p_user_id AND break_date = v_day AND cancelled_at IS NULL;

  FOR t IN
    SELECT ts.id, ts.team_id, bt.is_coach_max_team
    FROM team_streaks ts
    JOIN team_members tm ON tm.team_id = ts.team_id
    JOIN buddy_teams bt ON bt.id = ts.team_id
    WHERE tm.user_id = p_user_id AND ts.is_active = true
      AND (p_streak_id IS NULL OR ts.id = p_streak_id)
  LOOP
    INSERT INTO daily_team_checkins (team_streak_id, user_id, check_in_date, check_in_time)
    VALUES (t.id, p_user_id, v_day, p_time)
    ON CONFLICT (team_streak_id, user_id, check_in_date) DO NOTHING;
    CONTINUE WHEN NOT FOUND;

    v_rc := public._recompute_team_streak(t.id, v_day);
    IF (v_rc->>'updated')::boolean AND p_pay THEN
      v_rw := public._apply_checkin_rewards(p_user_id, t.id, v_day);
      v_xp := v_xp + COALESCE((v_rw->>'xp_awarded')::integer, 0);
      v_coins := v_coins + COALESCE((v_rw->>'coins_awarded')::integer, 0);
    END IF;

    IF t.is_coach_max_team AND NOT EXISTS (
      SELECT 1 FROM daily_team_checkins
      WHERE team_streak_id = t.id AND user_id = v_coach_max_id AND check_in_date = v_day
    ) THEN
      PERFORM public._finish_coach_max_checkin(t.id, p_user_id, v_day);
    END IF;

    v_teams := v_teams || jsonb_build_object(
      'streak_id', t.id, 'team_id', t.team_id,
      'updated', COALESCE((v_rc->>'updated')::boolean, false),
      'new_streak', (SELECT current_streak FROM team_streaks WHERE id = t.id));
  END LOOP;

  RETURN jsonb_build_object('credit_date', v_day, 'teams', v_teams, 'xp', v_xp, 'coins', v_coins);
END;
$function$;

-- finish_checkin_session: credit day and credits through the shared functions. Body otherwise unchanged.
CREATE OR REPLACE FUNCTION public.finish_checkin_session(p_workout_id uuid DEFAULT NULL::uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_uid uuid := auth.uid();
  v_tz text;
  v_start timestamptz;
  v_day date;
  v_level_before integer;
  v_level_after integer;
  v_on_break boolean;
  v_before jsonb;
  v_teams jsonb;
  v_checked_in integer;
  v_wk record;
  v_partner uuid;
  v_pday date;
  v_partner_before integer;
  v_partner_n integer := 0;
  v_sess_ok boolean := false;
  v_wk_ok boolean := false;
  v_sess_early boolean := false;
BEGIN
  IF v_uid IS NULL THEN
    RAISE EXCEPTION 'unauthenticated';
  END IF;
  v_tz := public.safe_user_tz(v_uid);

  -- FIN-1: credit only (a) an eligible own session or (b) an eligible
  -- workout participation; anything else is a no-op that writes nothing.
  -- (a) own session: start pinned by the server, at least 15 minutes and at
  --     most 3h30 ago, and not tied to a workout the caller left or cancelled.
  --     Under 15 minutes it is too_early.
  SELECT COALESCE(w.workout_started_at, s.started_at),
         COALESCE(w.workout_started_at, s.started_at) BETWEEN now() - interval '210 minutes' AND now()
           AND NOT COALESCE(CASE WHEN v_uid = w.user_id THEN w.creator_cancelled ELSE w.buddy_cancelled END, false)
  INTO v_start, v_sess_ok
  FROM active_checkin_sessions s
  LEFT JOIN workouts w ON w.id = s.workout_id AND v_uid IN (w.user_id, w.buddy_id)
  WHERE s.user_id = v_uid
  FOR UPDATE OF s;
  v_sess_early := COALESCE(v_sess_ok AND v_start > now() - interval '15 minutes', false);
  v_sess_ok := COALESCE(v_sess_ok AND NOT v_sess_early, false);

  -- (b) participant of a started workout who has not left or cancelled, past
  --     the 15-minute floor: in progress and started within 3h30, or completed
  --     (by a person, not the cron) within 3h40 of its start (M3 grace),
  --     whenever Finish arrives; start day inside the reward window
  --     [today-1, today].
  IF p_workout_id IS NOT NULL THEN
    SELECT * INTO v_wk FROM workouts
    WHERE id = p_workout_id AND v_uid IN (user_id, buddy_id)
      AND workout_started_at <= now()
      AND (workout_started_at AT TIME ZONE v_tz)::date >= (now() AT TIME ZONE v_tz)::date - 1
      AND CASE WHEN status = 'completed'
               THEN workout_completed_at <= workout_started_at + interval '220 minutes'
                    AND NOT COALESCE(auto_completed, false)
               ELSE workout_started_at >= now() - interval '210 minutes' END
      AND status IN ('in_progress', 'completed')
      AND NOT COALESCE(CASE WHEN v_uid = user_id THEN creator_cancelled ELSE buddy_cancelled END, false)
      AND CASE WHEN status = 'completed' THEN COALESCE(actual_duration_minutes, 0) >= 15
               ELSE now() - workout_started_at >= interval '15 minutes' END;
    v_wk_ok := FOUND;
  END IF;

  IF NOT (v_sess_ok OR v_wk_ok) THEN
    RETURN jsonb_build_object(
      'result', CASE WHEN v_sess_early THEN 'too_early' ELSE 'nothing_to_finish' END,
      'credit_date', (now() AT TIME ZONE v_tz)::date,
      'checked_in', 0, 'break_cancelled', false, 'did_level_up', false,
      'new_level', COALESCE((SELECT level FROM user_profiles WHERE id = v_uid), 1),
      'teams', '[]'::jsonb, 'partner_checked_in', 0);
  END IF;

  IF NOT v_sess_ok THEN
    v_start := v_wk.workout_started_at;
  END IF;
  v_day := public._credit_day(v_uid, v_start);

  SELECT level INTO v_level_before FROM user_profiles WHERE id = v_uid;
  v_on_break := EXISTS (SELECT 1 FROM break_day_usage
                        WHERE user_id = v_uid AND break_date = v_day AND cancelled_at IS NULL);
  SELECT jsonb_object_agg(ts.id, jsonb_build_object(
           'total', ts.total_workouts, 'best', ts.best_streak,
           'in', EXISTS (SELECT 1 FROM daily_team_checkins d
                         WHERE d.team_streak_id = ts.id AND d.user_id = v_uid AND d.check_in_date = v_day)))
  INTO v_before
  FROM team_streaks ts JOIN team_members tm ON tm.team_id = ts.team_id
  WHERE tm.user_id = v_uid AND ts.is_active = true;

  PERFORM public._credit_checkin(v_uid, v_start);
  DELETE FROM active_checkin_sessions WHERE user_id = v_uid;

  -- M6a (owner rule 2026-10-02): in a buddy workout, the other participant
  -- who confirmed ready and has not cancelled is "in", session or not. Only
  -- when the caller is a participant and the workout started at most 3h30
  -- ago; credited to the partner's own local start day; idempotent through
  -- UNIQUE per team/user/day. Runs before the caller's results are read, so
  -- a shared streak the partner completes shows as advanced to the caller.
  -- FIN-1: only through a finisher eligible under (b) above, so a leaver
  -- never triggers it; v_wk is that workout (started, inside its window).
  IF v_wk_ok THEN
    IF v_wk.buddy_id IS NOT NULL AND v_wk.buddy_id <> v_wk.user_id THEN
      v_partner := CASE WHEN v_uid = v_wk.user_id THEN v_wk.buddy_id ELSE v_wk.user_id END;
      IF (v_partner = v_wk.user_id AND v_wk.creator_ready AND NOT v_wk.creator_cancelled)
         OR (v_partner = v_wk.buddy_id AND v_wk.buddy_ready AND NOT v_wk.buddy_cancelled) THEN
        v_pday := public._credit_day(v_partner, v_wk.workout_started_at);
        SELECT count(*) INTO v_partner_before FROM daily_team_checkins
        WHERE user_id = v_partner AND check_in_date = v_pday;
        PERFORM public._credit_checkin(v_partner, v_wk.workout_started_at);
        DELETE FROM active_checkin_sessions WHERE user_id = v_partner AND workout_id = p_workout_id;
        SELECT count(*) - v_partner_before INTO v_partner_n FROM daily_team_checkins
        WHERE user_id = v_partner AND check_in_date = v_pday;
      END IF;
    END IF;
  END IF;

  SELECT level INTO v_level_after FROM user_profiles WHERE id = v_uid;
  SELECT COALESCE(jsonb_agg(jsonb_build_object(
           'streak_id', ts.id, 'team_id', ts.team_id, 'is_coach_max_team', bt.is_coach_max_team,
           'updated', ts.total_workouts IS DISTINCT FROM (v_before->ts.id::text->>'total')::integer,
           'new_streak', ts.current_streak,
           'old_best_streak', COALESCE((v_before->ts.id::text->>'best')::integer, 0),
           'new_best_streak', ts.best_streak)), '[]'::jsonb),
         count(*) FILTER (WHERE NOT COALESCE((v_before->ts.id::text->>'in')::boolean, false)
                            AND EXISTS (SELECT 1 FROM daily_team_checkins d
                                        WHERE d.team_streak_id = ts.id AND d.user_id = v_uid AND d.check_in_date = v_day))
  INTO v_teams, v_checked_in
  FROM team_streaks ts
  JOIN team_members tm ON tm.team_id = ts.team_id
  JOIN buddy_teams bt ON bt.id = ts.team_id
  WHERE tm.user_id = v_uid AND ts.is_active = true;

  RETURN jsonb_build_object(
    'credit_date', v_day,
    'checked_in', v_checked_in,
    'break_cancelled', v_on_break AND NOT EXISTS (SELECT 1 FROM break_day_usage
                         WHERE user_id = v_uid AND break_date = v_day AND cancelled_at IS NULL),
    'did_level_up', COALESCE(v_level_after, 1) > COALESCE(v_level_before, 1),
    'new_level', COALESCE(v_level_after, 1),
    'teams', v_teams,
    'partner_checked_in', v_partner_n);
END;
$function$;

-- _auto_credit (process_stale_sessions' credit step): same.
CREATE OR REPLACE FUNCTION public._auto_credit(p_user uuid, p_start timestamp with time zone, p_goal integer, p_type text, p_emoji text)
 RETURNS boolean
 LANGUAGE plpgsql
 SET search_path TO 'public'
AS $function$
DECLARE
  v_day date := public._credit_day(p_user, p_start);
BEGIN
  IF EXISTS (SELECT 1 FROM workout_logs
             WHERE user_id = p_user AND auto_completed AND workout_date = v_day) THEN
    RETURN false;
  END IF;
  PERFORM public._credit_checkin(p_user, p_start);
  INSERT INTO workout_logs (user_id, workout_date, workout_time, workout_name, workout_category,
                            workout_emoji, planned_duration_minutes, actual_duration_minutes, auto_completed)
  VALUES (p_user, v_day, p_start + make_interval(mins => p_goal), p_type,
          COALESCE((SELECT category FROM workout_templates WHERE name = p_type LIMIT 1), 'other'),
          COALESCE(p_emoji, '💪'), p_goal, p_goal, true);
  RETURN true;
END;
$function$;

DROP FUNCTION public._server_checkin(uuid, date);

COMMENT ON FUNCTION public.process_stale_sessions(timestamp with time zone) IS 'Its inline (start AT TIME ZONE safe_user_tz(u))::date "already credited?" guards must stay equal to public._credit_day(), the credit-day formula _auto_credit uses.';

-- CAP-2: the daily cap counts payouts by credit day (reference_id suffix), not by creation day.
CREATE OR REPLACE FUNCTION public._apply_checkin_rewards(p_user_id uuid, p_streak_id uuid, p_check_in_date date)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_ref text := p_streak_id::text || ':' || p_check_in_date::text;
  v_current_streak integer;
  v_xp integer := 10;
  v_coins integer := 10;
  v_coop_xp integer := 5;
  v_coop_coins integer := 5;
  v_milestone_xp integer := 0;
  v_milestone_coins integer := 0;
  v_reasons jsonb := '[]'::jsonb;
  v_partner_checked_in boolean := false;
  v_teammate record;
  v_coach_max_id uuid := '00000000-0000-0000-0000-000000000001';
  v_old_level integer;
  v_new_level integer;
  v_daily_cap_xp constant integer := 1000;
  v_daily_cap_coins constant integer := 100;
  v_already_xp integer;
  v_already_coins integer;
  v_capped boolean := false;
BEGIN
  -- One payout run per (streak, day) at a time, so the existence checks
  -- below cannot race a concurrent run for a teammate.
  PERFORM pg_advisory_xact_lock(hashtext('checkin_rewards:' || v_ref));

  IF EXISTS (
    SELECT 1 FROM xp_transactions
    WHERE user_id = p_user_id AND reference_id = v_ref
  ) THEN
    RETURN jsonb_build_object('already_awarded', true);
  END IF;

  SELECT level INTO v_old_level FROM user_profiles WHERE id = p_user_id;
  v_old_level := COALESCE(v_old_level, 1);

  SELECT current_streak INTO v_current_streak FROM team_streaks WHERE id = p_streak_id;
  v_current_streak := COALESCE(v_current_streak, 1);

  SELECT EXISTS (
    SELECT 1 FROM daily_team_checkins
    WHERE team_streak_id = p_streak_id
      AND check_in_date = p_check_in_date
      AND user_id <> p_user_id
      AND user_id <> v_coach_max_id
  ) INTO v_partner_checked_in;

  IF v_partner_checked_in THEN
    v_xp := v_xp + v_coop_xp;
    v_coins := v_coins + v_coop_coins;
    v_reasons := v_reasons || jsonb_build_array('coop_bonus');
  END IF;

  -- Milestone amounts hoisted so the retro teammate loop can reuse them
  -- (same v_current_streak, same call -> symmetric by construction).
  IF v_current_streak = 7 THEN
    v_milestone_xp := 50; v_milestone_coins := 50;
    v_reasons := v_reasons || jsonb_build_array('milestone_7');
  ELSIF v_current_streak = 30 THEN
    v_milestone_xp := 50; v_milestone_coins := 100;
    v_reasons := v_reasons || jsonb_build_array('milestone_30');
  ELSIF v_current_streak = 100 THEN
    v_milestone_xp := 50; v_milestone_coins := 250;
    v_reasons := v_reasons || jsonb_build_array('milestone_100');
  END IF;
  v_xp := v_xp + v_milestone_xp;
  v_coins := v_coins + v_milestone_coins;

  -- Daily cap for the primary user, counted by credit day: the date after the
  -- last colon of reference_id (streak:day), not the day the row was created (CAP-2).
  SELECT COALESCE(SUM(amount), 0) INTO v_already_xp
  FROM xp_transactions
  WHERE user_id = p_user_id
    AND transaction_type = 'xp_award' AND description IN ('daily_checkin', 'partner_bonus')
    AND substring(reference_id from '[^:]*$') = p_check_in_date::text;

  SELECT COALESCE(SUM(amount), 0) INTO v_already_coins
  FROM coin_transactions
  WHERE user_id = p_user_id
    AND transaction_type IN ('daily_checkin', 'partner_bonus')
    AND substring(reference_id from '[^:]*$') = p_check_in_date::text;

  IF v_already_xp + v_xp > v_daily_cap_xp THEN
    v_xp := GREATEST(0, v_daily_cap_xp - v_already_xp);
    v_capped := true;
  END IF;
  IF v_already_coins + v_coins > v_daily_cap_coins THEN
    v_coins := GREATEST(0, v_daily_cap_coins - v_already_coins);
    v_capped := true;
  END IF;

  PERFORM award_xp(p_user_id, v_xp, 'daily_checkin', v_ref);
  PERFORM award_coins(p_user_id, v_coins, 'daily_checkin', 'Daily check-in rewards', v_ref);

  SELECT level INTO v_new_level FROM user_profiles WHERE id = p_user_id;

  IF v_partner_checked_in THEN
    FOR v_teammate IN
      SELECT DISTINCT dtc.user_id
      FROM daily_team_checkins dtc
      WHERE dtc.team_streak_id = p_streak_id
        AND dtc.check_in_date = p_check_in_date
        AND dtc.user_id <> p_user_id
        AND dtc.user_id <> v_coach_max_id
    LOOP
      DECLARE
        -- Owed-checks: each entitlement deduped by its own kind + reference_id
        -- (XP rows carry the kind in description, coin rows in transaction_type).
        v_t_owed_base boolean;
        v_t_owed_coop boolean;
        v_t_already_xp integer;
        v_t_already_coins integer;
        v_t_base_xp integer := 0;
        v_t_base_coins integer := 0;
        v_t_coop_xp integer := 0;
        v_t_coop_coins integer := 0;
        v_t_room_xp integer;
        v_t_room_coins integer;
      BEGIN
        v_t_owed_base := NOT EXISTS (
          SELECT 1 FROM xp_transactions
          WHERE user_id = v_teammate.user_id
            AND transaction_type = 'xp_award' AND description = 'daily_checkin'
            AND reference_id = v_ref
        );
        v_t_owed_coop := NOT EXISTS (
          SELECT 1 FROM coin_transactions
          WHERE user_id = v_teammate.user_id
            AND transaction_type = 'partner_bonus'
            AND reference_id = v_ref
        );

        IF v_t_owed_base OR v_t_owed_coop THEN
          -- 10/10 base matches the primary's v_xp/v_coins initialisers;
          -- milestone shares the hoisted amounts from this same call.
          IF v_t_owed_base THEN
            v_t_base_xp := 10 + v_milestone_xp;
            v_t_base_coins := 10 + v_milestone_coins;
          END IF;
          IF v_t_owed_coop THEN
            v_t_coop_xp := v_coop_xp;
            v_t_coop_coins := v_coop_coins;
          END IF;

          -- Teammate's cap window: the same credit day (CAP-2).
          SELECT COALESCE(SUM(amount), 0) INTO v_t_already_xp
          FROM xp_transactions
          WHERE user_id = v_teammate.user_id
            AND transaction_type = 'xp_award' AND description IN ('daily_checkin', 'partner_bonus')
            AND substring(reference_id from '[^:]*$') = p_check_in_date::text;

          SELECT COALESCE(SUM(amount), 0) INTO v_t_already_coins
          FROM coin_transactions
          WHERE user_id = v_teammate.user_id
            AND transaction_type IN ('daily_checkin', 'partner_bonus')
            AND substring(reference_id from '[^:]*$') = p_check_in_date::text;

          -- Cap the combined owed amount: base takes the remaining room
          -- first, co-op whatever is left after that.
          v_t_room_xp := GREATEST(0, v_daily_cap_xp - v_t_already_xp);
          v_t_room_coins := GREATEST(0, v_daily_cap_coins - v_t_already_coins);
          v_t_base_xp := LEAST(v_t_base_xp, v_t_room_xp);
          v_t_base_coins := LEAST(v_t_base_coins, v_t_room_coins);
          v_t_coop_xp := LEAST(v_t_coop_xp, v_t_room_xp - v_t_base_xp);
          v_t_coop_coins := LEAST(v_t_coop_coins, v_t_room_coins - v_t_base_coins);

          -- Award each owed part even when capped to 0: the ref-tagged txn
          -- is what marks the entitlement as covered for future dedup.
          IF v_t_owed_base THEN
            PERFORM award_xp(v_teammate.user_id, v_t_base_xp, 'daily_checkin', v_ref);
            PERFORM award_coins(v_teammate.user_id, v_t_base_coins, 'daily_checkin', 'Daily check-in rewards', v_ref);
          END IF;
          IF v_t_owed_coop THEN
            PERFORM award_xp(v_teammate.user_id, v_t_coop_xp, 'partner_bonus', v_ref);
            PERFORM award_coins(v_teammate.user_id, v_t_coop_coins, 'partner_bonus', 'Partner checked in too!', v_ref);
          END IF;
        END IF;
      END;
    END LOOP;
  END IF;

  RETURN jsonb_build_object(
    'xp_awarded', v_xp,
    'coins_awarded', v_coins,
    'current_streak', v_current_streak,
    'reasons', v_reasons,
    'old_level', v_old_level,
    'new_level', v_new_level,
    'did_level_up', v_new_level > v_old_level,
    'daily_cap_reached', v_capped
  );
END;
$function$;

-- submit_checkin: copies members' real check-ins for their local today onto shared teams. Never a first check-in.
CREATE OR REPLACE FUNCTION public.submit_checkin()
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_uid uuid := auth.uid();
  v_coach_max_id constant uuid := '00000000-0000-0000-0000-000000000001';
  v_day date;
  v_before jsonb;
  v_mine_before integer;
  v_mine integer;
  v_xp integer := 0;
  v_coins integer := 0;
  v_r jsonb;
  c record;
BEGIN
  IF v_uid IS NULL THEN
    RAISE EXCEPTION 'unauthenticated';
  END IF;
  v_day := public._credit_day(v_uid, now());

  SELECT jsonb_object_agg(ts.id, ts.total_workouts) INTO v_before
  FROM team_streaks ts JOIN team_members tm ON tm.team_id = ts.team_id
  WHERE tm.user_id = v_uid AND ts.is_active = true;

  IF v_before IS NULL THEN
    RETURN jsonb_build_object('credited', false, 'reason', 'no_teams', 'credit_date', v_day,
                              'streak', 0, 'xp', 0, 'coins', 0, 'teams', '[]'::jsonb);
  END IF;

  SELECT count(*) INTO v_mine_before FROM daily_team_checkins
  WHERE user_id = v_uid AND check_in_date = v_day;

  -- Copy each member's real check-in for their own local today onto every
  -- shared active team that lacks it. Nobody gets a first check-in here (that
  -- stays behind finish_checkin_session), Coach Max is never copied, a copy
  -- keeps its source's earliest check_in_time, and copies pay nothing.
  FOR c IN
    SELECT ts.id AS streak_id, m.user_id, src.t
    FROM team_streaks ts
    JOIN team_members me ON me.team_id = ts.team_id AND me.user_id = v_uid
    JOIN team_members m ON m.team_id = ts.team_id AND m.user_id <> v_coach_max_id
    CROSS JOIN LATERAL (SELECT public._credit_day(m.user_id, now()) AS day) d
    CROSS JOIN LATERAL (
      SELECT min(x.check_in_time) AS t FROM daily_team_checkins x
      WHERE x.user_id = m.user_id AND x.check_in_date = d.day
    ) src
    WHERE ts.is_active = true
      AND src.t IS NOT NULL
      AND NOT EXISTS (
        SELECT 1 FROM daily_team_checkins y
        WHERE y.team_streak_id = ts.id AND y.user_id = m.user_id AND y.check_in_date = d.day
      )
    ORDER BY ts.id, m.user_id
  LOOP
    -- A copy is not a new check-in: notify_buddy_checkin sends no push for it.
    PERFORM set_config('app.checkin_copy', '1', true);
    v_r := public._credit_checkin(c.user_id, now(), false, c.t, c.streak_id);
    PERFORM set_config('app.checkin_copy', '', true);
    IF c.user_id = v_uid THEN
      v_xp := v_xp + (v_r->>'xp')::integer;
      v_coins := v_coins + (v_r->>'coins')::integer;
    END IF;
  END LOOP;

  SELECT count(*) INTO v_mine FROM daily_team_checkins
  WHERE user_id = v_uid AND check_in_date = v_day;

  RETURN (
    SELECT jsonb_build_object(
      'credited', v_mine > v_mine_before,
      'reason', CASE WHEN v_mine > v_mine_before THEN 'credited'
                     WHEN v_mine_before > 0 THEN 'already_checked_in'
                     ELSE 'not_checked_in_today' END,
      'credit_date', v_day,
      'streak', COALESCE(max(ts.current_streak), 0),
      'xp', v_xp,
      'coins', v_coins,
      'teams', COALESCE(jsonb_agg(jsonb_build_object(
                 'streak_id', ts.id, 'team_id', ts.team_id,
                 'updated', ts.total_workouts IS DISTINCT FROM (v_before->>ts.id::text)::integer,
                 'new_streak', ts.current_streak) ORDER BY ts.id), '[]'::jsonb))
    FROM team_streaks ts JOIN team_members tm ON tm.team_id = ts.team_id
    WHERE tm.user_id = v_uid AND ts.is_active = true);
END;
$function$;

-- notify_buddy_checkin: no push for a copy (transaction-local flag set by submit_checkin only).
CREATE OR REPLACE FUNCTION public.notify_buddy_checkin()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_other_user_id uuid;
  v_team_id uuid;
BEGIN
  -- Copies written by submit_checkin are not new check-ins: no push.
  IF current_setting('app.checkin_copy', true) = '1' THEN
    RETURN NEW;
  END IF;

  SELECT team_id INTO v_team_id FROM team_streaks WHERE id = NEW.team_streak_id;
  IF v_team_id IS NULL THEN
    RETURN NEW;
  END IF;

  SELECT tm.user_id INTO v_other_user_id
  FROM team_members tm
  WHERE tm.team_id = v_team_id
    AND tm.user_id != NEW.user_id
  LIMIT 1;

  PERFORM public._send_push(v_other_user_id, 'buddy_checked_in', '{}'::jsonb, 'emerald', 'streaks',
                            'buddy_checked_in', v_team_id::text, 'streak_' || v_team_id, false, NEW.user_id);
  RETURN NEW;
END;
$function$;

-- F3: create_invite_team no longer pays the invitee at join ...
CREATE OR REPLACE FUNCTION public.create_invite_team(p_inviter_id uuid, p_invitee_id uuid)
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_team_id UUID;
  v_invite_id UUID;
  v_now TIMESTAMPTZ := NOW();
BEGIN
  IF auth.uid() IS NULL OR auth.uid() <> p_invitee_id THEN
    RAISE EXCEPTION 'not_authorized';
  END IF;

  SELECT id INTO v_invite_id
  FROM invites
  WHERE inviter_id = p_inviter_id
    AND accepted_by = p_invitee_id
    AND status = 'accepted'
  ORDER BY accepted_at DESC NULLS LAST
  LIMIT 1;

  IF v_invite_id IS NULL THEN
    RAISE EXCEPTION 'no_accepted_invite';
  END IF;

  SELECT tm1.team_id INTO v_team_id
  FROM team_members tm1
  JOIN team_members tm2 ON tm2.team_id = tm1.team_id AND tm2.user_id = p_invitee_id
  WHERE tm1.user_id = p_inviter_id
  LIMIT 1;

  IF v_team_id IS NOT NULL THEN
    RETURN v_team_id;
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

  INSERT INTO friendships (user_id, friend_id, status)
  SELECT p_inviter_id, p_invitee_id, 'accepted'
  WHERE NOT EXISTS (
    SELECT 1 FROM friendships
    WHERE (user_id = p_inviter_id AND friend_id = p_invitee_id)
       OR (user_id = p_invitee_id AND friend_id = p_inviter_id)
  );

  -- The invitee's welcome bonus is paid on their first credited day by
  -- _fulfil_invite_reward, once per account (F3), no longer here.

  RETURN v_team_id;
END;
$function$;

-- ... _fulfil_invite_reward pays it once per account, on the first credited row.
CREATE OR REPLACE FUNCTION public._fulfil_invite_reward()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_invite  RECORD;
  v_days    INT;
  v_friends INT;
  v_amount  INT;
  v_bonus   BOOLEAN := false;
BEGIN
  FOR v_invite IN
    SELECT i.id, i.inviter_id, i.created_at
    FROM invites i
    WHERE i.accepted_by = NEW.user_id
      AND i.status = 'accepted'
    FOR UPDATE
  LOOP
    -- F3: the invitee's own 20-coin welcome bonus, once per account for life,
    -- paid on its first credited row after joining through an invite. The
    -- FOR UPDATE above serialises concurrent rows for the same invitee.
    IF NOT v_bonus
       AND NOT EXISTS (
         SELECT 1 FROM coin_transactions
         WHERE user_id = NEW.user_id AND transaction_type = 'invite_bonus'
       )
       AND EXISTS (
         SELECT 1 FROM auth.users u
         WHERE u.id = NEW.user_id AND u.created_at > v_invite.created_at
       ) THEN
      BEGIN
        PERFORM award_coins(NEW.user_id, 20, 'invite_bonus', 'Joined via buddy invite', v_invite.id::text);
      EXCEPTION WHEN OTHERS THEN
        -- Never block the check-in. No invite_bonus row, so the next row retries.
        RAISE WARNING 'invite_bonus failed for %: %', NEW.user_id, SQLERRM;
      END;
      v_bonus := true;
    END IF;

    IF EXISTS (
      SELECT 1 FROM coin_transactions
      WHERE transaction_type = 'invite_reward'
        AND reference_id = v_invite.id::text
    ) THEN
      CONTINUE;
    END IF;

    IF NOT EXISTS (
      SELECT 1 FROM auth.users u
      WHERE u.id = NEW.user_id
        AND u.created_at > v_invite.created_at
    ) THEN
      CONTINUE;
    END IF;

    SELECT COUNT(DISTINCT check_in_date) INTO v_days
    FROM daily_team_checkins
    WHERE user_id = NEW.user_id;

    IF v_days < 2 THEN
      CONTINUE;
    END IF;

    SELECT COUNT(*) INTO v_friends
    FROM friendships
    WHERE status = 'accepted'
      AND (user_id = v_invite.inviter_id OR friend_id = v_invite.inviter_id);

    v_amount := CASE
      WHEN v_friends < 30 THEN 20
      WHEN v_friends < 60 THEN 10
      WHEN v_friends < 90 THEN 5
      ELSE 2
    END;

    BEGIN
      PERFORM award_coins(
        v_invite.inviter_id, v_amount, 'invite_reward',
        'Buddy invite paid off', v_invite.id::text
      );
    EXCEPTION WHEN OTHERS THEN
      INSERT INTO invite_reward_dead_letters (invite_id, inviter_id, amount, error_message)
      VALUES (v_invite.id, v_invite.inviter_id, v_amount, SQLERRM);
    END;
  END LOOP;

  RETURN NULL;
END;
$function$;

REVOKE EXECUTE ON FUNCTION public._credit_day(uuid, timestamp with time zone) FROM PUBLIC, anon, authenticated;
GRANT  EXECUTE ON FUNCTION public._credit_day(uuid, timestamp with time zone) TO service_role;
REVOKE EXECUTE ON FUNCTION public._credit_checkin(uuid, timestamp with time zone, boolean, timestamp with time zone, uuid) FROM PUBLIC, anon, authenticated;
GRANT  EXECUTE ON FUNCTION public._credit_checkin(uuid, timestamp with time zone, boolean, timestamp with time zone, uuid) TO service_role;
REVOKE EXECUTE ON FUNCTION public._apply_checkin_rewards(uuid, uuid, date) FROM PUBLIC, anon, authenticated;
REVOKE EXECUTE ON FUNCTION public.submit_checkin() FROM PUBLIC, anon;
GRANT  EXECUTE ON FUNCTION public.submit_checkin() TO authenticated;
REVOKE EXECUTE ON FUNCTION public.finish_checkin_session(uuid) FROM PUBLIC, anon;
GRANT  EXECUTE ON FUNCTION public.finish_checkin_session(uuid) TO authenticated;
REVOKE EXECUTE ON FUNCTION public.create_invite_team(uuid, uuid) FROM PUBLIC, anon;
GRANT  EXECUTE ON FUNCTION public.create_invite_team(uuid, uuid) TO authenticated;

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
