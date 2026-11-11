-- Prompt 40 probe: the inbox delete policy and grants, read from the catalog and tried as a client. One transaction that ends
-- in RAISE EXCEPTION, so nothing is kept. Run after 20261106120000 is applied:
--   supabase db query --linked -f dev/hygiene/40_notification_inbox_delete_probe.sql
-- Before it is applied:  (printf 'BEGIN;\n'; cat supabase/migrations/20261106120000_notification_inbox_delete.sql; cat dev/hygiene/40_notification_inbox_delete_probe.sql) > /tmp/p.sql
--                        supabase db query --linked -f /tmp/p.sql
-- Test accounts: rokitest1 (the other user), testtest1 (the client). Never a real phone's account.
DO $probe$
DECLARE
  other constant uuid := '5e67f64d-16e3-4b09-9b00-ddc49df8c3f6';  -- rokitest1
  me constant uuid := 'cf4946f5-f921-4e81-bbf4-88d574e8baf5';     -- testtest1
  mine uuid; theirs uuid; got text; want text;
  res text := ''; ok boolean := true;
BEGIN
  SELECT string_agg(ro || ' ' || pr, ', ' ORDER BY ro, pr) INTO got
  FROM unnest(ARRAY['anon', 'authenticated', 'public', 'service_role']) ro, unnest(ARRAY['SELECT', 'INSERT', 'UPDATE', 'DELETE', 'TRUNCATE', 'REFERENCES', 'TRIGGER']) pr
  WHERE has_table_privilege(ro, 'public.notification_inbox', pr);
  want := 'authenticated DELETE, authenticated SELECT, service_role DELETE, service_role INSERT, service_role REFERENCES, service_role SELECT, service_role TRIGGER, service_role TRUNCATE, service_role UPDATE';
  res := res || format(E'\nprivileges -> %s', got);
  ok := ok AND got IS NOT DISTINCT FROM want;

  SELECT string_agg(policyname || ' ' || cmd || ' ' || roles::text || ' ' || qual, '; ' ORDER BY policyname) INTO got
  FROM pg_policies WHERE schemaname = 'public' AND tablename = 'notification_inbox';
  want := 'Users delete own inbox DELETE {authenticated} (user_id = ( SELECT auth.uid() AS uid)); Users read own inbox SELECT {authenticated} (user_id = ( SELECT auth.uid() AS uid))';
  res := res || format(E'\npolicies -> %s', got);
  ok := ok AND got IS NOT DISTINCT FROM want;

  SELECT relrowsecurity::text INTO got FROM pg_class WHERE oid = 'public.notification_inbox'::regclass;
  res := res || format(E'\nRLS on -> %s', got);
  ok := ok AND got = 'true';

  INSERT INTO public.notification_inbox (user_id, notification_type, title, body) VALUES (me, 'nudge', 'p40 mine', 'b') RETURNING id INTO mine;
  INSERT INTO public.notification_inbox (user_id, notification_type, title, body) VALUES (other, 'nudge', 'p40 theirs', 'b') RETURNING id INTO theirs;

  PERFORM set_config('request.jwt.claims', json_build_object('sub', me, 'role', 'authenticated')::text, true);
  SET LOCAL ROLE authenticated;
  BEGIN EXECUTE format('WITH d AS (DELETE FROM public.notification_inbox WHERE id = %L RETURNING 1) SELECT count(*)::text FROM d', theirs) INTO got;
  EXCEPTION WHEN OTHERS THEN got := SQLSTATE; END;
  res := res || format(E'\ndelete another user''s row -> %s rows (0 expected, no error)', got);
  ok := ok AND got = '0';
  BEGIN EXECUTE format('WITH d AS (DELETE FROM public.notification_inbox WHERE id = %L RETURNING 1) SELECT count(*)::text FROM d', mine) INTO got;
  EXCEPTION WHEN OTHERS THEN got := SQLSTATE; END;
  res := res || format(E'\ndelete own row -> %s rows (1 expected)', got);
  ok := ok AND got = '1';
  BEGIN EXECUTE format('INSERT INTO public.notification_inbox (user_id, notification_type, title, body) VALUES (%L, ''nudge'', ''t'', ''b'') RETURNING id::text', me) INTO got; got := 'no error';
  EXCEPTION WHEN OTHERS THEN got := SQLSTATE; END;
  res := res || format(E'\nauthenticated insert -> %s (42501 expected)', got);
  ok := ok AND got = '42501';
  BEGIN EXECUTE format('UPDATE public.notification_inbox SET quiet = true WHERE user_id = %L RETURNING id::text', me) INTO got; got := 'no error';
  EXCEPTION WHEN OTHERS THEN got := SQLSTATE; END;
  res := res || format(E'\nauthenticated update -> %s (42501 expected)', got);
  ok := ok AND got = '42501';
  RESET ROLE;

  PERFORM set_config('request.jwt.claims', json_build_object('role', 'anon')::text, true);
  SET LOCAL ROLE anon;
  BEGIN EXECUTE format('WITH d AS (DELETE FROM public.notification_inbox WHERE id = %L RETURNING 1) SELECT count(*)::text FROM d', theirs) INTO got; got := 'no error';
  EXCEPTION WHEN OTHERS THEN got := SQLSTATE; END;
  res := res || format(E'\nanon delete -> %s (42501 expected)', got);
  ok := ok AND got = '42501';
  RESET ROLE;
  PERFORM set_config('request.jwt.claims', '', true);

  SELECT count(*) FILTER (WHERE id = mine) || '/' || count(*) FILTER (WHERE id = theirs) INTO got
  FROM public.notification_inbox WHERE id IN (mine, theirs);
  res := res || format(E'\nleft after all that, own/other -> %s (0/1 expected)', got);
  ok := ok AND got = '0/1';

  RAISE EXCEPTION E'PROBE_RESULTS: %\n%', CASE WHEN ok THEN 'ALL OK' ELSE 'MISMATCH' END, res;
END $probe$;
