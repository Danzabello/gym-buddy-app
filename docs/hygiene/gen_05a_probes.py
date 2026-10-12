# Builds docs/hygiene/05a_probes.sql: migration + probes inside ONE DO block that ends in RAISE EXCEPTION,
# so everything (including cron.schedule and every fixture) is rolled back. Results come back in the error text.
import re
V = "20261013000000"
R, M, T, N = ("5e67f64d-16e3-4b09-9b00-ddc49df8c3f6", "6dfac56a-74a1-4a60-b7fa-e200338350f3",
              "cf4946f5-f921-4e81-bbf4-88d574e8baf5", "6ef4e82e-a54d-4b91-8ce4-b5f179a65f66")
mig = open(f"supabase/migrations/{V}_hygiene_05a.sql").read()
mig = "\n".join(l for l in mig.splitlines() if not l.startswith("--"))
mig = mig.replace("SELECT cron.schedule(", "PERFORM cron.schedule(")
snap = open("docs/hygiene/economy_snapshot.sql").read().strip().rstrip(";")
SNAP = f"(SELECT string_agg(t||':'||n||':'||h, '|' ORDER BY t) FROM ({snap}) s)"
out = []
def raw(s): out.append(s)
def lit(s): return "'" + s.replace("'", "''") + "'"
def chk(label, expr):
    out.append(f"v := NULL; n := ''; BEGIN v := ({expr}); EXCEPTION WHEN OTHERS THEN v := false; n := SQLERRM; END;\n"
               f"r := array_append(r, CASE WHEN v IS TRUE THEN 'PASS ' ELSE 'FAIL ' END || {lit(label)} || CASE WHEN n <> '' THEN ' [' || n || ']' ELSE '' END);")
def err(label, stmt, must=None):
    cond = "true" if not must else f"n LIKE '%{must}%'"
    out.append(f"v := false; n := ''; BEGIN {stmt} EXCEPTION WHEN OTHERS THEN n := SQLERRM; v := ({cond}); END;\n"
               f"r := array_append(r, CASE WHEN v THEN 'PASS ' ELSE 'FAIL ' END || {lit(label)} || ' [' || CASE WHEN n='' THEN 'NOT rejected' ELSE left(n,80) END || ']');")
def q(label, stmt):
    """stmt is a full statement ending in 'INTO v' form; wrapped with error capture."""
    out.append(f"v := NULL; n := ''; BEGIN {stmt} EXCEPTION WHEN OTHERS THEN v := false; n := SQLERRM; END;\n"
               f"r := array_append(r, CASE WHEN v IS TRUE THEN 'PASS ' ELSE 'FAIL ' END || {lit(label)} || CASE WHEN n <> '' THEN ' [' || n || ']' ELSE '' END);")
def as_user(u): return f"PERFORM set_config('request.jwt.claims', '{{\"sub\":\"{u}\",\"role\":\"authenticated\"}}', true); SET LOCAL ROLE authenticated;"
RESET = "RESET ROLE; PERFORM set_config('request.jwt.claims', '', true);"

raw("DO $probe$\n#variable_conflict use_column\nDECLARE r text[] := ARRAY[]::text[]; v boolean; n text; h0 text; h1 text; team1 uuid; streak1 uuid; sess uuid; x text; c int; old0 int; old1 int; wid uuid; cmd text;\nBEGIN")
raw(f"h0 := {SNAP};")
raw("RESET ROLE;")
# Authenticated-first probes would be safest, but they need the migration applied; apply now, then fixtures.
raw(mig)
raw(f"h1 := {SNAP};")
raw(f"UPDATE public.user_profiles SET timezone='America/New_York' WHERE id='{R}';")
raw(f"UPDATE public.user_profiles SET timezone='Pacific/Auckland' WHERE id='{M}';")
raw(f"UPDATE public.user_profiles SET timezone='Asia/Tokyo' WHERE id='{T}';")
raw(f"INSERT INTO public.buddy_teams DEFAULT VALUES RETURNING id INTO team1;")
raw(f"INSERT INTO public.team_members(team_id,user_id) VALUES (team1,'{R}'),(team1,'{M}');")
raw(f"INSERT INTO public.team_streaks(team_id) VALUES (team1) RETURNING id INTO streak1;")

