# Phase C backup. Reads LIVE through the CLI (read-only) and writes restore scripts into docs/hygiene/05c_backup/.
import json, subprocess, os
OUT = "docs/hygiene/05c_backup"
TEAMS = "'d168695d','3847194a','a3ae42dc','c06f57ea','05c20a6a','bd6736f1','dc1ee1ab','2a45a481','0e596a48','c2e4b37e'"
def q(sql):
    p = subprocess.run(["supabase", "db", "query", "--linked", sql], capture_output=True, text=True)
    t = "\n".join(l for l in (p.stdout + p.stderr).splitlines() if not l.startswith(("Initialising", "A new version", "We recommend")))
    j = json.loads(t)
    return j["rows"]
def one(sql): return list(q(sql)[0].values())[0]
def rows_restore(table, where, order="1"):
    data = one(f"select coalesce(jsonb_agg(to_jsonb(t)), '[]'::jsonb)::text from (select * from {table} where {where}) t")
    n = len(json.loads(data)) if isinstance(data, str) else len(data)
    data = data if isinstance(data, str) else json.dumps(data)
    return n, f"-- {table}: {n} rows\nINSERT INTO {table} SELECT * FROM jsonb_populate_recordset(null::{table}, $j${data}$j$::jsonb);\n"
tl = f"left(id::text,8) in ({TEAMS})"
ts = f"team_id in (select id from public.buddy_teams where {tl})"

# 1 workout_invites
cols = q("select a.attname, format_type(a.atttypid,a.atttypmod) typ, a.attnotnull nn, pg_get_expr(d.adbin,d.adrelid) def from pg_attribute a left join pg_attrdef d on d.adrelid=a.attrelid and d.adnum=a.attnum where a.attrelid='public.workout_invites'::regclass and a.attnum>0 and not a.attisdropped order by a.attnum")
ddl = "CREATE TABLE public.workout_invites (\n" + ",\n".join(f"  {c['attname']} {c['typ']}" + (f" DEFAULT {c['def']}" if c['def'] else "") + (" NOT NULL" if c['nn'] else "") for c in cols) + ",\n  CONSTRAINT workout_invites_pkey PRIMARY KEY (id)"
for c in q("select conname, pg_get_constraintdef(oid) d from pg_constraint where conrelid='public.workout_invites'::regclass and contype<>'p' order by conname"):
    ddl += f",\n  CONSTRAINT {c['conname']} {c['d']}"
ddl += "\n);\n"
for i in q("select indexdef from pg_indexes where tablename='workout_invites' and indexname<>'workout_invites_pkey'"): ddl += i["indexdef"] + ";\n"
ddl += "ALTER TABLE public.workout_invites ENABLE ROW LEVEL SECURITY;\n"
for p in q("select policyname, cmd, permissive, roles::text, qual, with_check from pg_policies where tablename='workout_invites'"):
    ddl += f"CREATE POLICY \"{p['policyname']}\" ON public.workout_invites FOR {p['cmd']}" + (f" USING ({p['qual']})" if p['qual'] else "") + (f" WITH CHECK ({p['with_check']})" if p['with_check'] else "") + ";\n"
for t in q("select pg_get_triggerdef(oid) d from pg_trigger where tgrelid='public.workout_invites'::regclass and not tgisinternal"): ddl += t["d"] + ";\n"
ddl += "REVOKE ALL ON public.workout_invites FROM PUBLIC, anon, authenticated, service_role;\nGRANT SELECT ON public.workout_invites TO anon;\nGRANT DELETE, INSERT, SELECT, UPDATE ON public.workout_invites TO authenticated;\nGRANT ALL ON public.workout_invites TO service_role;\n"
n_inv, data = rows_restore("public.workout_invites", "true")
open(f"{OUT}/01_workout_invites.sql", "w", newline="").write("-- Restore order: functions (02) first, then this file (its triggers call them).\n" + ddl + data)

