-- Post-apply probe, own connection, authenticated/anon only (no privileged call first). RAISE rolls back.
DO $probe$
DECLARE r text[] := ARRAY[]::text[]; n text; j jsonb;
  o1 uuid := '81f83cdb-e09b-4f1f-8045-afa0d3d2181e';  -- onboard_check1, no check-in today
BEGIN
  PERFORM set_config('request.jwt.claims', json_build_object('sub', o1, 'role', 'authenticated')::text, true);
  SET LOCAL ROLE authenticated;
  n := 'ok'; BEGIN j := public.submit_checkin(); EXCEPTION WHEN OTHERS THEN n := SQLSTATE || ' ' || SQLERRM; END;
  r := array_append(r, CASE WHEN n = 'ok' AND j->>'reason' = 'not_checked_in_today' AND j->>'credited' = 'false' THEN 'PASS ' ELSE 'FAIL ' END
                       || 'L1 authenticated submit_checkin (no row today) -> ' || n || ' ' || coalesce(j::text, 'null'));
  n := 'no error'; BEGIN PERFORM public._credit_checkin(o1, now()); EXCEPTION WHEN OTHERS THEN n := SQLSTATE || ' ' || SQLERRM; END;
  r := array_append(r, CASE WHEN n LIKE '42501 permission denied for function _credit_checkin%' THEN 'PASS ' ELSE 'FAIL ' END || 'L2 authenticated _credit_checkin -> ' || n);
  n := 'no error'; BEGIN PERFORM public._credit_day(o1, now()); EXCEPTION WHEN OTHERS THEN n := SQLSTATE || ' ' || SQLERRM; END;
  r := array_append(r, CASE WHEN n LIKE '42501 permission denied for function _credit_day%' THEN 'PASS ' ELSE 'FAIL ' END || 'L3 authenticated _credit_day -> ' || n);
  RESET ROLE;
  PERFORM set_config('request.jwt.claims', json_build_object('role', 'anon')::text, true);
  SET LOCAL ROLE anon;
  n := 'no error'; BEGIN PERFORM public.submit_checkin(); EXCEPTION WHEN OTHERS THEN n := SQLSTATE || ' ' || SQLERRM; END;
  r := array_append(r, CASE WHEN n LIKE '42501 permission denied for function submit_checkin%' THEN 'PASS ' ELSE 'FAIL ' END || 'L4 anon submit_checkin -> ' || n);
  RESET ROLE;
  RAISE EXCEPTION E'PROBE_RESULTS\n%', array_to_string(r, E'\n');
END
$probe$;
