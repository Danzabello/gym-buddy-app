-- Prompt 27 probe: the REAL _send_push (the suite stubs it), checked on the requests it queues, and the inbox read by a
-- client. One transaction that ends in RAISE EXCEPTION, so nothing is ever sent or kept (net.http_request_queue is
-- transactional: rolled-back rows are never picked up by the pg_net worker). Run after 20261105230000 is applied:
--   supabase db query --linked -f dev/hygiene/27_notification_inbox_probe.sql
-- Before it is applied:  (printf 'BEGIN;\n'; cat supabase/migrations/20261105230000_notification_inbox.sql; cat dev/hygiene/27_notification_inbox_probe.sql) > /tmp/p.sql
--                        supabase db query --linked -f /tmp/p.sql
-- Test accounts: rokitest1 (A, gets a fake device token here), testtest1 (C, its tokens are removed here). Never a real phone's account.
-- The Authorization header is reported as its first 7 characters only.
DO $probe$
DECLARE
  A constant uuid := '5e67f64d-16e3-4b09-9b00-ddc49df8c3f6';  -- rokitest1
  C constant uuid := 'cf4946f5-f921-4e81-bbf4-88d574e8baf5';  -- testtest1
  CMX constant uuid := '00000000-0000-0000-0000-000000000001';
  m bigint; b jsonb; h jsonb; ret boolean; n int; got text; av text; w1 uuid; w2 uuid;
  res text := ''; ok boolean := true;