# 2 functions
fx = "-- Functions to restore (definitions as captured). ACL note: original ACL was PUBLIC+anon+authenticated+service_role on the first three;\n-- notify_* were revoked from PUBLIC/anon/authenticated by 05a/05a2, so the rollback of 05c re-applies the grants below.\n"
for name in ("notify_workout_invite", "notify_workout_invite_response", "is_user_in_active_workout", "get_workouts_awaiting_creator_join"):
    for r in q(f"select pg_get_functiondef(p.oid) d, p.proacl::text acl, pg_get_function_identity_arguments(p.oid) a from pg_proc p where p.pronamespace='public'::regnamespace and p.proname='{name}'"):
        fx += f"-- {name}({r['a']}) acl at capture: {r['acl']}\n{r['d']};\n"
open(f"{OUT}/02_functions.sql", "w", newline="").write(fx)

# 3 columns
cdefs = q("select table_name, column_name, data_type, column_default, is_nullable from information_schema.columns where table_schema='public' and ((table_name='workouts' and column_name in ('ready_expires_at','creator_popup_shown')) or (table_name='user_profiles' and column_name='workout_join_popups_enabled')) order by 1,2")
cx = "-- Columns dropped by 05c. Recreate, then restore values (only rows that differ from the default are listed).\n"
for c in cdefs:
    cx += f"ALTER TABLE public.{c['table_name']} ADD COLUMN IF NOT EXISTS {c['column_name']} {c['data_type']}" + (f" DEFAULT {c['column_default']}" if c['column_default'] else "") + (" NOT NULL" if c['is_nullable']=='NO' else "") + ";\n"
cx += "GRANT INSERT (workout_join_popups_enabled), UPDATE (workout_join_popups_enabled) ON public.user_profiles TO authenticated;\n"
vals = one("select jsonb_agg(jsonb_build_object('id',id,'v',ready_expires_at))::text from workouts where ready_expires_at is not null") or "[]"
cx += f"UPDATE public.workouts w SET ready_expires_at = (x->>'v')::timestamptz FROM jsonb_array_elements($j${vals}$j$::jsonb) x WHERE w.id = (x->>'id')::uuid;\n"
vals = one("select jsonb_agg(jsonb_build_object('id',id,'v',creator_popup_shown))::text from workouts where creator_popup_shown is true") or "[]"
cx += f"UPDATE public.workouts w SET creator_popup_shown = true FROM jsonb_array_elements($j${vals}$j$::jsonb) x WHERE w.id = (x->>'id')::uuid;\n"
vals = one("select jsonb_agg(jsonb_build_object('id',id,'v',workout_join_popups_enabled))::text from user_profiles where workout_join_popups_enabled is distinct from true") or "[]"
cx += f"UPDATE public.user_profiles u SET workout_join_popups_enabled = (x->>'v')::boolean FROM jsonb_array_elements($j${vals}$j$::jsonb) x WHERE u.id = (x->>'id')::uuid;\n"
open(f"{OUT}/03_columns.sql", "w").write(cx)

# 4 teams (all 10 candidates, restore order parents first)
tx = "-- Rows for the 10 DB-9 candidate teams (all are backed up even if some are skipped). Restore in this order.\n"
counts = {}
for table, where in (("public.buddy_teams", tl), ("public.team_members", ts), ("public.team_streaks", ts),
                     ("public.daily_team_checkins", f"team_streak_id in (select id from public.team_streaks where {ts})"),
                     ("public.streak_events", ts)):
    n, s = rows_restore(table, where); counts[table] = n; tx += s
open(f"{OUT}/04_teams.sql", "w").write(tx)

# 5 vault (metadata only; the value is NOT backed up on purpose)
v = q("select id, description, created_at, updated_at from vault.secrets where name <> 'service_role_key'")
open(f"{OUT}/05_vault_secret_metadata.txt", "w").write("Vault secret to be deleted by id (name and value deliberately not stored here):\n" + json.dumps(v, indent=1, default=str) + "\n")
print(n_inv, counts, v)
