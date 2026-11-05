-- Prompt 34 probe: the REAL _send_push through process_stale_sessions (the suite stubs it), checked on the request
-- it queues. One transaction that ends in RAISE EXCEPTION, so nothing is ever sent or kept (net.http_request_queue
-- is transactional: rolled-back rows are never picked up by the pg_net worker).
--   Before the migration is applied:  (printf 'BEGIN;\n'; cat supabase/migrations/20261105120000_checkin_ready_pushes.sql; cat docs/hygiene/34_checkin_ready_probe.sql) > /tmp/p.sql
--                                      supabase db query --linked -f /tmp/p.sql
--   After it is applied:               supabase db query --linked -f docs/hygiene/34_checkin_ready_probe.sql
-- Test accounts: rokitest1 (A, gets a fake device token here) and testtest1 (C, no token). Never a real phone's account.
-- The Authorization header is reported as its first 7 characters only.
DO $probe$
DECLARE
  A constant uuid := '5e67f64d-16e3-4b09-9b00-ddc49df8c3f6';  -- rokitest1
  C constant uuid := 'cf4946f5-f921-4e81-bbf4-88d574e8baf5';  -- testtest1
  m bigint; sa uuid; sc uuid; j jsonb; b jsonb; h jsonb; u text; k text; n int;
  want text[][] := ARRAY[
    ['30',  'session_goal',      'emerald', '#50C878', 'Timer''s done',          'Your check-in is unlocked. Open the app and tap Complete Check-In.'],
    ['60',  'session_reminder',  'orange',  '#EA580C', 'Still waiting on you',   'Your workout isn''t counted until you check in. It takes one tap.'],
    ['120', 'session_reminder2', 'amber',   '#FBBF24', 'Last reminder',          'Tap Complete Check-In now. If you skip it, it''s counted automatically 3½ hours after you started.']];
  i int; res text := ''; ok boolean := true; got text; exp text;
BEGIN
  SELECT coalesce(max(id), 0) INTO m FROM net.http_request_queue;
  DELETE FROM active_checkin_sessions WHERE user_id IN (A, C);
  DELETE FROM device_tokens WHERE user_id IN (A, C);
  INSERT INTO device_tokens (user_id, token) VALUES (A, 'p34-probe-A');
  INSERT INTO active_checkin_sessions (user_id, started_at, workout_type, planned_duration) VALUES (A, now(), 'Strength', 30) RETURNING id INTO sa;
  INSERT INTO active_checkin_sessions (user_id, started_at, workout_type, planned_duration) VALUES (C, now(), 'Strength', 30) RETURNING id INTO sc;

  FOR i IN 1..3 LOOP
    j := public.process_stale_sessions(now() + want[i][1]::int * interval '1 minute');
    SELECT count(*) INTO n FROM net.http_request_queue q
    WHERE q.id > m AND q.url LIKE '%/send-notification' AND convert_from(q.body, 'utf8')::jsonb->>'user_id' = A::text
      AND convert_from(q.body, 'utf8')::jsonb->>'batch_key' = want[i][2] || '_' || sa;
    res := res || format(E'\nrun at +%s min -> job says %s; queued for A with batch_key %s_%s: %s', want[i][1], j, want[i][2], sa, n);
    SELECT convert_from(q.body, 'utf8')::jsonb, q.headers, q.url INTO b, h, u
    FROM net.http_request_queue q
    WHERE q.id > m AND convert_from(q.body, 'utf8')::jsonb->>'batch_key' = want[i][2] || '_' || sa;
    got := jsonb_build_object('type', b->>'type', 'reference_id', b->>'reference_id', 'kind', b->>'kind', 'color', b->>'color',
             'channel', b->>'channel', 'tag', b->>'tag', 'urgent', b->'urgent', 'dedupe_minutes', b->'dedupe_minutes',
             'title', b->>'title', 'body', b->>'body')::text;
    exp := jsonb_build_object('type', 'checkin_ready', 'reference_id', sa::text, 'kind', want[i][3], 'color', want[i][4],
             'channel', 'gym_buddy_high_importance', 'tag', 'session_' || sa, 'urgent', false, 'dedupe_minutes', 60,
             'title', want[i][5], 'body', want[i][6])::text;
    ok := ok AND n = 1 AND got = exp AND u = 'https://jwpbunulswiihkzpjopy.supabase.co/functions/v1/send-notification'
          AND left(h->>'Authorization', 7) = 'Bearer ' AND b->>'user_id' = A::text;
    res := res || format(E'\n  url=%s\n  auth=%s... content-type=%s user_id=%s\n  fields=%s\n  match expected: %s',
             u, left(h->>'Authorization', 7), h->>'Content-Type', b->>'user_id', got, got = exp);
  END LOOP;

  SELECT count(*) INTO n FROM net.http_request_queue q WHERE q.id > m AND convert_from(q.body, 'utf8')::jsonb->>'user_id' = C::text;
  res := res || format(E'\nrequests queued for C (no device token): %s', n);
  ok := ok AND n = 0;
  SELECT count(*) INTO n FROM net.http_request_queue q WHERE q.id > m AND q.url LIKE '%/send-notification';
  res := res || format(E'\ntotal send-notification requests queued: %s (3 expected)', n);
  ok := ok AND n = 3;
  RAISE EXCEPTION E'PROBE_RESULTS: %\n%', CASE WHEN ok THEN 'ALL OK' ELSE 'MISMATCH' END, res;
END $probe$;
