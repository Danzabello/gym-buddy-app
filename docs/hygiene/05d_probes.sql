-- 05d probes: BEGIN; migration 20261013020000 inline; probes; DO block ends in RAISE so the whole transaction rolls back.
BEGIN;
-- Hygiene 05d. Report: docs/hygiene/05d_report.md. Rollback: docs/rollback_20261013020000.sql

-- check_in_coach_max_with_buddy: no caller in Dart, edge functions, SQL bodies, triggers or cron since b99b0b2.
-- Kept for service_role/postgres; closed to clients.
REVOKE EXECUTE ON FUNCTION public.check_in_coach_max_with_buddy(uuid) FROM PUBLIC, anon, authenticated;

-- purchase_shop_item: lock the caller's user_profiles row before the balance check. Logic otherwise unchanged.
CREATE OR REPLACE FUNCTION public.purchase_shop_item(p_shop_item_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_caller uuid := auth.uid();
  v_cost integer;
  v_name text;
  v_unlock_level integer;
  v_unlock_achievement_id text;
  v_level integer;
  v_balance integer;
  v_already_owned boolean;
BEGIN
  IF v_caller IS NULL THEN
    RAISE EXCEPTION 'unauthenticated';
  END IF;

  -- Serialise purchases per user: concurrent calls wait here, then see the committed balance.
  PERFORM 1 FROM user_profiles WHERE id = v_caller FOR UPDATE;

  SELECT cost, name, unlock_level, unlock_achievement_id
  INTO v_cost, v_name, v_unlock_level, v_unlock_achievement_id
  FROM shop_items WHERE id = p_shop_item_id AND is_available = true;

  IF v_cost IS NULL THEN
    RAISE EXCEPTION 'item_not_found_or_unavailable';
  END IF;

  SELECT EXISTS(
    SELECT 1 FROM user_inventory WHERE user_id = v_caller AND shop_item_id = p_shop_item_id
  ) INTO v_already_owned;

  IF v_already_owned THEN
    RETURN jsonb_build_object('success', false, 'reason', 'already_owned');
  END IF;

  SELECT COALESCE(level, 1), coin_balance INTO v_level, v_balance
  FROM user_profiles WHERE id = v_caller;

  -- An item with neither gate set behaves exactly as before: purchasable
  -- on coins alone (no live row currently has that combination, but the
  -- checks are written to allow for it rather than assume it).
  IF v_unlock_level IS NOT NULL AND COALESCE(v_level, 1) < v_unlock_level THEN
    RETURN jsonb_build_object('success', false, 'reason', 'level_locked', 'required_level', v_unlock_level, 'current_level', v_level);
  END IF;

  IF v_unlock_achievement_id IS NOT NULL AND NOT EXISTS (
    SELECT 1 FROM user_achievements
    WHERE user_id = v_caller AND achievement_id = v_unlock_achievement_id AND unlocked_at IS NOT NULL
  ) THEN
    RETURN jsonb_build_object('success', false, 'reason', 'achievement_locked', 'required_achievement', v_unlock_achievement_id);
  END IF;

  IF COALESCE(v_balance, 0) < v_cost THEN
    RETURN jsonb_build_object('success', false, 'reason', 'insufficient_funds', 'balance', v_balance, 'cost', v_cost);
  END IF;

  PERFORM award_coins(v_caller, -v_cost, 'shop_purchase', 'Purchased: ' || v_name, p_shop_item_id::text);

  INSERT INTO user_inventory (user_id, shop_item_id) VALUES (v_caller, p_shop_item_id);

  RETURN jsonb_build_object('success', true, 'new_balance', v_balance - v_cost);
END;
$function$;

REVOKE EXECUTE ON FUNCTION public.purchase_shop_item(uuid) FROM PUBLIC, anon;
GRANT  EXECUTE ON FUNCTION public.purchase_shop_item(uuid) TO authenticated;

-- coin_balance can never go negative. Only negative writer is award_coins(-cost) from purchase_shop_item,
-- which checks the balance first. VALIDATE only if no row violates.
ALTER TABLE public.user_profiles ADD CONSTRAINT user_profiles_coin_balance_nonneg CHECK (coin_balance >= 0) NOT VALID;
DO $$
DECLARE v_bad int;
BEGIN
  SELECT count(*) INTO v_bad FROM public.user_profiles WHERE coin_balance < 0;
  IF v_bad > 0 THEN
    RAISE EXCEPTION 'user_profiles has % rows with coin_balance < 0; not validating', v_bad;
  END IF;
END $$;
ALTER TABLE public.user_profiles VALIDATE CONSTRAINT user_profiles_coin_balance_nonneg;

-- rest_tokens_available: no client or server reader/writer. UPDATE is granted per column (no table-level UPDATE),
-- so a column REVOKE is effective. INSERT on the column is left as is.
REVOKE UPDATE (rest_tokens_available) ON public.user_profiles FROM authenticated;
DO $probe$
DECLARE
  r text[] := ARRAY[]::text[]; v boolean; n text; j jsonb; k int; b int;
  tt1 uuid := 'cf4946f5-f921-4e81-bbf4-88d574e8baf5'; mijo uuid := '6dfac56a-74a1-4a60-b7fa-e200338350f3';
  early uuid := '9eeca178-1353-406d-8671-54e59bdcf26d'; star uuid := '78594031-1074-46ed-b80b-a1cbcb7043b0';
BEGIN
-- Permission probes first, before any privileged call in this session.
PERFORM set_config('request.jwt.claims', json_build_object('sub', tt1, 'role', 'authenticated')::text, true); SET LOCAL ROLE authenticated;
n := 'no error'; BEGIN PERFORM public.check_in_coach_max_with_buddy(tt1); EXCEPTION WHEN OTHERS THEN n := SQLSTATE || ' ' || SQLERRM; END;
r := array_append(r, CASE WHEN n LIKE '42501 permission denied for function%' THEN 'PASS ' ELSE 'FAIL ' END || 'F1.1 authenticated check_in_coach_max_with_buddy -> ' || n);
n := 'no error'; BEGIN UPDATE public.user_profiles SET rest_tokens_available = rest_tokens_available WHERE id = tt1; EXCEPTION WHEN OTHERS THEN n := SQLSTATE || ' ' || SQLERRM; END;
r := array_append(r, CASE WHEN n LIKE '42501 permission denied%' THEN 'PASS ' ELSE 'FAIL ' END || 'F3.1 authenticated UPDATE rest_tokens_available -> ' || n);
n := 'no error'; BEGIN UPDATE public.user_profiles SET coin_balance = -1 WHERE id = tt1; EXCEPTION WHEN OTHERS THEN n := SQLSTATE || ' ' || SQLERRM; END;
r := array_append(r, CASE WHEN n LIKE '42501 permission denied%' THEN 'PASS ' ELSE 'FAIL ' END || 'F2.1 authenticated UPDATE coin_balance -> ' || n);
n := 'ok'; BEGIN UPDATE public.user_profiles SET avatar_id = avatar_id, avatar_border = avatar_border, updated_at = now(), display_name = display_name, looking_for_buddy = true WHERE id = tt1; GET DIAGNOSTICS k = ROW_COUNT; EXCEPTION WHEN OTHERS THEN n := SQLSTATE || ' ' || SQLERRM; k := -1; END;
r := array_append(r, CASE WHEN n = 'ok' AND k = 1 THEN 'PASS ' ELSE 'FAIL ' END || format('F3.2 authenticated UPDATE avatar_id/avatar_border/updated_at (avatar picker payload) + display_name/looking_for_buddy -> %s, rows %s', n, k));
RESET ROLE;
PERFORM set_config('request.jwt.claims', json_build_object('role', 'anon')::text, true); SET LOCAL ROLE anon;
n := 'no error'; BEGIN PERFORM public.check_in_coach_max_with_buddy(tt1); EXCEPTION WHEN OTHERS THEN n := SQLSTATE || ' ' || SQLERRM; END;
r := array_append(r, CASE WHEN n LIKE '42501 permission denied for function%' THEN 'PASS ' ELSE 'FAIL ' END || 'F1.2 anon check_in_coach_max_with_buddy -> ' || n);
RESET ROLE;
PERFORM set_config('request.jwt.claims', json_build_object('sub', mijo, 'role', 'authenticated')::text, true); SET LOCAL ROLE authenticated;
n := 'ok'; BEGIN j := public.check_in_coach_max(mijo); EXCEPTION WHEN OTHERS THEN n := SQLSTATE || ' ' || SQLERRM; END;
r := array_append(r, CASE WHEN n = 'ok' AND j IS NOT NULL THEN 'PASS ' ELSE 'FAIL ' END || 'F1.3 mijotest check_in_coach_max still callable -> ' || n || ' ' || coalesce(j::text, 'null'));
RESET ROLE; PERFORM set_config('request.jwt.claims', '', true);

-- Catalog checks
v := has_function_privilege('service_role', 'public.check_in_coach_max_with_buddy(uuid)', 'EXECUTE') AND has_function_privilege('postgres', 'public.check_in_coach_max_with_buddy(uuid)', 'EXECUTE')
     AND NOT has_function_privilege('authenticated', 'public.check_in_coach_max_with_buddy(uuid)', 'EXECUTE') AND NOT has_function_privilege('anon', 'public.check_in_coach_max_with_buddy(uuid)', 'EXECUTE');
r := array_append(r, CASE WHEN v THEN 'PASS ' ELSE 'FAIL ' END || 'F1.4 with_buddy: service_role+postgres EXECUTE kept, authenticated+anon none; function exists');
v := pg_get_functiondef('public.purchase_shop_item(uuid)'::regprocedure) LIKE '%PERFORM 1 FROM user_profiles WHERE id = v_caller FOR UPDATE;%';
r := array_append(r, CASE WHEN v THEN 'PASS ' ELSE 'FAIL ' END || 'F2.2 purchase_shop_item def contains FOR UPDATE lock');
SELECT proacl::text = '{postgres=X/postgres,authenticated=X/postgres,service_role=X/postgres}' AND proconfig = '{search_path=public}' AND prosecdef INTO v FROM pg_proc WHERE oid = 'public.purchase_shop_item(uuid)'::regprocedure;
r := array_append(r, CASE WHEN v THEN 'PASS ' ELSE 'FAIL ' END || 'F2.3 purchase_shop_item ACL, search_path, SECURITY DEFINER unchanged');
SELECT convalidated INTO v FROM pg_constraint WHERE conname = 'user_profiles_coin_balance_nonneg';
r := array_append(r, CASE WHEN v THEN 'PASS ' ELSE 'FAIL ' END || 'F2.4 user_profiles_coin_balance_nonneg validated');
v := NOT has_column_privilege('authenticated', 'public.user_profiles', 'rest_tokens_available', 'UPDATE') AND has_column_privilege('authenticated', 'public.user_profiles', 'rest_tokens_available', 'INSERT')
     AND has_column_privilege('authenticated', 'public.user_profiles', 'display_name', 'UPDATE');
r := array_append(r, CASE WHEN v THEN 'PASS ' ELSE 'FAIL ' END || 'F3.3 rest_tokens_available: UPDATE revoked, INSERT unchanged; display_name UPDATE kept');
SELECT count(*) INTO k FROM information_schema.column_privileges WHERE table_schema = 'public' AND table_name = 'user_profiles' AND grantee = 'authenticated' AND privilege_type = 'UPDATE';
r := array_append(r, CASE WHEN k = 21 THEN 'PASS ' ELSE 'FAIL ' END || 'F3.4 authenticated UPDATE columns (was 22, expect 21) -> ' || k);

-- Purchase probes. Fixture: testtest1 balance set directly (rolled back).
IF EXISTS (SELECT 1 FROM public.user_inventory WHERE user_id = tt1 AND shop_item_id IN (early, star)) THEN RAISE EXCEPTION 'fixture: testtest1 already owns a probe item'; END IF;
UPDATE public.user_profiles SET coin_balance = 99 WHERE id = tt1;
PERFORM set_config('request.jwt.claims', json_build_object('sub', tt1, 'role', 'authenticated')::text, true); SET LOCAL ROLE authenticated;
j := public.purchase_shop_item(early);
RESET ROLE;
SELECT coin_balance INTO b FROM public.user_profiles WHERE id = tt1;
v := j->>'reason' = 'insufficient_funds' AND b = 99 AND NOT EXISTS (SELECT 1 FROM public.user_inventory WHERE user_id = tt1 AND shop_item_id = early);
r := array_append(r, CASE WHEN v THEN 'PASS ' ELSE 'FAIL ' END || format('F2.5 99 coins, cost 100 -> %s, balance %s', j, b));
UPDATE public.user_profiles SET coin_balance = 100 WHERE id = tt1;
SET LOCAL ROLE authenticated;
j := public.purchase_shop_item(early);
RESET ROLE;
SELECT coin_balance INTO b FROM public.user_profiles WHERE id = tt1;
v := (j->>'success')::boolean AND b = 0 AND EXISTS (SELECT 1 FROM public.user_inventory WHERE user_id = tt1 AND shop_item_id = early)
     AND EXISTS (SELECT 1 FROM public.coin_transactions WHERE user_id = tt1 AND amount = -100 AND transaction_type = 'shop_purchase' AND reference_id = early::text);
r := array_append(r, CASE WHEN v THEN 'PASS ' ELSE 'FAIL ' END || format('F2.6 100 coins, cost 100 -> %s, balance %s, inventory + ledger rows written', j, b));
SET LOCAL ROLE authenticated;
j := public.purchase_shop_item(star);
RESET ROLE;
SELECT coin_balance INTO b FROM public.user_profiles WHERE id = tt1;
v := j->>'reason' = 'insufficient_funds' AND b = 0;
r := array_append(r, CASE WHEN v THEN 'PASS ' ELSE 'FAIL ' END || format('F2.7 immediate second purchase (cost 150) -> %s, balance %s', j, b));
SET LOCAL ROLE authenticated;
j := public.purchase_shop_item(early);
RESET ROLE;
r := array_append(r, CASE WHEN j->>'reason' = 'already_owned' THEN 'PASS ' ELSE 'FAIL ' END || 'F2.8 rebuy owned item -> ' || j);
n := 'no error'; BEGIN UPDATE public.user_profiles SET coin_balance = -1 WHERE id = tt1; EXCEPTION WHEN OTHERS THEN n := SQLSTATE || ' ' || SQLERRM; END;
r := array_append(r, CASE WHEN n LIKE '23514%user_profiles_coin_balance_nonneg%' THEN 'PASS ' ELSE 'FAIL ' END || 'F2.9 direct UPDATE coin_balance = -1 (postgres) -> ' || n);
PERFORM set_config('request.jwt.claims', '', true);

RAISE EXCEPTION E'PROBE_RESULTS\n%', array_to_string(r, E'\n');
END
$probe$;
ROLLBACK;
