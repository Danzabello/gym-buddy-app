-- 05b probes: one DO block ending in RAISE => fully rolled back. Applies 20261013010000_credit_sweep_05b inline, then checks.
-- PASS/FAIL lines are expectations. FINDING lines record NEEDS-DECISION behaviour (docs/hygiene/05b_sweep.md); no fix is expected.
-- Users: mijotest 6dfac56a (Coach Max streak 8bef7476), rokitest1 5e67f64d, testtest4 068f10c8, testtest1 cf4946f5. Bot and d557efec untouched.
DO $probe$
#variable_conflict use_column
DECLARE
  r text[] := ARRAY[]::text[]; v boolean; n text; j jsonb; x text; c1 text; c2 text; k int; k2 int;
  t4 uuid[] := ARRAY['05c20a6a-e239-47e2-93c0-347e6324e927','3847194a-24c5-48c4-a7b7-1858011bc730','a3ae42dc-8fb4-4c70-b4b5-2bcf5120f080','c06f57ea-0868-46b8-8887-489a008efe78']::uuid[];
  b_bt int; b_tm int; b_ts int; b_dtc int; b_se int; a_bt int; a_tm int; a_ts int; a_dtc int; a_se int;
  h_before text; h_after text; h_keep_before text; h_keep_after text;
  mijo uuid := '6dfac56a-74a1-4a60-b7fa-e200338350f3'; mijo_cm uuid := '8bef7476-85a3-43c1-aef5-0eb662151f7d';
  roki uuid := '5e67f64d-16e3-4b09-9b00-ddc49df8c3f6'; tt4 uuid := '068f10c8-3b6c-4a5d-8864-6f93c0149029'; tt1 uuid := 'cf4946f5-f921-4e81-bbf4-88d574e8baf5';
  cur_before int; cur_after int; coins_before int; coins_after int; today date;
BEGIN
RESET ROLE;
SELECT count(*) INTO b_bt FROM public.buddy_teams; SELECT count(*) INTO b_tm FROM public.team_members; SELECT count(*) INTO b_ts FROM public.team_streaks;
SELECT count(*) INTO b_dtc FROM public.daily_team_checkins; SELECT count(*) INTO b_se FROM public.streak_events;
-- economy tables the migration must not touch
h_before := (SELECT md5(string_agg(h, '|')) FROM (
  SELECT md5(coalesce(string_agg(d::text, '|' ORDER BY d.id), '')) h FROM public.workout_logs d
  UNION ALL SELECT md5(coalesce(string_agg(d::text, '|' ORDER BY d.id), '')) FROM public.xp_transactions d
  UNION ALL SELECT md5(coalesce(string_agg(d::text, '|' ORDER BY d.id), '')) FROM public.coin_transactions d
  UNION ALL SELECT md5(coalesce(string_agg(d.id||':'||d.xp||':'||d.coin_balance||':'||coalesce(d.level,0), '|' ORDER BY d.id), '')) FROM public.user_profiles d
  UNION ALL SELECT md5(coalesce(string_agg(d::text, '|' ORDER BY d.id), '')) FROM public.user_inventory d
  UNION ALL SELECT md5(coalesce(string_agg(d::text, '|' ORDER BY d.user_id, d.achievement_id), '')) FROM public.user_achievements d
  UNION ALL SELECT md5(coalesce(string_agg(to_jsonb(d)::text, '|' ORDER BY d.id), '')) FROM public.workouts d) z);
-- team tables outside the 4 teams (includes Coach Max teams and streak d557efec)
h_keep_before := (SELECT md5(string_agg(h, '|')) FROM (
  SELECT md5(coalesce(string_agg(d::text, '|' ORDER BY d.id), '')) h FROM public.buddy_teams d WHERE d.id <> ALL(t4)
  UNION ALL SELECT md5(coalesce(string_agg(d::text, '|' ORDER BY d.id), '')) FROM public.team_members d WHERE d.team_id <> ALL(t4)
  UNION ALL SELECT md5(coalesce(string_agg(d::text, '|' ORDER BY d.id), '')) FROM public.team_streaks d WHERE d.team_id <> ALL(t4)
  UNION ALL SELECT md5(coalesce(string_agg(d::text, '|' ORDER BY d.id), '')) FROM public.daily_team_checkins d WHERE d.team_streak_id NOT IN (SELECT id FROM public.team_streaks WHERE team_id = ANY(t4))
  UNION ALL SELECT md5(coalesce(string_agg(d::text, '|' ORDER BY d.id), '')) FROM public.streak_events d WHERE d.team_id <> ALL(t4)) z);

