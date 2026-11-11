# Builds supabase/migrations/20261029160000_credit_lock_order.sql, docs/rollback_20261029160000.sql and
# docs/hygiene/07_rollback_test.sql. Replaced bodies are derived from the live dumps in 07_backup/ (2026-10-29)
# by exact, count-checked replacements, so the body diff is exactly the lock lines.
import hashlib, pathlib

V = "20261029160000"
ROOT = pathlib.Path(__file__).resolve().parents[2]
BK = ROOT / "docs/hygiene/07_backup"
LIVE_MD5 = {
    "_credit_checkin": "6b96429f2c9bd74af229aeca79541bb0",
    "_recompute_team_streak": "d924df92c84adc0fe82b2e80ec5577cb",
    "finish_checkin_session": "74eee93e25530e4071bc1cd4ccf15e4a",
    "check_in_coach_max": "93d0cd778b8e863ad490e34c5af26ce6",
    "reconcile_stale_streaks": "124947b1c46d74fc7bb859b520ec23a1",
}
SIG = {
    "_credit_checkin": "public._credit_checkin(uuid, timestamptz, boolean, timestamptz, uuid)",
    "_recompute_team_streak": "public._recompute_team_streak(uuid, date)",
    "finish_checkin_session": "public.finish_checkin_session(uuid)",
    "check_in_coach_max": "public.check_in_coach_max(uuid)",
    "reconcile_stale_streaks": "public.reconcile_stale_streaks()",
}
CLIENT = {"finish_checkin_session", "check_in_coach_max"}


def live(name):
    text = (BK / f"{name}.sql").read_text()
    assert hashlib.md5(text.encode()).hexdigest() == LIVE_MD5[name], name
    return text


def sub(text, old, new, count=1):
    n = text.count(old)
    assert n == count, f"expected {count} x {old!r}, found {n}"
    return text.replace(old, new)


def stmt(body):
    return body.rstrip("\n") + ";\n"


def grants(name):
    s = SIG[name]
    g = f"REVOKE EXECUTE ON FUNCTION {s} FROM PUBLIC, anon"
    if name in CLIENT:
        return g + f";\nGRANT EXECUTE ON FUNCTION {s} TO authenticated, service_role;\n"
    return g + f", authenticated;\nGRANT EXECUTE ON FUNCTION {s} TO service_role;\n"


LOCK_CREDIT = """CREATE OR REPLACE FUNCTION public._lock_credit(p_users uuid[], p_pay boolean, p_streak_id uuid DEFAULT NULL::uuid)
 RETURNS void
 LANGUAGE plpgsql
 SET search_path TO 'public'
AS $function$
-- Credit lock order (CLAUDE.md): L2 every active streak of these users, ascending id, one statement;
-- then, when the credit pays, L3 one cap lock per non-bot member of those streaks, ascending key.
-- Re-taking a lock this transaction already holds is a no-op.
DECLARE
  v_k integer;
BEGIN
  -- L2 (RACE-1): teammates crediting the same streak serialise here, so the later one sees the earlier row.
  PERFORM 1 FROM team_streaks ts
  WHERE ts.is_active = true
    AND (p_streak_id IS NULL OR ts.id = p_streak_id)
    AND EXISTS (SELECT 1 FROM team_members tm WHERE tm.team_id = ts.team_id AND tm.user_id = ANY(p_users))
  ORDER BY ts.id
  FOR NO KEY UPDATE;

  IF NOT p_pay THEN
    RETURN;
  END IF;

  -- L3 (CAP-RACE): one lock per user, whatever the streak or day, held to commit; ordered by the lock key itself.
  FOR v_k IN
    SELECT DISTINCT hashtext(tm.user_id::text)
    FROM team_streaks ts
    JOIN team_members tm ON tm.team_id = ts.team_id
    WHERE ts.is_active = true
      AND (p_streak_id IS NULL OR ts.id = p_streak_id)
      AND tm.user_id <> '00000000-0000-0000-0000-000000000001'
      AND EXISTS (SELECT 1 FROM team_members me WHERE me.team_id = ts.team_id AND me.user_id = ANY(p_users))
    ORDER BY 1
  LOOP
    PERFORM pg_advisory_xact_lock(hashtext('checkin_cap'), v_k);
  END LOOP;
END;
$function$
"""

credit = live("_credit_checkin")
credit = sub(credit, "BEGIN\n  -- Same as BreakDayService.cancelBreakDay",
             "BEGIN\n"
             "  PERFORM public._lock_credit(ARRAY[p_user_id], p_pay, p_streak_id);  -- L2+L3: before any write\n\n"
             "  -- Same as BreakDayService.cancelBreakDay")

recompute = live("_recompute_team_streak")
recompute = sub(recompute, "  FROM team_streaks WHERE id = p_streak_id;\n\n  IF v_team_id IS NULL THEN",
                "  FROM team_streaks WHERE id = p_streak_id\n"
                "  FOR NO KEY UPDATE;  -- L2: a recompute waits for an in-flight credit on this streak, then sees its row\n\n"
                "  IF v_team_id IS NULL THEN")

finish = live("finish_checkin_session")
finish = sub(finish, "  v_tz := public.safe_user_tz(v_uid);\n\n",
             "  v_tz := public.safe_user_tz(v_uid);\n\n"
             "  -- L0: the shared workout row before the session row, so two buddies finishing together serialise.\n"
             "  IF p_workout_id IS NOT NULL THEN\n"
             "    PERFORM 1 FROM workouts WHERE id = p_workout_id AND v_uid IN (user_id, buddy_id) FOR NO KEY UPDATE;\n"
             "  END IF;\n\n")
