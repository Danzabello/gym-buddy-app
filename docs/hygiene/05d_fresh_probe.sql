-- 05d post-apply probe, own connection, authenticated only (no privileged call first). RAISE rolls back.
DO $probe$
DECLARE r text[] := ARRAY[]::text[]; n text; k int; tt1 uuid := 'cf4946f5-f921-4e81-bbf4-88d574e8baf5';
BEGIN
PERFORM set_config('request.jwt.claims', json_build_object('sub', tt1, 'role', 'authenticated')::text, true); SET LOCAL ROLE authenticated;
n := 'no error'; BEGIN PERFORM public.check_in_coach_max_with_buddy(tt1); EXCEPTION WHEN OTHERS THEN n := SQLSTATE || ' ' || SQLERRM; END;
r := array_append(r, CASE WHEN n LIKE '42501 permission denied for function%' THEN 'PASS ' ELSE 'FAIL ' END || 'L1 check_in_coach_max_with_buddy -> ' || n);
n := 'no error'; BEGIN UPDATE public.user_profiles SET rest_tokens_available = 0 WHERE id = tt1; EXCEPTION WHEN OTHERS THEN n := SQLSTATE || ' ' || SQLERRM; END;
r := array_append(r, CASE WHEN n LIKE '42501 permission denied%' THEN 'PASS ' ELSE 'FAIL ' END || 'L2 UPDATE rest_tokens_available -> ' || n);
n := 'ok'; BEGIN UPDATE public.user_profiles SET avatar_id = avatar_id, avatar_border = avatar_border, updated_at = now() WHERE id = tt1; GET DIAGNOSTICS k = ROW_COUNT; EXCEPTION WHEN OTHERS THEN n := SQLSTATE || ' ' || SQLERRM; k := -1; END;
r := array_append(r, CASE WHEN n = 'ok' AND k = 1 THEN 'PASS ' ELSE 'FAIL ' END || format('L3 UPDATE avatar picker payload -> %s, rows %s', n, k));
RAISE EXCEPTION E'PROBE_RESULTS\n%', array_to_string(r, E'\n');
END
$probe$;