-- ===== migration 20261013010000_credit_sweep_05b =====
DROP FUNCTION public.checkin_team_for_user(uuid, uuid);
DO $$
DECLARE v_ids uuid[] := ARRAY['05c20a6a-e239-47e2-93c0-347e6324e927','3847194a-24c5-48c4-a7b7-1858011bc730','a3ae42dc-8fb4-4c70-b4b5-2bcf5120f080','c06f57ea-0868-46b8-8887-489a008efe78']::uuid[];
BEGIN
  IF EXISTS (SELECT 1 FROM team_members WHERE team_id = ANY(v_ids) AND user_id NOT IN ('07960b8c-300b-44cb-89dd-93f3f38099b8','2b61ae0f-655f-4111-b754-b18e00afe9d8','5e5c9752-7ff9-4b67-8800-915c2515d88b','64de5abb-df2e-4d87-b80a-4dc70742df86')) THEN
    RAISE EXCEPTION 'credit_sweep_05b: unexpected member in a team scheduled for deletion';
  END IF;
  IF EXISTS (SELECT 1 FROM buddy_teams WHERE id = ANY(v_ids) AND is_coach_max_team)
     OR EXISTS (SELECT 1 FROM team_streaks WHERE team_id = ANY(v_ids) AND id = 'd557efec-96c6-41af-b43a-8254cd098579') THEN
    RAISE EXCEPTION 'credit_sweep_05b: Coach Max team or protected streak scheduled for deletion';
  END IF;
  IF EXISTS (SELECT 1 FROM workout_logs WHERE team_id = ANY(v_ids)) THEN
    RAISE EXCEPTION 'credit_sweep_05b: workout_logs reference a team scheduled for deletion';
  END IF;
  DELETE FROM streak_events WHERE team_id = ANY(v_ids);
  DELETE FROM daily_team_checkins WHERE team_streak_id IN (SELECT id FROM team_streaks WHERE team_id = ANY(v_ids));
  DELETE FROM team_streaks WHERE team_id = ANY(v_ids);
  DELETE FROM team_members WHERE team_id = ANY(v_ids);
  DELETE FROM buddy_teams WHERE id = ANY(v_ids);
END
$$;
-- ===== end migration =====

-- Step 2
v := to_regprocedure('public.checkin_team_for_user(uuid,uuid)') IS NULL;
r := array_append(r, CASE WHEN v THEN 'PASS ' ELSE 'FAIL ' END || 'S2.1 checkin_team_for_user dropped');
v := NOT EXISTS (SELECT 1 FROM pg_proc WHERE prosrc ~ 'checkin_team_for_user') AND NOT EXISTS (SELECT 1 FROM cron.job WHERE command ~ 'checkin_team_for_user');
r := array_append(r, CASE WHEN v THEN 'PASS ' ELSE 'FAIL ' END || 'S2.2 no function body or cron job mentions it');
v := (SELECT array_agg(p.proname::text ORDER BY p.proname) FROM pg_proc p WHERE p.prosrc ~ '\m_server_checkin\s*\(' AND p.proname <> '_server_checkin') = ARRAY['_auto_credit','finish_checkin_session']
     AND (SELECT array_agg(p.proname::text ORDER BY p.proname) FROM pg_proc p WHERE p.prosrc ~ '\m_apply_checkin_rewards\s*\(' AND p.proname <> '_apply_checkin_rewards') = ARRAY['_server_checkin','award_checkin_rewards']
     AND NOT has_function_privilege('authenticated', 'public._auto_credit(uuid,timestamptz,integer,text,text)', 'EXECUTE')
     AND NOT has_function_privilege('authenticated', 'public.award_checkin_rewards(uuid,date)', 'EXECUTE')
     AND NOT has_function_privilege('authenticated', 'public.process_stale_sessions(timestamptz)', 'EXECUTE');
