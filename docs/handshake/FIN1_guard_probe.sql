-- FIN-1 guard probe: H4a scenarios a..j unchanged, plus n1..n7 (FIN-1 Step 3).
-- Same fixtures and rules as H4a (below). One transaction, ends in RAISE
-- EXCEPTION: nothing persists. Credit functions only run inside it.
-- H4a Step 1: finish-flow scenarios a..h (+ i, j extras). Test accounts only:
-- rokitest1 (A), newesttest (B), testtest1 (C). One transaction; each scenario
-- runs in its own sub-transaction (rolled back so scenarios start from the same
-- state) and the whole thing ends in RAISE EXCEPTION, so nothing persists and
-- process_stale_sessions can never see any of it.
-- Fixtures: A and B each have the Coach Max streak (completes on one check-in)
-- plus a fresh shared team T1 (A+B, completes only when BOTH are in).
--   expected: credited alone  = Coach Max streak only  = 1 check-in row... see ci below
--   per credited person: ci = 2 rows (coach + T1), coach pays 10 xp / 10 coins,
--   T1 pays 15 / 15 to each member once both are in (10 base + 5 co-op, the first
--   one in is topped up retroactively).
CREATE TEMP TABLE pr (n serial, scn text DEFAULT current_setting('h4.scn', true), t text, ok boolean, info text);

CREATE FUNCTION pg_temp.ua() RETURNS uuid LANGUAGE sql AS $$ SELECT '5e67f64d-16e3-4b09-9b00-ddc49df8c3f6'::uuid $$;
CREATE FUNCTION pg_temp.ub() RETURNS uuid LANGUAGE sql AS $$ SELECT '6ef4e82e-a54d-4b91-8ce4-b5f179a65f66'::uuid $$;
CREATE FUNCTION pg_temp.uc() RETURNS uuid LANGUAGE sql AS $$ SELECT 'cf4946f5-f921-4e81-bbf4-88d574e8baf5'::uuid $$;

CREATE FUNCTION pg_temp.u(p_uid uuid, p_sql text, p_role text DEFAULT 'authenticated')
RETURNS text LANGUAGE plpgsql AS $f$
DECLARE r text; d text;
BEGIN
  PERFORM set_config('request.jwt.claims',
    CASE WHEN p_uid IS NULL THEN json_build_object('role', p_role)::text
         ELSE json_build_object('sub', p_uid, 'role', p_role)::text END, true);
  BEGIN
    EXECUTE format('SET LOCAL ROLE %I', p_role);
    EXECUTE p_sql INTO r;
    RESET ROLE;
  EXCEPTION WHEN OTHERS THEN
    GET STACKED DIAGNOSTICS d = PG_EXCEPTION_DETAIL;
    r := 'ERR:' || SQLERRM || CASE WHEN coalesce(d, '') <> '' THEN '|' || d ELSE '' END;
  END;
  RESET ROLE;
  PERFORM set_config('request.jwt.claims', '', true);
  RETURN r;
END $f$;

CREATE FUNCTION pg_temp.st(r text) RETURNS text LANGUAGE sql AS $$
  SELECT CASE WHEN r IS NULL THEN 'NULL' WHEN r LIKE 'ERR:%' THEN r ELSE r::jsonb->>'state' END $$;
CREATE FUNCTION pg_temp.ck(p_t text, p_ok boolean, p_info text DEFAULT NULL) RETURNS void
LANGUAGE sql AS $$ INSERT INTO pr (t, ok, info) VALUES (p_t, coalesce(p_ok, false), p_info) $$;
CREATE FUNCTION pg_temp.eq(p_t text, p_got text, p_want text) RETURNS void
LANGUAGE sql AS $$ SELECT pg_temp.ck(p_t, p_got IS NOT DISTINCT FROM p_want, 'got ' || coalesce(p_got, 'NULL') || CASE WHEN p_got IS DISTINCT FROM p_want THEN ' want ' || coalesce(p_want, 'NULL') ELSE '' END) $$;
CREATE FUNCTION pg_temp.call(p uuid, fn text, w uuid, extra text DEFAULT '') RETURNS text LANGUAGE sql AS $$
  SELECT pg_temp.u(p, format('SELECT public.%s(%L%s)::text', fn, w, extra)) $$;
CREATE FUNCTION pg_temp.fin(p uuid, w uuid) RETURNS text LANGUAGE sql AS $$
  SELECT pg_temp.u(p, CASE WHEN w IS NULL THEN 'SELECT public.finish_checkin_session()::text'
                           ELSE format('SELECT public.finish_checkin_session(%L)::text', w) END) $$;

CREATE FUNCTION pg_temp.mk(p_c uuid, p_b uuid, p_off interval, p_bs text DEFAULT 'accepted',
                           p_dur int DEFAULT 60) RETURNS uuid LANGUAGE plpgsql AS $f$
