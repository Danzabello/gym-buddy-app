# Builds docs/hygiene/05a2_probes.sql (one DO block ending in RAISE EXCEPTION => fully rolled back)
# and docs/hygiene/05a2_rollback_test.sql (migration then rollback, prints catalog diff).
V = "20261013001000"
R, M, T, N = ("5e67f64d-16e3-4b09-9b00-ddc49df8c3f6", "6dfac56a-74a1-4a60-b7fa-e200338350f3",
              "cf4946f5-f921-4e81-bbf4-88d574e8baf5", "6ef4e82e-a54d-4b91-8ce4-b5f179a65f66")
keep = lambda t: "".join(l for l in t.splitlines(keepends=True) if not l.startswith("--"))
mig = keep(open(f"supabase/migrations/{V}_hygiene_05a2.sql").read())
rb = keep(open(f"docs/rollback_{V}.sql").read())
snap = open("docs/hygiene/economy_snapshot.sql").read().strip().rstrip(";")
SNAP = f"(SELECT string_agg(t||':'||n||':'||h, '|' ORDER BY t) FROM ({snap}) s)"
out = []
raw = out.append
lit = lambda s: "'" + s.replace("'", "''") + "'"
def chk(label, expr):
    raw(f"v := NULL; n := ''; BEGIN v := ({expr}); EXCEPTION WHEN OTHERS THEN v := false; n := SQLERRM; END;\n"
        f"r := array_append(r, CASE WHEN v IS TRUE THEN 'PASS ' ELSE 'FAIL ' END || {lit(label)} || CASE WHEN n <> '' THEN ' [' || n || ']' ELSE '' END);")
def q(label, stmt):
    raw(f"v := NULL; n := ''; BEGIN {stmt} EXCEPTION WHEN OTHERS THEN v := false; n := SQLERRM; END;\n"
        f"r := array_append(r, CASE WHEN v IS TRUE THEN 'PASS ' ELSE 'FAIL ' END || {lit(label)} || CASE WHEN n <> '' THEN ' [' || n || ']' ELSE '' END);")
as_user = lambda u: f"PERFORM set_config('request.jwt.claims', '{{\"sub\":\"{u}\",\"role\":\"authenticated\"}}', true); SET LOCAL ROLE authenticated;"
RESET = "RESET ROLE; PERFORM set_config('request.jwt.claims', '', true);"

raw("DO $probe$\n#variable_conflict use_column\nDECLARE r text[] := ARRAY[]::text[]; v boolean; n text; h0 text; h1 text; team1 uuid; c int;\nBEGIN")
raw(f"h0 := {SNAP};\nRESET ROLE;")
raw(mig)
raw(f"h1 := {SNAP};")
raw(f"UPDATE public.user_profiles SET timezone='America/New_York' WHERE id='{R}';")
raw(f"UPDATE public.user_profiles SET timezone='Pacific/Auckland' WHERE id='{M}';")
raw(f"UPDATE public.user_profiles SET timezone='Asia/Tokyo' WHERE id='{T}';")
raw(f"UPDATE public.user_profiles SET timezone='Australia/Perth' WHERE id='{N}';")
raw("INSERT INTO public.buddy_teams DEFAULT VALUES RETURNING id INTO team1;")
raw(f"INSERT INTO public.team_members(team_id,user_id) VALUES (team1,'{R}'),(team1,'{M}');")
raw(f"INSERT INTO public.friendships(user_id,friend_id,status) VALUES ('{R}','{T}','accepted');")
raw(f"INSERT INTO public.friendships(user_id,friend_id,status) VALUES ('{N}','{R}','pending');")
raw(as_user(R))
chk("A5b self", f"public.safe_user_tz('{R}')='America/New_York'")
chk("A5b teammate", f"public.safe_user_tz('{M}')='Pacific/Auckland'")
chk("A5b accepted friend (caller is user_id side)", f"public.safe_user_tz('{T}')='Asia/Tokyo'")
chk("A5b pending friend -> fallback", f"public.safe_user_tz('{N}')='Europe/Dublin'")
raw(RESET)
raw(as_user(T))
chk("A5b accepted friend (caller is friend_id side)", f"public.safe_user_tz('{R}')='America/New_York'")
chk("A5b stranger -> fallback", f"public.safe_user_tz('{M}')='Europe/Dublin'")
raw(RESET)
raw(as_user(R))
q("trigger _enforce_workout_daily_cap still fires: client workout insert works",
  f"WITH i AS (INSERT INTO public.workouts(user_id,workout_type,workout_date,workout_time) VALUES ('{R}','Strength',current_date+3,'10:00') RETURNING planned_at) SELECT planned_at IS NOT NULL INTO v FROM i;")