# ---- role-based behaviour first (clean authenticated-only calls) ----
raw(as_user(R))
chk("B1 authenticated reads own team_members (2 rows in fixture team)", "(SELECT count(*) FROM public.team_members WHERE team_id=team1)=2")
chk("A5 safe_user_tz self -> own tz", f"public.safe_user_tz('{R}')='America/New_York'")
chk("A5 safe_user_tz teammate -> teammate tz", f"public.safe_user_tz('{M}')='Pacific/Auckland'")
chk("A5 safe_user_tz stranger -> fallback Europe/Dublin (real tz is Asia/Tokyo)", f"public.safe_user_tz('{T}')='Europe/Dublin'")
chk("A5 caller is_on_break_today(self) runs", f"public.is_on_break_today('{R}') IS NOT NULL")
q("A5 caller _set_workout_planned_at: solo insert gets planned_at in own tz",
    f"WITH i AS (INSERT INTO public.workouts(user_id,workout_type,workout_date,workout_time) VALUES ('{R}','Strength',current_date+3,'10:00') RETURNING planned_at) SELECT planned_at = ((current_date+3 + time '10:00') AT TIME ZONE 'America/New_York') INTO v FROM i;")
q("A6 client insert with teammate buddy still works",
    f"WITH i AS (INSERT INTO public.workouts(user_id,workout_type,workout_date,workout_time,buddy_id,buddy_status) VALUES ('{R}','Cardio',current_date+4,'11:00','{M}','pending') RETURNING id) SELECT count(*)=1 INTO v FROM i;")
err("A6 self-buddy insert rejected", f"INSERT INTO public.workouts(user_id,workout_type,workout_date,workout_time,buddy_id,buddy_status) VALUES ('{R}','Cardio',current_date+5,'11:00','{R}','pending');", "workouts_buddy_not_self")
q("A5 caller _pin_client_checkin_date: check_in_date in own tz",
    f"WITH i AS (INSERT INTO public.daily_team_checkins(team_streak_id,user_id) VALUES (streak1,'{R}') RETURNING check_in_date) SELECT check_in_date = (now() AT TIME ZONE 'America/New_York')::date INTO v FROM i;")
q("A10 owner inserts own session", f"WITH i AS (INSERT INTO public.active_checkin_sessions(user_id,workout_type) VALUES ('{R}','Strength') RETURNING id) SELECT count(*)=1 INTO v FROM i;")
raw(f"SELECT id INTO sess FROM public.active_checkin_sessions WHERE user_id='{R}' ORDER BY created_at DESC LIMIT 1;")
q("A10 owner updates own session", "WITH u AS (UPDATE public.active_checkin_sessions SET workout_type='Cardio' WHERE id=sess RETURNING 1) SELECT count(*)=1 INTO v FROM u;")
err("A10 owner cannot hand session to someone else (WITH CHECK)", f"UPDATE public.active_checkin_sessions SET user_id='{M}' WHERE id=sess;")
chk("B6 get_my_profile() still returns own row", "(SELECT count(*)=1 FROM public.get_my_profile())")
chk("A2 authenticated can still execute get_level_for_xp / can_take_rest_day / get_random_team_name",
    f"public.get_level_for_xp(100) IS NOT NULL AND public.can_take_rest_day('{R}') IS NOT NULL AND (SELECT count(*)>=0 FROM public.get_random_team_name())")
raw(RESET)
raw(as_user(M))
q("A10 buddy cannot update partner's session (0 rows)", "WITH u AS (UPDATE public.active_checkin_sessions SET workout_type='HIIT' WHERE id=sess RETURNING 1) SELECT count(*)=0 INTO v FROM u;")
chk("A10 buddy cannot see partner's session", "(SELECT count(*)=0 FROM public.active_checkin_sessions WHERE id=sess)")
q("A10 buddy cannot delete partner's session (0 rows)", "WITH d AS (DELETE FROM public.active_checkin_sessions WHERE id=sess RETURNING 1) SELECT count(*)=0 INTO v FROM d;")
err("A10 buddy cannot insert a session as the partner", f"INSERT INTO public.active_checkin_sessions(user_id,workout_type) VALUES ('{R}','Strength');")
chk("A5 teammate-direction: M reads R's tz via teammate rule", f"public.safe_user_tz('{R}')='America/New_York'")
raw(RESET)
raw(as_user(R))
q("A10 owner deletes own session", "WITH d AS (DELETE FROM public.active_checkin_sessions WHERE id=sess RETURNING 1) SELECT count(*)=1 INTO v FROM d;")
chk("A2 authenticated cannot write achievements (privilege)", "NOT has_table_privilege('authenticated','public.achievements','INSERT')")
raw(RESET)
raw("SET LOCAL ROLE anon;")
raw("v := NULL; n := ''; BEGIN SELECT count(*) INTO c FROM public.team_members; v := (c=0); n := 'rows=' || c; EXCEPTION WHEN OTHERS THEN v := true; n := 'denied: ' || left(SQLERRM,60); END;")
raw("r := array_append(r, CASE WHEN v THEN 'PASS ' ELSE 'FAIL ' END || 'A3 anon reads no team_members rows (empty or denied)' || ' [' || n || ']');")
raw(RESET)
raw("SET LOCAL ROLE service_role; PERFORM set_config('request.jwt.claims','{\"role\":\"service_role\"}',true);")
chk("A5 service role (no uid) gets real tz of any user", f"public.safe_user_tz('{T}')='Asia/Tokyo'")
raw(RESET)
raw("RESET ROLE;")
chk("A5 postgres/cron context (no uid) gets real tz", f"public.safe_user_tz('{T}')='Asia/Tokyo'")

