-- H1 probe. One transaction; ends in RAISE EXCEPTION so everything rolls back.
-- Test accounts only: rokitest1 (A), newesttest (B), testtest1 (C).
CREATE TEMP TABLE pr (n serial, t text, ok boolean, info text);

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
LANGUAGE sql AS $$ SELECT pg_temp.ck(p_t, p_got IS NOT DISTINCT FROM p_want, 'got ' || coalesce(p_got, 'NULL')) $$;

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

-- card state of workout w as user p
CREATE FUNCTION pg_temp.card(p uuid, w uuid) RETURNS text LANGUAGE sql AS $$
  SELECT CASE WHEN r LIKE 'ERR:%' THEN r ELSE r::jsonb->'workout'->>'state' END
  FROM (SELECT pg_temp.u(p, format('SELECT public.get_workout_card(%L)::text', w)) r) x $$;

CREATE FUNCTION pg_temp.call(p uuid, fn text, w uuid, extra text DEFAULT '') RETURNS text LANGUAGE sql AS $$
  SELECT pg_temp.u(p, format('SELECT public.%s(%L%s)::text', fn, w, extra)) $$;

DO $probe$
DECLARE
  A constant uuid := '5e67f64d-16e3-4b09-9b00-ddc49df8c3f6';  -- rokitest1
  B constant uuid := '6ef4e82e-a54d-4b91-8ce4-b5f179a65f66';  -- newesttest
  C constant uuid := 'cf4946f5-f921-4e81-bbf4-88d574e8baf5';  -- testtest1
  RING constant uuid := '777d7a64-631e-41b3-97a8-2c8ea5a352a7'; -- #FF6F5E
  DUMMY constant uuid := '00000000-0000-0000-0000-0000000000ff';
  v_today date := (now() AT TIME ZONE 'Europe/Dublin')::date;
  v_team uuid; nA int; nB int; n int; q0 bigint;
  r text; f text;
  w1 uuid; w2 uuid; w3 uuid; w4 uuid; w5 uuid; w6 uuid; w7 uuid; w8 uuid; w9 uuid;
  w10 uuid; w11 uuid; w12 uuid; w13 uuid; w14 uuid; w15 uuid; w16 uuid; w17 uuid;
  w18 uuid; w19 uuid; w20 uuid;
  cap uuid[] := '{}';
  rpcs text[] := ARRAY['accept_workout_invite', 'decline_workout_invite', 'im_here', 'cant_make_it',
    'go_solo', 'cancel_workout', 'leave_workout', 'nudge_workout', 'change_workout_time',
    'complete_workout', 'get_workout_card'];
  extra text;
  res text;
