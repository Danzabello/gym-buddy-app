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
  A constant uuid := '5e67f64d-16e3-4b09-9b00-ddc49df8c3f6';
  B constant uuid := '6ef4e82e-a54d-4b91-8ce4-b5f179a65f66';
  C constant uuid := 'cf4946f5-f921-4e81-bbf4-88d574e8baf5';
  acc uuid; pend uuid; solo uuid; res text;
BEGIN
  FOR i IN 1..5 LOOP PERFORM pg_temp.mk(C, B, make_interval(days => i), 'pending'); END LOOP;
  acc := pg_temp.mk(C, B, '10 days', 'accepted');
  pend := (SELECT id FROM workouts WHERE user_id = C AND buddy_status = 'pending' AND status = 'scheduled' ORDER BY planned_at LIMIT 1);
  solo := pg_temp.mk(C, NULL, '11 days', 'pending');
  PERFORM pg_temp.eq('cap: rescheduling an accepted invite past 5 refused',
    pg_temp.st(pg_temp.call(C, 'change_workout_time', acc, ', current_date + 12, ''10:00''')), 'ERR:invite_cap_reached');
  PERFORM pg_temp.eq('cap: refused change left the row untouched', (SELECT buddy_status FROM workouts WHERE id = acc), 'accepted');
  PERFORM pg_temp.eq('cap: rescheduling an already-pending invite (does not count itself)',
    pg_temp.st(pg_temp.call(C, 'change_workout_time', pend, ', current_date + 13, ''10:00''')), 'rescheduled');
  PERFORM pg_temp.eq('cap: solo reschedule unaffected',
    pg_temp.st(pg_temp.call(C, 'change_workout_time', solo, ', current_date + 14, ''10:00''')), 'rescheduled');
  PERFORM pg_temp.eq('cap: after a decline the accepted one can move',
    pg_temp.st(pg_temp.call(B, 'decline_workout_invite', pend)) || '/' ||
    pg_temp.st(pg_temp.call(C, 'change_workout_time', acc, ', current_date + 12, ''10:00''')), 'closed/rescheduled');
  PERFORM pg_temp.eq('grants unchanged',
    (SELECT string_agg(coalesce(ro.rolname, 'PUBLIC'), ',' ORDER BY coalesce(ro.rolname, 'PUBLIC'))
     FROM pg_proc p, aclexplode(p.proacl) a LEFT JOIN pg_roles ro ON ro.oid = a.grantee WHERE p.proname = 'change_workout_time'),
    'authenticated,postgres,service_role');
  SELECT count(*) FILTER (WHERE ok) || ' pass, ' || count(*) FILTER (WHERE NOT ok) || ' fail. FAILED: ' ||
         coalesce(string_agg(t || ' [' || coalesce(info, '') || ']', '; ') FILTER (WHERE NOT ok), 'none') INTO res FROM pr;
  RAISE EXCEPTION 'PROBE_RESULTS: %', res;
END $probe$;
