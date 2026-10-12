-- 04c probe (LIVE-10 profile visibility). One transaction; ends in RAISE EXCEPTION
-- so everything rolls back, including the setup rows and the throwaway column.
-- Test accounts only: rokitest1 (A, caller), newesttest (B, made A's friend,
-- teammate and workout buddy inside the txn), testtest1 (C, stranger).
-- Embedded selects are the SQL PostgREST generates for the Dart queries: a
-- correlated subquery on user_profiles per embed, run as the caller.
CREATE TEMP TABLE pr (n serial, t text, ok boolean, info text);

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

CREATE FUNCTION pg_temp.ck(p_t text, p_ok boolean, p_info text DEFAULT NULL) RETURNS void
LANGUAGE sql AS $$ INSERT INTO pr (t, ok, info) VALUES (p_t, coalesce(p_ok, false), p_info) $$;
CREATE FUNCTION pg_temp.eq(p_t text, p_got text, p_want text) RETURNS void
LANGUAGE sql AS $$ SELECT pg_temp.ck(p_t, p_got IS NOT DISTINCT FROM p_want, 'got ' || coalesce(p_got, 'NULL')) $$;
CREATE FUNCTION pg_temp.denied(p_t text, p_got text) RETURNS void
LANGUAGE sql AS $$ SELECT pg_temp.ck(p_t, p_got LIKE 'ERR:permission denied%', 'got ' || coalesce(p_got, 'NULL')) $$;

DO $probe$
DECLARE
  A uuid := '5e67f64d-16e3-4b09-9b00-ddc49df8c3f6';  -- rokitest1
  B uuid := '6ef4e82e-a54d-4b91-8ce4-b5f179a65f66';  -- newesttest
  C uuid := 'cf4946f5-f921-4e81-bbf4-88d574e8baf5';  -- testtest1
  CM uuid := '00000000-0000-0000-0000-000000000001';
  N uuid := gen_random_uuid();  -- throwaway auth user, rolled back
  v_today date := (now() AT TIME ZONE public.safe_user_tz(A))::date;
  v_team uuid; v_streak uuid; v_w uuid; r text; r2 text; res text;
  q_embed_inprog text; q_order_old text; q_await_old text;