# ---- structural ----
chk("A1 no public function without pinned search_path", "(SELECT count(*)=0 FROM pg_proc p WHERE p.pronamespace='public'::regnamespace AND p.prokind='f' AND (p.proconfig IS NULL OR NOT EXISTS (SELECT 1 FROM unnest(p.proconfig) c WHERE c LIKE 'search_path=%')))")
chk("A2 anon holds only SELECT on public tables", "(SELECT count(*)=0 FROM pg_class c WHERE c.relnamespace='public'::regnamespace AND c.relkind IN ('r','p') AND (has_table_privilege('anon',c.oid,'REFERENCES') OR has_table_privilege('anon',c.oid,'TRIGGER') OR has_table_privilege('anon',c.oid,'INSERT') OR has_table_privilege('anon',c.oid,'UPDATE') OR has_table_privilege('anon',c.oid,'DELETE') OR has_table_privilege('anon',c.oid,'TRUNCATE') OR has_table_privilege('anon',c.oid,'MAINTAIN')))")
chk("A2 authenticated: no I/U/D (table or column level) on 6 read-only tables", "(SELECT count(*)=0 FROM unnest(ARRAY['achievements','shop_items','level_definitions','coin_transactions','cosmetic_unlock_conditions','team_names']) t WHERE has_any_column_privilege('authenticated','public.'||t,'INSERT') OR has_any_column_privilege('authenticated','public.'||t,'UPDATE') OR has_table_privilege('authenticated','public.'||t,'DELETE'))")
chk("A2 xp_transactions: no UPDATE/DELETE for authenticated, SELECT kept", "(NOT has_any_column_privilege('authenticated','public.xp_transactions','UPDATE') AND NOT has_table_privilege('authenticated','public.xp_transactions','DELETE') AND has_table_privilege('authenticated','public.xp_transactions','SELECT'))")
chk("A2 invite_reward_dead_letters: no privileges for authenticated or anon", "(SELECT count(*)=0 FROM unnest(ARRAY['authenticated','anon']) ro, unnest(ARRAY['SELECT','INSERT','UPDATE','DELETE','TRUNCATE','REFERENCES','TRIGGER']) p WHERE has_table_privilege(ro,'public.invite_reward_dead_letters',p) OR (p IN ('SELECT','INSERT','UPDATE','REFERENCES') AND has_any_column_privilege(ro,'public.invite_reward_dead_letters',p)))")
chk("DB-2/5/8 no DELETE for authenticated on daily_team_checkins, workout_templates, buddy_teams", "(SELECT count(*)=0 FROM unnest(ARRAY['daily_team_checkins','workout_templates','buddy_teams']) t WHERE has_table_privilege('authenticated','public.'||t,'DELETE'))")
chk("A2 no public function executable by anon or PUBLIC", "(SELECT count(*)=0 FROM pg_proc p WHERE p.pronamespace='public'::regnamespace AND has_function_privilege('anon',p.oid,'EXECUTE'))")
chk("A2 authenticated lost EXECUTE on _grant_achievement_shop_items, user_created_team, award_checkin_rewards; service_role keeps award_checkin_rewards",
    "(NOT has_function_privilege('authenticated','public._grant_achievement_shop_items()','EXECUTE') AND NOT has_function_privilege('authenticated','public.user_created_team(uuid)','EXECUTE') AND NOT has_function_privilege('authenticated','public.award_checkin_rewards(uuid,date)','EXECUTE') AND has_function_privilege('service_role','public.award_checkin_rewards(uuid,date)','EXECUTE'))")