DECLARE v_local timestamp := (now() + p_off) AT TIME ZONE public.safe_user_tz(p_c); v_id uuid;
BEGIN
  INSERT INTO workouts (user_id, buddy_id, workout_type, workout_date, workout_time,
                        planned_duration_minutes, status, buddy_status)
  VALUES (p_c, p_b, 'Strength', v_local::date, v_local::time, p_dur, 'scheduled', p_bs)
  RETURNING id INTO v_id;
  RETURN v_id;
END $f$;

CREATE FUNCTION pg_temp.back(w uuid, mins int) RETURNS void LANGUAGE sql AS $$
  UPDATE workouts SET workout_started_at = now() - make_interval(mins => mins) WHERE id = w;
  UPDATE active_checkin_sessions SET started_at = now() - make_interval(mins => mins) WHERE workout_id = w;
  SELECT 1 WHERE false $$;

-- two people, both tapped, started, started_at backdated
CREATE FUNCTION pg_temp.run2(p_mins int DEFAULT 30) RETURNS uuid LANGUAGE plpgsql AS $f$
DECLARE w uuid := pg_temp.mk(pg_temp.ua(), pg_temp.ub(), '0', 'accepted', 15);
BEGIN
  PERFORM pg_temp.ck('setup: A taps', pg_temp.st(pg_temp.call(pg_temp.ua(), 'im_here', w)) = 'waiting_for_buddy');
  PERFORM pg_temp.ck('setup: B taps, started', pg_temp.st(pg_temp.call(pg_temp.ub(), 'im_here', w)) = 'started');
  PERFORM pg_temp.back(w, p_mins);
  RETURN w;
END $f$;

CREATE FUNCTION pg_temp.sn(p_u uuid) RETURNS jsonb LANGUAGE sql AS $$
  SELECT jsonb_build_object(
    'ci', (SELECT count(*) FROM daily_team_checkins WHERE user_id = p_u AND check_in_date >= current_setting('h4.day')::date),
    'coins', (SELECT coin_balance FROM user_profiles WHERE id = p_u),
    'xp', (SELECT xp FROM user_profiles WHERE id = p_u),
    'xt', (SELECT count(*) FROM xp_transactions WHERE user_id = p_u AND reference_id LIKE '%:' || current_setting('h4.day')),
    'ct', (SELECT count(*) FROM coin_transactions WHERE user_id = p_u AND reference_id LIKE '%:' || current_setting('h4.day')),
    'dupe', (SELECT count(*) FROM (SELECT 1 FROM xp_transactions WHERE user_id = p_u AND reference_id LIKE '%:' || current_setting('h4.day')
                                   GROUP BY reference_id, description HAVING count(*) > 1) d)
          + (SELECT count(*) FROM (SELECT 1 FROM coin_transactions WHERE user_id = p_u AND reference_id LIKE '%:' || current_setting('h4.day')
                                   GROUP BY reference_id, transaction_type HAVING count(*) > 1) d),
    'wl', (SELECT count(*) FROM workout_logs WHERE user_id = p_u AND workout_date >= current_setting('h4.day')::date),
    'ev', (SELECT count(*) FROM streak_events WHERE user_id = p_u),
    'neg', (SELECT count(*) FROM coin_transactions WHERE user_id = p_u AND amount < 0 AND created_at >= now() - interval '1 day')) $$;

CREATE FUNCTION pg_temp.dl(b jsonb, a jsonb, k text) RETURNS text LANGUAGE sql AS $$
  SELECT ((a->>k)::numeric - (b->>k)::numeric)::int::text $$;

-- effect of a person since snapshot b: rows, coins, xp, no dupes, no penalty/events/logs
CREATE FUNCTION pg_temp.fx(p_t text, p_u uuid, b jsonb, p_ci int, p_coins int, p_xp int) RETURNS void
LANGUAGE plpgsql AS $f$
DECLARE a jsonb := pg_temp.sn(p_u);
BEGIN
  PERFORM pg_temp.eq(p_t,
    format('ci=%s coins=%s xp=%s dupe=%s ev=%s neg=%s wl=%s', pg_temp.dl(b, a, 'ci'), pg_temp.dl(b, a, 'coins'), pg_temp.dl(b, a, 'xp'),
           a->>'dupe', pg_temp.dl(b, a, 'ev'), pg_temp.dl(b, a, 'neg'), pg_temp.dl(b, a, 'wl')),
    format('ci=%s coins=%s xp=%s dupe=0 ev=0 neg=0 wl=0', p_ci, p_coins, p_xp));
END $f$;

CREATE FUNCTION pg_temp.strk(p_u uuid) RETURNS text LANGUAGE sql AS $$
  SELECT ts.current_streak || '/' || ts.total_workouts || '/' || coalesce(ts.last_workout_date::text, '-')
  FROM team_streaks ts JOIN buddy_teams bt ON bt.id = ts.team_id JOIN team_members tm ON tm.team_id = bt.id
  WHERE tm.user_id = p_u AND bt.is_coach_max_team AND ts.is_active $$;
CREATE FUNCTION pg_temp.t1() RETURNS text LANGUAGE sql AS $$
  SELECT current_streak || '/' || total_workouts || '/' || coalesce(last_workout_date::text, '-')
  FROM team_streaks WHERE id = current_setting('h4.t1')::uuid $$;
