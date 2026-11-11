# Builds supabase/migrations/20261028230000_single_server_checkin.sql, docs/rollback_20261028230000.sql,
# docs/hygiene/checkin_rpc_probes.sql (from checkin_rpc_probes.in.sql) and docs/hygiene/checkin_rpc_rollback_test.sql.
# Replaced bodies are derived from the live dumps in checkin_rpc_backup/ by exact, count-checked replacements.
import hashlib, pathlib

V = "20261028230000"
ROOT = pathlib.Path(__file__).resolve().parents[2]
BK = ROOT / "docs/hygiene/checkin_rpc_backup"


def live(name):
    return (BK / f"{name}.sql").read_text()


def sub(text, old, new, count=1):
    n = text.count(old)
    assert n == count, f"expected {count} x {old!r}, found {n}"
    return text.replace(old, new)


def stmt(body):
    return body.rstrip("\n") + ";\n"


# ── replaced bodies ─────────────────────────────────────────────────────────
finish = live("finish_checkin_session")
finish = sub(finish, "  v_day := (v_start AT TIME ZONE v_tz)::date;", "  v_day := public._credit_day(v_uid, v_start);")
finish = sub(finish, "  PERFORM public._server_checkin(v_uid, v_day);", "  PERFORM public._credit_checkin(v_uid, v_start);")
finish = sub(finish, "        v_pday := (v_wk.workout_started_at AT TIME ZONE public.safe_user_tz(v_partner))::date;",
             "        v_pday := public._credit_day(v_partner, v_wk.workout_started_at);")
finish = sub(finish, "        PERFORM public._server_checkin(v_partner, v_pday);",
             "        PERFORM public._credit_checkin(v_partner, v_wk.workout_started_at);")

auto = live("_auto_credit")
auto = sub(auto, "  v_day date := (p_start AT TIME ZONE public.safe_user_tz(p_user))::date;",
           "  v_day date := public._credit_day(p_user, p_start);")
auto = sub(auto, "  PERFORM public._server_checkin(p_user, v_day);", "  PERFORM public._credit_checkin(p_user, p_start);")

rewards = live("_apply_checkin_rewards")
rewards = sub(rewards, "  v_user_tz text := public.safe_user_tz(p_user_id);\n", "")
rewards = sub(rewards, "  -- Daily cap check for the primary user, in THEIR OWN local day (tz3_2)\n",
              "  -- Daily cap for the primary user, counted by credit day: the date after the\n"
              "  -- last colon of reference_id (streak:day), not the day the row was created (CAP-2).\n")
rewards = sub(rewards, "    AND (created_at AT TIME ZONE v_user_tz)::date = p_check_in_date;",
              "    AND substring(reference_id from '[^:]*$') = p_check_in_date::text;", 2)
rewards = sub(rewards, "        -- Teammate's cap window is measured in the TEAMMATE's own local day.\n"
                       "        v_t_tz text := public.safe_user_tz(v_teammate.user_id);\n", "")
rewards = sub(rewards, "            AND (created_at AT TIME ZONE v_t_tz)::date = p_check_in_date;",
              "            AND substring(reference_id from '[^:]*$') = p_check_in_date::text;", 2)
rewards = sub(rewards, "          SELECT COALESCE(SUM(amount), 0) INTO v_t_already_xp\n",
              "          -- Teammate's cap window: the same credit day (CAP-2).\n"
              "          SELECT COALESCE(SUM(amount), 0) INTO v_t_already_xp\n")

notify = live("notify_buddy_checkin")
notify = sub(notify, "BEGIN\n  SELECT team_id INTO v_team_id",
             "BEGIN\n"
             "  -- Copies written by submit_checkin are not new check-ins: no push.\n"
             "  IF current_setting('app.checkin_copy', true) = '1' THEN\n"
             "    RETURN NEW;\n"
             "  END IF;\n\n"
             "  SELECT team_id INTO v_team_id")

invite_team = live("create_invite_team")
invite_team = sub(invite_team, "  v_invite_created TIMESTAMPTZ;\n  v_invitee_is_new BOOLEAN;\n", "")
invite_team = sub(invite_team, "  SELECT id, created_at INTO v_invite_id, v_invite_created\n", "  SELECT id INTO v_invite_id\n")
old_bonus = invite_team[invite_team.index("  SELECT (u.created_at > v_invite_created) INTO v_invitee_is_new"):invite_team.index("  RETURN v_team_id;\nEND;")]
assert old_bonus.count("award_coins") == 1, old_bonus
invite_team = sub(invite_team, old_bonus,
                  "  -- The invitee's welcome bonus is paid on their first credited day by\n"
                  "  -- _fulfil_invite_reward, once per account (F3), no longer here.\n\n")