r := array_append(r, CASE WHEN v THEN 'PASS ' ELSE 'FAIL ' END || 'S2.3 reward paths: _server_checkin <- {_auto_credit, finish_checkin_session}; _apply_checkin_rewards <- {_server_checkin, award_checkin_rewards}; only finish_checkin_session is client-callable');

-- Step 4
SELECT count(*) INTO a_bt FROM public.buddy_teams; SELECT count(*) INTO a_tm FROM public.team_members; SELECT count(*) INTO a_ts FROM public.team_streaks;
SELECT count(*) INTO a_dtc FROM public.daily_team_checkins; SELECT count(*) INTO a_se FROM public.streak_events;
v := (b_bt - a_bt, b_tm - a_tm, b_ts - a_ts, b_dtc - a_dtc, b_se - a_se) = (4, 4, 4, 7, 1);
r := array_append(r, CASE WHEN v THEN 'PASS ' ELSE 'FAIL ' END || format('S4.1 deltas buddy_teams -%s team_members -%s team_streaks -%s daily_team_checkins -%s streak_events -%s (expect 4/4/4/7/1)', b_bt-a_bt, b_tm-a_tm, b_ts-a_ts, b_dtc-a_dtc, b_se-a_se));
h_keep_after := (SELECT md5(string_agg(h, '|')) FROM (
  SELECT md5(coalesce(string_agg(d::text, '|' ORDER BY d.id), '')) h FROM public.buddy_teams d WHERE d.id <> ALL(t4)
  UNION ALL SELECT md5(coalesce(string_agg(d::text, '|' ORDER BY d.id), '')) FROM public.team_members d WHERE d.team_id <> ALL(t4)
  UNION ALL SELECT md5(coalesce(string_agg(d::text, '|' ORDER BY d.id), '')) FROM public.team_streaks d WHERE d.team_id <> ALL(t4)
  UNION ALL SELECT md5(coalesce(string_agg(d::text, '|' ORDER BY d.id), '')) FROM public.daily_team_checkins d WHERE d.team_streak_id NOT IN (SELECT id FROM public.team_streaks WHERE team_id = ANY(t4))
  UNION ALL SELECT md5(coalesce(string_agg(d::text, '|' ORDER BY d.id), '')) FROM public.streak_events d WHERE d.team_id <> ALL(t4)) z);
r := array_append(r, CASE WHEN h_keep_after = h_keep_before THEN 'PASS ' ELSE 'FAIL ' END || 'S4.2 every team row outside the 4 teams unchanged (Coach Max teams, streak d557efec)');
v := EXISTS (SELECT 1 FROM public.team_streaks WHERE id = 'd557efec-96c6-41af-b43a-8254cd098579') AND EXISTS (SELECT 1 FROM public.user_profiles WHERE id = '00000000-0000-0000-0000-000000000001' AND is_bot);
r := array_append(r, CASE WHEN v THEN 'PASS ' ELSE 'FAIL ' END || 'S4.3 streak d557efec and the Coach Max bot still present');
v := (SELECT count(*) FROM auth.users WHERE id IN ('07960b8c-300b-44cb-89dd-93f3f38099b8','2b61ae0f-655f-4111-b754-b18e00afe9d8','5e5c9752-7ff9-4b67-8800-915c2515d88b','64de5abb-df2e-4d87-b80a-4dc70742df86')) = 4;
r := array_append(r, CASE WHEN v THEN 'PASS ' ELSE 'FAIL ' END || 'S4.4 the 4 member accounts are not deleted');
h_after := (SELECT md5(string_agg(h, '|')) FROM (
  SELECT md5(coalesce(string_agg(d::text, '|' ORDER BY d.id), '')) h FROM public.workout_logs d
  UNION ALL SELECT md5(coalesce(string_agg(d::text, '|' ORDER BY d.id), '')) FROM public.xp_transactions d
  UNION ALL SELECT md5(coalesce(string_agg(d::text, '|' ORDER BY d.id), '')) FROM public.coin_transactions d
  UNION ALL SELECT md5(coalesce(string_agg(d.id||':'||d.xp||':'||d.coin_balance||':'||coalesce(d.level,0), '|' ORDER BY d.id), '')) FROM public.user_profiles d
  UNION ALL SELECT md5(coalesce(string_agg(d::text, '|' ORDER BY d.id), '')) FROM public.user_inventory d
  UNION ALL SELECT md5(coalesce(string_agg(d::text, '|' ORDER BY d.user_id, d.achievement_id), '')) FROM public.user_achievements d
  UNION ALL SELECT md5(coalesce(string_agg(to_jsonb(d)::text, '|' ORDER BY d.id), '')) FROM public.workouts d) z);