CREATE FUNCTION pg_temp.wrow(w uuid) RETURNS text LANGUAGE sql AS $$
  SELECT status || '/' || coalesce(closed_reason, '-') || '/cc=' || creator_cancelled || '/bc=' || buddy_cancelled
         || '/dur=' || coalesce(actual_duration_minutes::text, '-') || '/sess=' || (SELECT count(*) FROM active_checkin_sessions WHERE workout_id = w)
  FROM workouts WHERE id = w $$;

-- ═════════ scenarios (each returns nothing; asserts go into pr) ═════════

-- a. one finishes while the other still runs, then the other finishes
CREATE FUNCTION pg_temp.s_a() RETURNS void LANGUAGE plpgsql AS $f$
DECLARE A uuid := pg_temp.ua(); B uuid := pg_temp.ub(); w uuid := pg_temp.run2(); bA jsonb := pg_temp.sn(A); bB jsonb := pg_temp.sn(B); r text;
BEGIN
  PERFORM pg_temp.eq('A complete_workout', pg_temp.st(pg_temp.call(A, 'complete_workout', w, ', 30')), 'completed');
  PERFORM pg_temp.eq('cleanup trigger on completion: row + remaining sessions (A and B)', pg_temp.wrow(w), 'completed/completed/cc=false/bc=false/dur=30/sess=0');
  PERFORM pg_temp.fx('before A finish: nobody credited yet (complete alone credits nothing)', A, bA, 0, 0, 0);
  r := pg_temp.fin(A, w);
  PERFORM pg_temp.eq('A finish: partner_checked_in = B streaks (M6a partner credit)', r::jsonb->>'partner_checked_in', '2');
  PERFORM pg_temp.fx('A credited once (coach 10 + T1 15)', A, bA, 2, 25, 25);
  PERFORM pg_temp.fx('PROMPT EXPECTATION "B not credited yet" (design M6a credits ready B at A finish)', B, bB, 0, 0, 0);
  PERFORM pg_temp.fx('B as designed: credited by partner credit (coach 10 + T1 15)', B, bB, 2, 25, 25);
  PERFORM pg_temp.eq('T1 streak cs/tw/lw', pg_temp.t1(), '1/1/' || current_setting('h4.day'));
  -- B, whose session the cleanup trigger already deleted, now completes and finishes
  PERFORM pg_temp.eq('B complete_workout after A completed (idempotent)', pg_temp.st(pg_temp.call(B, 'complete_workout', w, ', 30')), 'completed');
  PERFORM pg_temp.ck('B buddy_completed_at set', (SELECT buddy_completed_at IS NOT NULL FROM workouts WHERE id = w));
  r := pg_temp.fin(B, w);
  PERFORM pg_temp.eq('B finish: second finisher credits no partner again', r::jsonb->>'checked_in', '0');
  PERFORM pg_temp.fx('B credited once in total', B, bB, 2, 25, 25);
  PERFORM pg_temp.fx('A not credited a second time', A, bA, 2, 25, 25);
  PERFORM pg_temp.eq('T1 streak unchanged by B finish', pg_temp.t1(), '1/1/' || current_setting('h4.day'));
END $f$;

-- coach streak after a credit: cs 1, total +1, on the credit day; untouched otherwise
CREATE FUNCTION pg_temp.coach(p_t text, p_u uuid, p_before text, p_credited boolean) RETURNS void LANGUAGE sql AS $$
  SELECT pg_temp.eq(p_t, pg_temp.strk(p_u),
    CASE WHEN p_credited THEN '1/' || (split_part(p_before, '/', 2)::int + 1) || '/' || current_setting('h4.day') ELSE p_before END) $$;

-- b. A then B back to back, and B then A: each credited exactly once
CREATE FUNCTION pg_temp.both(p_x uuid, p_y uuid) RETURNS void LANGUAGE plpgsql AS $f$
DECLARE A uuid := pg_temp.ua(); B uuid := pg_temp.ub(); w uuid := pg_temp.run2(); bA jsonb := pg_temp.sn(A); bB jsonb := pg_temp.sn(B);
  cA text := pg_temp.strk(A); cB text := pg_temp.strk(B);
BEGIN
  PERFORM pg_temp.eq('first completes', pg_temp.st(pg_temp.call(p_x, 'complete_workout', w, ', 30')), 'completed');
  PERFORM pg_temp.ck('first finish no error', pg_temp.fin(p_x, w) NOT LIKE 'ERR:%');
  PERFORM pg_temp.eq('second completes (idempotent)', pg_temp.st(pg_temp.call(p_y, 'complete_workout', w, ', 30')), 'completed');
  PERFORM pg_temp.ck('second finish no error', pg_temp.fin(p_y, w) NOT LIKE 'ERR:%');
  PERFORM pg_temp.fx('A credited once (coach 10 + T1 15)', A, bA, 2, 25, 25);
  PERFORM pg_temp.fx('B credited once (coach 10 + T1 15)', B, bB, 2, 25, 25);
  PERFORM pg_temp.eq('T1 streak cs/tw/lw', pg_temp.t1(), '1/1/' || current_setting('h4.day'));
  PERFORM pg_temp.coach('A coach streak +1', A, cA, true);
  PERFORM pg_temp.coach('B coach streak +1', B, cB, true);
  PERFORM pg_temp.eq('workout row', pg_temp.wrow(w), 'completed/completed/cc=false/bc=false/dur=30/sess=0');
