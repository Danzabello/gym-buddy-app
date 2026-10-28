-- Migration B post-apply probe, own connection, authenticated only (no privileged call first). RAISE rolls back.
-- onboard_check3 (not the phone account): the direct insert the old app made is denied; submit_checkin still answers.
DO $probe$
DECLARE r text[] := ARRAY[]::text[]; n text; j jsonb; acl text;
  o3 uuid := 'f0f43430-80aa-4c38-8f87-c11226bef86f';
  s uuid := (SELECT ts.id FROM team_streaks ts JOIN buddy_teams bt ON bt.id = ts.team_id JOIN team_members tm ON tm.team_id = bt.id
             WHERE tm.user_id = 'f0f43430-80aa-4c38-8f87-c11226bef86f' AND bt.is_coach_max_team AND ts.is_active LIMIT 1);
BEGIN
  SELECT relacl::text INTO acl FROM pg_class WHERE oid = 'public.daily_team_checkins'::regclass;
  PERFORM set_config('request.jwt.claims', json_build_object('sub', o3, 'role', 'authenticated')::text, true);
  SET LOCAL ROLE authenticated;
  n := 'no error';
  BEGIN
    EXECUTE format('INSERT INTO public.daily_team_checkins (team_streak_id, user_id, check_in_date, check_in_time) VALUES (%L, %L, current_date, now())', s, o3);
  EXCEPTION WHEN OTHERS THEN n := SQLSTATE || ' ' || SQLERRM;
  END;
  r := array_append(r, CASE WHEN n LIKE '42501 permission denied for table daily_team_checkins%' THEN 'PASS ' ELSE 'FAIL ' END
                       || 'B1 authenticated direct INSERT into daily_team_checkins -> ' || n);
  n := 'ok'; BEGIN j := public.submit_checkin(); EXCEPTION WHEN OTHERS THEN n := SQLSTATE || ' ' || SQLERRM; END;
  r := array_append(r, CASE WHEN n = 'ok' AND j ? 'reason' THEN 'PASS ' ELSE 'FAIL ' END || 'B2 authenticated submit_checkin still answers -> ' || n || ' ' || coalesce(j->>'reason', 'null'));
  RESET ROLE;
  r := array_append(r, CASE WHEN acl = '{postgres=arwdDxtm/postgres,anon=r/postgres,authenticated=r/postgres,service_role=arwdDxtm/postgres}'
                            THEN 'PASS ' ELSE 'FAIL ' END || 'B3 table ACL -> ' || acl);
  r := array_append(r, CASE WHEN NOT has_any_column_privilege('authenticated', 'public.daily_team_checkins', 'INSERT')
                            THEN 'PASS ' ELSE 'FAIL ' END || 'B4 no table or column INSERT for authenticated');
  RAISE EXCEPTION E'PROBE_RESULTS\n%', array_to_string(r, E'\n');
END
$probe$;
