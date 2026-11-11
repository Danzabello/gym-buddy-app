-- H2 probe: pushes. One transaction, ends in RAISE EXCEPTION (rolls back,
-- so nothing queued here is ever sent). Prepend docs/handshake/H1_probe.sql's
-- helper section (everything above its DO block) when running.
-- Test accounts: rokitest1 (A), newesttest (B), testtest1 (C).
CREATE FUNCTION pg_temp.mark() RETURNS bigint LANGUAGE sql AS
  $$ SELECT coalesce(max(id), 0) FROM net.http_request_queue $$;
-- pushes queued after mark m (send-notification bodies only)
CREATE FUNCTION pg_temp.qs(m bigint) RETURNS SETOF jsonb LANGUAGE sql AS $$
  SELECT convert_from(body, 'utf8')::jsonb FROM net.http_request_queue
  WHERE id > m AND url LIKE '%/send-notification' ORDER BY id $$;
-- the single push since m, as "user|type|kind|channel|tag|urgent" (or a count)
CREATE FUNCTION pg_temp.one(m bigint) RETURNS text LANGUAGE sql AS $$
  SELECT CASE WHEN count(*) = 1 THEN max(b->>'user_id' || '|' || (b->>'type') || '|' || (b->>'kind') || '|' ||
    (b->>'channel') || '|' || (b->>'tag') || '|' || (b->>'urgent')) ELSE count(*) || ' pushes' END
  FROM pg_temp.qs(m) b $$;

DO $probe$
DECLARE
  A constant uuid := '5e67f64d-16e3-4b09-9b00-ddc49df8c3f6';  -- rokitest1 "rokitest"
  B constant uuid := '6ef4e82e-a54d-4b91-8ce4-b5f179a65f66';  -- newesttest
  C constant uuid := 'cf4946f5-f921-4e81-bbf4-88d574e8baf5';  -- testtest1
  RING constant uuid := '777d7a64-631e-41b3-97a8-2c8ea5a352a7'; -- #FF6F5E
  EMOJI constant text := '[\U0001F000-\U0001FAFF☀-➿⬀-⯿⌀-⏿️‍]';
  v_today date := (now() AT TIME ZONE 'Europe/Dublin')::date;
  m bigint; m0 bigint; r text; j jsonb; v_team uuid; v_streak_id uuid; w uuid; w2 uuid; f uuid;
  n int; res text; k text; v_old text; v_new text;