fulfil = live("_fulfil_invite_reward")
fulfil = sub(fulfil, "  v_amount  INT;\n", "  v_amount  INT;\n  v_bonus   BOOLEAN := false;\n")
fulfil = sub(fulfil, "    FOR UPDATE\n  LOOP\n",
             "    FOR UPDATE\n  LOOP\n"
             "    -- F3: the invitee's own 20-coin welcome bonus, once per account for life,\n"
             "    -- paid on its first credited row after joining through an invite. The\n"
             "    -- FOR UPDATE above serialises concurrent rows for the same invitee.\n"
             "    IF NOT v_bonus\n"
             "       AND NOT EXISTS (\n"
             "         SELECT 1 FROM coin_transactions\n"
             "         WHERE user_id = NEW.user_id AND transaction_type = 'invite_bonus'\n"
             "       )\n"
             "       AND EXISTS (\n"
             "         SELECT 1 FROM auth.users u\n"
             "         WHERE u.id = NEW.user_id AND u.created_at > v_invite.created_at\n"
             "       ) THEN\n"
             "      BEGIN\n"
             "        PERFORM award_coins(NEW.user_id, 20, 'invite_bonus', 'Joined via buddy invite', v_invite.id::text);\n"
             "      EXCEPTION WHEN OTHERS THEN\n"
             "        -- Never block the check-in. No invite_bonus row, so the next row retries.\n"
             "        RAISE WARNING 'invite_bonus failed for %: %', NEW.user_id, SQLERRM;\n"
             "      END;\n"
             "      v_bonus := true;\n"
             "    END IF;\n\n")

# ── new functions ───────────────────────────────────────────────────────────
credit_day = """CREATE OR REPLACE FUNCTION public._credit_day(p_user_id uuid, p_at timestamp with time zone)
 RETURNS date
 LANGUAGE sql
 STABLE
 SET search_path TO 'public'
AS $function$
  -- The credit-day formula: the user's local date at p_at. Every credit path
  -- takes its day from here. process_stale_sessions repeats this formula
  -- inline in its "already credited?" guards (see its COMMENT): keep them equal.
  SELECT (p_at AT TIME ZONE public.safe_user_tz(p_user_id))::date;
$function$"""

server_checkin = live("_server_checkin")
credit_checkin = server_checkin
credit_checkin = sub(credit_checkin, "CREATE OR REPLACE FUNCTION public._server_checkin(p_user_id uuid, p_day date)\n RETURNS void\n",
                     "CREATE OR REPLACE FUNCTION public._credit_checkin(p_user_id uuid, p_at timestamp with time zone, "
                     "p_pay boolean DEFAULT true, p_time timestamp with time zone DEFAULT now(), p_streak_id uuid DEFAULT NULL::uuid)\n RETURNS jsonb\n")
credit_checkin = sub(credit_checkin, "  v_coach_max_id constant uuid := '00000000-0000-0000-0000-000000000001';\nBEGIN\n",
                     "  v_coach_max_id constant uuid := '00000000-0000-0000-0000-000000000001';\n"
                     "  v_day date := public._credit_day(p_user_id, p_at);\n"
                     "  v_rc jsonb;\n  v_rw jsonb;\n  v_teams jsonb := '[]'::jsonb;\n"
                     "  v_xp integer := 0;\n  v_coins integer := 0;\nBEGIN\n")
credit_checkin = sub(credit_checkin, "p_day", "v_day", 6)
credit_checkin = sub(credit_checkin, "    SELECT ts.id, bt.is_coach_max_team\n", "    SELECT ts.id, ts.team_id, bt.is_coach_max_team\n")
credit_checkin = sub(credit_checkin, "    WHERE tm.user_id = p_user_id AND ts.is_active = true\n",
                     "    WHERE tm.user_id = p_user_id AND ts.is_active = true\n"
                     "      AND (p_streak_id IS NULL OR ts.id = p_streak_id)\n")
