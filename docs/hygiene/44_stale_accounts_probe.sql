-- Prompt 44 probe: stale-account candidates, the preview, the run log and the daily job, read from the catalog and tried as
-- each role. One transaction that ends in RAISE EXCEPTION, so nothing is kept (the profile flags it flips are rolled back).
-- Run after 20261111190000 is applied:
--   supabase db query --linked -f docs/hygiene/44_stale_accounts_probe.sql
-- Before it is applied:  (printf 'BEGIN;\n'; cat supabase/migrations/20261111190000_stale_accounts.sql; cat docs/hygiene/44_stale_accounts_probe.sql) > /tmp/p.sql
--                        supabase db query --linked -f /tmp/p.sql      (the cron.schedule inside is rolled back with the rest)
-- Test accounts: rokitest1, testtest1. Never a real phone's account. Role checks come first, before any privileged call.
--
-- Not part of the probe, for later (by hand, as postgres):
--   preview:  SELECT * FROM public.stale_account_preview();            SELECT action, count(*) FROM public.stale_account_preview() GROUP BY 1;
--   job off/on: SELECT cron.alter_job((SELECT jobid FROM cron.job WHERE jobname = 'stale-accounts-daily'), active := true);   -- false to stop
--   log:      SELECT * FROM public.stale_account_runs ORDER BY ran_at DESC LIMIT 5;
DO $probe$
DECLARE
  coach constant uuid := '00000000-0000-0000-0000-000000000001';
  other constant uuid := '5e67f64d-16e3-4b09-9b00-ddc49df8c3f6';  -- rokitest1
  me constant uuid := 'cf4946f5-f921-4e81-bbf4-88d574e8baf5';     -- testtest1
  ro text; stmt text; fn text;
  got text; want text; n integer; m integer; before_n text; after_n text;
  res text := ''; ok boolean := true;