BEGIN
  m0 := pg_temp.mark();
  -- setup: tokens (fake, rolled back), shared A+B streak at day 5, B in New York, C has a ring
  DELETE FROM daily_team_checkins WHERE user_id IN (A, B, C) AND check_in_date = v_today;
  DELETE FROM active_checkin_sessions WHERE user_id IN (A, B, C);
  DELETE FROM device_tokens WHERE user_id IN (A, B, C);
  INSERT INTO device_tokens (user_id, token) VALUES (A, 'h2-probe-A'), (B, 'h2-probe-B'), (C, 'h2-probe-C');
  INSERT INTO buddy_teams (team_name, created_by) VALUES ('Probe Pair', A) RETURNING id INTO v_team;
  INSERT INTO team_members (team_id, user_id) VALUES (v_team, A), (v_team, B);
  INSERT INTO team_streaks (team_id, is_active, current_streak) VALUES (v_team, true, 5) RETURNING id INTO v_streak_id;
  UPDATE user_profiles SET timezone = 'America/New_York' WHERE id = B;
  INSERT INTO user_inventory (user_id, shop_item_id, equipped) VALUES (C, RING, true);

  -- ── invite_received (client insert by A) ──
  m := pg_temp.mark();
  r := pg_temp.u(A, format('INSERT INTO workouts (user_id, buddy_id, workout_type, workout_date, workout_time, planned_duration_minutes, status) VALUES (%L, %L, ''Strength'', %L, ''18:30'', 45, ''scheduled'') RETURNING id::text', A, B, v_today + 2));
  w := r::uuid;
  PERFORM pg_temp.eq('invite_received → invitee', pg_temp.one(m), B || '|invite_received|lavender|gym_buddy_invites|invite_' || w || '|false');
  j := (SELECT x FROM pg_temp.qs(m) x LIMIT 1);
  PERFORM pg_temp.eq('{name} = sender first name', j->>'title', 'rokitest');
  PERFORM pg_temp.ck('{time} in the recipient''s zone (New York)', j->>'body' LIKE '%' ||
    to_char(((v_today + 2) + time '18:30') AT TIME ZONE 'Europe/Dublin' AT TIME ZONE 'America/New_York', 'HH24:MI') || '%', j->>'body');
  PERFORM pg_temp.ck('{type} filled, no {x} left', j->>'body' LIKE '%Strength%' AND (j->>'title') || (j->>'body') !~ '\{', j->>'body');
  PERFORM pg_temp.eq('payload fields', concat_ws('|', j->>'color', j->>'batch_key', j->>'dedupe_minutes', j->'data'->>'avatar_id',
    j->'data'->>'avatar_border', coalesce(j->'data'->>'ring_hex', 'none'), j->'data'->>'sender_name', j->'data'->>'streak'),
    '#A99BF5|invite_received_' || w || '|1|lion|simple|none|rokitest|5');

  -- ── invite_accepted (B accepts) → creator, Dublin time ──
  m := pg_temp.mark();
  PERFORM pg_temp.call(B, 'accept_workout_invite', w, ', true');
  PERFORM pg_temp.eq('invite_accepted → creator', pg_temp.one(m), A || '|invite_accepted|lavender|gym_buddy_invites|invite_' || w || '|false');
  j := (SELECT x FROM pg_temp.qs(m) x LIMIT 1);
  PERFORM pg_temp.ck('{time} in creator''s zone (Dublin) 18:30', j->>'body' LIKE '%18:30%', j->>'body');

  -- ── invite_rescheduled (A changes time) → buddy ──
  m := pg_temp.mark();
  PERFORM pg_temp.call(A, 'change_workout_time', w, format(', %L, ''19:00''', v_today + 3));
  PERFORM pg_temp.eq('invite_rescheduled → buddy', pg_temp.one(m), B || '|invite_rescheduled|lavender|gym_buddy_invites|invite_' || w || '|false');

  -- ── invite_declined → creator ──
  m := pg_temp.mark();
  PERFORM pg_temp.call(B, 'decline_workout_invite', w);
  PERFORM pg_temp.eq('invite_declined → creator', pg_temp.one(m), A || '|invite_declined|grey|gym_buddy_invites|invite_' || w || '|false');

  -- ── invite_expired (cron) → creator ──
  w := pg_temp.mk(A, B, '-20 minutes', 'pending');
  m := pg_temp.mark();
  PERFORM public.expire_stale_workout_invites();
  PERFORM pg_temp.eq('invite_expired → creator', (SELECT count(*)::text FROM pg_temp.qs(m) x
    WHERE x->>'user_id' = A::text AND x->>'type' = 'invite_expired' AND x->>'tag' = 'invite_' || w AND x->>'kind' = 'grey'), '1');
  PERFORM pg_temp.eq('invite_expired: nobody else from this row', (SELECT count(*)::text FROM pg_temp.qs(m) x WHERE x->>'reference_id' = w::text), '1');

  -- ── workout_cancelled → buddy ──
  w := pg_temp.mk(A, B, '1 day', 'accepted');
  m := pg_temp.mark();
  PERFORM pg_temp.call(A, 'cancel_workout', w);
  PERFORM pg_temp.eq('workout_cancelled → buddy', pg_temp.one(m), B || '|workout_cancelled|red|gym_buddy_handshake|hs_' || w || '|false');

  -- ── cant_make_it → creator; then a cancel reaches nobody (buddy is out) ──
  w := pg_temp.mk(A, B, '1 day', 'accepted');
  m := pg_temp.mark();
  PERFORM pg_temp.call(B, 'cant_make_it', w);
  PERFORM pg_temp.eq('cant_make_it → creator', pg_temp.one(m), A || '|cant_make_it|grey|gym_buddy_handshake|hs_' || w || '|false');
  m := pg_temp.mark();
  PERFORM pg_temp.call(A, 'cancel_workout', w);
  PERFORM pg_temp.eq('cancelled recipient skipped (buddy already out)', pg_temp.one(m), '0 pushes');

  -- ── buddy_tapped_first, nudge, started, buddy_left ──
  w := pg_temp.mk(A, B, '0', 'accepted', 40);
  m := pg_temp.mark();
  PERFORM pg_temp.call(B, 'im_here', w);
  PERFORM pg_temp.eq('buddy_tapped_first → the other, urgent', pg_temp.one(m), A || '|buddy_tapped_first|orange|gym_buddy_handshake|hs_' || w || '|true');
  j := (SELECT x FROM pg_temp.qs(m) x LIMIT 1);
  PERFORM pg_temp.ck('{streak} shown with a shared streak (variant 1) or name only (variant 2)',
    j->>'title' IN ('newesttest · Day 5', 'newesttest'), j->>'title');
  m := pg_temp.mark();
  PERFORM pg_temp.call(B, 'nudge_workout', w);
  PERFORM pg_temp.eq('nudge → the one who has not tapped', pg_temp.one(m), A || '|nudge|orange|gym_buddy_handshake|nudge_' || w || '|true');
  j := (SELECT x FROM pg_temp.qs(m) x LIMIT 1);
  PERFORM pg_temp.eq('nudge dedupe window', j->>'dedupe_minutes', '10');
  m := pg_temp.mark();
  r := pg_temp.call(B, 'nudge_workout', w);
  PERFORM pg_temp.eq('second nudge inside 10 min: refused, no push', pg_temp.st(r) || '/' || pg_temp.one(m), 'ERR:nudge_too_soon|600/0 pushes');
  m := pg_temp.mark();
  PERFORM pg_temp.call(A, 'im_here', w);
  PERFORM pg_temp.eq('started → the first tapper only', pg_temp.one(m), B || '|started|emerald|gym_buddy_handshake|hs_' || w || '|true');
  j := (SELECT x FROM pg_temp.qs(m) x LIMIT 1);
  PERFORM pg_temp.eq('started copy', (j->>'title') || ' / ' || (j->>'body'), 'Clock''s running / rokitest is in. 40 minutes, no excuses.');
  m := pg_temp.mark();
  PERFORM pg_temp.call(B, 'leave_workout', w);
  PERFORM pg_temp.eq('buddy_left → the other', pg_temp.one(m), A || '|buddy_left|grey|gym_buddy_handshake|run_' || w || '|false');
  UPDATE workouts SET workout_started_at = now() - interval '45 minutes' WHERE id = w;
  m := pg_temp.mark();
  PERFORM pg_temp.call(A, 'complete_workout', w, ', 40');
  PERFORM pg_temp.eq('buddy_finished skipped for a buddy who left', pg_temp.one(m), '0 pushes');

  -- ── buddy_finished → the other (both in) ──
  w := pg_temp.mk(A, B, '0', 'accepted', 30);
  PERFORM pg_temp.call(A, 'im_here', w);
  PERFORM pg_temp.call(B, 'im_here', w);
  UPDATE workouts SET workout_started_at = now() - interval '35 minutes' WHERE id = w;
  m := pg_temp.mark();
  PERFORM pg_temp.call(B, 'complete_workout', w, ', 30');
  PERFORM pg_temp.eq('buddy_finished → the other, not the completer', pg_temp.one(m), A || '|buddy_finished|emerald|gym_buddy_handshake|run_' || w || '|false');

  -- ── no streak: C (no shared team) taps first with B; ring colour in data ──
  w := pg_temp.mk(C, B, '0', 'accepted');
  m := pg_temp.mark();
  PERFORM pg_temp.call(C, 'im_here', w);
  j := (SELECT x FROM pg_temp.qs(m) x LIMIT 1);
  PERFORM pg_temp.eq('{streak} omitted without a shared streak', (j->>'title') || '|' || (j->'data'->>'streak'), 'testtest1|');
  PERFORM pg_temp.eq('sender ring colour in data', j->'data'->>'ring_hex', '#FF6F5E');

  -- ── time_to_start: both people, once only ──
  w := pg_temp.mk(A, B, '-1 minute', 'accepted');
  m := pg_temp.mark();
  PERFORM public.send_time_to_start_pushes();
  PERFORM public.send_time_to_start_pushes();
  PERFORM pg_temp.eq('time_to_start: both, once, urgent', (SELECT string_agg(x->>'user_id' || ':' || (x->>'urgent'), ',' ORDER BY x->>'user_id')
    FROM pg_temp.qs(m) x WHERE x->>'reference_id' = w::text AND x->>'type' = 'time_to_start'),
    (SELECT string_agg(u::text || ':true', ',' ORDER BY u::text) FROM unnest(ARRAY[A, B]) u));
  PERFORM pg_temp.eq('time_to_start recorded', (SELECT (time_to_start_sent_at = now())::text FROM workouts WHERE id = w), 'true');
  w2 := pg_temp.mk(C, B, '-1 minute', 'accepted');
  PERFORM pg_temp.call(B, 'im_here', w2);
  m := pg_temp.mark();
  PERFORM public.send_time_to_start_pushes();
  PERFORM pg_temp.eq('time_to_start skips who already tapped', pg_temp.one(m), C || '|time_to_start|orange|gym_buddy_handshake|hs_' || w2 || '|true');
  m := pg_temp.mark();
  PERFORM public.send_time_to_start_pushes();
  PERFORM pg_temp.eq('time_to_start never twice', pg_temp.one(m), '0 pushes');

  -- ── missing token: skipped ──
  DELETE FROM device_tokens WHERE user_id = C;
  m := pg_temp.mark();
  PERFORM pg_temp.u(B, format('INSERT INTO workouts (user_id, buddy_id, workout_type, workout_date, workout_time, status) VALUES (%L, %L, ''Yoga'', %L, ''08:00'', ''scheduled'') RETURNING id::text', B, C, v_today + 4));
  PERFORM pg_temp.eq('no-token recipient skipped', pg_temp.one(m), '0 pushes');
  INSERT INTO device_tokens (user_id, token) VALUES (C, 'h2-probe-C');

  -- ── friend request / accepted ──
  m := pg_temp.mark();
  INSERT INTO friendships (user_id, friend_id) VALUES (C, A) RETURNING id INTO f;
  PERFORM pg_temp.eq('friend_request', pg_temp.one(m), A || '|friend_request|lavender|gym_buddy_friends|friend_' || f || '|false');
  m := pg_temp.mark();
  UPDATE friendships SET status = 'accepted' WHERE id = f;
  PERFORM pg_temp.eq('friend_accepted', pg_temp.one(m), C || '|friend_accepted|lavender|gym_buddy_friends|friend_' || f || '|false');
  j := (SELECT x FROM pg_temp.qs(m) x LIMIT 1);
  PERFORM pg_temp.eq('friend_accepted copy', (j->>'title') || ' / ' || (j->>'body'), 'rokitest / is your buddy now. Pick a time and train.');

  -- ── buddy_checked_in, streak milestone, streak broken ──
  m := pg_temp.mark();
  INSERT INTO daily_team_checkins (team_streak_id, user_id, check_in_date) VALUES (v_streak_id, B, v_today);
  PERFORM pg_temp.eq('buddy_checked_in → the other member', pg_temp.one(m), A || '|buddy_checked_in|emerald|gym_buddy_streaks|streak_' || v_team || '|false');
  j := (SELECT x FROM pg_temp.qs(m) x LIMIT 1);
  PERFORM pg_temp.eq('buddy_checked_in copy with streak', (j->>'title') || ' / ' || (j->>'body'), 'newesttest · Day 5 / is done. Your turn.');
  m := pg_temp.mark();
  UPDATE team_streaks SET current_streak = 7 WHERE id = v_streak_id;
  PERFORM pg_temp.eq('streak_milestone → both members', (SELECT string_agg(x->>'title' || '|' || (x->>'kind') || '|' || (x->>'tag'), ',') FROM pg_temp.qs(m) x),
    'Day 7 with Probe Pair|emerald|streak_' || v_team || ',Day 7 with Probe Pair|emerald|streak_' || v_team);
  m := pg_temp.mark();
  UPDATE team_streaks SET current_streak = 0 WHERE id = v_streak_id;
  PERFORM pg_temp.eq('streak_broken knows the old length', (SELECT string_agg(DISTINCT (x->>'body') || '|' || (x->>'kind'), ',') FROM pg_temp.qs(m) x),
    '7 days with Probe Pair. Start the next one today.|red');

  -- ── every variant reachable; every template emoji-free ──
  FOR k, n IN SELECT key, count(*) FROM push_templates GROUP BY key LOOP
    m := pg_temp.mark();
    FOR i IN 1..(CASE WHEN n = 1 THEN 1 ELSE 40 END) LOOP
      PERFORM public._send_push(A, k, jsonb_build_object('type', 'Yoga', 'planned_at', now(), 'n', 9, 'next', 10, 'team', 'T', 'minutes', 30),
                                'grey', 'handshake', k, 'probe', 'probe', false, B);
    END LOOP;
    PERFORM pg_temp.eq('variants reachable: ' || k, (SELECT count(DISTINCT (x->>'title') || (x->>'body'))::text FROM pg_temp.qs(m) x), n::text);
  END LOOP;
  PERFORM pg_temp.eq('no emoji in any title/body sent in this probe',
    (SELECT count(*)::text FROM pg_temp.qs(m0) x WHERE (x->>'title') || (x->>'body') ~ EMOJI), '0');
  PERFORM pg_temp.eq('no emoji in any template', (SELECT count(*)::text FROM push_templates WHERE title || body ~ EMOJI), '0');
  PERFORM pg_temp.ck('emoji regex works', 'Go 💪' ~ EMOJI AND 'A · Day 5 — ok' !~ EMOJI);
  PERFORM pg_temp.eq('actor never got their own push (all RPC-driven pushes above)',
    (SELECT count(*)::text FROM pg_temp.qs(m0) x WHERE x->>'reference_id' <> 'probe' AND x->>'title' LIKE 'rokitest%' AND x->>'user_id' = A::text), '0');

  -- ── process_stale_sessions: #8/#9 gone, body otherwise unchanged ──
  INSERT INTO active_checkin_sessions (user_id, started_at, planned_duration, workout_type)
  VALUES (C, now() - interval '40 minutes', 30, 'Yoga');
  m := pg_temp.mark();
  PERFORM public.process_stale_sessions(now());
  PERFORM pg_temp.eq('stale: goal bookkeeping still runs', (SELECT (goal_notified_at = now())::text FROM active_checkin_sessions WHERE user_id = C), 'true');
  PERFORM pg_temp.eq('stale: no #8/#9 push', (SELECT count(*)::text FROM pg_temp.qs(m) x WHERE x->>'type' = 'workout_overtime' OR x->>'title' IN ('Workout complete', 'Workout waiting')), '0');
  w := pg_temp.mk(A, B, '-4 hours', 'accepted', 30);
  UPDATE workouts SET status = 'in_progress', workout_started_at = now() - interval '215 minutes', creator_ready = true, buddy_ready = true WHERE id = w;
  INSERT INTO active_checkin_sessions (user_id, started_at, planned_duration, workout_type, workout_id)
  VALUES (A, now() - interval '215 minutes', 30, 'Strength', w), (B, now() - interval '215 minutes', 30, 'Strength', w)
  ON CONFLICT (user_id) DO UPDATE SET started_at = EXCLUDED.started_at, workout_id = EXCLUDED.workout_id;
  DELETE FROM workout_logs WHERE user_id IN (A, B) AND auto_completed AND workout_date = ((now() - interval '215 minutes') AT TIME ZONE 'Europe/Dublin')::date;
  PERFORM public.process_stale_sessions(now());
  PERFORM pg_temp.eq('stale: 3h30 still credits both and closes the row',
    (SELECT status || '/' || auto_completed || '/' || (SELECT count(*) FROM workout_logs WHERE user_id IN (A, B) AND auto_completed
       AND workout_date = ((now() - interval '215 minutes') AT TIME ZONE 'Europe/Dublin')::date) FROM workouts WHERE id = w), 'completed/true/2');
  SELECT md5(pg_get_functiondef('public.process_stale_sessions'::regproc)) INTO v_new;
  PERFORM pg_temp.ck('stale: body = old body minus the push block (md5 checked outside)', v_new IS NOT NULL, v_new);

  -- ── templates locked; functions pinned; grants ──
  PERFORM pg_temp.eq('push_templates: RLS on, no policies',
    (SELECT relrowsecurity::text || '/' || (SELECT count(*) FROM pg_policies WHERE tablename = 'push_templates') FROM pg_class WHERE oid = 'public.push_templates'::regclass), 'true/0');
  PERFORM pg_temp.ck('push_templates: authenticated denied', pg_temp.u(A, 'SELECT count(*)::text FROM push_templates') LIKE 'ERR:permission denied%');
  PERFORM pg_temp.ck('push_templates: anon denied', pg_temp.u(NULL, 'SELECT count(*)::text FROM push_templates', 'anon') LIKE 'ERR:permission denied%');
  PERFORM pg_temp.ck('_send_push: authenticated denied',
    pg_temp.u(A, format('SELECT public._send_push(%L, ''nudge'', ''{}'', ''orange'', ''handshake'', ''x'', ''x'', ''x'')::text', B)) LIKE 'ERR:permission denied%');
  FOREACH k IN ARRAY ARRAY['_send_push', 'notify_workout_handshake', 'send_time_to_start_pushes', 'notify_friend_request',
                           'notify_friend_accepted', 'notify_buddy_checkin', 'notify_streak_update', 'process_stale_sessions', 'change_workout_time'] LOOP
    PERFORM pg_temp.ck('search_path pinned: ' || k, (SELECT bool_and('search_path=public' = ANY(proconfig)) FROM pg_proc WHERE proname = k AND pronamespace = 'public'::regnamespace));
    SELECT string_agg(coalesce(ro.rolname, 'PUBLIC'), ',' ORDER BY coalesce(ro.rolname, 'PUBLIC')) INTO r
    FROM pg_proc p, aclexplode(p.proacl) a LEFT JOIN pg_roles ro ON ro.oid = a.grantee
    WHERE p.proname = k AND p.pronamespace = 'public'::regnamespace;
    PERFORM pg_temp.eq('grants: ' || k, r, CASE WHEN k = 'change_workout_time' THEN 'authenticated,postgres,service_role' ELSE 'postgres,service_role' END);
  END LOOP;
  PERFORM pg_temp.eq('cron job time_to_start every minute', (SELECT schedule FROM cron.job WHERE jobname = 'handshake-time-to-start'), '* * * * *');

  SELECT count(*) FILTER (WHERE ok) || ' pass, ' || count(*) FILTER (WHERE NOT ok) || ' fail. md5(stale)=' || v_new || '. FAILED: ' ||
         coalesce(string_agg(t || ' [' || coalesce(info, '') || ']', '; ') FILTER (WHERE NOT ok), 'none')
  INTO res FROM pr;
  RAISE EXCEPTION 'PROBE_RESULTS: %', res;
END $probe$;
