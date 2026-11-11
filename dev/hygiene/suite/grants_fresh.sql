-- Grants and denied writes (prompt 07 suite, G9). Own connection, and the first call is the authenticated one, so no
-- earlier privileged call can leave a cached plan behind (CLAUDE.md). Ends in RAISE: nothing persists.
-- Fixture account: testtest1 (swap the id here and in economy_suite.sql's list).
BEGIN;
-- run.sh --with inlines the migration on the next line (DDL only, as postgres; no function is called before the authenticated block).
-- @@MIGRATION@@

DO $g$
DECLARE
  r text[] := ARRAY[]::text[];
  u uuid := 'cf4946f5-f921-4e81-bbf4-88d574e8baf5';  -- testtest1
  n text; ok boolean; fn text;
BEGIN
  -- G12.9 fixture (prompt 27): one inbox row for this user and one for another test account (rokitest1). A plain INSERT, no function called.
  INSERT INTO public.notification_inbox (user_id, notification_type, title, body, sender_id) VALUES
    (u, 'nudge', 'g12.9 mine', 'b', '5e67f64d-16e3-4b09-9b00-ddc49df8c3f6'), ('5e67f64d-16e3-4b09-9b00-ddc49df8c3f6', 'nudge', 'g12.9 theirs', 'b', NULL);
  PERFORM set_config('request.jwt.claims', json_build_object('sub', u, 'role', 'authenticated')::text, true);
  SET LOCAL ROLE authenticated;

  BEGIN INSERT INTO public.daily_team_checkins (team_streak_id, user_id) VALUES (gen_random_uuid(), u); n := 'no error';
  EXCEPTION WHEN OTHERS THEN n := SQLSTATE || ' ' || SQLERRM; END;
  r := r || (CASE WHEN n LIKE '42501%' THEN 'PASS ' ELSE 'FAIL ' END || 'G9.1 authenticated direct INSERT daily_team_checkins -> ' || n);
  BEGIN UPDATE public.user_profiles SET coin_balance = 999 WHERE id = u; n := 'no error';
  EXCEPTION WHEN OTHERS THEN n := SQLSTATE || ' ' || SQLERRM; END;
  r := r || (CASE WHEN n LIKE '42501%' THEN 'PASS ' ELSE 'FAIL ' END || 'G9.2 authenticated UPDATE coin_balance -> ' || n);
  BEGIN UPDATE public.user_profiles SET xp = 999 WHERE id = u; n := 'no error';
  EXCEPTION WHEN OTHERS THEN n := SQLSTATE || ' ' || SQLERRM; END;
  r := r || (CASE WHEN n LIKE '42501%' THEN 'PASS ' ELSE 'FAIL ' END || 'G9.3 authenticated UPDATE xp -> ' || n);
  BEGIN UPDATE public.user_profiles SET rest_tokens_available = 99 WHERE id = u; n := 'no error';
  EXCEPTION WHEN OTHERS THEN n := SQLSTATE || ' ' || SQLERRM; END;
  r := r || (CASE WHEN n LIKE '42501%' THEN 'PASS ' ELSE 'FAIL ' END || 'G9.4 authenticated UPDATE rest_tokens_available -> ' || n);
  BEGIN INSERT INTO public.coin_transactions (user_id, amount, transaction_type, description) VALUES (u, 1000, 'daily_checkin', 'x'); n := 'no error';
  EXCEPTION WHEN OTHERS THEN n := SQLSTATE || ' ' || SQLERRM; END;
  r := r || (CASE WHEN n LIKE '42501%' THEN 'PASS ' ELSE 'FAIL ' END || 'G9.5 authenticated INSERT coin_transactions -> ' || n);
  BEGIN INSERT INTO public.xp_transactions (user_id, amount, transaction_type, description) VALUES (u, 1000, 'xp_award', 'x'); n := 'no error';
  EXCEPTION WHEN OTHERS THEN n := SQLSTATE || ' ' || SQLERRM; END;
  r := r || (CASE WHEN n LIKE '42501%' THEN 'PASS ' ELSE 'FAIL ' END || 'G9.6 authenticated INSERT xp_transactions -> ' || n);
  BEGIN UPDATE public.team_streaks SET current_streak = 99 WHERE id IN (SELECT ts.id FROM public.team_streaks ts JOIN public.team_members tm ON tm.team_id = ts.team_id WHERE tm.user_id = u); n := 'no error';
  EXCEPTION WHEN OTHERS THEN n := SQLSTATE || ' ' || SQLERRM; END;
  r := r || (CASE WHEN n LIKE '42501%' THEN 'PASS ' ELSE 'FAIL ' END || 'G9.7 authenticated UPDATE team_streaks -> ' || n);
  BEGIN INSERT INTO public.user_inventory (user_id, shop_item_id) VALUES (u, '78594031-1074-46ed-b80b-a1cbcb7043b0'); n := 'no error';
  EXCEPTION WHEN OTHERS THEN n := SQLSTATE || ' ' || SQLERRM; END;
  r := r || (CASE WHEN n LIKE '42501%' THEN 'PASS ' ELSE 'FAIL ' END || 'G9.8 authenticated INSERT user_inventory -> ' || n);
  FOREACH fn IN ARRAY ARRAY['public._lock_credit(ARRAY[''' || u || '''::uuid], true)', 'public._credit_checkin(''' || u || ''', now())',
                            'public._credit_day(''' || u || ''', now())', 'public.award_coins(''' || u || ''', 1, ''x'', ''x'')',
                            'public.award_xp(''' || u || ''', 1, ''x'')', 'public.award_checkin_rewards(gen_random_uuid(), current_date)',
                            'public.check_in_coach_max_with_buddy(''' || u || ''')', 'public.reconcile_stale_streaks()',
                            'public.process_stale_sessions()', 'public._recompute_team_streak(gen_random_uuid(), current_date)'] LOOP
    BEGIN EXECUTE 'SELECT ' || fn; n := 'no error';
    EXCEPTION WHEN OTHERS THEN n := SQLSTATE || ' ' || SQLERRM; END;
    r := r || (CASE WHEN n LIKE '42501%' THEN 'PASS ' ELSE 'FAIL ' END || 'G9.9 authenticated cannot execute ' || split_part(fn, '(', 1) || ' -> ' || n);
  END LOOP;
  BEGIN n := public.submit_checkin()->>'reason';
  EXCEPTION WHEN OTHERS THEN n := SQLSTATE || ' ' || SQLERRM; END;
  r := r || (CASE WHEN n IN ('not_checked_in_today', 'already_checked_in', 'no_teams') THEN 'PASS ' ELSE 'FAIL ' END || 'G9.10 authenticated submit_checkin answers -> ' || n);
  -- Onboarding profile write (client: writeProfileRow). A fresh id, so no real account is touched (user_profiles.id has no FK to auth.users).
  -- authenticated has no SELECT on age, onboarding_completed, preferred_workout_style, updated_at (LIVE-10), so an upsert (ON CONFLICT DO UPDATE
  -- reads EXCLUDED) is 42501, while UPDATE ... RETURNING id and a plain INSERT work.
  DECLARE
    v uuid := gen_random_uuid();
    cols constant text := 'display_name, username, age, avatar_id, avatar_border, fitness_level, looking_for_buddy, preferred_workout_style, onboarding_completed, updated_at';
    vals text; k int;
  BEGIN
    PERFORM set_config('request.jwt.claims', json_build_object('sub', v, 'role', 'authenticated')::text, true);
    vals := format('%L, %L, 30, ''lion'', ''simple'', ''beginner'', true, ''both'', false, now()', 'Suite', 'suite_' || substr(v::text, 1, 8));
    BEGIN EXECUTE format('UPDATE public.user_profiles SET age = 31, onboarding_completed = true WHERE id = %L RETURNING id', v);
      GET DIAGNOSTICS k = ROW_COUNT; n := k::text; EXCEPTION WHEN OTHERS THEN n := SQLSTATE || ' ' || SQLERRM; END;
    r := r || (CASE WHEN n = '0' THEN 'PASS ' ELSE 'FAIL ' END || 'G9.17.1 UPDATE RETURNING id of a missing own row -> ' || n || ' rows');
    BEGIN EXECUTE format('INSERT INTO public.user_profiles (id, %s) VALUES (%L, %s)', cols, v, vals); n := 'ok';
    EXCEPTION WHEN OTHERS THEN n := SQLSTATE || ' ' || SQLERRM; END;
    r := r || (CASE WHEN n = 'ok' THEN 'PASS ' ELSE 'FAIL ' END || 'G9.17.2 plain INSERT of the onboarding row -> ' || n);
    BEGIN EXECUTE format('UPDATE public.user_profiles SET age = 31, onboarding_completed = true WHERE id = %L RETURNING id', v);
      GET DIAGNOSTICS k = ROW_COUNT; n := k::text; EXCEPTION WHEN OTHERS THEN n := SQLSTATE || ' ' || SQLERRM; END;
    r := r || (CASE WHEN n = '1' THEN 'PASS ' ELSE 'FAIL ' END || 'G9.17.3 UPDATE RETURNING id of the existing own row -> ' || n || ' rows');
    BEGIN EXECUTE format('INSERT INTO public.user_profiles (id, %s) VALUES (%L, %s) ON CONFLICT (id) DO UPDATE SET age = EXCLUDED.age, onboarding_completed = EXCLUDED.onboarding_completed, preferred_workout_style = EXCLUDED.preferred_workout_style, updated_at = EXCLUDED.updated_at',
                         cols, v, vals); n := 'no error';
    EXCEPTION WHEN OTHERS THEN n := SQLSTATE || ' ' || SQLERRM; END;
    r := r || (CASE WHEN n LIKE '42501%' THEN 'PASS ' ELSE 'FAIL ' END || 'G9.17.4 upsert of the onboarding row is denied (the bug this guards) -> ' || n);
    PERFORM set_config('request.jwt.claims', json_build_object('sub', u, 'role', 'authenticated')::text, true);
  END;
  -- G9.18 (prompt 35): the auto check-in counter is not readable or writable by a client; only the credit functions touch it.
  FOREACH fn IN ARRAY ARRAY['SELECT count(*) FROM public.auto_checkin_counts',
                            'INSERT INTO public.auto_checkin_counts (user_id, consecutive) VALUES (''' || u || ''', 1)',
                            'UPDATE public.auto_checkin_counts SET consecutive = 1',
                            'DELETE FROM public.auto_checkin_counts'] LOOP
    BEGIN EXECUTE fn; n := 'no error';
    EXCEPTION WHEN OTHERS THEN n := SQLSTATE || ' ' || SQLERRM; END;
    r := r || (CASE WHEN n LIKE '42501%' THEN 'PASS ' ELSE 'FAIL ' END || 'G9.18 authenticated ' || split_part(fn, ' ', 1) || ' auto_checkin_counts -> ' || n);
  END LOOP;
  -- G12.9 (prompts 27, 40): a client reads its own rows and deletes its own rows, and writes nothing else.
  FOREACH fn IN ARRAY ARRAY['INSERT INTO public.notification_inbox (user_id, notification_type, title, body) VALUES (''' || u || ''', ''nudge'', ''t'', ''b'')',
                            'UPDATE public.notification_inbox SET quiet = true WHERE user_id = ''' || u || '''',
                            'TRUNCATE public.notification_inbox'] LOOP
    BEGIN EXECUTE fn; n := 'no error';
    EXCEPTION WHEN OTHERS THEN n := SQLSTATE || ' ' || SQLERRM; END;
    r := r || (CASE WHEN n LIKE '42501%' THEN 'PASS ' ELSE 'FAIL ' END || 'G12.9 authenticated ' || split_part(fn, ' ', 1) || ' notification_inbox -> ' || n);
  END LOOP;
  BEGIN EXECUTE 'SELECT string_agg(title, '','') FROM public.notification_inbox WHERE title LIKE ''g12.9%''' INTO n;
  EXCEPTION WHEN OTHERS THEN n := SQLSTATE || ' ' || SQLERRM; END;
  r := r || (CASE WHEN n = 'g12.9 mine' THEN 'PASS ' ELSE 'FAIL ' END || 'G12.9 authenticated SELECT sees its own row and not another user''s -> ' || coalesce(n, 'no rows'));
  BEGIN EXECUTE 'SELECT sender_id::text FROM public.notification_inbox WHERE title = ''g12.9 mine''' INTO n;
  EXCEPTION WHEN OTHERS THEN n := SQLSTATE || ' ' || SQLERRM; END;
  r := r || (CASE WHEN n = '5e67f64d-16e3-4b09-9b00-ddc49df8c3f6' THEN 'PASS ' ELSE 'FAIL ' END || 'G12.9 authenticated can read sender_id on its own row -> ' || coalesce(n, 'null'));
  BEGIN EXECUTE 'WITH d AS (DELETE FROM public.notification_inbox WHERE title = ''g12.9 theirs'' RETURNING 1) SELECT count(*)::text FROM d' INTO n;
  EXCEPTION WHEN OTHERS THEN n := SQLSTATE || ' ' || SQLERRM; END;
  r := r || (CASE WHEN n = '0' THEN 'PASS ' ELSE 'FAIL ' END || 'G12.9 authenticated DELETE of another user''s row affects 0 rows, no error -> ' || coalesce(n, 'null'));
  BEGIN EXECUTE 'WITH d AS (DELETE FROM public.notification_inbox WHERE title = ''g12.9 mine'' RETURNING 1) SELECT count(*)::text FROM d' INTO n;
  EXCEPTION WHEN OTHERS THEN n := SQLSTATE || ' ' || SQLERRM; END;
  r := r || (CASE WHEN n = '1' THEN 'PASS ' ELSE 'FAIL ' END || 'G12.9 authenticated DELETE of its own row affects 1 row -> ' || coalesce(n, 'null'));
  BEGIN EXECUTE 'SELECT count(*)::text FROM public.notification_inbox WHERE title = ''g12.9 mine''' INTO n;
  EXCEPTION WHEN OTHERS THEN n := SQLSTATE || ' ' || SQLERRM; END;
  r := r || (CASE WHEN n = '0' THEN 'PASS ' ELSE 'FAIL ' END || 'G12.9 its own row is gone afterwards -> ' || coalesce(n, 'null'));
  RESET ROLE;
  SELECT count(*)::text INTO n FROM public.notification_inbox WHERE title = 'g12.9 theirs';
  r := r || (CASE WHEN n = '1' THEN 'PASS ' ELSE 'FAIL ' END || 'G12.9 the other user''s row is still there -> ' || coalesce(n, 'null'));
  -- Rate-limit meters (prompt 13): neither role can read or write them.
  FOREACH fn IN ARRAY ARRAY['authenticated', 'anon'] LOOP
    PERFORM set_config('request.jwt.claims', json_build_object('sub', u, 'role', fn)::text, true);
    EXECUTE format('SET LOCAL ROLE %I', fn);
    FOREACH n IN ARRAY ARRAY['SELECT count(*) FROM public.username_search_attempts',
                             'INSERT INTO public.username_search_attempts (user_id) VALUES (''' || u || ''')',
                             'SELECT count(*) FROM public.friend_request_attempts',
                             'INSERT INTO public.friend_request_attempts (user_id, target_id) VALUES (''' || u || ''', ''' || u || ''')'] LOOP
      BEGIN EXECUTE n; ok := false;
      EXCEPTION WHEN OTHERS THEN ok := SQLSTATE = '42501';
      END;
      r := r || (CASE WHEN ok THEN 'PASS ' ELSE 'FAIL ' END || 'G9.15 ' || fn || ' denied: ' || split_part(n, ' (', 1));
    END LOOP;
    RESET ROLE;
  END LOOP;
  -- Stale accounts (prompt 44): neither client role can call the candidate functions or touch the run log.
  FOREACH fn IN ARRAY ARRAY['authenticated', 'anon'] LOOP
    PERFORM set_config('request.jwt.claims', json_build_object('sub', u, 'role', fn)::text, true);
    EXECUTE format('SET LOCAL ROLE %I', fn);
    FOREACH n IN ARRAY ARRAY['SELECT count(*) FROM public.stale_account_candidates(30)',
                             'SELECT count(*) FROM public.stale_account_preview(30, 25)',
                             'SELECT count(*) FROM public.stale_account_runs',
                             'INSERT INTO public.stale_account_runs (mode, cap, candidates) VALUES (''dry_run'', 1, 0)'] LOOP
      BEGIN EXECUTE n; ok := false;
      EXCEPTION WHEN OTHERS THEN ok := SQLSTATE = '42501';
      END;
      r := r || (CASE WHEN ok THEN 'PASS ' ELSE 'FAIL ' END || 'G13.1 ' || fn || ' denied: ' || split_part(n, ' (', 1));
    END LOOP;
    RESET ROLE;
  END LOOP;

  PERFORM set_config('request.jwt.claims', json_build_object('role', 'anon')::text, true);
  SET LOCAL ROLE anon;
  BEGIN n := public.submit_checkin()::text;
  EXCEPTION WHEN OTHERS THEN n := SQLSTATE || ' ' || SQLERRM; END;
  r := r || (CASE WHEN n LIKE '42501%' THEN 'PASS ' ELSE 'FAIL ' END || 'G9.11 anon cannot execute submit_checkin -> ' || n);
  BEGIN EXECUTE 'SELECT count(*)::text FROM public.notification_inbox' INTO n;
  EXCEPTION WHEN OTHERS THEN n := SQLSTATE || ' ' || SQLERRM; END;
  r := r || (CASE WHEN n LIKE '42501%' THEN 'PASS ' ELSE 'FAIL ' END || 'G12.9 anon SELECT notification_inbox -> ' || n);
  BEGIN EXECUTE 'DELETE FROM public.notification_inbox'; n := 'no error';
  EXCEPTION WHEN OTHERS THEN n := SQLSTATE || ' ' || SQLERRM; END;
  r := r || (CASE WHEN n LIKE '42501%' THEN 'PASS ' ELSE 'FAIL ' END || 'G12.9 anon DELETE notification_inbox -> ' || n);
  RESET ROLE;
  SET LOCAL ROLE service_role;
  BEGIN EXECUTE 'INSERT INTO public.notification_inbox (user_id, notification_type, title, body, quiet) VALUES (''' || u || ''', ''nudge'', ''t'', ''b'', true)'; n := 'ok';
  EXCEPTION WHEN OTHERS THEN n := SQLSTATE || ' ' || SQLERRM; END;
  r := r || (CASE WHEN n = 'ok' THEN 'PASS ' ELSE 'FAIL ' END || 'G12.9 service_role can write the row send-notification writes -> ' || n);
  FOREACH n IN ARRAY ARRAY['SELECT count(*) FROM public.stale_account_candidates(30)',
                           'SELECT count(*) FROM public.stale_account_preview(30, 25)',
                           'SELECT count(*) FROM public.stale_account_runs',
                           'INSERT INTO public.stale_account_runs (mode, cap, candidates) VALUES (''dry_run'', 1, 0)'] LOOP
    BEGIN EXECUTE n; ok := true;
    EXCEPTION WHEN OTHERS THEN ok := false;
    END;
    r := r || (CASE WHEN ok THEN 'PASS ' ELSE 'FAIL ' END || 'G13.2 service_role allowed: ' || split_part(n, ' (', 1));
  END LOOP;
  RESET ROLE;
  PERFORM set_config('request.jwt.claims', '', true);

  -- Catalog: no economy function executable by anon; table privileges pinned (2026-10-29 live).
  SELECT string_agg(p.oid::regprocedure::text, ', ') INTO n FROM pg_proc p
  WHERE p.pronamespace = 'public'::regnamespace AND has_function_privilege('anon', p.oid, 'EXECUTE')
    AND p.proname IN ('submit_checkin', 'finish_checkin_session', 'check_in_coach_max', 'recompute_team_streak', 'purchase_shop_item',
                      'verify_achievement_progress', 'create_invite_team', 'create_buddy_team', 'accept_invite', 'award_coins', 'award_xp',
                      '_apply_checkin_rewards', '_credit_checkin', '_lock_credit', '_recompute_team_streak', 'award_checkin_rewards');
  r := r || (CASE WHEN n IS NULL THEN 'PASS ' ELSE 'FAIL ' END || 'G9.12 anon can execute no economy function -> ' || coalesce(n, 'none'));
  SELECT string_agg(x, ', ') INTO n FROM unnest(ARRAY[
    CASE WHEN has_function_privilege('anon', 'public.search_usernames(text)', 'EXECUTE') THEN 'anon search_usernames' END,
    CASE WHEN NOT has_function_privilege('authenticated', 'public.search_usernames(text)', 'EXECUTE') THEN 'authenticated lost search_usernames' END,
    CASE WHEN has_function_privilege('anon', 'public._meter_friend_request()', 'EXECUTE') THEN 'anon _meter_friend_request' END,
    CASE WHEN has_function_privilege('authenticated', 'public._meter_friend_request()', 'EXECUTE') THEN 'authenticated _meter_friend_request' END]) x;
  r := r || (CASE WHEN n IS NULL THEN 'PASS ' ELSE 'FAIL ' END || 'G9.16 search_usernames authenticated-only; _meter_friend_request executable by neither -> ' || coalesce(n, 'ok'));
  SELECT string_agg(t || ' ' || coalesce((SELECT string_agg(p, '' ORDER BY p) FROM unnest(ARRAY['SELECT','INSERT','UPDATE','DELETE','TRUNCATE']) p
                                          WHERE has_table_privilege('authenticated', 'public.' || t, p)), '-'), '; ' ORDER BY t) INTO n
  FROM unnest(ARRAY['coin_transactions', 'daily_team_checkins', 'team_streaks', 'user_achievements', 'user_inventory', 'user_unlocked_cosmetics', 'xp_transactions']) t;
  r := r || (CASE WHEN n = 'coin_transactions SELECT; daily_team_checkins SELECT; team_streaks DELETESELECT; user_achievements SELECT; '
                           'user_inventory SELECT; user_unlocked_cosmetics DELETESELECTUPDATE; xp_transactions SELECT'
                  THEN 'PASS ' ELSE 'FAIL ' END || 'G9.13 authenticated table privileges on economy tables (no INSERT anywhere) -> ' || n);
  r := r || (CASE WHEN NOT has_any_column_privilege('authenticated', 'public.daily_team_checkins', 'INSERT')
                  THEN 'PASS ' ELSE 'FAIL ' END || 'G9.14 no column-level INSERT on daily_team_checkins for authenticated');
  SELECT string_agg(ro || ' ' || pr, ', ') INTO n
  FROM unnest(ARRAY['anon', 'authenticated']) ro, unnest(ARRAY['SELECT', 'INSERT', 'UPDATE', 'DELETE', 'TRUNCATE', 'REFERENCES', 'TRIGGER']) pr
  WHERE has_table_privilege(ro, 'public.auto_checkin_counts', pr);
  r := r || (CASE WHEN n IS NULL THEN 'PASS ' ELSE 'FAIL ' END || 'G9.18 anon and authenticated hold no privilege on auto_checkin_counts -> ' || coalesce(n, 'none'));
  SELECT string_agg(ro || ' ' || pr, ', ' ORDER BY ro, pr) INTO n
  FROM unnest(ARRAY['anon', 'authenticated', 'public', 'service_role']) ro, unnest(ARRAY['SELECT', 'INSERT', 'UPDATE', 'DELETE', 'TRUNCATE', 'REFERENCES', 'TRIGGER']) pr
  WHERE has_table_privilege(ro, 'public.notification_inbox', pr);
  r := r || (CASE WHEN n = 'authenticated DELETE, authenticated SELECT, service_role DELETE, service_role INSERT, service_role REFERENCES, service_role SELECT, service_role TRIGGER, service_role TRUNCATE, service_role UPDATE'
                  THEN 'PASS ' ELSE 'FAIL ' END || 'G12.9 notification_inbox privileges: authenticated SELECT and DELETE only, service_role all, nothing for anon or PUBLIC -> ' || coalesce(n, 'none'));
  SELECT string_agg(policyname || ' ' || cmd || ' ' || roles::text || ' ' || qual, '; ' ORDER BY policyname) INTO n FROM pg_policies WHERE schemaname = 'public' AND tablename = 'notification_inbox';
  r := r || (CASE WHEN (SELECT relrowsecurity FROM pg_class WHERE oid = 'public.notification_inbox'::regclass)
                       AND n = 'Users delete own inbox DELETE {authenticated} (user_id = ( SELECT auth.uid() AS uid)); Users read own inbox SELECT {authenticated} (user_id = ( SELECT auth.uid() AS uid))'
                  THEN 'PASS ' ELSE 'FAIL ' END || 'G12.9 notification_inbox: RLS on, exactly the SELECT and DELETE policies, own rows -> ' || coalesce(n, 'none'));
  SELECT string_agg(a.attname || ' ' || c.confdeltype::text, ', ' ORDER BY a.attname) INTO n
  FROM pg_constraint c JOIN pg_attribute a ON a.attrelid = c.conrelid AND a.attnum = c.conkey[1]
  WHERE c.conrelid = 'public.notification_inbox'::regclass AND c.contype = 'f' AND c.confrelid = 'public.user_profiles'::regclass;
  r := r || (CASE WHEN n = 'sender_id n, user_id c' THEN 'PASS ' ELSE 'FAIL ' END || 'G12.9 foreign keys to user_profiles: sender_id SET NULL (n), user_id CASCADE (c) -> ' || coalesce(n, 'none'));
  r := r || (CASE WHEN NOT EXISTS (SELECT 1 FROM pg_depend d JOIN pg_class c ON c.oid = d.objid
                                   WHERE c.relkind = 'S' AND d.refobjid = 'public.notification_inbox'::regclass)
                  THEN 'PASS ' ELSE 'FAIL ' END || 'G12.9 notification_inbox owns no sequence, so there is nothing to grant a client');

  -- G13.3-5 (prompt 44) the run log is service_role only with RLS on; both functions are service_role-only SECURITY DEFINER with a pinned search_path; the daily job.
  SELECT string_agg(ro || ' ' || pr, ', ' ORDER BY ro, pr) INTO n
  FROM unnest(ARRAY['anon', 'authenticated', 'public', 'service_role']) ro, unnest(ARRAY['SELECT', 'INSERT', 'UPDATE', 'DELETE', 'TRUNCATE', 'REFERENCES', 'TRIGGER']) pr
  WHERE has_table_privilege(ro, 'public.stale_account_runs', pr);
  r := r || (CASE WHEN n = 'service_role DELETE, service_role INSERT, service_role REFERENCES, service_role SELECT, service_role TRIGGER, service_role TRUNCATE, service_role UPDATE'
                       AND (SELECT relrowsecurity FROM pg_class WHERE oid = 'public.stale_account_runs'::regclass)
                  THEN 'PASS ' ELSE 'FAIL ' END || 'G13.3 stale_account_runs: RLS on, privileges for service_role only -> ' || coalesce(n, 'none'));
  SELECT string_agg(p.oid::regprocedure::text || ' ' || p.proacl::text || ' secdef=' || p.prosecdef || ' ' || coalesce(p.proconfig::text, '-'), '; ' ORDER BY p.oid::regprocedure::text) INTO n
  FROM pg_proc p WHERE p.pronamespace = 'public'::regnamespace AND p.proname IN ('stale_account_candidates', 'stale_account_preview');
  r := r || (CASE WHEN n = 'stale_account_candidates(integer) {postgres=X/postgres,service_role=X/postgres} secdef=true {search_path=public}; '
                           'stale_account_preview(integer,integer) {postgres=X/postgres,service_role=X/postgres} secdef=true {search_path=public}'
                  THEN 'PASS ' ELSE 'FAIL ' END || 'G13.4 stale_account functions: service_role only, SECURITY DEFINER, search_path pinned -> ' || coalesce(n, 'none'));
  SELECT schedule || ' | ' || (command LIKE '%vault.decrypted_secrets%' AND command NOT LIKE '%eyJ%' AND command LIKE '%"cap":25%')::text INTO n
  FROM cron.job WHERE jobname = 'stale-accounts-daily';
  r := r || (CASE WHEN n = '47 3 * * * | true' THEN 'PASS ' ELSE 'FAIL ' END || 'G13.5 stale-accounts-daily at 03:47 UTC, key read from the vault, cap 25 -> ' || coalesce(n, 'missing'));

  RAISE EXCEPTION E'SUITE_RESULTS\n%', array_to_string(r, E'\n');
END
$g$;
ROLLBACK;