q("trigger notify_workout_invite still fires: workout_invites insert works",
  f"WITH i AS (INSERT INTO public.workout_invites(sender_id,recipient_id,scheduled_for) VALUES ('{R}','{M}',now()+interval '1 day') RETURNING 1) SELECT count(*)=1 INTO v FROM i;")
chk("B1 authenticated reads own team_members", "(SELECT count(*)=2 FROM public.team_members WHERE team_id=team1)")
chk("B6 get_my_profile", "(SELECT count(*)=1 FROM public.get_my_profile())")
raw(RESET)
chk("authenticated has no REFERENCES/TRIGGER/MAINTAIN on any public table", "(SELECT count(*)=0 FROM pg_class c WHERE c.relnamespace='public'::regnamespace AND c.relkind IN ('r','p') AND (has_table_privilege('authenticated',c.oid,'REFERENCES') OR has_table_privilege('authenticated',c.oid,'TRIGGER') OR has_table_privilege('authenticated',c.oid,'MAINTAIN')))")
chk("authenticated still has SELECT on app tables", "has_table_privilege('authenticated','public.workouts','SELECT') AND has_table_privilege('authenticated','public.team_members','SELECT')")
raw("CREATE TABLE public.zz_probe_default_acl (id int);")
chk("default privileges: new table gets no REFERENCES/TRIGGER/MAINTAIN for authenticated or anon", "(NOT has_table_privilege('authenticated','public.zz_probe_default_acl','REFERENCES') AND NOT has_table_privilege('authenticated','public.zz_probe_default_acl','TRIGGER') AND NOT has_table_privilege('authenticated','public.zz_probe_default_acl','MAINTAIN') AND NOT has_table_privilege('anon','public.zz_probe_default_acl','REFERENCES') AND NOT has_table_privilege('anon','public.zz_probe_default_acl','MAINTAIN'))")
chk("EXECUTE gone for authenticated on the 3 trigger functions", "NOT has_function_privilege('authenticated','public._enforce_workout_daily_cap()','EXECUTE') AND NOT has_function_privilege('authenticated','public.notify_workout_invite()','EXECUTE') AND NOT has_function_privilege('authenticated','public.notify_workout_invite_response()','EXECUTE')")
chk("service role / postgres no-uid still gets any tz", f"public.safe_user_tz('{T}')='Asia/Tokyo'")
chk("economy tables identical before/after migration", "h0 IS NOT DISTINCT FROM h1")
raw("RAISE EXCEPTION E'PROBE_RESULTS\\n%', array_to_string(r, E'\\n');\nEND\n$probe$;")
open("docs/hygiene/05a2_probes.sql", "w").write("-- 05a2 probes (rolled back). Generated by gen_05a2_probes.py\n" + "\n".join(out) + "\n")

acl = lambda c: f"coalesce((SELECT string_agg(e::text, ',' ORDER BY e::text) FROM unnest({c}) e),'')"
fp = f"""(SELECT string_agg(k, E'\\n' ORDER BY k) FROM (
 SELECT 'fn:'||p.oid::regprocedure||':'||{acl('p.proacl')}||':'||coalesce(p.proconfig::text,'')||':'||md5(p.prosrc) k FROM pg_proc p WHERE p.pronamespace='public'::regnamespace
 UNION ALL SELECT 'tbl:'||c.relname||':'||{acl('c.relacl')} FROM pg_class c WHERE c.relnamespace='public'::regnamespace AND c.relkind IN ('r','p')
 UNION ALL SELECT 'dacl:'||defaclrole::regrole||':'||defaclobjtype::text||':'||{acl('defaclacl')} FROM pg_default_acl WHERE defaclnamespace='public'::regnamespace) z)"""
open("docs/hygiene/05a2_rollback_test.sql", "w").write(f"""-- Applies 05a2 then its rollback in one DO that raises (rolled back); prints catalog differences.
DO $t$
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
""")
