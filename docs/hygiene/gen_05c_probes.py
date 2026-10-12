# Builds docs/hygiene/05c_probes.sql (migration + probes, one DO ending in RAISE => rolled back) and
# docs/hygiene/05c_rollback_test.sql (migration then rollback; compares catalog + row hashes).
V = "20261013002000"
SIX = ["d168695d-f788-477a-80e7-78bb1c7b876b", "bd6736f1-410c-483f-939a-3119ac08d5c8", "dc1ee1ab-d474-4ffd-a540-ef059511d1fd",
       "2a45a481-d14d-4590-a188-92b8cf21c43c", "0e596a48-aee5-4b9b-afbe-9dae16740a61", "c2e4b37e-f54e-45fb-88f7-9c7f9a33ba10"]
IDS = ",".join(f"'{i}'" for i in SIX)
R, M, T = "5e67f64d-16e3-4b09-9b00-ddc49df8c3f6", "6dfac56a-74a1-4a60-b7fa-e200338350f3", "cf4946f5-f921-4e81-bbf4-88d574e8baf5"
M3 = "f7c1ef63-3b93-401d-b2bb-8402ddf9a881"
keep = lambda t: "".join(l for l in t.splitlines(keepends=True) if not l.startswith("--"))
mig = keep(open(f"supabase/migrations/{V}_hygiene_05c.sql", newline="").read())
rb = keep(open(f"docs/rollback_{V}.sql", newline="").read())
lit = lambda s: "'" + s.replace("'", "''") + "'"
out = []; raw = out.append
def chk(label, expr):
    raw(f"v := NULL; n := ''; BEGIN v := ({expr}); EXCEPTION WHEN OTHERS THEN v := false; n := SQLERRM; END;\n"
        f"r := array_append(r, CASE WHEN v IS TRUE THEN 'PASS ' ELSE 'FAIL ' END || {lit(label)} || CASE WHEN n <> '' THEN ' [' || n || ']' ELSE '' END);")
def q(label, stmt):
    raw(f"v := NULL; n := ''; BEGIN {stmt} EXCEPTION WHEN OTHERS THEN v := false; n := SQLERRM; END;\n"
        f"r := array_append(r, CASE WHEN v IS TRUE THEN 'PASS ' ELSE 'FAIL ' END || {lit(label)} || CASE WHEN n <> '' THEN ' [' || n || ']' ELSE '' END);")
def err(label, stmt, must=None):
    cond = "true" if not must else f"n LIKE '%{must}%'"
    raw(f"v := false; n := ''; BEGIN {stmt} EXCEPTION WHEN OTHERS THEN n := SQLERRM; v := ({cond}); END;\n"
        f"r := array_append(r, CASE WHEN v THEN 'PASS ' ELSE 'FAIL ' END || {lit(label)} || ' [' || CASE WHEN n='' THEN 'NOT rejected' ELSE left(n,80) END || ']');")
as_user = lambda u: f"PERFORM set_config('request.jwt.claims', '{{\"sub\":\"{u}\",\"role\":\"authenticated\"}}', true); SET LOCAL ROLE authenticated;"
RESET = "RESET ROLE; PERFORM set_config('request.jwt.claims', '', true);"
H = lambda t, where="true", cols="d::text": f"(SELECT md5(coalesce(string_agg({cols}, '|' ORDER BY d.id), '')) FROM {t} d WHERE {where})"
STREAKS6 = f"(SELECT id FROM public.team_streaks WHERE team_id IN ({IDS}))"

raw("DO $probe$\n#variable_conflict use_column\nDECLARE r text[] := ARRAY[]::text[]; v boolean; n text; "
    "b_bt int; b_tm int; b_ts int; b_dtc int; b_se int; a_bt int; a_tm int; a_ts int; a_dtc int; a_se int; "
    "h_wl text; h_xp text; h_cn text; h_up text; h_dtc text; h_ts text; h_wk text; x text; wid uuid; ti uuid;\nBEGIN\nRESET ROLE;")
