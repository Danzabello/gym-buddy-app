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
  RESET ROLE;

  PERFORM set_config('request.jwt.claims', json_build_object('role', 'anon')::text, true);
  SET LOCAL ROLE anon;
  BEGIN n := public.submit_checkin()::text;
  EXCEPTION WHEN OTHERS THEN n := SQLSTATE || ' ' || SQLERRM; END;
  r := r || (CASE WHEN n LIKE '42501%' THEN 'PASS ' ELSE 'FAIL ' END || 'G9.11 anon cannot execute submit_checkin -> ' || n);
  RESET ROLE;
  PERFORM set_config('request.jwt.claims', '', true);

  -- Catalog: no economy function executable by anon; table privileges pinned (2026-10-29 live).
  SELECT string_agg(p.oid::regprocedure::text, ', ') INTO n FROM pg_proc p
  WHERE p.pronamespace = 'public'::regnamespace AND has_function_privilege('anon', p.oid, 'EXECUTE')
    AND p.proname IN ('submit_checkin', 'finish_checkin_session', 'check_in_coach_max', 'recompute_team_streak', 'purchase_shop_item',
                      'verify_achievement_progress', 'create_invite_team', 'create_buddy_team', 'accept_invite', 'award_coins', 'award_xp',
                      '_apply_checkin_rewards', '_credit_checkin', '_lock_credit', '_recompute_team_streak', 'award_checkin_rewards');
  r := r || (CASE WHEN n IS NULL THEN 'PASS ' ELSE 'FAIL ' END || 'G9.12 anon can execute no economy function -> ' || coalesce(n, 'none'));
  SELECT string_agg(t || ' ' || coalesce((SELECT string_agg(p, '' ORDER BY p) FROM unnest(ARRAY['SELECT','INSERT','UPDATE','DELETE','TRUNCATE']) p
                                          WHERE has_table_privilege('authenticated', 'public.' || t, p)), '-'), '; ' ORDER BY t) INTO n
  FROM unnest(ARRAY['coin_transactions', 'daily_team_checkins', 'team_streaks', 'user_achievements', 'user_inventory', 'user_unlocked_cosmetics', 'xp_transactions']) t;
  r := r || (CASE WHEN n = 'coin_transactions SELECT; daily_team_checkins SELECT; team_streaks DELETESELECT; user_achievements SELECT; '
                           'user_inventory SELECT; user_unlocked_cosmetics DELETESELECTUPDATE; xp_transactions SELECT'
                  THEN 'PASS ' ELSE 'FAIL ' END || 'G9.13 authenticated table privileges on economy tables (no INSERT anywhere) -> ' || n);
  r := r || (CASE WHEN NOT has_any_column_privilege('authenticated', 'public.daily_team_checkins', 'INSERT')
                  THEN 'PASS ' ELSE 'FAIL ' END || 'G9.14 no column-level INSERT on daily_team_checkins for authenticated');

  RAISE EXCEPTION E'SUITE_RESULTS\n%', array_to_string(r, E'\n');
END
$g$;
ROLLBACK;