credit_checkin = sub(credit_checkin, "    VALUES (t.id, p_user_id, v_day, now())\n", "    VALUES (t.id, p_user_id, v_day, p_time)\n")
credit_checkin = sub(credit_checkin,
                     "    IF (public._recompute_team_streak(t.id, v_day)->>'updated')::boolean THEN\n"
                     "      PERFORM public._apply_checkin_rewards(p_user_id, t.id, v_day);\n"
                     "    END IF;\n",
                     "    v_rc := public._recompute_team_streak(t.id, v_day);\n"
                     "    IF (v_rc->>'updated')::boolean AND p_pay THEN\n"
                     "      v_rw := public._apply_checkin_rewards(p_user_id, t.id, v_day);\n"
                     "      v_xp := v_xp + COALESCE((v_rw->>'xp_awarded')::integer, 0);\n"
                     "      v_coins := v_coins + COALESCE((v_rw->>'coins_awarded')::integer, 0);\n"
                     "    END IF;\n")
credit_checkin = sub(credit_checkin,
                     "      PERFORM public._finish_coach_max_checkin(t.id, p_user_id, v_day);\n    END IF;\n  END LOOP;\nEND;\n",
                     "      PERFORM public._finish_coach_max_checkin(t.id, p_user_id, v_day);\n    END IF;\n\n"
                     "    v_teams := v_teams || jsonb_build_object(\n"
                     "      'streak_id', t.id, 'team_id', t.team_id,\n"
                     "      'updated', COALESCE((v_rc->>'updated')::boolean, false),\n"
                     "      'new_streak', (SELECT current_streak FROM team_streaks WHERE id = t.id));\n"
                     "  END LOOP;\n\n"
                     "  RETURN jsonb_build_object('credit_date', v_day, 'teams', v_teams, 'xp', v_xp, 'coins', v_coins);\nEND;\n")

submit = """CREATE OR REPLACE FUNCTION public.submit_checkin()
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_uid uuid := auth.uid();
  v_coach_max_id constant uuid := '00000000-0000-0000-0000-000000000001';
  v_day date;
  v_before jsonb;
  v_mine_before integer;
  v_mine integer;
  v_xp integer := 0;
  v_coins integer := 0;
  v_r jsonb;
  c record;
BEGIN
  IF v_uid IS NULL THEN
    RAISE EXCEPTION 'unauthenticated';
  END IF;
  v_day := public._credit_day(v_uid, now());

  SELECT jsonb_object_agg(ts.id, ts.total_workouts) INTO v_before
  FROM team_streaks ts JOIN team_members tm ON tm.team_id = ts.team_id
  WHERE tm.user_id = v_uid AND ts.is_active = true;

  IF v_before IS NULL THEN
    RETURN jsonb_build_object('credited', false, 'reason', 'no_teams', 'credit_date', v_day,
                              'streak', 0, 'xp', 0, 'coins', 0, 'teams', '[]'::jsonb);
  END IF;

  SELECT count(*) INTO v_mine_before FROM daily_team_checkins
  WHERE user_id = v_uid AND check_in_date = v_day;

  -- Copy each member's real check-in for their own local today onto every
  -- shared active team that lacks it. Nobody gets a first check-in here (that
  -- stays behind finish_checkin_session), Coach Max is never copied, a copy
  -- keeps its source's earliest check_in_time, and copies pay nothing.
  FOR c IN
    SELECT ts.id AS streak_id, m.user_id, src.t
    FROM team_streaks ts
    JOIN team_members me ON me.team_id = ts.team_id AND me.user_id = v_uid
    JOIN team_members m ON m.team_id = ts.team_id AND m.user_id <> v_coach_max_id
    CROSS JOIN LATERAL (SELECT public._credit_day(m.user_id, now()) AS day) d
    CROSS JOIN LATERAL (
      SELECT min(x.check_in_time) AS t FROM daily_team_checkins x
      WHERE x.user_id = m.user_id AND x.check_in_date = d.day
    ) src
    WHERE ts.is_active = true
      AND src.t IS NOT NULL
      AND NOT EXISTS (
        SELECT 1 FROM daily_team_checkins y
        WHERE y.team_streak_id = ts.id AND y.user_id = m.user_id AND y.check_in_date = d.day
      )
    ORDER BY ts.id, m.user_id
  LOOP
    -- A copy is not a new check-in: notify_buddy_checkin sends no push for it.
    PERFORM set_config('app.checkin_copy', '1', true);
    v_r := public._credit_checkin(c.user_id, now(), false, c.t, c.streak_id);
    PERFORM set_config('app.checkin_copy', '', true);
    IF c.user_id = v_uid THEN
      v_xp := v_xp + (v_r->>'xp')::integer;
      v_coins := v_coins + (v_r->>'coins')::integer;
    END IF;
  END LOOP;

  SELECT count(*) INTO v_mine FROM daily_team_checkins
  WHERE user_id = v_uid AND check_in_date = v_day;

  RETURN (
    SELECT jsonb_build_object(
      'credited', v_mine > v_mine_before,
      'reason', CASE WHEN v_mine > v_mine_before THEN 'credited'
                     WHEN v_mine_before > 0 THEN 'already_checked_in'
                     ELSE 'not_checked_in_today' END,
      'credit_date', v_day,
      'streak', COALESCE(max(ts.current_streak), 0),
      'xp', v_xp,
      'coins', v_coins,
      'teams', COALESCE(jsonb_agg(jsonb_build_object(
                 'streak_id', ts.id, 'team_id', ts.team_id,
                 'updated', ts.total_workouts IS DISTINCT FROM (v_before->>ts.id::text)::integer,
                 'new_streak', ts.current_streak) ORDER BY ts.id), '[]'::jsonb))
    FROM team_streaks ts JOIN team_members tm ON tm.team_id = ts.team_id
    WHERE tm.user_id = v_uid AND ts.is_active = true);
END;
$function$"""