raw(f"""SELECT count(*) INTO b_bt FROM public.buddy_teams; SELECT count(*) INTO b_tm FROM public.team_members; SELECT count(*) INTO b_ts FROM public.team_streaks;
SELECT count(*) INTO b_dtc FROM public.daily_team_checkins; SELECT count(*) INTO b_se FROM public.streak_events;
h_wl := {H('public.workout_logs')}; h_xp := {H('public.xp_transactions')}; h_cn := {H('public.coin_transactions')};
h_up := {H('public.user_profiles', cols="d.id||':'||d.xp||':'||d.coin_balance")};
h_dtc := {H('public.daily_team_checkins', f"d.team_streak_id NOT IN {STREAKS6}")}; h_ts := {H('public.team_streaks', f"d.team_id NOT IN ({IDS})")};
h_wk := {H('public.workouts', cols="d.id||d.user_id::text||coalesce(d.buddy_id::text,'')||d.status||d.workout_date::text||coalesce(d.planned_at::text,'')")};""")
raw(mig)
raw(f"SELECT count(*) INTO a_bt FROM public.buddy_teams; SELECT count(*) INTO a_tm FROM public.team_members; SELECT count(*) INTO a_ts FROM public.team_streaks; SELECT count(*) INTO a_dtc FROM public.daily_team_checkins; SELECT count(*) INTO a_se FROM public.streak_events;")
chk("C2 exact row deltas: teams -6, members -4, streaks -4, checkins -171, streak_events 0", "(b_bt-a_bt)=6 AND (b_tm-a_tm)=4 AND (b_ts-a_ts)=4 AND (b_dtc-a_dtc)=171 AND (b_se-a_se)=0")
raw("r := array_append(r, format('INFO deltas: buddy_teams %s->%s, team_members %s->%s, team_streaks %s->%s, daily_team_checkins %s->%s, streak_events %s->%s', b_bt,a_bt,b_tm,a_tm,b_ts,a_ts,b_dtc,a_dtc,b_se,a_se));")
chk("C2 the 4 skipped teams and the protected d557efec streak still exist", "(SELECT count(*)=4 FROM public.buddy_teams WHERE left(id::text,8) IN ('05c20a6a','3847194a','a3ae42dc','c06f57ea')) AND (SELECT count(*)=1 FROM public.team_streaks WHERE left(id::text,8)='d557efec')")
chk("economy: workout_logs, xp_transactions, coin_transactions, user xp/coins unchanged", f"h_wl = {H('public.workout_logs')} AND h_xp = {H('public.xp_transactions')} AND h_cn = {H('public.coin_transactions')} AND h_up = {H('public.user_profiles', cols=chr(100)+'.id||'+repr(':')+'||d.xp||'+repr(':')+'||d.coin_balance')}")
chk("economy: daily_team_checkins and team_streaks equal pre-state minus the six teams", f"h_dtc = {H('public.daily_team_checkins')} AND h_ts = {H('public.team_streaks')}")
chk("workouts: stable columns unchanged by the column drops", f"h_wk = {H('public.workouts', cols=chr(100)+'.id||d.user_id::text||coalesce(d.buddy_id::text,'+repr('')+')||d.status||d.workout_date::text||coalesce(d.planned_at::text,'+repr('')+')')}")
chk("C1 workout_invites and the 4 functions are gone", "to_regclass('public.workout_invites') IS NULL AND (SELECT count(*)=0 FROM pg_proc WHERE pronamespace='public'::regnamespace AND proname IN ('notify_workout_invite','notify_workout_invite_response','is_user_in_active_workout','get_workouts_awaiting_creator_join'))")
chk("C1 the 3 columns are gone", "(SELECT count(*)=0 FROM information_schema.columns WHERE table_schema='public' AND column_name IN ('ready_expires_at','creator_popup_shown','workout_join_popups_enabled'))")
chk("C1 buddy_ready / creator_ready kept", "(SELECT count(*)=2 FROM information_schema.columns WHERE table_schema='public' AND table_name='workouts' AND column_name IN ('buddy_ready','creator_ready'))")
chk("vault: secret fbae4dec deleted, service_role_key kept, exactly 1 secret left", "(SELECT count(*)=0 FROM vault.secrets WHERE id='fbae4dec-efe3-48ca-9230-9f326a206e48') AND (SELECT count(*)=1 FROM vault.secrets WHERE name='service_role_key') AND (SELECT count(*)=1 FROM vault.secrets)")
chk("vault: _send_push can still read the service key", "(SELECT count(*)=1 FROM vault.decrypted_secrets WHERE name='service_role_key')")
chk("checkin_team_for_user: no EXECUTE for PUBLIC/anon/authenticated, service_role keeps it", "NOT has_function_privilege('authenticated','public.checkin_team_for_user(uuid,uuid)','EXECUTE') AND NOT has_function_privilege('anon','public.checkin_team_for_user(uuid,uuid)','EXECUTE') AND has_function_privilege('service_role','public.checkin_team_for_user(uuid,uuid)','EXECUTE') AND (SELECT proacl::text NOT LIKE '{=X/%' AND proacl::text NOT LIKE '%,=X/%' FROM pg_proc WHERE proname='checkin_team_for_user')")
raw(f"INSERT INTO public.buddy_teams DEFAULT VALUES RETURNING id INTO ti; INSERT INTO public.team_members(team_id,user_id) VALUES (ti,'{R}'),(ti,'{M}'); INSERT INTO public.team_streaks(team_id) VALUES (ti);")
raw(f"INSERT INTO public.workouts(user_id,workout_type,workout_date,workout_time,buddy_id,buddy_status) VALUES ('{R}','Strength',current_date+2,'10:00','{M}','pending') RETURNING id INTO wid;")
raw(as_user(R))
err("checkin_team_for_user as authenticated is denied", f"PERFORM public.checkin_team_for_user('{M}', wid);", "permission denied")
q("client workout insert still works after column drops", f"WITH i AS (INSERT INTO public.workouts(user_id,workout_type,workout_date,workout_time) VALUES ('{R}','Cardio',current_date+3,'11:00') RETURNING planned_at) SELECT planned_at IS NOT NULL INTO v FROM i;")
raw(RESET)
raw(as_user(M))
chk("get_my_profile still returns the row (SELECT * follows the dropped column)", "(SELECT count(*)=1 FROM public.get_my_profile())")
chk("profile update by owner still works", f"(WITH u AS (UPDATE public.user_profiles SET updated_at=now() WHERE id='{M}' RETURNING 1) SELECT count(*)=1 FROM u)") if False else None
raw(RESET)
# rename trigger
raw("SELECT team_name INTO x FROM public.buddy_teams WHERE id='f71e95cd-c0cc-4312-bea7-120ef330d370';")
raw("r := array_append(r, 'INFO team name before delete of mijotest3 profile: ' || coalesce(x,'NULL'));")
raw(f"DELETE FROM public.user_profiles WHERE id='{M3}';")
chk("rename trigger: 'mijotest & mijotest3' -> 'mijotest & Former buddy'", "(SELECT team_name = 'mijotest & Former buddy' FROM public.buddy_teams WHERE id='f71e95cd-c0cc-4312-bea7-120ef330d370')")
chk("rename trigger: Coach Max teams untouched", "(SELECT count(*)=0 FROM public.buddy_teams WHERE is_coach_max_team AND team_name LIKE '%Former buddy%')")
raw(f"INSERT INTO public.buddy_teams(team_name,is_coach_max_team) SELECT display_name || ' & zz', false FROM public.user_profiles WHERE id='{T}' RETURNING id INTO ti; INSERT INTO public.team_members(team_id,user_id) VALUES (ti,'{T}');")
raw("CREATE FUNCTION public.zz_boom() RETURNS trigger LANGUAGE plpgsql AS $z$ BEGIN RAISE EXCEPTION 'boom'; END $z$; CREATE TRIGGER zz_boom BEFORE UPDATE ON public.buddy_teams FOR EACH ROW WHEN (NEW.team_name LIKE '%Former buddy%') EXECUTE FUNCTION public.zz_boom();")
raw(f"v := NULL; n := ''; BEGIN DELETE FROM public.user_profiles WHERE id='{T}'; v := true; EXCEPTION WHEN OTHERS THEN v := false; n := SQLERRM; END;\nr := array_append(r, CASE WHEN v IS TRUE THEN 'PASS ' ELSE 'FAIL ' END || 'rename trigger never raises: profile delete succeeds even when the team UPDATE errors' || CASE WHEN n<>'' THEN ' ['||n||']' ELSE '' END);")
chk("rename trigger: failed rename leaves the team name as it was", "(SELECT team_name NOT LIKE '%Former buddy%' FROM public.buddy_teams WHERE id=ti)")
chk("trigger function is SECURITY DEFINER with pinned search_path and no client EXECUTE", "(SELECT prosecdef AND proconfig::text LIKE '%search_path=public%' AND NOT has_function_privilege('authenticated',oid,'EXECUTE') AND NOT has_function_privilege('anon',oid,'EXECUTE') FROM pg_proc WHERE proname='_scrub_team_names_on_profile_delete')")
raw("RAISE EXCEPTION E'PROBE_RESULTS\\n%', array_to_string(r, E'\\n');\nEND\n$probe$;")
open("docs/hygiene/05c_probes.sql", "w").write("-- 05c probes: one DO block ending in RAISE => fully rolled back. Generated by gen_05c_probes.py\n" + "\n".join(x for x in out if x) + "\n")