BEGIN
  DELETE FROM device_tokens WHERE user_id IN (A, C);
  INSERT INTO device_tokens (user_id, token) VALUES (A, 'p27-probe-A');
  SELECT coalesce(max(id), 0) INTO m FROM net.http_request_queue;

  -- A user with a token: one request, true, as before.
  ret := public._send_push(A, 'friend_request', '{}'::jsonb, 'lavender', 'friends', 'friend_request', 'p27-a', 'p27-tag', false, C);
  SELECT count(*) INTO n FROM net.http_request_queue q WHERE q.id > m;
  SELECT convert_from(q.body, 'utf8')::jsonb INTO b FROM net.http_request_queue q WHERE q.id > m;
  res := res || format(E'\nuser with a token -> returned %s, requests %s, sender_id %s', ret, n, b->>'sender_id');
  ok := ok AND ret AND n = 1 AND b->>'sender_id' = C::text;

  -- A user with no token: still one request, false.
  SELECT coalesce(max(id), 0) INTO m FROM net.http_request_queue;
  ret := public._send_push(C, 'friend_request', '{}'::jsonb, 'lavender', 'friends', 'friend_request', 'p27-c', 'p27-tag', false, A);
  SELECT count(*) INTO n FROM net.http_request_queue q WHERE q.id > m;
  SELECT convert_from(q.body, 'utf8')::jsonb, q.headers INTO b, h FROM net.http_request_queue q WHERE q.id > m;
  got := jsonb_build_object('user_id', b->>'user_id', 'sender_id', b->>'sender_id', 'type', b->>'type', 'reference_id', b->>'reference_id', 'batch_key', b->>'batch_key',
                            'dedupe_minutes', b->'dedupe_minutes', 'urgent', b->'urgent', 'body', b->>'body')::text;
  res := res || format(E'\nuser with no token -> returned %s, requests %s\n  auth=%s...\n  title=%s\n  fields=%s', ret, n, left(h->>'Authorization', 7), b->>'title', got);
  ok := ok AND NOT ret AND n = 1 AND left(h->>'Authorization', 7) = 'Bearer ' AND b->>'user_id' = C::text AND b->>'sender_id' = A::text AND b->>'type' = 'friend_request'
        AND b->>'batch_key' = 'friend_request_p27-c' AND (b->>'dedupe_minutes')::int = 60 AND b->>'body' = 'wants to be your gym buddy. Accept to start a streak together.'
        AND b->>'title' !~ '[{}]';

  -- Coach Max, no user, no template: no request, false.
  SELECT coalesce(max(id), 0) INTO m FROM net.http_request_queue;
  ret := public._send_push(CMX, 'buddy_checked_in', '{}'::jsonb, 'emerald', 'streaks', 'buddy_checked_in', 'p27-m', 'p27-tag', false, A);
  res := res || format(E'\nCoach Max -> returned %s', ret);
  ok := ok AND NOT ret;
  ret := public._send_push(NULL, 'buddy_checked_in', '{}'::jsonb, 'emerald', 'streaks', 'buddy_checked_in', 'p27-n', 'p27-tag', false, A);
  res := res || format(E'\nno user -> returned %s', ret);
  ok := ok AND NOT ret;
  ret := public._send_push(C, 'p27_no_such_template', '{}'::jsonb, 'emerald', 'streaks', 'buddy_checked_in', 'p27-t', 'p27-tag', false, A);
  res := res || format(E'\nno template -> returned %s', ret);
  ok := ok AND NOT ret;
  SELECT count(*) INTO n FROM net.http_request_queue q WHERE q.id > m;
  res := res || format(E'\nrequests from those three: %s (0 expected)', n);
  ok := ok AND n = 0;

  -- Coach Max as the sender; a push with no sender carries an explicit null.
  SELECT coalesce(max(id), 0) INTO m FROM net.http_request_queue;
  PERFORM public._send_push(C, 'coach_max_day1', '{}'::jsonb, 'emerald', 'coach_max', 'coach_max_motivational', 'p27-cmx', 'p27-tag', false, CMX);
  SELECT convert_from(q.body, 'utf8')::jsonb INTO b FROM net.http_request_queue q WHERE q.id > m;
  res := res || format(E'\nCoach Max as sender -> sender_id %s', b->>'sender_id');
  ok := ok AND b->>'sender_id' = CMX::text;
  SELECT coalesce(max(id), 0) INTO m FROM net.http_request_queue;
  PERFORM public._send_push(C, 'session_goal', '{}'::jsonb, 'emerald', 'high_importance', 'checkin_ready', 'p27-sys', 'p27-tag', false, NULL);
  SELECT convert_from(q.body, 'utf8')::jsonb INTO b FROM net.http_request_queue q WHERE q.id > m;
  res := res || format(E'\nsystem push -> sender_id present %s, value %s', b ? 'sender_id', coalesce(b->>'sender_id', 'null'));
  ok := ok AND b ? 'sender_id' AND b->>'sender_id' IS NULL;

  -- Through the real triggers and cron function: invite_expired carries the buddy, time_to_start the partner.
  -- C is the buddy, A the creator. Only requests about these two workouts are counted.
  INSERT INTO public.workouts (user_id, buddy_id, workout_type, workout_date, workout_time, status, buddy_status, planned_duration_minutes)
  VALUES (A, C, 'Strength', current_date + 1, '10:00', 'scheduled', 'pending', 30) RETURNING id INTO w1;
  SELECT coalesce(max(id), 0) INTO m FROM net.http_request_queue;
  UPDATE public.workouts SET buddy_status = 'expired' WHERE id = w1;
  SELECT convert_from(q.body, 'utf8')::jsonb INTO b FROM net.http_request_queue q
  WHERE q.id > m AND convert_from(q.body, 'utf8')::jsonb->>'type' = 'invite_expired' AND convert_from(q.body, 'utf8')::jsonb->>'reference_id' = w1::text;
  res := res || format(E'\ninvite_expired -> to %s, sender_id %s', b->>'user_id', b->>'sender_id');
  ok := ok AND b->>'user_id' = A::text AND b->>'sender_id' = C::text;
  INSERT INTO public.workouts (user_id, buddy_id, workout_type, workout_date, workout_time, status, buddy_status, planned_duration_minutes)
  VALUES (A, C, 'Strength', ((now() - interval '1 minute') AT TIME ZONE public.safe_user_tz(A))::date,
          ((now() - interval '1 minute') AT TIME ZONE public.safe_user_tz(A))::time, 'scheduled', 'accepted', 30) RETURNING id INTO w2;
  SELECT coalesce(max(id), 0) INTO m FROM net.http_request_queue;
  PERFORM public.send_time_to_start_pushes();
  SELECT string_agg((convert_from(q.body, 'utf8')::jsonb->>'user_id') || '<-' || (convert_from(q.body, 'utf8')::jsonb->>'sender_id'), ','
                    ORDER BY convert_from(q.body, 'utf8')::jsonb->>'user_id') INTO got
  FROM net.http_request_queue q
  WHERE q.id > m AND convert_from(q.body, 'utf8')::jsonb->>'type' = 'time_to_start' AND convert_from(q.body, 'utf8')::jsonb->>'reference_id' = w2::text;
  res := res || format(E'\ntime_to_start (recipient<-sender) -> %s', got);
  ok := ok AND got = format('%s<-%s,%s<-%s', A, C, C, A);

  -- The row a client reads: the columns prompt 28 selects, its own rows only; then the sender's avatar from the public columns.
  INSERT INTO public.notification_inbox (user_id, notification_type, title, body, quiet, reference_id, sender_id, batch_key) VALUES
    (C, 'nudge', 'p27 held', 'b', true, 'r1', CMX, 'k1'), (A, 'nudge', 'p27 other', 'b', false, 'r2', NULL, 'k2');
  PERFORM set_config('request.jwt.claims', json_build_object('sub', C, 'role', 'authenticated')::text, true);
  SET LOCAL ROLE authenticated;
  EXECUTE 'SELECT string_agg(concat_ws(''|'', notification_type, title, body, quiet, reference_id, sender_id), '','') FROM public.notification_inbox
           WHERE title LIKE ''p27%'' AND created_at >= now() - interval ''7 days''' INTO got;
  EXECUTE 'SELECT avatar_id FROM public.user_profiles WHERE id = (SELECT sender_id FROM public.notification_inbox WHERE title = ''p27 held'')' INTO av;
  RESET ROLE;
  PERFORM set_config('request.jwt.claims', '', true);
  res := res || format(E'\nthe client reads: %s\nand the sender''s avatar_id: %s', got, av);
  ok := ok AND got = 'nudge|p27 held|b|t|r1|' || CMX AND av IS NOT NULL;

  RAISE EXCEPTION E'PROBE_RESULTS: %\n%', CASE WHEN ok THEN 'ALL OK' ELSE 'MISMATCH' END, res;
END $probe$;