CD = "public._credit_day(uuid, timestamp with time zone)"
CC = "public._credit_checkin(uuid, timestamp with time zone, boolean, timestamp with time zone, uuid)"
PSS = "public.process_stale_sessions(timestamp with time zone)"
PSS_COMMENT = ("Its inline (start AT TIME ZONE safe_user_tz(u))::date \"already credited?\" guards must stay "
               "equal to public._credit_day(), the credit-day formula _auto_credit uses.")

migration = f"""-- Single server check-in RPC. Design: docs/hygiene/checkin_rpc_design.md. Report: docs/hygiene/checkin_rpc_report.md.
-- Rollback: docs/rollback_{V}.sql. Additive: the installed build's direct inserts keep working until Migration B.

-- The one credit-day formula (Q7).
{stmt(credit_day)}
-- The one internal credit path, replacing _server_checkin (same loop and body).
-- p_at: the moment the credit belongs to; the day comes only from _credit_day.
-- p_time: stored check_in_time (a copy keeps its source's time). p_pay = false
-- skips rewards (copies pay nothing). p_streak_id limits it to one team.
{stmt(credit_checkin)}
-- finish_checkin_session: credit day and credits through the shared functions. Body otherwise unchanged.
{stmt(finish)}
-- _auto_credit (process_stale_sessions' credit step): same.
{stmt(auto)}
DROP FUNCTION public._server_checkin(uuid, date);

COMMENT ON FUNCTION {PSS} IS '{PSS_COMMENT}';

-- CAP-2: the daily cap counts payouts by credit day (reference_id suffix), not by creation day.
{stmt(rewards)}
-- submit_checkin: copies members' real check-ins for their local today onto shared teams. Never a first check-in.
{stmt(submit)}
-- notify_buddy_checkin: no push for a copy (transaction-local flag set by submit_checkin only).
{stmt(notify)}
-- F3: create_invite_team no longer pays the invitee at join ...
{stmt(invite_team)}
-- ... _fulfil_invite_reward pays it once per account, on the first credited row.
{stmt(fulfil)}
REVOKE EXECUTE ON FUNCTION {CD} FROM PUBLIC, anon, authenticated;
GRANT  EXECUTE ON FUNCTION {CD} TO service_role;
REVOKE EXECUTE ON FUNCTION {CC} FROM PUBLIC, anon, authenticated;
GRANT  EXECUTE ON FUNCTION {CC} TO service_role;
REVOKE EXECUTE ON FUNCTION public._apply_checkin_rewards(uuid, uuid, date) FROM PUBLIC, anon, authenticated;
REVOKE EXECUTE ON FUNCTION public.submit_checkin() FROM PUBLIC, anon;
GRANT  EXECUTE ON FUNCTION public.submit_checkin() TO authenticated;
REVOKE EXECUTE ON FUNCTION public.finish_checkin_session(uuid) FROM PUBLIC, anon;
GRANT  EXECUTE ON FUNCTION public.finish_checkin_session(uuid) TO authenticated;
REVOKE EXECUTE ON FUNCTION public.create_invite_team(uuid, uuid) FROM PUBLIC, anon;
GRANT  EXECUTE ON FUNCTION public.create_invite_team(uuid, uuid) TO authenticated;
"""