BEGIN
  -- ── setup (as postgres): A and B friends, teammates, workout buddies ──
  UPDATE user_profiles SET timezone = 'Asia/Tokyo' WHERE id = B;
  INSERT INTO friendships (user_id, friend_id, status) VALUES (A, B, 'accepted');
  INSERT INTO friendships (user_id, friend_id, status) VALUES (C, A, 'pending');
  INSERT INTO buddy_teams (team_name, created_by) VALUES ('04c probe', A) RETURNING id INTO v_team;
  INSERT INTO team_members (team_id, user_id) VALUES (v_team, A), (v_team, B);
  INSERT INTO team_streaks (team_id) VALUES (v_team) RETURNING id INTO v_streak;
  INSERT INTO daily_team_checkins (team_streak_id, user_id, check_in_date, check_in_time)
  VALUES (v_streak, B, v_today, now() - interval '2 hours'), (v_streak, A, v_today, now() - interval '1 hour');
  INSERT INTO workouts (user_id, buddy_id, workout_type, workout_date, workout_time,
                        planned_duration_minutes, status, buddy_status, started_by_user_id, workout_started_at)
  VALUES (A, B, 'Strength', v_today, '07:00', 60, 'in_progress', 'accepted', B, now())
  RETURNING id INTO v_w;
  INSERT INTO workout_logs (user_id, workout_date, workout_time, workout_name, workout_category, buddy_id, actual_duration_minutes)
  VALUES (A, v_today, now(), '04c probe', 'Strength', B, 30);

  -- ── 1. stranger C ──
  PERFORM pg_temp.denied('1 C: B.age', pg_temp.u(C, format('SELECT age::text FROM user_profiles WHERE id = %L', B)));
  PERFORM pg_temp.denied('1 C: B.timezone', pg_temp.u(C, format('SELECT timezone FROM user_profiles WHERE id = %L', B)));
  PERFORM pg_temp.denied('1 C: B.coin_balance', pg_temp.u(C, format('SELECT coin_balance::text FROM user_profiles WHERE id = %L', B)));
  PERFORM pg_temp.denied('1 C: select *', pg_temp.u(C, format('SELECT id::text FROM (SELECT * FROM user_profiles WHERE id = %L) x', B)));
  PERFORM pg_temp.denied('1 C: filter on private col', pg_temp.u(C, 'SELECT count(*)::text FROM user_profiles WHERE is_bot'));
  r := pg_temp.u(C, format('SELECT row_to_json(p)::text FROM (SELECT id, username, display_name, avatar_id, avatar_border, fitness_level,
       looking_for_buddy, workout_days_per_week, created_at FROM user_profiles WHERE id = %L) p', B));
  PERFORM pg_temp.eq('1 C: B discovery cols', r, (SELECT row_to_json(p)::text FROM (SELECT id, username, display_name, avatar_id, avatar_border,
       fitness_level, looking_for_buddy, workout_days_per_week, created_at FROM user_profiles WHERE id = B) p));
  PERFORM pg_temp.eq('1 C: get_my_profile is own row only', pg_temp.u(C, 'SELECT string_agg(id::text, '','') FROM public.get_my_profile()'), C::text);
  PERFORM pg_temp.eq('1 C: Coach Max discovery still visible', pg_temp.u(C, format('SELECT display_name IS NOT NULL AND avatar_id IS NOT NULL FROM user_profiles WHERE id = %L', CM)), 'true');

  -- ── 2. own row (A) ──
  r := pg_temp.u(A, 'SELECT row_to_json(p)::text FROM public.get_my_profile() p');
  PERFORM pg_temp.eq('2 A: get_my_profile 28 cols', (SELECT count(*)::text FROM json_object_keys(r::json)), '28');
  PERFORM pg_temp.eq('2 A: get_my_profile = table row', r, (SELECT row_to_json(p)::text FROM user_profiles p WHERE id = A));
  PERFORM pg_temp.denied('2 A: own private col via table (now via get_my_profile)', pg_temp.u(A, format('SELECT xp::text FROM user_profiles WHERE id = %L', A)));
  r := pg_temp.u(A, format('UPDATE user_profiles SET preferred_streak_sort = ''alpha'', timezone = ''Europe/Paris'', updated_at = now() WHERE id = %L RETURNING 1', A));
  PERFORM pg_temp.eq('2 A: own update', r || '|' || (SELECT preferred_streak_sort || '/' || timezone FROM user_profiles WHERE id = A), '1|alpha/Europe/Paris');
  r := pg_temp.u(A, format(
    'INSERT INTO user_profiles (id, display_name, username, age, gender, avatar_id, avatar_border, fitness_goals,
                                fitness_level, looking_for_buddy, preferred_workout_style, onboarding_completed, updated_at)
     SELECT id, display_name, username, age, gender, avatar_id, avatar_border, fitness_goals, fitness_level,
            looking_for_buddy, preferred_workout_style, true, now() FROM json_populate_record(null::user_profiles, %L)
     ON CONFLICT (id) DO UPDATE SET display_name = EXCLUDED.display_name, username = EXCLUDED.username, age = EXCLUDED.age,
       gender = EXCLUDED.gender, avatar_id = EXCLUDED.avatar_id, avatar_border = EXCLUDED.avatar_border,
       fitness_goals = EXCLUDED.fitness_goals, fitness_level = EXCLUDED.fitness_level, looking_for_buddy = EXCLUDED.looking_for_buddy,
       preferred_workout_style = EXCLUDED.preferred_workout_style, onboarding_completed = EXCLUDED.onboarding_completed,
       updated_at = EXCLUDED.updated_at RETURNING 1',
    (SELECT row_to_json(p) FROM user_profiles p WHERE id = A)));
  PERFORM pg_temp.denied('2 A: old onboarding upsert (EXCLUDED reads private cols, why the client now inserts)', r);
  -- onboarding now does a plain insert for a brand-new user (no profile row exists before it)
  INSERT INTO auth.users (id, instance_id, aud, role, email) VALUES (N, '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', '04c-probe@example.invalid');
  r := pg_temp.u(N, format(
    'INSERT INTO user_profiles (id, display_name, username, age, gender, avatar_id, avatar_border, fitness_goals,
                                fitness_level, looking_for_buddy, preferred_workout_style, onboarding_completed, updated_at)
     VALUES (%L, ''Probe'', ''zz04cprobe'', 30, ''other'', ''a1'', ''simple'', ARRAY[''strength''], ''beginner'', true, ''gym'', true, now()) RETURNING 1', N));
  PERFORM pg_temp.eq('2 N: onboarding insert (new user)', r, '1');
  PERFORM pg_temp.eq('2 N: own row readable via get_my_profile', pg_temp.u(N, 'SELECT username || ''/'' || age FROM public.get_my_profile()'), 'zz04cprobe/30');
  PERFORM pg_temp.denied('2 A: coin_balance update still blocked', pg_temp.u(A, format('UPDATE user_profiles SET coin_balance = 999999 WHERE id = %L RETURNING 1', A)));
  PERFORM pg_temp.eq('2 A: update of B row hits 0 rows', pg_temp.u(A, format('WITH x AS (UPDATE user_profiles SET display_name = ''pwn'' WHERE id = %L RETURNING 1) SELECT count(*)::text FROM x', B)), '0');

  -- ── 3. friend and teammate ──
  PERFORM pg_temp.eq('3 B: A discovery', pg_temp.u(B, format('SELECT username FROM user_profiles WHERE id = %L', A)), 'rokitest1');
  PERFORM pg_temp.denied('3 B (friend+teammate): A.age', pg_temp.u(B, format('SELECT age::text FROM user_profiles WHERE id = %L', A)));
  PERFORM pg_temp.eq('3 A: teammate tz', pg_temp.u(A, format('SELECT string_agg(user_id || ''='' || timezone, '','') FROM public.get_teammate_timezones(ARRAY[%L, %L]::uuid[])', B, C)), B || '=Asia/Tokyo');
  PERFORM pg_temp.eq('3 B: teammate tz', pg_temp.u(B, format('SELECT string_agg(timezone, '','') FROM public.get_teammate_timezones(ARRAY[%L]::uuid[])', A)), 'Europe/Paris');
  PERFORM pg_temp.eq('3 C: non-teammate tz', pg_temp.u(C, format('SELECT count(*)::text FROM public.get_teammate_timezones(ARRAY[%L, %L]::uuid[])', A, B)), '0');

  -- ── 4. anon ──
  PERFORM pg_temp.denied('4 anon: table', pg_temp.u(NULL, 'SELECT id::text FROM user_profiles LIMIT 1', 'anon'));
  PERFORM pg_temp.denied('4 anon: get_my_profile', pg_temp.u(NULL, 'SELECT id::text FROM public.get_my_profile()', 'anon'));
  PERFORM pg_temp.denied('4 anon: get_teammate_timezones', pg_temp.u(NULL, format('SELECT timezone FROM public.get_teammate_timezones(ARRAY[%L]::uuid[])', A), 'anon'));
  PERFORM pg_temp.denied('4 anon: get_team_checkin_order', pg_temp.u(NULL, format('SELECT 1 FROM public.get_team_checkin_order(%L, %L)', v_streak, v_today), 'anon'));
  PERFORM pg_temp.denied('4 anon: get_workouts_awaiting_creator_join', pg_temp.u(NULL, format('SELECT 1 FROM public.get_workouts_awaiting_creator_join(%L)', A), 'anon'));

  -- ── 5. embedded selects, copied from the Dart ──
  -- workout_service in-progress: creator/buddy (display_name, fitness_level, avatar_id)
  q_embed_inprog := 'SELECT json_agg(json_build_object(''id'', w.id,
       ''creator'', (SELECT row_to_json(c) FROM (SELECT display_name, fitness_level, avatar_id FROM user_profiles WHERE id = w.user_id) c),
       ''buddy'',   (SELECT row_to_json(b) FROM (SELECT display_name, fitness_level, avatar_id FROM user_profiles WHERE id = w.buddy_id) b)))::text
     FROM workouts w WHERE (w.user_id = %1$L OR w.buddy_id = %1$L) AND w.status = ''in_progress'' AND w.id = %2$L';
  r := pg_temp.u(B, format(q_embed_inprog, B, v_w));
  PERFORM pg_temp.eq('5 B workouts: creator name+avatar', (SELECT (e->'creator'->>'display_name') IS NOT NULL AND (e->'creator'->>'avatar_id') IS NOT NULL FROM json_array_elements(r::json) e)::text, 'true');
  r := pg_temp.u(A, format(q_embed_inprog, A, v_w));
  PERFORM pg_temp.eq('5 A workouts: buddy name+avatar', (SELECT (e->'buddy'->>'display_name') = (SELECT display_name FROM user_profiles WHERE id = B) AND (e->'buddy'->>'avatar_id') IS NOT NULL FROM json_array_elements(r::json) e)::text, 'true');
  PERFORM pg_temp.denied('5 A workouts: embed of private col fails', pg_temp.u(A, format(
    'SELECT json_agg((SELECT age FROM user_profiles WHERE id = w.buddy_id))::text FROM workouts w WHERE w.id = %L', v_w)));
  -- workout_history_service: buddy:user_profiles!workout_logs_buddy_id_fkey(display_name)
  r := pg_temp.u(A, format('SELECT string_agg((SELECT display_name FROM user_profiles WHERE id = l.buddy_id), '','') FROM workout_logs l WHERE l.user_id = %L AND l.workout_name = ''04c probe''', A));
  PERFORM pg_temp.eq('5 A history: buddy name', r, (SELECT display_name FROM user_profiles WHERE id = B));
  -- friend_service:336 pending requests: user_profiles!friendships_user_id_fkey(id, display_name, username, avatar_id, fitness_level)
  r := pg_temp.u(A, format('SELECT json_agg((SELECT row_to_json(p) FROM (SELECT id, display_name, username, avatar_id, fitness_level FROM user_profiles WHERE id = f.user_id) p))::text
                            FROM friendships f WHERE f.friend_id = %L AND f.status = ''pending''', A));
  PERFORM pg_temp.ck('5 A pending request: requester username', r LIKE '%"username":"testtest1"%', r);
  -- friend_service:390 friend list
  r := pg_temp.u(A, format('SELECT json_agg(p)::text FROM (SELECT id, username, display_name, avatar_id, avatar_border, fitness_level, looking_for_buddy, workout_days_per_week FROM user_profiles WHERE id IN (%L)) p', B));
  PERFORM pg_temp.ck('5 A friend list', r LIKE '%"username":"newesttest"%', r);
  -- friend_service:35 search
  r := pg_temp.u(A, format('SELECT string_agg(username, '','') FROM (SELECT id, username, display_name, fitness_level, avatar_id FROM user_profiles WHERE username ILIKE ''%%newesttes%%'' AND id <> %L AND username IS NOT NULL LIMIT 20) s', A));
  PERFORM pg_temp.eq('5 A search', r, 'newesttest');
  -- profile_view_dialog:53, onboarding:247
  PERFORM pg_temp.ck('5 A profile dialog created_at', pg_temp.u(A, format('SELECT created_at::text FROM user_profiles WHERE id = %L', B)) NOT LIKE 'ERR:%');
  PERFORM pg_temp.eq('5 A username taken check', pg_temp.u(A, 'SELECT id::text FROM user_profiles WHERE username = ''newesttest'''), B::text);
  -- team member names (team card) come from get_user_streaks (DEFINER)
  r := pg_temp.u(A, format('SELECT public.get_user_streaks(%L)::text', A));
  PERFORM pg_temp.ck('5 A team card: teammate name via get_user_streaks', r LIKE '%' || (SELECT display_name FROM user_profiles WHERE id = B) || '%', left(r, 200));

  -- ── 6. definer functions vs the old INVOKER bodies run as the same caller ──
  q_order_old := 'SELECT json_agg(x)::text FROM (SELECT dtc.user_id, up.display_name, dtc.check_in_time,
       ROW_NUMBER() OVER (ORDER BY dtc.check_in_time)::INTEGER as check_order
     FROM daily_team_checkins dtc JOIN user_profiles up ON dtc.user_id = up.id
     WHERE dtc.team_streak_id = %L AND dtc.check_in_date = %L ORDER BY dtc.check_in_time) x';
  FOREACH r2 IN ARRAY ARRAY[A::text, B::text, C::text] LOOP
    r := pg_temp.u(r2::uuid, format('SELECT json_agg(x)::text FROM public.get_team_checkin_order(%L, %L) x', v_streak, v_today));
    PERFORM pg_temp.eq('6 checkin order = old (' || left(r2, 4) || ')', r, pg_temp.u(r2::uuid, format(q_order_old, v_streak, v_today)));
  END LOOP;
  PERFORM pg_temp.ck('6 checkin order: A sees 2 rows', json_array_length(pg_temp.u(A, format('SELECT json_agg(x)::text FROM public.get_team_checkin_order(%L, %L) x', v_streak, v_today))::json) = 2);
  q_await_old := 'SELECT json_agg(x)::text FROM (SELECT w.id as workout_id, w.workout_type, up.display_name as buddy_name, w.planned_duration_minutes,
       w.workout_started_at as started_at, COALESCE(w.creator_popup_shown, FALSE) as popup_already_shown
     FROM workouts w LEFT JOIN user_profiles up ON up.id = w.buddy_id
     WHERE w.user_id = %L AND w.status = ''in_progress'' AND w.started_by_user_id = w.buddy_id
       AND (w.creator_joined IS NULL OR w.creator_joined = FALSE) AND w.workout_started_at IS NOT NULL) x';
  FOREACH r2 IN ARRAY ARRAY[A::text, C::text] LOOP
    r := pg_temp.u(r2::uuid, format('SELECT json_agg(x)::text FROM (SELECT workout_id, workout_type, buddy_name, planned_duration_minutes, started_at, popup_already_shown FROM public.get_workouts_awaiting_creator_join(%L)) x', A));
    PERFORM pg_temp.eq('6 awaiting join(A) = old (' || left(r2, 4) || ')', r, pg_temp.u(r2::uuid, format(q_await_old, A)));
  END LOOP;
  PERFORM pg_temp.ck('6 awaiting join: A sees probe workout', pg_temp.u(A, format('SELECT count(*)::text FROM public.get_workouts_awaiting_creator_join(%L) WHERE workout_id = %L', A, v_w)) = '1');

  -- ── 7. a column added later is private by default ──
  ALTER TABLE user_profiles ADD COLUMN zz_probe text DEFAULT 'secret';
  PERFORM pg_temp.denied('7 C: new column', pg_temp.u(C, format('SELECT zz_probe FROM user_profiles WHERE id = %L', A)));
  PERFORM pg_temp.denied('7 B (teammate): new column', pg_temp.u(B, format('SELECT zz_probe FROM user_profiles WHERE id = %L', A)));
  PERFORM pg_temp.eq('7 A: own new column via get_my_profile', pg_temp.u(A, 'SELECT zz_probe FROM public.get_my_profile()'), 'secret');

  SELECT count(*) FILTER (WHERE ok) || ' pass, ' || count(*) FILTER (WHERE NOT ok) || ' fail. FAILED: ' ||
         coalesce(string_agg(t || ' [' || coalesce(info, '') || ']', '; ') FILTER (WHERE NOT ok), 'none')
  INTO res FROM pr;
  RAISE EXCEPTION 'PROBE_RESULTS: %', res;
END $probe$;