BEGIN
  -- 1. Roles first: a client can call neither function and cannot touch the log; service_role can use all three.
  FOREACH ro IN ARRAY ARRAY['authenticated', 'anon'] LOOP
    PERFORM set_config('request.jwt.claims', CASE WHEN ro = 'anon' THEN json_build_object('role', 'anon')::text
                                                  ELSE json_build_object('sub', me, 'role', ro)::text END, true);
    EXECUTE format('SET LOCAL ROLE %I', ro);
    FOREACH stmt IN ARRAY ARRAY['SELECT count(*)::text FROM public.stale_account_candidates(30)',
                                'SELECT count(*)::text FROM public.stale_account_preview(30, 25)',
                                'SELECT count(*)::text FROM public.stale_account_runs',
                                'INSERT INTO public.stale_account_runs (mode, cap, candidates) VALUES (''dry_run'', 1, 0) RETURNING id::text'] LOOP
      BEGIN EXECUTE stmt INTO got; got := 'no error';
      EXCEPTION WHEN OTHERS THEN got := SQLSTATE; END;
      res := res || format(E'\n%s: %s -> %s (42501 expected)', ro, left(stmt, 52), got);
      ok := ok AND got = '42501';
    END LOOP;
    RESET ROLE;
  END LOOP;
  PERFORM set_config('request.jwt.claims', json_build_object('role', 'service_role')::text, true);
  SET LOCAL ROLE service_role;
  BEGIN EXECUTE 'SELECT count(*)::text FROM public.stale_account_candidates(30)' INTO got; got := 'ok';
  EXCEPTION WHEN OTHERS THEN got := SQLSTATE; END;
  res := res || format(E'\nservice_role candidates -> %s (ok expected)', got);
  ok := ok AND got = 'ok';
  BEGIN EXECUTE 'SELECT count(*)::text FROM public.stale_account_preview(30, 25)' INTO got; got := 'ok';
  EXCEPTION WHEN OTHERS THEN got := SQLSTATE; END;
  res := res || format(E'\nservice_role preview -> %s (ok expected)', got);
  ok := ok AND got = 'ok';
  BEGIN EXECUTE 'INSERT INTO public.stale_account_runs (mode, cap, candidates) VALUES (''dry_run'', 1, 0) RETURNING id::text' INTO got; got := 'ok';
  EXCEPTION WHEN OTHERS THEN got := SQLSTATE; END;
  res := res || format(E'\nservice_role log insert -> %s (ok expected)', got);
  ok := ok AND got = 'ok';
  RESET ROLE;
  PERFORM set_config('request.jwt.claims', '', true);

  -- 2. Catalog: table privileges and RLS, function ACL, SECURITY DEFINER, search_path.
  SELECT string_agg(r || ' ' || pr, ', ' ORDER BY r, pr) INTO got
  FROM unnest(ARRAY['anon', 'authenticated', 'public', 'service_role']) r, unnest(ARRAY['SELECT', 'INSERT', 'UPDATE', 'DELETE', 'TRUNCATE', 'REFERENCES', 'TRIGGER']) pr
  WHERE has_table_privilege(r, 'public.stale_account_runs', pr);
  want := 'service_role DELETE, service_role INSERT, service_role REFERENCES, service_role SELECT, service_role TRIGGER, service_role TRUNCATE, service_role UPDATE';
  res := res || format(E'\nlog table privileges -> %s', got);
  ok := ok AND got IS NOT DISTINCT FROM want;
  SELECT relrowsecurity::text INTO got FROM pg_class WHERE oid = 'public.stale_account_runs'::regclass;
  res := res || format(E'\nlog table RLS on -> %s', got);
  ok := ok AND got = 'true';
  FOREACH fn IN ARRAY ARRAY['public.stale_account_candidates(integer)', 'public.stale_account_preview(integer,integer)'] LOOP
    SELECT p.proacl::text || ' secdef=' || p.prosecdef || ' ' || coalesce(p.proconfig::text, '-') INTO got FROM pg_proc p WHERE p.oid = fn::regprocedure;
    res := res || format(E'\n%s -> %s', fn, got);
    ok := ok AND got = '{postgres=X/postgres,service_role=X/postgres} secdef=true {search_path=public}';
  END LOOP;

  -- 3. The daily job: the schedule, no key in the command, and whether it is on (off until switched on by hand).
  SELECT schedule || ' active=' || active::text INTO got FROM cron.job WHERE jobname = 'stale-accounts-daily';
  res := res || format(E'\njob -> %s (47 3 * * *; active=false until you switch it on)', coalesce(got, 'missing'));
  ok := ok AND got LIKE '47 3 * * * active=%';
  SELECT (command LIKE '%vault.decrypted_secrets%' AND command NOT LIKE '%eyJ%' AND command LIKE '%"cap":25%' AND command LIKE '%/functions/v1/stale-accounts-cron%')::text
    INTO got FROM cron.job WHERE jobname = 'stale-accounts-daily';
  res := res || format(E'\njob command reads the key from the vault, posts cap 25, no key in the text -> %s', coalesce(got, 'missing'));
  ok := ok AND got = 'true';

  -- 4. What the functions return. A window of -36500 days makes every account old enough, so only the other rules decide.
  UPDATE public.user_profiles SET onboarding_completed = false WHERE id IN (coach, other, me);
  SELECT count(*) INTO n FROM public.stale_account_candidates(-36500) WHERE user_id = coach;
  res := res || format(E'\nCoach Max, flag false, huge window -> %s rows (0 expected)', n);
  ok := ok AND n = 0;
  SELECT count(*) INTO n FROM public.stale_account_candidates(-36500) WHERE user_id IN (other, me);
  res := res || format(E'\ntwo test accounts flipped to unfinished, huge window -> %s rows (2 expected)', n);
  ok := ok AND n = 2;
  SELECT count(*) INTO n FROM public.stale_account_candidates(36500) WHERE user_id IN (other, me);
  res := res || format(E'\nsame accounts, window of 100 years -> %s rows (0 expected: not idle that long)', n);
  ok := ok AND n = 0;
  SELECT count(*) INTO n FROM public.stale_account_candidates(-36500) WHERE has_profile AND onboarding_completed IS DISTINCT FROM false;
  res := res || format(E'\nrows with a finished or NULL flag, huge window -> %s (0 expected)', n);
  ok := ok AND n = 0;
  UPDATE public.user_profiles SET onboarding_completed = NULL WHERE id = other;
  SELECT count(*) INTO n FROM public.stale_account_candidates(-36500) WHERE user_id = other;
  res := res || format(E'\nNULL flag -> %s rows (0 expected: counts as finished)', n);
  ok := ok AND n = 0;
  SELECT (c.paired = EXISTS (SELECT 1 FROM public.team_members tm WHERE tm.user_id = me))::text INTO got
  FROM public.stale_account_candidates(-36500) c WHERE c.user_id = me;
  res := res || format(E'\npaired flag matches team_members for testtest1 -> %s', coalesce(got, 'no row'));
  ok := ok AND got = 'true';

  -- 5. The preview: same rows, the cap marks the next run, emails masked, nothing written or deleted.
  SELECT count(*) INTO n FROM public.stale_account_candidates(-36500);
  SELECT count(*) INTO m FROM public.stale_account_preview(-36500, 1);
  res := res || format(E'\npreview rows vs candidates -> %s / %s (equal expected)', m, n);
  ok := ok AND n = m;
  SELECT count(*) FILTER (WHERE action = 'delete (next run)')::text INTO got FROM public.stale_account_preview(-36500, 1);
  SELECT least(1, count(*) FILTER (WHERE NOT paired))::text INTO want FROM public.stale_account_candidates(-36500);
  res := res || format(E'\npreview with cap 1 marks %s for the next run (%s expected)', got, want);
  ok := ok AND got IS NOT DISTINCT FROM want;
  SELECT count(*)::text INTO got FROM public.stale_account_preview(-36500, 1) p JOIN auth.users u ON u.id = p.user_id WHERE p.email_masked = u.email;
  res := res || format(E'\npreview rows showing a full email -> %s (0 expected)', got);
  ok := ok AND got = '0';
  before_n := (SELECT count(*) FROM public.user_profiles) || '/' || (SELECT count(*) FROM auth.users) || '/' || (SELECT count(*) FROM public.stale_account_runs);
  PERFORM count(*) FROM public.stale_account_preview(-36500, 25);
  after_n := (SELECT count(*) FROM public.user_profiles) || '/' || (SELECT count(*) FROM auth.users) || '/' || (SELECT count(*) FROM public.stale_account_runs);
  res := res || format(E'\nprofiles/auth users/log rows before and after a preview -> %s and %s (equal expected)', before_n, after_n);
  ok := ok AND before_n = after_n;

  RAISE EXCEPTION E'PROBE_RESULTS: %\n%', CASE WHEN ok THEN 'ALL OK' ELSE 'MISMATCH' END, res;
END $probe$;
