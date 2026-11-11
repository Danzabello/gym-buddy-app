# Builds supabase/migrations/20261013002000_hygiene_05c.sql, docs/rollback_20261013002000.sql and the two probe scripts.
import json, subprocess
V = "20261013002000"
SIX = ["d168695d-f788-477a-80e7-78bb1c7b876b", "bd6736f1-410c-483f-939a-3119ac08d5c8", "dc1ee1ab-d474-4ffd-a540-ef059511d1fd",
       "2a45a481-d14d-4590-a188-92b8cf21c43c", "0e596a48-aee5-4b9b-afbe-9dae16740a61", "c2e4b37e-f54e-45fb-88f7-9c7f9a33ba10"]
ALLOWED = ["5e67f64d-16e3-4b09-9b00-ddc49df8c3f6", "6ef4e82e-a54d-4b91-8ce4-b5f179a65f66", "cf4946f5-f921-4e81-bbf4-88d574e8baf5",
           "6dfac56a-74a1-4a60-b7fa-e200338350f3", "f7c1ef63-3b93-401d-b2bb-8402ddf9a881", "00000000-0000-0000-0000-000000000001"]
IDS = ",".join(f"'{i}'" for i in SIX)
AL = ",".join(f"'{i}'" for i in ALLOWED)
VAULT = "fbae4dec-efe3-48ca-9230-9f326a206e48"
mig = f"""-- Hygiene 05c (Phase C, destructive). Backup + dry run: docs/hygiene/05c_backup/, docs/hygiene/05c_dry_run_output.txt
-- Rollback: docs/rollback_{V}.sql
-- C1 legacy handshake: table workout_invites and its trigger functions, is_user_in_active_workout, the dead join-popup RPC and columns.
DROP TABLE public.workout_invites;
DROP FUNCTION public.notify_workout_invite();
DROP FUNCTION public.notify_workout_invite_response();
DROP FUNCTION public.is_user_in_active_workout(uuid);
DROP FUNCTION public.get_workouts_awaiting_creator_join(uuid);
ALTER TABLE public.workouts DROP COLUMN ready_expires_at, DROP COLUMN creator_popup_shown;
ALTER TABLE public.user_profiles DROP COLUMN workout_join_popups_enabled;

-- Partner credit hole: any participant of any workout (even one never started) could credit the other.
REVOKE EXECUTE ON FUNCTION public.checkin_team_for_user(uuid, uuid) FROM PUBLIC, anon, authenticated;

-- Team names embed display names ("A & B"); scrub the deleted user's name. Never raises: account deletion must not depend on it.
CREATE OR REPLACE FUNCTION public._scrub_team_names_on_profile_delete()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
BEGIN
  BEGIN
    IF OLD.display_name IS NOT NULL AND btrim(OLD.display_name) <> '' THEN
      UPDATE buddy_teams bt
         SET team_name = (SELECT string_agg(CASE WHEN lower(btrim(u.p)) = lower(btrim(OLD.display_name)) THEN 'Former buddy' ELSE u.p END, ' & ' ORDER BY u.o)
                            FROM unnest(string_to_array(bt.team_name, ' & ')) WITH ORDINALITY AS u(p, o))
       WHERE coalesce(bt.is_coach_max_team, false) = false
         AND bt.team_name IS NOT NULL
         AND position(lower(btrim(OLD.display_name)) IN lower(bt.team_name)) > 0
         AND bt.id IN (SELECT tm.team_id FROM team_members tm WHERE tm.user_id = OLD.id);
    END IF;
  EXCEPTION WHEN OTHERS THEN
    NULL;
  END;
  RETURN OLD;
END;
$function$;
REVOKE EXECUTE ON FUNCTION public._scrub_team_names_on_profile_delete() FROM PUBLIC, anon, authenticated;
CREATE TRIGGER scrub_team_names_on_profile_delete BEFORE DELETE ON public.user_profiles
  FOR EACH ROW EXECUTE FUNCTION public._scrub_team_names_on_profile_delete();

-- Unused vault secret named with the anon JWT; its value duplicated service_role_key (which stays). No consumers anywhere.
DELETE FROM vault.secrets WHERE id = '{VAULT}';

-- C2 DB-9: six test-only teams. Aborts if any member is not a known test account or any team has workout_logs.
DO $$
DECLARE v_ids uuid[] := ARRAY[{IDS}]::uuid[];
BEGIN
  IF EXISTS (SELECT 1 FROM team_members WHERE team_id = ANY(v_ids) AND user_id NOT IN ({AL})) THEN
    RAISE EXCEPTION 'hygiene_05c: non-test member in a team scheduled for deletion';
  END IF;
  IF EXISTS (SELECT 1 FROM workout_logs WHERE team_id = ANY(v_ids)) THEN
    RAISE EXCEPTION 'hygiene_05c: workout_logs reference a team scheduled for deletion';
  END IF;
  DELETE FROM streak_events WHERE team_id = ANY(v_ids);
  DELETE FROM daily_team_checkins WHERE team_streak_id IN (SELECT id FROM team_streaks WHERE team_id = ANY(v_ids));
  DELETE FROM team_streaks WHERE team_id = ANY(v_ids);
  DELETE FROM team_members WHERE team_id = ANY(v_ids);
  DELETE FROM buddy_teams WHERE id = ANY(v_ids);
END
$$;
"""
open(f"supabase/migrations/{V}_hygiene_05c.sql", "w").write(mig)