END $f$;
CREATE FUNCTION pg_temp.s_b() RETURNS void LANGUAGE sql AS $$ SELECT pg_temp.both(pg_temp.ua(), pg_temp.ub()) $$;
CREATE FUNCTION pg_temp.s_b2() RETURNS void LANGUAGE sql AS $$ SELECT pg_temp.both(pg_temp.ub(), pg_temp.ua()) $$;

-- c. B leaves while running, A finishes: A credited (coach only), B not, no penalty
CREATE FUNCTION pg_temp.s_c() RETURNS void LANGUAGE plpgsql AS $f$
DECLARE A uuid := pg_temp.ua(); B uuid := pg_temp.ub(); w uuid := pg_temp.run2(); bA jsonb := pg_temp.sn(A); bB jsonb := pg_temp.sn(B);
  cA text := pg_temp.strk(A); cB text := pg_temp.strk(B); r text;
BEGIN
  PERFORM pg_temp.eq('B leaves', pg_temp.st(pg_temp.call(B, 'leave_workout', w)), 'left');
  PERFORM pg_temp.eq('row after leave', pg_temp.wrow(w), 'in_progress/-/cc=false/bc=true/dur=-/sess=1');
  PERFORM pg_temp.eq('leaver cannot complete', pg_temp.st(pg_temp.call(B, 'complete_workout', w, ', 30')), 'ERR:wrong_state');
  PERFORM pg_temp.eq('A completes', pg_temp.st(pg_temp.call(A, 'complete_workout', w, ', 30')), 'completed');
  r := pg_temp.fin(A, w);
  PERFORM pg_temp.eq('A finish: leaver not credited via partner', r::jsonb->>'partner_checked_in', '0');
  PERFORM pg_temp.fx('A credited (coach 10; T1 not complete)', A, bA, 2, 10, 10);
  PERFORM pg_temp.fx('B not credited, no penalty row', B, bB, 0, 0, 0);
  PERFORM pg_temp.eq('T1 streak untouched', pg_temp.t1(), '0/0/-');
  PERFORM pg_temp.coach('A coach streak +1', A, cA, true);
  PERFORM pg_temp.coach('B coach streak untouched', B, cB, false);
END $f$;

-- d. cancel before start, can't make it, inviter goes solo and is credited
CREATE FUNCTION pg_temp.s_d() RETURNS void LANGUAGE plpgsql AS $f$
DECLARE A uuid := pg_temp.ua(); B uuid := pg_temp.ub(); w1 uuid; w2 uuid; bA jsonb := pg_temp.sn(A); bB jsonb := pg_temp.sn(B);
  cA text := pg_temp.strk(A); r text;
BEGIN
  w1 := pg_temp.mk(A, B, '1 hour', 'accepted');
  PERFORM pg_temp.eq('d1: A cancels before start', pg_temp.st(pg_temp.call(A, 'cancel_workout', w1)), 'closed');
  PERFORM pg_temp.eq('d1: row', pg_temp.wrow(w1), 'cancelled/cancelled_by_creator/cc=false/bc=false/dur=-/sess=0');
  PERFORM pg_temp.fx('d1: A not credited', A, bA, 0, 0, 0);
  PERFORM pg_temp.fx('d1: B not credited', B, bB, 0, 0, 0);
  w2 := pg_temp.mk(A, B, '0', 'accepted', 15);
  PERFORM pg_temp.eq('d2: B cant_make_it', pg_temp.st(pg_temp.call(B, 'cant_make_it', w2)), 'closed');
  PERFORM pg_temp.fx('d2: nobody credited by can''t make it (A)', A, bA, 0, 0, 0);
  PERFORM pg_temp.fx('d2: nobody credited by can''t make it (B)', B, bB, 0, 0, 0);
  PERFORM pg_temp.eq('d2: A goes solo', pg_temp.st(pg_temp.call(A, 'go_solo', w2)), 'solo');
  PERFORM pg_temp.eq('d2: solo starts at once', pg_temp.st(pg_temp.call(A, 'im_here', w2)), 'started');
  PERFORM pg_temp.back(w2, 30);
  PERFORM pg_temp.eq('d2: solo complete', pg_temp.st(pg_temp.call(A, 'complete_workout', w2, ', 30')), 'completed');
  r := pg_temp.fin(A, w2);
  PERFORM pg_temp.eq('d2: solo finish partner 0', r::jsonb->>'partner_checked_in', '0');
  PERFORM pg_temp.fx('d2: A credited once for the solo workout', A, bA, 2, 10, 10);
  PERFORM pg_temp.fx('d2: B still not credited', B, bB, 0, 0, 0);
  PERFORM pg_temp.coach('d2: A coach streak +1', A, cA, true);
  PERFORM pg_temp.eq('d2: T1 untouched', pg_temp.t1(), '0/0/-');