r := array_append(r, CASE WHEN h_after = h_before THEN 'PASS ' ELSE 'FAIL ' END || 'S4.5 workout_logs, xp/coin transactions, profile xp/coins/level, inventory, achievements, workouts unchanged by the migration');

-- Step 3 grants
v := NOT EXISTS (SELECT 1 FROM pg_proc p WHERE p.pronamespace = 'public'::regnamespace AND has_function_privilege('anon', p.oid, 'EXECUTE')
                 AND p.proname IN ('accept_workout_invite','award_achievement_rewards','cancel_workout','cant_make_it','change_workout_time','check_in_coach_max','check_in_coach_max_with_buddy','complete_workout','create_buddy_team','create_invite_team','decline_workout_invite','ensure_coach_max_team','finish_checkin_session','go_solo','im_here','leave_workout','mark_notice_seen','nudge_workout','purchase_shop_item','recompute_team_streak','register_device_token','remove_friend','verify_achievement_progress'));
r := array_append(r, CASE WHEN v THEN 'PASS ' ELSE 'FAIL ' END || 'S3.1 no economy-writing function is executable by anon');
v := NOT EXISTS (SELECT 1 FROM pg_proc p WHERE p.pronamespace = 'public'::regnamespace AND has_function_privilege('authenticated', p.oid, 'EXECUTE')
                 AND p.proname IN ('award_xp','award_coins','_apply_checkin_rewards','_server_checkin','_auto_credit','award_checkin_rewards','_recompute_team_streak','_finish_coach_max_checkin','_record_streak_loss','process_stale_sessions','reconcile_stale_streaks'));
r := array_append(r, CASE WHEN v THEN 'PASS ' ELSE 'FAIL ' END || 'S3.2 credit helpers (award_xp, award_coins, _apply_checkin_rewards, _server_checkin, _auto_credit, ...) not executable by authenticated');

-- Authenticated probes. First calls of these functions in this session are as authenticated (no plan-cache carry-over).
today := (now() AT TIME ZONE public.safe_user_tz(mijo))::date;
SELECT current_streak INTO cur_before FROM public.team_streaks WHERE id = mijo_cm;
PERFORM set_config('request.jwt.claims', json_build_object('sub', mijo, 'role', 'authenticated')::text, true); SET LOCAL ROLE authenticated;
v := false; n := ''; BEGIN PERFORM public.checkin_team_for_user(roki, gen_random_uuid()); EXCEPTION WHEN OTHERS THEN n := SQLSTATE || ' ' || SQLERRM; v := SQLSTATE = '42883'; END;
r := array_append(r, CASE WHEN v THEN 'PASS ' ELSE 'FAIL ' END || 'S2.4 authenticated call to checkin_team_for_user -> undefined function [' || left(n, 70) || ']');
v := false; n := ''; BEGIN j := public.finish_checkin_session(NULL); v := j->>'result' = 'nothing_to_finish' AND (j->>'partner_checked_in')::int = 0; n := j->>'result'; EXCEPTION WHEN OTHERS THEN n := SQLERRM; END;
r := array_append(r, CASE WHEN v THEN 'PASS ' ELSE 'FAIL ' END || 'S2.5 finish_checkin_session with no session/workout credits nobody [' || coalesce(n,'') || ']');
-- F1 (A-3): direct daily_team_checkins INSERT + recompute_team_streak advances a Coach Max streak with no workout
n := ''; BEGIN
  INSERT INTO public.daily_team_checkins (team_streak_id, user_id) VALUES (mijo_cm, mijo);
  j := public.recompute_team_streak(mijo_cm, today);