ACL_SVC = "{postgres=X/postgres,service_role=X/postgres}"
ACL_AUTH = "{postgres=X/postgres,authenticated=X/postgres,service_role=X/postgres}"
rollback = f"""-- Rollback for {V}_single_server_checkin. Restores the bodies dumped from live on 2026-10-28
-- (docs/hygiene/checkin_rpc_backup/) and drops the new functions. CREATE OR REPLACE keeps ACLs.
-- Pre-change ACLs (all SET search_path=public):
--   _server_checkin(uuid,date), _auto_credit(...), _apply_checkin_rewards, _fulfil_invite_reward,
--   notify_buddy_checkin, process_stale_sessions: {ACL_SVC}
--   finish_checkin_session(uuid), create_invite_team(uuid,uuid): {ACL_AUTH}
--   process_stale_sessions comment: NULL

{stmt(server_checkin)}REVOKE EXECUTE ON FUNCTION public._server_checkin(uuid, date) FROM PUBLIC, anon, authenticated;
GRANT  EXECUTE ON FUNCTION public._server_checkin(uuid, date) TO service_role;

{stmt(live("finish_checkin_session"))}
{stmt(live("_auto_credit"))}
{stmt(live("_apply_checkin_rewards"))}
{stmt(live("notify_buddy_checkin"))}
{stmt(live("create_invite_team"))}
{stmt(live("_fulfil_invite_reward"))}
DROP FUNCTION public.submit_checkin();
DROP FUNCTION {CC};
DROP FUNCTION {CD};
COMMENT ON FUNCTION {PSS} IS NULL;
"""

NAMES = ["_server_checkin", "finish_checkin_session", "_auto_credit", "_apply_checkin_rewards",
         "notify_buddy_checkin", "create_invite_team", "_fulfil_invite_reward"]
expect = ",\n    ".join(f"('{n}', '{hashlib.md5(live(n).encode()).hexdigest()}')" for n in NAMES)
rollback_test = f"""-- Rollback test: migration {V}, then docs/rollback_{V}.sql, in one transaction ending in RAISE.
-- Expect every restored body md5 = the live dump, ACLs and comment as before, new functions gone.
BEGIN;
{migration}
{rollback}
DO $t$
DECLARE r text[] := ARRAY[]::text[]; x record;
BEGIN
  FOR x IN SELECT e.n, e.h, md5(pg_get_functiondef(p.oid)) AS got, p.proacl::text AS acl, p.proconfig::text AS cfg
           FROM (VALUES
    {expect}) e(n, h)
           LEFT JOIN pg_proc p ON p.proname = e.n AND p.pronamespace = 'public'::regnamespace
  LOOP
    r := array_append(r, CASE WHEN x.got = x.h AND x.cfg = '{{search_path=public}}' AND x.acl = CASE WHEN x.n IN ('finish_checkin_session', 'create_invite_team')
                                   THEN '{ACL_AUTH}' ELSE '{ACL_SVC}' END
                              THEN 'PASS ' ELSE 'FAIL ' END || format('%s md5 %s acl %s', x.n, x.got, x.acl));
  END LOOP;
  r := array_append(r, CASE WHEN NOT EXISTS (SELECT 1 FROM pg_proc WHERE pronamespace = 'public'::regnamespace
                                              AND proname IN ('submit_checkin', '_credit_checkin', '_credit_day'))
                            THEN 'PASS ' ELSE 'FAIL ' END || 'new functions dropped');
  r := array_append(r, CASE WHEN obj_description('{PSS}'::regprocedure, 'pg_proc') IS NULL
                            THEN 'PASS ' ELSE 'FAIL ' END || 'process_stale_sessions comment back to NULL');
  RAISE EXCEPTION E'ROLLBACK_TEST\\n%', array_to_string(r, E'\\n');
END
$t$;
ROLLBACK;
"""

(ROOT / f"supabase/migrations/{V}_single_server_checkin.sql").write_text(migration)
(ROOT / f"docs/rollback_{V}.sql").write_text(rollback)
(ROOT / "docs/hygiene/checkin_rpc_rollback_test.sql").write_text(rollback_test)
tpl = (ROOT / "docs/hygiene/checkin_rpc_probes.in.sql").read_text()
(ROOT / "docs/hygiene/checkin_rpc_probes.sql").write_text(sub(tpl, "-- @@MIGRATION_A@@\n", migration))
print("ok")
