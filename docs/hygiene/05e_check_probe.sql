-- 05e CHECK re-confirm. Fresh connection, authenticated call first; ends in RAISE so it rolls back.
DO $probe$
DECLARE r text[] := ARRAY[]::text[]; n text; tt1 uuid := 'cf4946f5-f921-4e81-bbf4-88d574e8baf5';
BEGIN
PERFORM set_config('request.jwt.claims', json_build_object('sub', tt1, 'role', 'authenticated')::text, true); SET LOCAL ROLE authenticated;
n := 'no error'; BEGIN UPDATE public.user_profiles SET coin_balance = 999 WHERE id = tt1; EXCEPTION WHEN OTHERS THEN n := SQLSTATE || ' ' || SQLERRM; END;
r := array_append(r, CASE WHEN n LIKE '42501%' THEN 'PASS ' ELSE 'FAIL ' END || 'C1 authenticated UPDATE coin_balance -> ' || n);
RESET ROLE; PERFORM set_config('request.jwt.claims', '', true);
n := 'no error'; BEGIN UPDATE public.user_profiles SET coin_balance = -1 WHERE id = tt1; EXCEPTION WHEN OTHERS THEN n := SQLSTATE || ' ' || SQLERRM; END;
r := array_append(r, CASE WHEN n LIKE '23514%user_profiles_coin_balance_nonneg%' THEN 'PASS ' ELSE 'FAIL ' END || 'C2 postgres UPDATE coin_balance = -1 -> ' || n);
RAISE EXCEPTION E'PROBE_RESULTS\n%', array_to_string(r, E'\n');
END
$probe$;