END $f$;

-- e. solo workout, f. double finish
CREATE FUNCTION pg_temp.solo(p_double boolean) RETURNS void LANGUAGE plpgsql AS $f$
DECLARE A uuid := pg_temp.ua(); B uuid := pg_temp.ub(); w uuid := pg_temp.mk(A, NULL, '0', 'pending', 30);
  bA jsonb := pg_temp.sn(A); bB jsonb := pg_temp.sn(B); cA text := pg_temp.strk(A); r text;
BEGIN
  PERFORM pg_temp.eq('solo starts', pg_temp.st(pg_temp.call(A, 'im_here', w)), 'started');
  PERFORM pg_temp.back(w, 45);
  PERFORM pg_temp.eq('solo complete', pg_temp.st(pg_temp.call(A, 'complete_workout', w, ', 30')), 'completed');
  r := pg_temp.fin(A, w);
  PERFORM pg_temp.eq('finish credited 2 streak rows', r::jsonb->>'checked_in', '2');
  PERFORM pg_temp.fx('A credited once', A, bA, 2, 10, 10);
  PERFORM pg_temp.fx('B untouched', B, bB, 0, 0, 0);
  PERFORM pg_temp.coach('A coach streak +1', A, cA, true);
  IF p_double THEN
    r := pg_temp.fin(A, w);
    PERFORM pg_temp.eq('2nd finish (same id): nothing new', r::jsonb->>'checked_in', '0');
    PERFORM pg_temp.fx('after 2nd finish: A unchanged', A, bA, 2, 10, 10);
    r := pg_temp.fin(A, NULL);
    PERFORM pg_temp.eq('3rd finish (no id): nothing new', r::jsonb->>'checked_in', '0');
    PERFORM pg_temp.fx('after 3rd finish: A unchanged', A, bA, 2, 10, 10);
    PERFORM pg_temp.coach('coach streak still +1 only', A, cA, true);
  END IF;
END $f$;
CREATE FUNCTION pg_temp.s_e() RETURNS void LANGUAGE sql AS $$ SELECT pg_temp.solo(false) $$;
CREATE FUNCTION pg_temp.s_f() RETURNS void LANGUAGE sql AS $$ SELECT pg_temp.solo(true) $$;

-- g. under 15 minutes
CREATE FUNCTION pg_temp.s_g() RETURNS void LANGUAGE plpgsql AS $f$
DECLARE A uuid := pg_temp.ua(); B uuid := pg_temp.ub(); w uuid := pg_temp.run2(5); bA jsonb := pg_temp.sn(A); bB jsonb := pg_temp.sn(B);
BEGIN
  PERFORM pg_temp.eq('complete with 10 min: too_early', pg_temp.st(pg_temp.call(A, 'complete_workout', w, ', 10')), 'ERR:too_early');
  PERFORM pg_temp.eq('complete with NULL min: too_early', pg_temp.st(pg_temp.call(A, 'complete_workout', w, ', NULL')), 'ERR:too_early');
  PERFORM pg_temp.eq('row still running, both sessions intact', pg_temp.wrow(w), 'in_progress/-/cc=false/bc=false/dur=-/sess=2');
  PERFORM pg_temp.fx('A not credited', A, bA, 0, 0, 0);
  PERFORM pg_temp.fx('B not credited', B, bB, 0, 0, 0);
END $f$;

-- h. RACE-1 observation: both finish at identical timestamps (now() is fixed in one
--    transaction). Serial replay only; true concurrency needs two committed
--    sessions, which this probe must not create (see the report).
CREATE FUNCTION pg_temp.s_h() RETURNS void LANGUAGE plpgsql AS $f$
DECLARE A uuid := pg_temp.ua(); B uuid := pg_temp.ub(); w uuid := pg_temp.run2(); bA jsonb := pg_temp.sn(A); bB jsonb := pg_temp.sn(B);
BEGIN
  PERFORM pg_temp.st(pg_temp.call(A, 'complete_workout', w, ', 30'));
  PERFORM pg_temp.st(pg_temp.call(B, 'complete_workout', w, ', 30'));
  PERFORM pg_temp.fin(A, w);
  PERFORM pg_temp.fin(B, w);
  PERFORM pg_temp.eq('all check-ins share one timestamp', (SELECT count(DISTINCT check_in_time)::text FROM daily_team_checkins
    WHERE user_id IN (A, B) AND check_in_date >= current_setting('h4.day')::date), '1');
  PERFORM pg_temp.fx('RACE-1 serial: A paid once', A, bA, 2, 25, 25);
  PERFORM pg_temp.fx('RACE-1 serial: B paid once', B, bB, 2, 25, 25);
END $f$;