q("A2 user_achievements insert still fires definer trigger _grant_achievement_shop_items", f"WITH a AS (SELECT id FROM public.achievements LIMIT 1), i AS (INSERT INTO public.user_achievements(user_id, achievement_id) SELECT '{R}', id FROM a RETURNING 1) SELECT count(*)=1 INTO v FROM i;")
chk("DB-5/8 policies gone: workout_templates INSERT/UPDATE, buddy_teams DELETE", "(SELECT count(*)=0 FROM pg_policies WHERE schemaname='public' AND ((tablename='workout_templates' AND cmd IN ('INSERT','UPDATE')) OR (tablename='buddy_teams' AND cmd='DELETE')))")
chk("A10 active_checkin_sessions: exactly 4 policies (one per command), UPDATE has WITH CHECK", "((SELECT count(*) FROM pg_policies WHERE schemaname='public' AND tablename='active_checkin_sessions')=4 AND (SELECT count(DISTINCT cmd) FROM pg_policies WHERE schemaname='public' AND tablename='active_checkin_sessions')=4 AND (SELECT with_check IS NOT NULL FROM pg_policies WHERE schemaname='public' AND tablename='active_checkin_sessions' AND cmd='UPDATE'))")
chk("A10 pin_client_session_start trigger untouched", "(SELECT count(*)=1 FROM pg_trigger WHERE tgname='pin_client_session_start' AND NOT tgisinternal)")
chk("A8 duplicate indexes dropped, unique guards remain", "((SELECT count(*) FROM pg_indexes WHERE indexname IN ('idx_daily_team_checkins_unique','unique_buddy_team'))=0 AND (SELECT count(*) FROM pg_constraint WHERE conname IN ('daily_team_checkins_team_streak_id_user_id_check_in_date_key','team_members_team_id_user_id_key') AND contype='u')=2)")
err("A8 duplicate team_members insert still rejected", f"INSERT INTO public.team_members(team_id,user_id) VALUES (team1,'{R}');", "duplicate key")
err("A8 duplicate daily_team_checkins insert still rejected", f"INSERT INTO public.daily_team_checkins(team_streak_id,user_id,check_in_date) SELECT team_streak_id,user_id,check_in_date FROM public.daily_team_checkins WHERE team_streak_id=streak1 LIMIT 1;", "duplicate key")
chk("A9 check_duplicate_team trigger and function gone", "((SELECT count(*) FROM pg_trigger WHERE tgname='prevent_duplicate_teams')=0 AND (SELECT count(*) FROM pg_proc WHERE proname='check_duplicate_team')=0)")
chk("A6 workouts_buddy_not_self exists and is validated", "(SELECT convalidated FROM pg_constraint WHERE conname='workouts_buddy_not_self')")
chk("A12 FKs to auth.users with ON DELETE CASCADE", "(SELECT count(*)=2 FROM pg_constraint WHERE conname IN ('invite_accept_attempts_user_id_fkey','invite_reward_dead_letters_inviter_id_fkey') AND confdeltype='c' AND confrelid='auth.users'::regclass)")
err("A12 orphan invite_accept_attempts insert rejected", "INSERT INTO public.invite_accept_attempts(user_id) VALUES (gen_random_uuid());", "foreign key")
raw("SELECT count(*) INTO old0 FROM cron.job_run_details WHERE end_time < now() - interval '7 days';")
raw("SELECT command INTO cmd FROM cron.job WHERE jobname='purge-cron-run-details';")
raw("EXECUTE cmd;")
raw("SELECT count(*) INTO old1 FROM cron.job_run_details WHERE end_time < now() - interval '7 days';")
raw("r := array_append(r, CASE WHEN old1=0 AND cmd IS NOT NULL THEN 'PASS ' ELSE 'FAIL ' END || 'A13 purge job scheduled; manual run: rows older than 7d before=' || old0 || ' after=' || old1);")
chk("A13 existing cron jobs untouched (6 old + 1 new)", "(SELECT count(*)=7 FROM cron.job) AND (SELECT count(*)=1 FROM cron.job WHERE jobname='workout-overtime-every-5min')")
raw("r := array_append(r, CASE WHEN h0 IS NOT DISTINCT FROM h1 THEN 'PASS ' ELSE 'FAIL ' END || 'economy tables identical before/after migration (7 table hashes)');")
raw("RAISE EXCEPTION E'PROBE_RESULTS\\n%', array_to_string(r, E'\\n');")
raw("END\n$probe$;")
open("docs/hygiene/05a_probes.sql", "w").write("-- 05a probes: ONE DO block, ends in RAISE EXCEPTION => everything rolled back. Run: supabase db query --linked -f docs/hygiene/05a_probes.sql\n-- Generated by gen_05a_probes.py from the migration file.\n" + "\n".join(out) + "\n")