finish = sub(finish, "  PERFORM public._credit_checkin(v_uid, v_start);\n",
             "  IF v_wk_ok THEN  -- L2+L3: caller and the M6a partner below, in one ordered pass\n"
             "    PERFORM public._lock_credit(ARRAY[v_uid, v_wk.user_id, v_wk.buddy_id], true);\n"
             "  ELSE  -- L2+L3\n"
             "    PERFORM public._lock_credit(ARRAY[v_uid], true);\n"
             "  END IF;\n"
             "  PERFORM public._credit_checkin(v_uid, v_start);\n")

coach = live("check_in_coach_max")
coach = sub(coach, "    RETURN jsonb_build_object('checked_in', false, 'reason', 'no_coach_max_team');\n  END IF;\n",
            "    RETURN jsonb_build_object('checked_in', false, 'reason', 'no_coach_max_team');\n  END IF;\n"
            "  PERFORM 1 FROM team_streaks WHERE id = v_streak_id FOR NO KEY UPDATE;  -- L2: before the bot row check and insert\n")

reconcile = live("reconcile_stale_streaks")
reconcile = sub(reconcile, "      AND (last_workout_date IS NULL OR last_workout_date < v_utc_today)\n  LOOP\n",
                "      AND (last_workout_date IS NULL OR last_workout_date < v_utc_today)\n"
                "    ORDER BY id\n"
                "    FOR NO KEY UPDATE  -- L2: ascending; a streak credited meanwhile is re-checked and skipped\n"
                "  LOOP\n")

NEW = {"_credit_checkin": credit, "_recompute_team_streak": recompute, "finish_checkin_session": finish,
       "check_in_coach_max": coach, "reconcile_stale_streaks": reconcile}

mig = [f"-- {V}_credit_lock_order: RACE-1 and CAP-RACE (prompt 07). Design: docs/hygiene/07_design.md.\n"
       f"-- Rollback: docs/rollback_{V}.sql. Credit lock order L0..L5: CLAUDE.md \"Lock order for credit paths\".\n"
       "-- No payout amount, cap, credit-day rule, return shape or public signature changes.\n\n",
       stmt(LOCK_CREDIT),
       "REVOKE EXECUTE ON FUNCTION public._lock_credit(uuid[], boolean, uuid) FROM PUBLIC, anon, authenticated;\n"
       "GRANT EXECUTE ON FUNCTION public._lock_credit(uuid[], boolean, uuid) TO service_role;\n\n"]
for name in ["_credit_checkin", "_recompute_team_streak", "finish_checkin_session", "check_in_coach_max", "reconcile_stale_streaks"]:
    mig += [stmt(NEW[name]), grants(name), "\n"]
migration = "".join(mig)

rb = [f"-- Rollback for {V}_credit_lock_order. Restores the five bodies dumped from live on 2026-10-29\n"
      "-- (docs/hygiene/07_backup/, md5 in gen_07.py) with their grants, then drops _lock_credit.\n"
      "-- Pre-change ACLs (all SET search_path=public):\n"
      "--   finish_checkin_session, check_in_coach_max: {postgres=X/postgres,authenticated=X/postgres,service_role=X/postgres}\n"
      "--   _credit_checkin, _recompute_team_streak, reconcile_stale_streaks: {postgres=X/postgres,service_role=X/postgres}\n\n"]
for name in ["_credit_checkin", "_recompute_team_streak", "finish_checkin_session", "check_in_coach_max", "reconcile_stale_streaks"]:
    rb += [stmt(live(name)), grants(name), "\n"]
rb.append("DROP FUNCTION public._lock_credit(uuid[], boolean, uuid);\n")
rollback = "".join(rb)

checks = "\n".join(
    f"  r := r || pg_temp_ok('{n} body = live dump, ACL, search_path', "
    f"md5(pg_get_functiondef('{SIG[n]}'::regprocedure)) = '{LIVE_MD5[n]}' "
    f"AND (SELECT proacl::text FROM pg_proc WHERE oid = '{SIG[n]}'::regprocedure) = "
    f"'{'{postgres=X/postgres,authenticated=X/postgres,service_role=X/postgres}' if n in CLIENT else '{postgres=X/postgres,service_role=X/postgres}'}' "
    f"AND (SELECT proconfig::text FROM pg_proc WHERE oid = '{SIG[n]}'::regprocedure) = '{{search_path=public}}');"
    for n in SIG)
rollback_test = (
    f"-- 07 rollback test: Migration {V}, then its rollback, in one transaction that ends in RAISE (nothing persists).\n"
    "BEGIN;\n" + migration + "\n-- ═════ rollback ═════\n" + rollback +
    "\nCREATE FUNCTION pg_temp.pg_temp_ok(t text, ok boolean) RETURNS text LANGUAGE sql AS $$\n"
    "  SELECT CASE WHEN coalesce(ok, false) THEN 'PASS ' ELSE 'FAIL ' END || t $$;\n"
    "DO $t$\nDECLARE r text[] := ARRAY[]::text[];\nBEGIN\n" + checks.replace("pg_temp_ok", "pg_temp.pg_temp_ok") + "\n"
    "  r := r || pg_temp.pg_temp_ok('_lock_credit dropped', to_regprocedure('public._lock_credit(uuid[],boolean,uuid)') IS NULL);\n"
    "  RAISE EXCEPTION E'SUITE_RESULTS\\n%', array_to_string(r, E'\\n');\nEND\n$t$;\nROLLBACK;\n")

(ROOT / f"supabase/migrations/{V}_credit_lock_order.sql").write_text(migration)
(ROOT / f"docs/rollback_{V}.sql").write_text(rollback)
(ROOT / "docs/hygiene/07_rollback_test.sql").write_text(rollback_test)
print("ok", hashlib.md5(migration.encode()).hexdigest())