-- i. extra: finish_checkin_session with no session and no workout
CREATE FUNCTION pg_temp.s_i() RETURNS void LANGUAGE plpgsql AS $f$
DECLARE A uuid := pg_temp.ua(); bA jsonb := pg_temp.sn(A); r text;
BEGIN
  r := pg_temp.fin(A, NULL);
  PERFORM pg_temp.fx('i: finish with no workout credits nothing', A, bA, 0, 0, 0);
END $f$;

-- j. extra: leaver (B) calls finish_checkin_session after leaving
CREATE FUNCTION pg_temp.s_j() RETURNS void LANGUAGE plpgsql AS $f$
DECLARE A uuid := pg_temp.ua(); B uuid := pg_temp.ub(); w uuid := pg_temp.run2(); bB jsonb := pg_temp.sn(B); r text;
BEGIN
  PERFORM pg_temp.st(pg_temp.call(B, 'leave_workout', w));
  PERFORM pg_temp.st(pg_temp.call(A, 'complete_workout', w, ', 30'));
  r := pg_temp.fin(B, w);
  PERFORM pg_temp.fx('j: leaver calling finish is not credited', B, bB, 0, 0, 0);
END $f$;

-- ═════════ FIN-1 additions ═════════
CREATE FUNCTION pg_temp.res(r text) RETURNS text LANGUAGE sql AS $$
  SELECT CASE WHEN r LIKE 'ERR:%' THEN r ELSE coalesce(r::jsonb->>'result', 'credited') || '/ci=' || (r::jsonb->>'checked_in') || '/p=' || (r::jsonb->>'partner_checked_in') END $$;
CREATE FUNCTION pg_temp.nrows(p_u uuid) RETURNS text LANGUAGE sql AS $$
  SELECT (SELECT count(*) FROM active_checkin_sessions WHERE user_id = p_u) || '/' ||
         (SELECT count(*) FROM daily_team_checkins WHERE user_id = p_u) || '/' ||
         (SELECT count(*) FROM xp_transactions WHERE user_id = p_u) || '/' ||
         (SELECT count(*) FROM coin_transactions WHERE user_id = p_u) $$;

-- n1. no session, no workout: clean no-op, no rows written
CREATE FUNCTION pg_temp.s_n1() RETURNS void LANGUAGE plpgsql AS $f$
DECLARE A uuid := pg_temp.ua(); bA jsonb := pg_temp.sn(A); n0 text := pg_temp.nrows(A); r text;
BEGIN
  r := pg_temp.fin(A, NULL);
  PERFORM pg_temp.eq('n1: result', pg_temp.res(r), 'nothing_to_finish/ci=0/p=0');
  PERFORM pg_temp.eq('n1: no rows written (sess/ci/xp/coin)', pg_temp.nrows(A), n0);
  PERFORM pg_temp.fx('n1: no credit', A, bA, 0, 0, 0);
END $f$;

-- n2. leaver calls finish while the partner is still running
CREATE FUNCTION pg_temp.s_n2() RETURNS void LANGUAGE plpgsql AS $f$
DECLARE A uuid := pg_temp.ua(); B uuid := pg_temp.ub(); w uuid := pg_temp.run2();
        bA jsonb := pg_temp.sn(A); bB jsonb := pg_temp.sn(B); r text;
BEGIN
  PERFORM pg_temp.eq('n2: B leaves', pg_temp.st(pg_temp.call(B, 'leave_workout', w)), 'left');
  r := pg_temp.fin(B, w);
  PERFORM pg_temp.eq('n2: leaver finish result', pg_temp.res(r), 'nothing_to_finish/ci=0/p=0');
  PERFORM pg_temp.fx('n2: leaver B not credited', B, bB, 0, 0, 0);
  PERFORM pg_temp.fx('n2: running partner A not credited by that call', A, bA, 0, 0, 0);
  PERFORM pg_temp.eq('n2: A still running with session', pg_temp.wrow(w), 'in_progress/-/cc=false/bc=true/dur=-/sess=1');
END $f$;

-- n3. participant of a cancelled workout, and of a workout never started
CREATE FUNCTION pg_temp.s_n3() RETURNS void LANGUAGE plpgsql AS $f$
DECLARE A uuid := pg_temp.ua(); B uuid := pg_temp.ub(); w1 uuid := pg_temp.mk(A, B, '0', 'accepted');
        w2 uuid := pg_temp.mk(A, B, '0', 'accepted'); bA jsonb := pg_temp.sn(A); bB jsonb := pg_temp.sn(B);
BEGIN
  PERFORM pg_temp.eq('n3: A cancels w1', pg_temp.st(pg_temp.call(A, 'cancel_workout', w1)), 'closed');
  PERFORM pg_temp.eq('n3: A finish cancelled', pg_temp.res(pg_temp.fin(A, w1)), 'nothing_to_finish/ci=0/p=0');
  PERFORM pg_temp.eq('n3: B finish cancelled', pg_temp.res(pg_temp.fin(B, w1)), 'nothing_to_finish/ci=0/p=0');
  PERFORM pg_temp.eq('n3: A finish never started', pg_temp.res(pg_temp.fin(A, w2)), 'nothing_to_finish/ci=0/p=0');
  PERFORM pg_temp.eq('n3: B finish never started', pg_temp.res(pg_temp.fin(B, w2)), 'nothing_to_finish/ci=0/p=0');
  PERFORM pg_temp.fx('n3: A not credited', A, bA, 0, 0, 0);
  PERFORM pg_temp.fx('n3: B not credited', B, bB, 0, 0, 0);