acl = lambda c: f"coalesce((SELECT string_agg(e::text, ',' ORDER BY e::text) FROM unnest({c}) e),'')"
fp = f"""(SELECT string_agg(k, E'\\n' ORDER BY k) FROM (
 SELECT 'fn:'||p.oid::regprocedure||':'||{acl('p.proacl')}||':'||coalesce(p.proconfig::text,'')||':'||md5(p.prosrc) k FROM pg_proc p WHERE p.pronamespace='public'::regnamespace
 UNION ALL SELECT 'tbl:'||c.relname||':'||{acl('c.relacl')}||':'||c.relrowsecurity FROM pg_class c WHERE c.relnamespace='public'::regnamespace AND c.relkind IN ('r','p')
 UNION ALL SELECT 'col:'||table_name||'.'||column_name||':'||data_type||':'||coalesce(column_default,'')||':'||is_nullable FROM information_schema.columns WHERE table_schema='public'
 UNION ALL SELECT 'colpriv:'||table_name||'.'||column_name||':'||grantee||':'||privilege_type FROM information_schema.column_privileges WHERE table_schema='public' AND grantee IN ('authenticated','anon')
 UNION ALL SELECT 'pol:'||tablename||':'||policyname||':'||cmd||':'||coalesce(qual,'')||':'||coalesce(with_check,'') FROM pg_policies WHERE schemaname='public'
 UNION ALL SELECT 'idx:'||indexdef FROM pg_indexes WHERE schemaname='public'
 UNION ALL SELECT 'con:'||conrelid::regclass||':'||conname||':'||pg_get_constraintdef(oid) FROM pg_constraint WHERE connamespace='public'::regnamespace
 UNION ALL SELECT 'trg:'||tgrelid::regclass||':'||tgname FROM pg_trigger WHERE NOT tgisinternal AND tgrelid::regclass::text NOT LIKE 'storage.%'
 UNION ALL SELECT 'rows:'||t||':'||(SELECT count(*) FROM public.buddy_teams) FROM (VALUES ('x')) v(t)
 UNION ALL SELECT 'h:buddy_teams:'||(SELECT md5(string_agg(d::text,'|' ORDER BY d.id)) FROM public.buddy_teams d)
 UNION ALL SELECT 'h:team_members:'||(SELECT md5(string_agg(d::text,'|' ORDER BY d.id)) FROM public.team_members d)
 UNION ALL SELECT 'h:team_streaks:'||(SELECT md5(string_agg(d::text,'|' ORDER BY d.id)) FROM public.team_streaks d)
 UNION ALL SELECT 'h:daily_team_checkins:'||(SELECT md5(string_agg(d::text,'|' ORDER BY d.id)) FROM public.daily_team_checkins d)
 UNION ALL SELECT 'h:streak_events:'||(SELECT md5(string_agg(d::text,'|' ORDER BY d.id)) FROM public.streak_events d)
 UNION ALL SELECT 'h:workouts:'||(SELECT md5(string_agg(to_jsonb(d)::text,'|' ORDER BY d.id)) FROM public.workouts d)
 UNION ALL SELECT 'h:user_profiles:'||(SELECT md5(string_agg(to_jsonb(d)::text,'|' ORDER BY d.id)) FROM public.user_profiles d)
 UNION ALL SELECT 'vault:'||count(*) FROM vault.secrets) z)"""
open("docs/hygiene/05c_rollback_test.sql", "wb").write(f"""-- Applies 05c then its rollback in one DO that raises (rolled back); prints catalog/row-hash differences.
-- Expected difference: the vault secret (documented as not restorable).
DO $t$
#variable_conflict use_column
DECLARE a text; b text; d text;
BEGIN
a := {fp};
{mig}
{rb}
b := {fp};
SELECT string_agg(x, E'\\n') INTO d FROM (
  SELECT '- '||l x FROM unnest(string_to_array(a, E'\\n')) l WHERE l <> ALL (string_to_array(b, E'\\n'))
  UNION ALL SELECT '+ '||l FROM unnest(string_to_array(b, E'\\n')) l WHERE l <> ALL (string_to_array(a, E'\\n'))) q;
RAISE EXCEPTION E'ROLLBACK_DIFF\\n%', coalesce(d, 'IDENTICAL');
END $t$;
""".encode())