BEGIN
  -- ── setup (test accounts only) ──
  DELETE FROM daily_team_checkins WHERE user_id IN (A, B, C) AND check_in_date = v_today;
  DELETE FROM active_checkin_sessions WHERE user_id IN (A, B, C);
  INSERT INTO buddy_teams (team_name, created_by) VALUES ('h1 probe', A) RETURNING id INTO v_team;
  INSERT INTO team_members (team_id, user_id) VALUES (v_team, A), (v_team, B);
  INSERT INTO team_streaks (team_id, is_active) VALUES (v_team, true);
  INSERT INTO user_inventory (user_id, shop_item_id, equipped) VALUES (C, RING, true);
  SELECT count(*) INTO nA FROM team_streaks ts JOIN team_members tm ON tm.team_id = ts.team_id
  WHERE tm.user_id = A AND ts.is_active;
  SELECT count(*) INTO nB FROM team_streaks ts JOIN team_members tm ON tm.team_id = ts.team_id
  WHERE tm.user_id = B AND ts.is_active;
  PERFORM pg_temp.ck('setup: A and B each have 2 active streaks', nA = 2 AND nB = 2, nA || '/' || nB);

  -- ── S1: config, grants, anon, unauthenticated ──
  FOREACH f IN ARRAY rpcs || ARRAY['_hs_lock', '_workout_card_json', 'expire_stale_workout_invites', '_set_workout_planned_at'] LOOP
    PERFORM pg_temp.ck('search_path pinned: ' || f,
      (SELECT bool_and('search_path=public' = ANY(proconfig)) FROM pg_proc
       WHERE proname = f AND pronamespace = 'public'::regnamespace));
  END LOOP;
  FOREACH f IN ARRAY rpcs LOOP
    SELECT string_agg(coalesce(ro.rolname, 'PUBLIC'), ',' ORDER BY coalesce(ro.rolname, 'PUBLIC')) INTO r
    FROM pg_proc p, aclexplode(p.proacl) a LEFT JOIN pg_roles ro ON ro.oid = a.grantee
    WHERE p.proname = f AND p.pronamespace = 'public'::regnamespace;
    PERFORM pg_temp.eq('grants exact: ' || f, r, 'authenticated,postgres,service_role');
    PERFORM pg_temp.ck('definer: ' || f, (SELECT bool_and(prosecdef) FROM pg_proc WHERE proname = f AND pronamespace = 'public'::regnamespace));
    extra := CASE f WHEN 'change_workout_time' THEN ', current_date, ''10:00''' WHEN 'complete_workout' THEN ', 30' ELSE '' END;
    r := pg_temp.u(NULL, format('SELECT public.%s(%L%s)::text', f, DUMMY, extra), 'anon');
    PERFORM pg_temp.ck('anon denied: ' || f, r LIKE 'ERR:permission denied%', r);
    r := pg_temp.u(NULL, format('SELECT public.%s(%L%s)::text', f, DUMMY, extra));
    PERFORM pg_temp.eq('unauthenticated denied: ' || f, r, 'ERR:not_authenticated');
  END LOOP;
  FOREACH f IN ARRAY ARRAY['_hs_lock', '_workout_card_json', 'expire_stale_workout_invites'] LOOP
    SELECT string_agg(coalesce(ro.rolname, 'PUBLIC'), ',' ORDER BY coalesce(ro.rolname, 'PUBLIC')) INTO r
    FROM pg_proc p, aclexplode(p.proacl) a LEFT JOIN pg_roles ro ON ro.oid = a.grantee
    WHERE p.proname = f AND p.pronamespace = 'public'::regnamespace;
    PERFORM pg_temp.eq('grants service only: ' || f, r, 'postgres,service_role');
  END LOOP;
  r := pg_temp.u(A, 'SELECT public.expire_stale_workout_invites()::text');
  PERFORM pg_temp.ck('authenticated cannot run expiry', r LIKE 'ERR:permission denied%', r);
  r := pg_temp.u(A, format('SELECT (public._hs_lock(%L)).id::text', DUMMY));
  PERFORM pg_temp.ck('authenticated cannot run _hs_lock', r LIKE 'ERR:permission denied%', r);
  PERFORM pg_temp.eq('not_found', pg_temp.st(pg_temp.call(A, 'im_here', DUMMY)), 'ERR:not_found');

  -- ── S2: accept / decline / overlap ──
  w1 := pg_temp.mk(A, B, '1 hour', 'pending');
  w2 := pg_temp.mk(A, B, '3 hours', 'pending');
  w3 := pg_temp.mk(B, NULL, '90 minutes', 'pending');   -- B's own solo, overlaps w1
  PERFORM pg_temp.eq('planned_at = planned instant (Dublin)',
    (SELECT (planned_at = now() + interval '1 hour')::text FROM workouts WHERE id = w1), 'true');
  PERFORM pg_temp.eq('accept: non-participant', pg_temp.st(pg_temp.call(C, 'accept_workout_invite', w1)), 'ERR:not_participant');
  PERFORM pg_temp.eq('accept: creator refused', pg_temp.st(pg_temp.call(A, 'accept_workout_invite', w1)), 'ERR:not_invitee');
  r := pg_temp.call(B, 'accept_workout_invite', w1);
  PERFORM pg_temp.eq('accept: overlap warning', pg_temp.st(r), 'overlap');
  PERFORM pg_temp.eq('overlap names the other workout', r::jsonb->>'with_workout_id', w3::text);
  PERFORM pg_temp.eq('overlap changes nothing', (SELECT buddy_status FROM workouts WHERE id = w1), 'pending');
  PERFORM pg_temp.eq('accept: p_force', pg_temp.st(pg_temp.call(B, 'accept_workout_invite', w1, ', true')), 'accepted');
  PERFORM pg_temp.eq('accept: repeat idempotent', pg_temp.st(pg_temp.call(B, 'accept_workout_invite', w1)), 'accepted');
  PERFORM pg_temp.eq('decline: creator refused', pg_temp.st(pg_temp.call(A, 'decline_workout_invite', w2)), 'ERR:not_invitee');
  PERFORM pg_temp.eq('decline: happy', pg_temp.st(pg_temp.call(B, 'decline_workout_invite', w2)), 'closed');
  PERFORM pg_temp.eq('decline: row', (SELECT status || '/' || buddy_status || '/' || closed_reason FROM workouts WHERE id = w2), 'cancelled/declined/declined');
  PERFORM pg_temp.eq('decline: repeat idempotent', pg_temp.st(pg_temp.call(B, 'decline_workout_invite', w2)), 'closed');
  PERFORM pg_temp.eq('accept: wrong state (declined)', pg_temp.st(pg_temp.call(B, 'accept_workout_invite', w2)), 'ERR:wrong_state');
  PERFORM pg_temp.eq('decline: wrong state (accepted)', pg_temp.st(pg_temp.call(B, 'decline_workout_invite', w1)), 'ERR:wrong_state');
  PERFORM pg_temp.eq('cancel: invitee refused', pg_temp.st(pg_temp.call(B, 'cancel_workout', w1)), 'ERR:not_creator');
  PERFORM pg_temp.eq('cancel: happy (solo)', pg_temp.st(pg_temp.call(B, 'cancel_workout', w3)), 'closed');
  PERFORM pg_temp.eq('cancel: row', (SELECT status || '/' || closed_reason FROM workouts WHERE id = w3), 'cancelled/cancelled_by_creator');
  PERFORM pg_temp.eq('cancel: repeat idempotent', pg_temp.st(pg_temp.call(B, 'cancel_workout', w3)), 'closed');
  PERFORM pg_temp.eq('im_here: too_early', pg_temp.st(pg_temp.call(B, 'im_here', w1)), 'ERR:too_early');
  w4 := pg_temp.mk(A, B, '-20 minutes', 'accepted');
  PERFORM pg_temp.eq('im_here: window_closed', pg_temp.st(pg_temp.call(A, 'im_here', w4)), 'ERR:window_closed');
  PERFORM pg_temp.eq('im_here: needs accepted', pg_temp.st(pg_temp.call(A, 'im_here', pg_temp.mk(A, B, '0', 'pending'))), 'ERR:wrong_state');
  PERFORM pg_temp.eq('card: waiting_start_time (+1h)', pg_temp.card(A, w1), 'waiting_start_time');

  -- ── S3: creator first, nudge, second tap starts ──
  w5 := pg_temp.mk(A, B, '0', 'accepted');
  PERFORM pg_temp.eq('im_here: non-participant', pg_temp.st(pg_temp.call(C, 'im_here', w5)), 'ERR:not_participant');
  PERFORM pg_temp.eq('card: time_to_start', pg_temp.card(A, w5), 'time_to_start');
  PERFORM pg_temp.eq('im_here: creator first waits', pg_temp.st(pg_temp.call(A, 'im_here', w5)), 'waiting_for_buddy');
  PERFORM pg_temp.eq('im_here: repeat idempotent', pg_temp.st(pg_temp.call(A, 'im_here', w5)), 'waiting_for_buddy');
  PERFORM pg_temp.eq('card: i_am_here (A)', pg_temp.card(A, w5), 'i_am_here');
  PERFORM pg_temp.eq('card: buddy_is_here (B)', pg_temp.card(B, w5), 'buddy_is_here');
  PERFORM pg_temp.eq('nudge: untapped caller refused', pg_temp.st(pg_temp.call(B, 'nudge_workout', w5)), 'ERR:wrong_state');
  PERFORM pg_temp.eq('nudge: non-participant', pg_temp.st(pg_temp.call(C, 'nudge_workout', w5)), 'ERR:not_participant');
  PERFORM pg_temp.eq('nudge: first', pg_temp.st(pg_temp.call(A, 'nudge_workout', w5)), 'nudged');
  r := pg_temp.call(A, 'nudge_workout', w5);
  PERFORM pg_temp.eq('nudge: second inside 10 min refused, detail = seconds left', r, 'ERR:nudge_too_soon|600');
  UPDATE workouts SET last_nudge_at = now() - interval '11 minutes' WHERE id = w5;
  PERFORM pg_temp.eq('nudge: allowed after 10 min', pg_temp.st(pg_temp.call(A, 'nudge_workout', w5)), 'nudged');
  r := pg_temp.call(B, 'im_here', w5);
  PERFORM pg_temp.eq('im_here: second tap starts', pg_temp.st(r), 'started');
  PERFORM pg_temp.eq('started_at returned = server now()', (r::jsonb->>'started_at')::timestamptz::text, now()::text);
  PERFORM pg_temp.eq('row started on server clock',
    (SELECT status || '/' || (workout_started_at = now()) || '/' || (started_by_user_id = B) FROM workouts WHERE id = w5),
    'in_progress/true/true');
  PERFORM pg_temp.eq('both sessions exist, pinned to start',
    (SELECT count(*)::text FROM active_checkin_sessions s JOIN workouts w ON w.id = s.workout_id
     WHERE s.workout_id = w5 AND s.user_id IN (A, B) AND s.started_at = w.workout_started_at), '2');
  PERFORM pg_temp.eq('im_here: repeat after start idempotent (B)', pg_temp.st(pg_temp.call(B, 'im_here', w5)), 'started');
  PERFORM pg_temp.eq('im_here: repeat after start idempotent (A)', pg_temp.st(pg_temp.call(A, 'im_here', w5)), 'started');
  PERFORM pg_temp.eq('card: running', pg_temp.card(A, w5), 'running');
  PERFORM pg_temp.eq('nudge: not while running', pg_temp.st(pg_temp.call(A, 'nudge_workout', w5)), 'ERR:wrong_state');

  -- ── S4: buddy first; already_in_workout ──
  w6 := pg_temp.mk(A, B, '2 minutes', 'accepted', 15);
  PERFORM pg_temp.eq('im_here: buddy first waits', pg_temp.st(pg_temp.call(B, 'im_here', w6)), 'waiting_for_buddy');
  PERFORM pg_temp.eq('card: buddy_is_here (A, buddy first)', pg_temp.card(A, w6), 'buddy_is_here');
  PERFORM pg_temp.eq('card: i_am_here (B, buddy first)', pg_temp.card(B, w6), 'i_am_here');
  PERFORM pg_temp.eq('im_here: already_in_workout', pg_temp.st(pg_temp.call(A, 'im_here', w6)), 'ERR:already_in_workout');
  PERFORM pg_temp.eq('already_in_workout leaves no flag', (SELECT creator_ready::text FROM workouts WHERE id = w6), 'false');

  -- ── S5: leave mid-run; remaining person is credited, leaver is not ──
  PERFORM pg_temp.eq('leave: non-participant', pg_temp.st(pg_temp.call(C, 'leave_workout', w5)), 'ERR:not_participant');
  PERFORM pg_temp.eq('leave: buddy leaves', pg_temp.st(pg_temp.call(B, 'leave_workout', w5)), 'left');
  PERFORM pg_temp.eq('leave: row + sessions',
    (SELECT status || '/' || buddy_cancelled || '/' ||
            (SELECT count(*) FROM active_checkin_sessions WHERE user_id = B) || '/' ||
            (SELECT count(*) FROM active_checkin_sessions WHERE user_id = A AND workout_id = w5)
     FROM workouts WHERE id = w5), 'in_progress/true/0/1');
  PERFORM pg_temp.eq('leave: repeat idempotent', pg_temp.st(pg_temp.call(B, 'leave_workout', w5)), 'left');
  PERFORM pg_temp.eq('card: leaver sees closed', pg_temp.card(B, w5), 'closed');
  PERFORM pg_temp.eq('card: remaining sees running', pg_temp.card(A, w5), 'running');
  UPDATE workouts SET workout_started_at = now() - interval '40 minutes' WHERE id = w5;
  UPDATE active_checkin_sessions SET started_at = now() - interval '40 minutes' WHERE workout_id = w5;
  PERFORM pg_temp.eq('complete: under 15 min refused', pg_temp.st(pg_temp.call(A, 'complete_workout', w5, ', 10')), 'ERR:too_early');
  PERFORM pg_temp.eq('complete: leaver refused', pg_temp.st(pg_temp.call(B, 'complete_workout', w5, ', 30')), 'ERR:wrong_state');
  r := pg_temp.call(A, 'complete_workout', w5, ', 30');
  PERFORM pg_temp.eq('complete: happy', pg_temp.st(r) || '/' || (r::jsonb->>'actual_minutes'), 'completed/30');
  PERFORM pg_temp.eq('complete: row',
    (SELECT status || '/' || actual_duration_minutes || '/' || closed_reason || '/' || (workout_completed_at = now()) FROM workouts WHERE id = w5),
    'completed/30/completed/true');
  r := pg_temp.call(A, 'finish_checkin_session', w5);
  PERFORM pg_temp.eq('finish (remaining): credit on start-local day', r::jsonb->>'credit_date', v_today::text);
  PERFORM pg_temp.eq('finish (remaining): leaver not credited via partner', r::jsonb->>'partner_checked_in', '0');
  PERFORM pg_temp.eq('remaining person credited on all streaks',
    (SELECT count(*)::text FROM daily_team_checkins WHERE user_id = A AND check_in_date = v_today), nA::text);
  PERFORM pg_temp.eq('leaver NOT credited',
    (SELECT count(*)::text FROM daily_team_checkins WHERE user_id = B AND check_in_date = v_today), '0');
  PERFORM pg_temp.eq('leave: wrong state after completion', pg_temp.st(pg_temp.call(A, 'leave_workout', w5)), 'ERR:wrong_state');

  -- ── S6: both tapped (buddy first), finished; credits both, all streaks ──
  r := pg_temp.call(A, 'im_here', w6);
  PERFORM pg_temp.eq('im_here: creator second starts (buddy-first order)', pg_temp.st(r), 'started');
  PERFORM pg_temp.eq('buddy-first: both sessions pinned',
    (SELECT count(*)::text FROM active_checkin_sessions s JOIN workouts w ON w.id = s.workout_id
     WHERE s.workout_id = w6 AND s.started_at = w.workout_started_at AND w.workout_started_at = now()), '2');
  UPDATE workouts SET workout_started_at = now() - interval '30 minutes' WHERE id = w6;
  UPDATE active_checkin_sessions SET started_at = now() - interval '30 minutes' WHERE workout_id = w6;
  PERFORM pg_temp.eq('card: goal_reached', pg_temp.card(A, w6), 'goal_reached');
  DELETE FROM daily_team_checkins WHERE user_id = A AND check_in_date = v_today;
  r := pg_temp.call(B, 'complete_workout', w6, ', 30');
  PERFORM pg_temp.eq('complete: buddy', pg_temp.st(r), 'completed');
  PERFORM pg_temp.eq('complete: buddy_completed_at set', (SELECT (buddy_completed_at = now())::text FROM workouts WHERE id = w6), 'true');
  r := pg_temp.call(B, 'finish_checkin_session', w6);
  PERFORM pg_temp.eq('finish: partner credited (all their streaks)', r::jsonb->>'partner_checked_in', nA::text);
  PERFORM pg_temp.eq('both credited: A all streaks',
    (SELECT count(*)::text FROM daily_team_checkins WHERE user_id = A AND check_in_date = v_today), nA::text);
  PERFORM pg_temp.eq('both credited: B all streaks',
    (SELECT count(*)::text FROM daily_team_checkins WHERE user_id = B AND check_in_date = v_today), nB::text);
  PERFORM pg_temp.eq('complete: second finisher idempotent', pg_temp.st(pg_temp.call(A, 'complete_workout', w6, ', 30')), 'completed');
  PERFORM pg_temp.ck('finish: second finisher no error', pg_temp.call(A, 'finish_checkin_session', w6) NOT LIKE 'ERR:%');
  PERFORM pg_temp.eq('no double credit',
    (SELECT count(*)::text FROM daily_team_checkins WHERE user_id IN (A, B) AND check_in_date = v_today), (nA + nB)::text);

  -- ── S7: cant_make_it, go_solo, cancel ──
  w7 := pg_temp.mk(A, B, '1 day', 'accepted');
  PERFORM pg_temp.eq('cant_make_it: creator refused', pg_temp.st(pg_temp.call(A, 'cant_make_it', w7)), 'ERR:not_invitee');
  PERFORM pg_temp.eq('cant_make_it: happy', pg_temp.st(pg_temp.call(B, 'cant_make_it', w7)), 'closed');
  PERFORM pg_temp.eq('cant_make_it: row', (SELECT status || '/' || buddy_cancelled || '/' || buddy_ready || '/' || coalesce(closed_reason, 'null') FROM workouts WHERE id = w7), 'scheduled/true/false/null');
  PERFORM pg_temp.eq('cant_make_it: repeat idempotent', pg_temp.st(pg_temp.call(B, 'cant_make_it', w7)), 'closed');
  PERFORM pg_temp.eq('cant_make_it: wrong state (pending)', pg_temp.st(pg_temp.call(B, 'cant_make_it', pg_temp.mk(A, B, '1 day', 'pending'))), 'ERR:wrong_state');
  PERFORM pg_temp.eq('card: buddy_cant_make_it (inviter)', pg_temp.card(A, w7), 'buddy_cant_make_it');
  PERFORM pg_temp.eq('card: closed (invitee)', pg_temp.card(B, w7), 'closed');
  PERFORM pg_temp.eq('go_solo: invitee refused', pg_temp.st(pg_temp.call(B, 'go_solo', w7)), 'ERR:not_creator');
  PERFORM pg_temp.eq('go_solo: wrong state (buddy still in)', pg_temp.st(pg_temp.call(A, 'go_solo', w1)), 'ERR:wrong_state');
  PERFORM pg_temp.eq('go_solo: happy', pg_temp.st(pg_temp.call(A, 'go_solo', w7)), 'solo');
  PERFORM pg_temp.eq('go_solo: row', (SELECT coalesce(buddy_id::text, 'null') || '/' || status || '/' || buddy_status FROM workouts WHERE id = w7), 'null/scheduled/pending');
  PERFORM pg_temp.eq('go_solo: repeat idempotent', pg_temp.st(pg_temp.call(A, 'go_solo', w7)), 'solo');
  PERFORM pg_temp.eq('card: solo scheduled waits', pg_temp.card(A, w7), 'waiting_start_time');
  PERFORM pg_temp.eq('card: old buddy locked out', pg_temp.card(B, w7), 'ERR:not_participant');
  PERFORM pg_temp.eq('cancel after go_solo', pg_temp.st(pg_temp.call(A, 'cancel_workout', w7)), 'closed');
  PERFORM pg_temp.eq('cancel: row', (SELECT status || '/' || closed_reason FROM workouts WHERE id = w7), 'cancelled/cancelled_by_creator');
  PERFORM pg_temp.eq('im_here after cancel', pg_temp.st(pg_temp.call(A, 'im_here', w7)), 'ERR:wrong_state');
  PERFORM pg_temp.eq('go_solo after decline reopens', pg_temp.st(pg_temp.call(A, 'go_solo', w2)), 'solo');

  -- ── S8: change_workout_time resets the buddy ──
  w8 := pg_temp.mk(A, B, '0', 'accepted');
  PERFORM pg_temp.eq('change_time setup: buddy here', pg_temp.st(pg_temp.call(B, 'im_here', w8)), 'waiting_for_buddy');
  PERFORM pg_temp.eq('change_time: invitee refused', pg_temp.st(pg_temp.call(B, 'change_workout_time', w8, format(', %L, ''10:00''', v_today + 1))), 'ERR:not_creator');
  PERFORM pg_temp.eq('change_time: past refused', pg_temp.st(pg_temp.call(A, 'change_workout_time', w8, format(', %L, ''10:00''', v_today - 1))), 'ERR:window_closed');
  PERFORM pg_temp.eq('change_time: happy', pg_temp.st(pg_temp.call(A, 'change_workout_time', w8, format(', %L, ''10:00''', v_today + 1))), 'rescheduled');
  PERFORM pg_temp.eq('change_time: buddy reset, planned_at recomputed',
    (SELECT buddy_status || '/' || buddy_ready || '/' || creator_ready || '/' ||
            (planned_at = ((v_today + 1) + time '10:00') AT TIME ZONE 'Europe/Dublin') FROM workouts WHERE id = w8),
    'pending/false/false/true');
  PERFORM pg_temp.eq('change_time: wrong state (completed)', pg_temp.st(pg_temp.call(A, 'change_workout_time', w5, format(', %L, ''10:00''', v_today + 1))), 'ERR:wrong_state');

  -- ── S9: solo start + abandon ──
  w9 := pg_temp.mk(A, NULL, '0', 'pending', 30);
  PERFORM pg_temp.eq('im_here: solo starts at once', pg_temp.st(pg_temp.call(A, 'im_here', w9)), 'started');
  PERFORM pg_temp.eq('card: solo (running)', pg_temp.card(A, w9), 'solo');
  PERFORM pg_temp.eq('leave: solo abandon', pg_temp.st(pg_temp.call(A, 'leave_workout', w9)), 'closed');
  PERFORM pg_temp.eq('leave: solo row', (SELECT status || '/' || closed_reason || '/' || (SELECT count(*) FROM active_checkin_sessions WHERE user_id = A) FROM workouts WHERE id = w9), 'cancelled/solo_abandoned/0');

  -- ── S11: card fields, ring colour without a shared team, invites ──
  w14 := pg_temp.mk(A, B, '-1 minute', 'accepted');
  w15 := pg_temp.mk(A, C, '4 hours', 'pending');
  r := pg_temp.u(A, format('SELECT public.get_workout_card(%L)::text', w15));
  PERFORM pg_temp.eq('card: invited friend ring colour (no shared team)', r::jsonb->'workout'->'other_person'->>'ring_color', '#FF6F5E');
  PERFORM pg_temp.eq('card: other person fields', r::jsonb->'workout'->'other_person'->>'avatar_id' || '/' || (r::jsonb->'workout'->'other_person'->>'avatar_border'), 'lion/simple');
  PERFORM pg_temp.ck('card: window/expiry/server time',
    (r::jsonb->'workout'->>'window_opens_at')::timestamptz = now() + interval '235 minutes'
    AND (r::jsonb->'workout'->>'expires_at')::timestamptz = now() + interval '255 minutes'
    AND (r::jsonb->>'server_now')::timestamptz = now());
  PERFORM pg_temp.eq('ring colour NOT readable directly (RLS)',
    pg_temp.u(A, format('SELECT count(*)::text FROM user_inventory WHERE user_id = %L', C)), '0');
  r := pg_temp.u(C, 'SELECT public.get_workout_card()::text');
  PERFORM pg_temp.eq('card (no id): nothing current for C', r::jsonb->>'state', 'none');
  PERFORM pg_temp.eq('card (no id): C sees received invite',
    (SELECT e->>'workout_id' || '/' || (e->>'direction') FROM jsonb_array_elements(r::jsonb->'invites') e), w15 || '/received');
  r := pg_temp.u(A, 'SELECT public.get_workout_card()::text');
  PERFORM pg_temp.eq('card (no id): A next = soonest open', r::jsonb->'workout'->>'workout_id', w14::text);
  PERFORM pg_temp.eq('card (no id): A open_invite_count (pending sent)', r::jsonb->>'open_invite_count', '4');
  PERFORM pg_temp.eq('card: non-participant', pg_temp.card(C, w5), 'ERR:not_participant');
  PERFORM pg_temp.eq('card: completed is closed', pg_temp.card(A, w6), 'closed');

  -- ── S12: expiry ──
  w10 := pg_temp.mk(A, B, '-20 minutes', 'pending');
  w11 := pg_temp.mk(A, B, '-30 minutes', 'accepted');
  w12 := pg_temp.mk(A, B, '-40 minutes', 'accepted');
  UPDATE workouts SET status = 'in_progress', workout_started_at = now() - interval '30 minutes' WHERE id = w12;
  w13 := pg_temp.mk(A, NULL, '-1 hour', 'pending');
  PERFORM pg_temp.eq('card: expired-not-swept reads closed', pg_temp.card(A, w10), 'closed');
  n := public.expire_stale_workout_invites();
  PERFORM pg_temp.eq('expiry: pending closed', (SELECT status || '/' || buddy_status || '/' || closed_reason FROM workouts WHERE id = w10), 'cancelled/expired/expired');
  PERFORM pg_temp.eq('expiry: accepted-never-started closed', (SELECT status || '/' || buddy_status || '/' || closed_reason FROM workouts WHERE id = w11), 'cancelled/accepted/expired');
  PERFORM pg_temp.eq('expiry: running untouched', (SELECT status || '/' || coalesce(closed_reason, 'null') FROM workouts WHERE id = w12), 'in_progress/null');
  PERFORM pg_temp.eq('expiry: solo untouched', (SELECT status FROM workouts WHERE id = w13), 'scheduled');
  PERFORM pg_temp.eq('expiry: future untouched', (SELECT status FROM workouts WHERE id = w1), 'scheduled');
  PERFORM pg_temp.eq('expiry: repeat closes nothing new', public.expire_stale_workout_invites()::text, '0');
  PERFORM pg_temp.ck('expiry: run count', n >= 3, n::text);

  -- ── S13: invite cap (client inserts, sender C → B) ──
  SELECT count(*) INTO q0 FROM net.http_request_queue;
  FOR i IN 1..5 LOOP
    r := pg_temp.u(C, format(
      'INSERT INTO workouts (user_id, buddy_id, workout_type, workout_date, workout_time, planned_duration_minutes, status, buddy_status, buddy_ready, creator_ready, buddy_cancelled, closed_reason, last_nudge_at, planned_at) ' ||
      'VALUES (%L, %L, ''Strength'', %L, ''09:00'', 60, ''scheduled'', ''accepted'', true, true, true, ''completed'', now(), now()) RETURNING id::text',
      C, B, v_today + 1 + i));
    PERFORM pg_temp.ck('cap: invite ' || i || ' allowed', r NOT LIKE 'ERR:%', r);
    cap := cap || r::uuid;
  END LOOP;
  PERFORM pg_temp.eq('client insert: forged fields forced safe',
    (SELECT buddy_status || '/' || buddy_ready || '/' || creator_ready || '/' || buddy_cancelled || '/' ||
            coalesce(closed_reason, 'null') || '/' || coalesce(last_nudge_at::text, 'null') || '/' ||
            (planned_at = ((v_today + 2) + time '09:00') AT TIME ZONE 'Europe/Dublin') FROM workouts WHERE id = cap[1]),
    'pending/false/false/false/null/null/true');
  f := format('INSERT INTO workouts (user_id, buddy_id, workout_type, workout_date, workout_time, planned_duration_minutes, status) ' ||
              'VALUES (%L, %L, ''Strength'', %L, ''18:00'', 60, ''scheduled'') RETURNING id::text', C, B, v_today + 20);
  PERFORM pg_temp.eq('cap: 6th refused', pg_temp.u(C, f), 'ERR:invite_cap_reached');
  PERFORM pg_temp.eq('cap: receiver sees only 5',
    pg_temp.u(B, format('SELECT count(*)::text FROM workouts WHERE user_id = %L AND buddy_status = ''pending'' AND status = ''scheduled''', C)), '5');
  PERFORM pg_temp.eq('cap: solo insert unaffected',
    CASE WHEN pg_temp.u(C, format('INSERT INTO workouts (user_id, workout_type, workout_date, workout_time, status) VALUES (%L, ''Strength'', %L, ''07:00'', ''scheduled'') RETURNING id::text', C, v_today + 21)) LIKE 'ERR:%' THEN 'err' ELSE 'ok' END, 'ok');
  PERFORM pg_temp.eq('cap: decline frees a slot (decline)', pg_temp.st(pg_temp.call(B, 'decline_workout_invite', cap[1])), 'closed');
  r := pg_temp.u(C, f);
  PERFORM pg_temp.ck('cap: allowed after a decline', r NOT LIKE 'ERR:%', r);
  PERFORM pg_temp.eq('cap: accepted does not count (accept)', pg_temp.st(pg_temp.call(B, 'accept_workout_invite', cap[2], ', true')), 'accepted');
  r := pg_temp.u(C, replace(f, '18:00', '19:00'));
  PERFORM pg_temp.ck('cap: allowed after an accept', r NOT LIKE 'ERR:%', r);
  PERFORM pg_temp.eq('cap: full again', pg_temp.u(C, replace(f, '18:00', '20:00')), 'ERR:invite_cap_reached');
  UPDATE workouts SET workout_date = v_today - 1 WHERE id = cap[3];
  r := pg_temp.u(C, replace(f, '18:00', '21:00'));
  PERFORM pg_temp.ck('cap: expired invite frees a slot', r NOT LIKE 'ERR:%', r);
  PERFORM pg_temp.eq('cap: card count', pg_temp.u(C, 'SELECT public.get_workout_card()::text')::jsonb->>'open_invite_count', '5');
  PERFORM pg_temp.eq('cap/invites: no push queued', ((SELECT count(*) FROM net.http_request_queue) - q0)::text, '0');

  -- ── S14: realtime ──
  PERFORM pg_temp.eq('publication has workouts',
    (SELECT count(*)::text FROM pg_publication_tables WHERE pubname = 'supabase_realtime' AND schemaname = 'public' AND tablename = 'workouts'), '1');
  INSERT INTO realtime.messages (topic, extension, event, payload, private)
  VALUES ('workouts', 'broadcast', 'probe', '{}', true), ('secret', 'broadcast', 'probe', '{}', true),
         ('dashboard_checkins', 'broadcast', 'probe', '{}', true), ('workouts', 'postgres_changes', 'probe', '{}', true);
  PERFORM set_config('realtime.topic', 'workouts', true);
  PERFORM pg_temp.eq('realtime: join workouts topic',
    pg_temp.u(A, 'SELECT count(*)::text FROM realtime.messages WHERE topic = ''workouts'' AND event = ''probe'''), '1');
  PERFORM pg_temp.eq('realtime: other topics closed while on workouts',
    pg_temp.u(A, 'SELECT count(*)::text FROM realtime.messages WHERE topic <> ''workouts'' AND event = ''probe'''), '0');
  PERFORM pg_temp.eq('realtime: anon closed',
    coalesce(nullif(pg_temp.u(NULL, 'SELECT count(*)::text FROM realtime.messages WHERE event = ''probe''', 'anon'), ''), '0'), '0');
  PERFORM set_config('realtime.topic', 'secret', true);
  PERFORM pg_temp.eq('realtime: unknown topic closed',
    pg_temp.u(A, 'SELECT count(*)::text FROM realtime.messages WHERE event = ''probe'''), '0');
  PERFORM set_config('realtime.topic', 'dashboard_checkins', true);
  PERFORM pg_temp.eq('realtime: dashboard_checkins still works',
    pg_temp.u(A, 'SELECT count(*)::text FROM realtime.messages WHERE event = ''probe'''), '1');
  PERFORM set_config('realtime.topic', '', true);
  PERFORM pg_temp.eq('rows: participant A sees w5', pg_temp.u(A, format('SELECT count(*)::text FROM workouts WHERE id = %L', w5)), '1');
  PERFORM pg_temp.eq('rows: participant B sees w5', pg_temp.u(B, format('SELECT count(*)::text FROM workouts WHERE id = %L', w5)), '1');
  PERFORM pg_temp.eq('rows: outsider C sees nothing', pg_temp.u(C, format('SELECT count(*)::text FROM workouts WHERE id = %L', w5)), '0');

  -- ── S15: Phase B (lockdown) inside this transaction ──
  w16 := pg_temp.mk(A, B, '2 hours', 'pending');
  PERFORM pg_temp.ck('before B: forgery possible (H0 hole)',
    pg_temp.u(A, format('UPDATE workouts SET buddy_ready = true WHERE id = %L RETURNING buddy_ready::text', w16)) = 'true');
  UPDATE workouts SET buddy_ready = false WHERE id = w16;
  REVOKE UPDATE ON public.workouts FROM authenticated, anon;
  DROP POLICY "Users can update own or buddy workouts" ON public.workouts;
  DROP POLICY "Users can update their workouts" ON public.workouts;
  PERFORM cron.unschedule('reset-expired-ready');
  r := pg_temp.u(B, format('UPDATE workouts SET buddy_status = ''accepted'' WHERE id = %L RETURNING id::text', w16));
  PERFORM pg_temp.ck('B: forged buddy_status by invitee denied', r LIKE 'ERR:permission denied%', r);
  r := pg_temp.u(A, format('UPDATE workouts SET buddy_ready = true WHERE id = %L RETURNING id::text', w16));
  PERFORM pg_temp.ck('B: forged buddy_ready by creator denied', r LIKE 'ERR:permission denied%', r);
  PERFORM pg_temp.eq('B: row unchanged', (SELECT buddy_status || '/' || buddy_ready FROM workouts WHERE id = w16), 'pending/false');
  PERFORM pg_temp.eq('B: reset-expired-ready unscheduled', (SELECT count(*)::text FROM cron.job WHERE jobname = 'reset-expired-ready'), '0');
  w17 := pg_temp.mk(A, B, '0', 'pending', 15);
  PERFORM pg_temp.eq('B: accept', pg_temp.st(pg_temp.call(B, 'accept_workout_invite', w17, ', true')), 'accepted');
  PERFORM pg_temp.eq('B: im_here 1', pg_temp.st(pg_temp.call(A, 'im_here', w17)), 'waiting_for_buddy');
  PERFORM pg_temp.eq('B: nudge', pg_temp.st(pg_temp.call(A, 'nudge_workout', w17)), 'nudged');
  PERFORM pg_temp.eq('B: im_here 2 starts', pg_temp.st(pg_temp.call(B, 'im_here', w17)), 'started');
  UPDATE workouts SET workout_started_at = now() - interval '30 minutes' WHERE id = w17;
  PERFORM pg_temp.eq('B: leave', pg_temp.st(pg_temp.call(B, 'leave_workout', w17)), 'left');
  PERFORM pg_temp.eq('B: complete', pg_temp.st(pg_temp.call(A, 'complete_workout', w17, ', 20')), 'completed');
  PERFORM pg_temp.ck('B: finish_checkin_session', pg_temp.call(A, 'finish_checkin_session', w17) NOT LIKE 'ERR:%');
  w18 := pg_temp.mk(A, B, '1 day', 'accepted');
  PERFORM pg_temp.eq('B: cant_make_it', pg_temp.st(pg_temp.call(B, 'cant_make_it', w18)), 'closed');
  PERFORM pg_temp.eq('B: go_solo', pg_temp.st(pg_temp.call(A, 'go_solo', w18)), 'solo');
  PERFORM pg_temp.eq('B: change_workout_time', pg_temp.st(pg_temp.call(A, 'change_workout_time', w18, format(', %L, ''11:00''', v_today + 2))), 'rescheduled');
  PERFORM pg_temp.eq('B: cancel_workout', pg_temp.st(pg_temp.call(A, 'cancel_workout', w18)), 'closed');
  w19 := pg_temp.mk(A, B, '2 days', 'pending');
  PERFORM pg_temp.eq('B: decline', pg_temp.st(pg_temp.call(B, 'decline_workout_invite', w19)), 'closed');
  w20 := pg_temp.mk(A, NULL, '0', 'pending', 30);
  PERFORM pg_temp.eq('B: solo im_here', pg_temp.st(pg_temp.call(A, 'im_here', w20)), 'started');
  PERFORM pg_temp.eq('B: solo leave', pg_temp.st(pg_temp.call(A, 'leave_workout', w20)), 'closed');
  PERFORM pg_temp.ck('B: get_workout_card', pg_temp.u(A, 'SELECT public.get_workout_card()::text') NOT LIKE 'ERR:%');
  r := pg_temp.u(A, format('INSERT INTO workouts (user_id, workout_type, workout_date, workout_time, status) VALUES (%L, ''Strength'', %L, ''07:00'', ''scheduled'') RETURNING id::text', A, v_today + 3));
  PERFORM pg_temp.ck('B: client INSERT still works', r NOT LIKE 'ERR:%', r);

  SELECT count(*) FILTER (WHERE ok) || ' pass, ' || count(*) FILTER (WHERE NOT ok) || ' fail. FAILED: ' ||
         coalesce(string_agg(t || ' [' || coalesce(info, '') || ']', '; ') FILTER (WHERE NOT ok), 'none')
  INTO res FROM pr;
  RAISE EXCEPTION 'PROBE_RESULTS: %', res;
END $probe$;