END $f$;

-- n4. started more than 3h30 ago: manual finish credits nothing; the cron's
--     auto-complete still credits both (process_stale_sessions, unchanged)
CREATE FUNCTION pg_temp.s_n4() RETURNS void LANGUAGE plpgsql AS $f$
DECLARE A uuid := pg_temp.ua(); B uuid := pg_temp.ub(); w uuid := pg_temp.run2(240);
        bA jsonb := pg_temp.sn(A); bB jsonb := pg_temp.sn(B); snap jsonb;
BEGIN
  PERFORM pg_temp.eq('n4: A finish after 4h', pg_temp.res(pg_temp.fin(A, w)), 'nothing_to_finish/ci=0/p=0');
  PERFORM pg_temp.eq('n4: B finish after 4h (no id)', pg_temp.res(pg_temp.fin(B, NULL)), 'nothing_to_finish/ci=0/p=0');
  PERFORM pg_temp.fx('n4: A not credited by finish', A, bA, 0, 0, 0);
  PERFORM pg_temp.eq('n4: sessions left for the cron', pg_temp.wrow(w), 'in_progress/-/cc=false/bc=false/dur=-/sess=2');
  PERFORM public.process_stale_sessions(now());
  PERFORM pg_temp.eq('n4: cron auto-completes the row', (SELECT status || '/auto=' || auto_completed FROM workouts WHERE id = w), 'completed/auto=true');
  snap := pg_temp.sn(A);
  PERFORM pg_temp.eq('n4: cron credits A (2 rows)', pg_temp.dl(bA, snap, 'ci'), '2');
  snap := pg_temp.sn(B);
  PERFORM pg_temp.eq('n4: cron credits B (2 rows)', pg_temp.dl(bB, snap, 'ci'), '2');
END $f$;

-- n5. forged ids: someone else's workout, a random uuid
CREATE FUNCTION pg_temp.s_n5() RETURNS void LANGUAGE plpgsql AS $f$
DECLARE A uuid := pg_temp.ua(); B uuid := pg_temp.ub(); C uuid := pg_temp.uc(); w uuid := pg_temp.run2();
        bA jsonb := pg_temp.sn(A); bB jsonb := pg_temp.sn(B); bC jsonb := pg_temp.sn(C);
BEGIN
  PERFORM pg_temp.eq('n5: A completes', pg_temp.st(pg_temp.call(A, 'complete_workout', w, ', 30')), 'completed');
  bA := pg_temp.sn(A);
  PERFORM pg_temp.eq('n5: C finishes A+B workout', pg_temp.res(pg_temp.fin(C, w)), 'nothing_to_finish/ci=0/p=0');
  PERFORM pg_temp.eq('n5: C finishes random uuid', pg_temp.res(pg_temp.fin(C, gen_random_uuid())), 'nothing_to_finish/ci=0/p=0');
  PERFORM pg_temp.eq('n5: A finishes random uuid', pg_temp.res(pg_temp.fin(A, gen_random_uuid())), 'nothing_to_finish/ci=0/p=0');
  PERFORM pg_temp.fx('n5: C not credited', C, bC, 0, 0, 0);
  PERFORM pg_temp.fx('n5: A not credited by forged calls', A, bA, 0, 0, 0);
  PERFORM pg_temp.fx('n5: B not credited by forged calls', B, bB, 0, 0, 0);
END $f$;

-- n6. solo finish, then double finish
CREATE FUNCTION pg_temp.s_n6() RETURNS void LANGUAGE plpgsql AS $f$
DECLARE A uuid := pg_temp.ua(); w uuid := pg_temp.mk(A, NULL, '0', 'accepted'); bA jsonb; r text;
BEGIN
  UPDATE workouts SET buddy_status = NULL WHERE id = w;
  PERFORM pg_temp.eq('n6: solo starts', pg_temp.st(pg_temp.call(A, 'im_here', w)), 'started');
  PERFORM pg_temp.back(w, 30);
  PERFORM pg_temp.eq('n6: solo complete', pg_temp.st(pg_temp.call(A, 'complete_workout', w, ', 30')), 'completed');
  bA := pg_temp.sn(A);
  PERFORM pg_temp.eq('n6: first finish', pg_temp.res(pg_temp.fin(A, w)), 'credited/ci=2/p=0');
  PERFORM pg_temp.fx('n6: credited once (coach 10; T1 not complete)', A, bA, 2, 10, 10);
  bA := pg_temp.sn(A);
  PERFORM pg_temp.eq('n6: second finish', pg_temp.res(pg_temp.fin(A, w)), 'credited/ci=0/p=0');
  PERFORM pg_temp.fx('n6: second finish credits nothing', A, bA, 0, 0, 0);
