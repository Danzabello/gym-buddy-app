-- Prompt 35 probe: the REAL _send_push through process_stale_sessions -> _auto_credit (the suite stubs it), checked on the
-- request it queues. One transaction that ends in RAISE EXCEPTION, so nothing is ever sent or kept (net.http_request_queue is
-- transactional: rolled-back rows are never picked up by the pg_net worker). Run after 20261105220000 is applied:
--   supabase db query --linked -f dev/hygiene/35_auto_checkin_limit_probe.sql
-- Before it is applied:  (printf 'BEGIN;\n'; cat supabase/migrations/20261105220000_auto_checkin_limit.sql; cat dev/hygiene/35_auto_checkin_limit_probe.sql) > /tmp/p.sql
--                        supabase db query --linked -f /tmp/p.sql
-- Test account: rokitest1 (A, gets a fake device token here). Never a real phone's account. Four forgotten sessions in a row for A:
-- counts 1, 2, 3 (one Coach Max request on the third only), the fourth refused. The day rows are cleared between runs (rolled back).
-- The Authorization header is reported as its first 7 characters only.
DO $probe$
DECLARE
  A constant uuid := '5e67f64d-16e3-4b09-9b00-ddc49df8c3f6';  -- rokitest1
  CMX constant uuid := '00000000-0000-0000-0000-000000000001';
  m bigint; j jsonb; b jsonb; h jsonb; u text; n int; i int; c text; sid int;
  res text := ''; ok boolean := true; got text; exp text; bodies text[];
BEGIN
  SELECT coalesce(max(id), 0) INTO m FROM net.http_request_queue;
  DELETE FROM active_checkin_sessions WHERE user_id = A;
  DELETE FROM device_tokens WHERE user_id = A;
  DELETE FROM auto_checkin_counts WHERE user_id = A;
  INSERT INTO device_tokens (user_id, token) VALUES (A, 'p35-probe-A');

  FOR i IN 1..4 LOOP
    DELETE FROM workout_logs WHERE user_id = A AND auto_completed;
    DELETE FROM daily_team_checkins WHERE user_id = A AND check_in_date = public._credit_day(A, now());
    INSERT INTO active_checkin_sessions (user_id, started_at, workout_type, planned_duration) VALUES (A, now(), 'Strength', 30);
    j := public.process_stale_sessions(now() + interval '210 minutes');
    SELECT coalesce((SELECT consecutive::text FROM auto_checkin_counts WHERE user_id = A), '0') INTO c;
    SELECT count(*) INTO n FROM net.http_request_queue q
    WHERE q.id > m AND q.url LIKE '%/send-notification' AND convert_from(q.body, 'utf8')::jsonb->>'user_id' = A::text
      AND convert_from(q.body, 'utf8')::jsonb->>'batch_key' = 'coach_max_auto_limit_' || A;
    res := res || format(E'\nforgotten session %s -> counter %s, Coach Max requests queued so far %s, session left %s, auto log rows %s',
             i, c, n, (SELECT count(*) FROM active_checkin_sessions WHERE user_id = A),
             (SELECT count(*) FROM workout_logs WHERE user_id = A AND auto_completed));
    ok := ok AND c = LEAST(i, 3)::text AND n = CASE WHEN i >= 3 THEN 1 ELSE 0 END
          AND NOT EXISTS (SELECT 1 FROM active_checkin_sessions WHERE user_id = A)
          AND (SELECT count(*) FROM workout_logs WHERE user_id = A AND auto_completed) = CASE WHEN i = 4 THEN 0 ELSE 1 END;
  END LOOP;

  SELECT convert_from(q.body, 'utf8')::jsonb, q.headers, q.url INTO b, h, u
  FROM net.http_request_queue q
  WHERE q.id > m AND convert_from(q.body, 'utf8')::jsonb->>'batch_key' = 'coach_max_auto_limit_' || A;
  bodies := ARRAY[
    'That''s three auto check-ins in a row. I''m done covering for you. Next time, you check in yourself.',
    'Three in a row. I covered for you, now it''s your turn. Check in yourself from now on.',
    'I''m not your alarm clock. Three auto check-ins is all you get. Check in yourself next time.'];
  got := jsonb_build_object('type', b->>'type', 'reference_id', b->>'reference_id', 'kind', b->>'kind', 'color', b->>'color',
           'channel', b->>'channel', 'tag', b->>'tag', 'urgent', b->'urgent', 'dedupe_minutes', b->'dedupe_minutes',
           'title', b->>'title', 'body_is_a_template', (b->>'body') = ANY(bodies))::text;
  exp := jsonb_build_object('type', 'coach_max_motivational', 'reference_id', A::text, 'kind', 'emerald', 'color', '#50C878',
           'channel', 'gym_buddy_coach_max', 'tag', 'coach_max_limit_' || A, 'urgent', false, 'dedupe_minutes', 60,
           'title', 'Coach Max', 'body_is_a_template', true)::text;
  ok := ok AND got = exp AND u = 'https://jwpbunulswiihkzpjopy.supabase.co/functions/v1/send-notification'
        AND left(h->>'Authorization', 7) = 'Bearer ' AND b->>'user_id' = A::text;
  res := res || format(E'\nthe Coach Max request:\n  url=%s\n  auth=%s... content-type=%s user_id=%s\n  fields=%s\n  body=%s\n  data=%s\n  match expected: %s',
           u, left(h->>'Authorization', 7), h->>'Content-Type', b->>'user_id', got, b->>'body', b->'data', got = exp);

  SELECT count(*) INTO n FROM net.http_request_queue q WHERE q.id > m AND q.url LIKE '%/send-notification'
    AND convert_from(q.body, 'utf8')::jsonb->>'user_id' = A::text;
  res := res || format(E'\nrequests queued for A in total: %s (1 expected: the three auto check-ins and the refusal send nothing else)', n);
  ok := ok AND n = 1;
  RAISE EXCEPTION E'PROBE_RESULTS: %\n%', CASE WHEN ok THEN 'ALL OK' ELSE 'MISMATCH' END, res;
END $probe$;