# 6-team restore data (parents first)
def q(sql):
    p = subprocess.run(["supabase", "db", "query", "--linked", sql], capture_output=True, text=True)
    t = "\n".join(l for l in (p.stdout + p.stderr).splitlines() if not l.startswith(("Initialising", "A new version", "We recommend")))
    return json.loads(t)["rows"]
def restore(table, where):
    d = list(q(f"select coalesce(jsonb_agg(to_jsonb(t)), '[]'::jsonb)::text from (select * from {table} where {where}) t")[0].values())[0]
    return f"INSERT INTO {table} SELECT * FROM jsonb_populate_recordset(null::{table}, $j${d}$j$::jsonb);\n"
ts = f"team_id in ({IDS})"
six = "-- 6 deleted teams (parents first)\n" + restore("public.buddy_teams", f"id in ({IDS})") + restore("public.team_members", ts) + \
      restore("public.team_streaks", ts) + restore("public.daily_team_checkins", f"team_streak_id in (select id from public.team_streaks where {ts})") + restore("public.streak_events", ts)
open("docs/hygiene/05c_backup/04b_teams_six_deleted.sql", "w").write(six)

rd = lambda f: open(f"docs/hygiene/05c_backup/{f}", newline="").read()
rb = f"""-- Rollback for {V}_hygiene_05c. Restores objects and rows from docs/hygiene/05c_backup/.
-- NOT restorable: the deleted vault secret (its value duplicated service_role_key, which was never touched).
DROP TRIGGER IF EXISTS scrub_team_names_on_profile_delete ON public.user_profiles;
DROP FUNCTION IF EXISTS public._scrub_team_names_on_profile_delete();
GRANT EXECUTE ON FUNCTION public.checkin_team_for_user(uuid, uuid) TO authenticated;
{six}
{rd('03_columns.sql')}
{rd('02_functions.sql')}
{rd('01_workout_invites.sql')}
ALTER FUNCTION public.notify_workout_invite() SET search_path = public;
ALTER FUNCTION public.notify_workout_invite_response() SET search_path = public;
ALTER FUNCTION public.is_user_in_active_workout(uuid) SET search_path = public;
-- ACL as left by 05a/05a2 (no PUBLIC/anon/authenticated EXECUTE) for the restored trigger functions:
REVOKE EXECUTE ON FUNCTION public.notify_workout_invite() FROM PUBLIC, anon, authenticated;
REVOKE EXECUTE ON FUNCTION public.notify_workout_invite_response() FROM PUBLIC, anon, authenticated;
REVOKE EXECUTE ON FUNCTION public.is_user_in_active_workout(uuid) FROM PUBLIC, anon, authenticated;
REVOKE EXECUTE ON FUNCTION public.get_workouts_awaiting_creator_join(uuid) FROM PUBLIC, anon;
"""
open(f"docs/rollback_{V}.sql", "w", newline="").write(rb)