END $f$;

-- n7. plain Check In (own session) earlier today, then a workout finish: no second pay
CREATE FUNCTION pg_temp.s_n7() RETURNS void LANGUAGE plpgsql AS $f$
DECLARE A uuid := pg_temp.ua(); w uuid; bA jsonb := pg_temp.sn(A); r text;
BEGIN
  r := pg_temp.u(A, format('INSERT INTO active_checkin_sessions (user_id, workout_type, planned_duration) VALUES (%L, ''Strength'', 30) RETURNING id::text', A));
  PERFORM pg_temp.ck('n7: A starts a plain check-in session', r NOT LIKE 'ERR:%', r);
  UPDATE active_checkin_sessions SET started_at = now() - interval '35 minutes' WHERE user_id = A;
  PERFORM pg_temp.eq('n7: plain Check In finish', pg_temp.res(pg_temp.fin(A, NULL)), 'credited/ci=2/p=0');
  PERFORM pg_temp.eq('n7: session cleared', (SELECT count(*)::text FROM active_checkin_sessions WHERE user_id = A), '0');
  PERFORM pg_temp.fx('n7: plain Check In credited once (coach 10; T1 not complete)', A, bA, 2, 10, 10);
  w := pg_temp.mk(A, NULL, '0', 'accepted');
  UPDATE workouts SET buddy_status = NULL WHERE id = w;
  PERFORM pg_temp.st(pg_temp.call(A, 'im_here', w));
  PERFORM pg_temp.back(w, 30);
  PERFORM pg_temp.st(pg_temp.call(A, 'complete_workout', w, ', 30'));
  bA := pg_temp.sn(A);
  PERFORM pg_temp.eq('n7: later workout finish', pg_temp.res(pg_temp.fin(A, w)), 'credited/ci=0/p=0');
  PERFORM pg_temp.fx('n7: not paid a second time', A, bA, 0, 0, 0);
END $f$;

DO $probe$
DECLARE
  A constant uuid := '5e67f64d-16e3-4b09-9b00-ddc49df8c3f6';
  B constant uuid := '6ef4e82e-a54d-4b91-8ce4-b5f179a65f66';
  C constant uuid := 'cf4946f5-f921-4e81-bbf4-88d574e8baf5';
  v_day date := ((now() - interval '30 minutes') AT TIME ZONE 'Europe/Dublin')::date;
  v_team uuid; v_t1 uuid; s text; acc text := ''; o text; cnt int;
BEGIN
  PERFORM set_config('h4.day', v_day::text, true);
  SELECT count(*) INTO cnt FROM workouts WHERE status = 'in_progress' AND (user_id IN (A, B, C) OR buddy_id IN (A, B, C));
  IF cnt > 0 THEN RAISE EXCEPTION 'PRECONDITION: % in_progress workouts for test accounts', cnt; END IF;
  DELETE FROM active_checkin_sessions WHERE user_id IN (A, B, C);
  DELETE FROM daily_team_checkins WHERE check_in_date >= v_day - 1 AND
    (user_id IN (A, B, C) OR team_streak_id IN (SELECT ts.id FROM team_streaks ts JOIN team_members tm ON tm.team_id = ts.team_id WHERE tm.user_id IN (A, B, C)));
  DELETE FROM xp_transactions WHERE user_id IN (A, B, C) AND reference_id LIKE '%:' || v_day;
  DELETE FROM coin_transactions WHERE user_id IN (A, B, C) AND reference_id LIKE '%:' || v_day;
  INSERT INTO buddy_teams (team_name, created_by) VALUES ('h4a probe', A) RETURNING id INTO v_team;
  INSERT INTO team_members (team_id, user_id) VALUES (v_team, A), (v_team, B);
  INSERT INTO team_streaks (team_id, is_active) VALUES (v_team, true) RETURNING id INTO v_t1;
  PERFORM set_config('h4.t1', v_t1::text, true);

  FOREACH s IN ARRAY ARRAY['a', 'b', 'b2', 'c', 'd', 'e', 'f', 'g', 'h', 'i', 'j', 'n1', 'n2', 'n3', 'n4', 'n5', 'n6', 'n7'] LOOP
    BEGIN
      PERFORM set_config('h4.scn', s, true);
      EXECUTE format('SELECT pg_temp.s_%s()', s);
      SELECT string_agg(CASE WHEN ok THEN 'ok   ' ELSE 'FAIL ' END || scn || ' ' || t || ' [' || coalesce(info, '') || ']', E'\n' ORDER BY n)
      INTO o FROM pr WHERE scn = s;
      RAISE EXCEPTION 'SCN_DONE';
    EXCEPTION WHEN OTHERS THEN
      IF SQLERRM = 'SCN_DONE' THEN acc := acc || o || E'\n'; ELSE acc := acc || 'ERROR ' || s || ' ' || SQLERRM || E'\n'; END IF;
    END;
  END LOOP;
  RAISE EXCEPTION E'FIN1_RESULTS\n%', acc;
END $probe$;