EXCEPTION WHEN OTHERS THEN n := SQLERRM; END;
RESET ROLE; SELECT current_streak INTO cur_after FROM public.team_streaks WHERE id = mijo_cm;
r := array_append(r, 'FINDING F1 mijotest: INSERT daily_team_checkins (own Coach Max streak) + rpc recompute_team_streak, no session, no workout -> ' || coalesce(n, '') || coalesce(j::text, '') || format(' | current_streak %s -> %s', cur_before, cur_after));
-- F2: check_in_coach_max_with_buddy (no Dart caller) accepts that same self-inserted row
PERFORM set_config('request.jwt.claims', json_build_object('sub', mijo, 'role', 'authenticated')::text, true); SET LOCAL ROLE authenticated;
n := ''; j := NULL; BEGIN j := public.check_in_coach_max_with_buddy(mijo); EXCEPTION WHEN OTHERS THEN n := SQLERRM; END;
r := array_append(r, 'FINDING F2 mijotest: rpc check_in_coach_max_with_buddy after F1 -> ' || coalesce(n, '') || coalesce(left(j::text, 120), ''));
v := false; n := ''; BEGIN PERFORM public.check_in_coach_max_with_buddy(roki); EXCEPTION WHEN OTHERS THEN n := SQLERRM; v := n = 'forbidden'; END;
r := array_append(r, CASE WHEN v THEN 'PASS ' ELSE 'FAIL ' END || 'S3.3 check_in_coach_max_with_buddy for another user -> forbidden');
RESET ROLE; PERFORM set_config('request.jwt.claims', '', true);
-- F3: invitee bonus is per inviter and needs no activity. Fixture: invites backdated to just before rokitest1 signed up
-- (simulates a fresh account; accept_invite only takes invites < 7 days old, and test accounts are older).
SELECT coin_balance INTO coins_before FROM public.user_profiles WHERE id = roki;
PERFORM set_config('request.jwt.claims', json_build_object('sub', tt4, 'role', 'authenticated')::text, true); SET LOCAL ROLE authenticated;
c1 := public.create_invite(tt4);
RESET ROLE; PERFORM set_config('request.jwt.claims', json_build_object('sub', tt1, 'role', 'authenticated')::text, true); SET LOCAL ROLE authenticated;
c2 := public.create_invite(tt1);
RESET ROLE; PERFORM set_config('request.jwt.claims', json_build_object('sub', roki, 'role', 'authenticated')::text, true); SET LOCAL ROLE authenticated;
n := ''; BEGIN
  PERFORM public.accept_invite(c1); PERFORM public.accept_invite(c2);
EXCEPTION WHEN OTHERS THEN n := SQLERRM; END;
RESET ROLE;
UPDATE public.invites SET created_at = (SELECT created_at - interval '1 minute' FROM auth.users WHERE id = roki) WHERE code IN (c1, c2);
PERFORM set_config('request.jwt.claims', json_build_object('sub', roki, 'role', 'authenticated')::text, true); SET LOCAL ROLE authenticated;
BEGIN
  PERFORM public.create_invite_team(tt4, roki); PERFORM public.create_invite_team(tt1, roki);
  PERFORM public.create_invite_team(tt4, roki);
EXCEPTION WHEN OTHERS THEN n := n || SQLERRM; END;
RESET ROLE; PERFORM set_config('request.jwt.claims', '', true);
SELECT coin_balance INTO coins_after FROM public.user_profiles WHERE id = roki;
SELECT count(*) INTO k FROM public.coin_transactions WHERE user_id = roki AND transaction_type = 'invite_bonus' AND created_at >= now() - interval '1 minute';
r := array_append(r, 'FINDING F3 rokitest1: accept_invite x2 (testtest4, testtest1) + create_invite_team x3 -> ' || coalesce(nullif(n, ''), 'ok') || format(' | coins %s -> %s, invite_bonus rows %s (repeat call for same inviter paid nothing)', coins_before, coins_after, k));
v := NOT EXISTS (SELECT 1 FROM public.coin_transactions WHERE transaction_type = 'invite_reward' AND user_id IN (tt4, tt1) AND created_at >= now() - interval '1 minute');
r := array_append(r, CASE WHEN v THEN 'PASS ' ELSE 'FAIL ' END || 'S3.4 inviters are not paid at accept time (invite_reward needs 2 check-in days)');

RAISE EXCEPTION E'PROBE_RESULTS\n%', array_to_string(r, E'\n');
END
$probe$;
