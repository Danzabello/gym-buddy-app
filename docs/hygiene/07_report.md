# Prompt 07 report: reward/streak suite, RACE-1 and CAP-RACE

Date: 2026-10-29 (UTC). Design and owner decisions are in `docs/hygiene/07_design.md`:

- Q1: L0 yes.
- Q2: the reconcile re-check yes.
- Q3: a control round plus a fix round.
- Q4: a per-user cap key.
- The two-key advisory form is accepted.
- CRON-ORDER is accepted as a residual.

## Result

- **RACE-1 is fixed and race-tested.** Two teammates crediting at the same instant now serialise on the team's `team_streaks` row, so the second credit sees the first one's row and completes the day.
  - Control: streak 0, nobody paid.
  - Fix: streak 1, both paid 15/15.
- **CAP-RACE is fixed and race-tested.** A teammate paid on two streaks at once is now capped exactly.
  - Control: 110 coins against a cap of 100.
  - Fix: exactly 100.
- **The suite is repeatable.** `docs/hygiene/suite/run.sh` runs 101 assertions on live inside transactions that always abort. It is one command, and `--with <migration>` tests a migration before it is pushed.
- **No behaviour change outside the two races.** Payout amounts, caps, credit-day rules, return shapes and public signatures are unchanged. The equivalence probes are byte-identical on all 7 fixtures.

| Commit | What |
|---|---|
| 1 | Migration `20261029160000_credit_lock_order` (applied), `docs/rollback_20261029160000.sql`, the live backups (`07_backup/`) and the rollback test |
| 2 | The suite: `docs/hygiene/suite/` (`economy_suite.sql`, `grants_fresh.sql`, `run.sh`) and `gen_07.py` |
| 3 | This report, the race scripts (`docs/hygiene/07_race/`), the suite outputs, the design doc and the CLAUDE.md "Lock order for credit paths" section |

Nothing is pushed to git. No commit carries attribution trailers.

## Lock order (also in CLAUDE.md)

Take locks in this order, ascending key order within a level.

| Level | Lock | Key order | Taken by | Proof |
|---|---|---|---|---|
| L0 | `workouts` row `FOR NO KEY UPDATE` | one row | `finish_checkin_session` (new, only when the caller is a participant); `_hs_lock` (`im_here`, `leave_workout`, `complete_workout`, `go_solo`, `cancel_workout`, `cant_make_it`, `change_workout_time`, `nudge_workout`) | **proven by body diff and equivalence probes, not race-tested** |
| L1 | `active_checkin_sessions` row(s) | own row; cron: `SKIP LOCKED`, then `ORDER BY id FOR UPDATE` | `finish_checkin_session`, `process_stale_sessions` | unchanged |
| L2 | `team_streaks` rows `FOR NO KEY UPDATE` | streak id | `_lock_credit` (new), via `_credit_checkin` and `finish_checkin_session`; `_recompute_team_streak` (first read); `check_in_coach_max`; `reconcile_stale_streaks` (loop, `ORDER BY id`) | race-tested (RACE-1). For `reconcile_stale_streaks`: **proven by body diff and equivalence probes, not race-tested** |
| L3 | `pg_advisory_xact_lock(hashtext('checkin_cap'), hashtext(user_id::text))`, paying credits only | lock key | `_lock_credit` | race-tested (CAP-RACE) |
| L4 | `checkin_rewards:<streak>:<day>` advisory (CAP-1) | per streak | `_apply_checkin_rewards` | unchanged |
| L5 | row writes: check-in unique key, `user_profiles`, transactions, `invites FOR UPDATE`, `coach_max_schedule`, `workout_logs` | n/a | all credit paths | unchanged |

### CRON-ORDER (known residual, left unchanged by owner decision)

`process_stale_sessions` takes the session rows first: a `SKIP LOCKED` batch, then the partner sessions `FOR UPDATE`. Only after that does it update the `workouts` row. That is the reverse of L0.

- **Pre-existing.** The cron already took the rows in this order against `complete_workout` and `leave_workout`.
- **Narrow.** A cycle needs a Finish (or a handshake call) on a shared workout during the same cron run that auto-completes that workout at 3h30.
- **Harmless on failure.** Postgres aborts one side with `40P01`, nothing is half-written, and the cron retries 5 minutes later.

The other residuals are in `07_design.md` §3.5:

- trigger-paid invite bonuses to an inviter who isn't a member;
- a former member paid without L3;
- the multi-user cron run.

### Pre-build checks (owner request)

- **Workout before session.** Every function that touches both the `workouts` row and the session row takes the workout first. The one exception is `process_stale_sessions` (CRON-ORDER above).
- **No read-only callers.** Every caller of `_recompute_team_streak` and `recompute_team_streak` is VOLATILE. The client and the Edge Function call through `.rpc()` POST, and none uses `get: true`, so no path runs read-only.

## Function body diffs

Old is the live dump of 2026-10-29 (`docs/hygiene/07_backup/`). New is live after `20261029160000`.

The new function `_lock_credit(uuid[], boolean, uuid)` is not SECURITY DEFINER, has `search_path=public`, and EXECUTE is granted to service_role only. Its body is in the migration file.

```diff
### _credit_checkin
@@ -13,6 +13,8 @@
   v_xp integer := 0;
   v_coins integer := 0;
 BEGIN
+  PERFORM public._lock_credit(ARRAY[p_user_id], p_pay, p_streak_id);  -- L2+L3: before any write
+
   -- Same as BreakDayService.cancelBreakDay: working out cancels today's break.
   UPDATE break_day_usage SET cancelled_at = now()
   WHERE user_id = p_user_id AND break_date = v_day AND cancelled_at IS NULL;
### _recompute_team_streak
@@ -25,7 +25,8 @@
 BEGIN
   SELECT team_id, current_streak, longest_streak, total_workouts, best_streak, last_workout_date
   INTO v_team_id, v_current_streak, v_longest_streak, v_total_workouts, v_best_streak, v_last_workout_date
-  FROM team_streaks WHERE id = p_streak_id;
+  FROM team_streaks WHERE id = p_streak_id
+  FOR NO KEY UPDATE;  -- L2: a recompute waits for an in-flight credit on this streak, then sees its row
 
   IF v_team_id IS NULL THEN
     RAISE EXCEPTION 'invalid_streak';
### finish_checkin_session
@@ -29,6 +29,11 @@
   END IF;
   v_tz := public.safe_user_tz(v_uid);
 
+  -- L0: the shared workout row before the session row, so two buddies finishing together serialise.
+  IF p_workout_id IS NOT NULL THEN
+    PERFORM 1 FROM workouts WHERE id = p_workout_id AND v_uid IN (user_id, buddy_id) FOR NO KEY UPDATE;
+  END IF;
+
   -- FIN-1: credit only (a) an eligible own session or (b) an eligible
   -- workout participation; anything else is a no-op that writes nothing.
   -- (a) own session: start pinned by the server, at least 15 minutes and at
@@ -91,6 +96,11 @@
   FROM team_streaks ts JOIN team_members tm ON tm.team_id = ts.team_id
   WHERE tm.user_id = v_uid AND ts.is_active = true;
 
+  IF v_wk_ok THEN  -- L2+L3: caller and the M6a partner below, in one ordered pass
+    PERFORM public._lock_credit(ARRAY[v_uid, v_wk.user_id, v_wk.buddy_id], true);
+  ELSE  -- L2+L3
+    PERFORM public._lock_credit(ARRAY[v_uid], true);
+  END IF;
   PERFORM public._credit_checkin(v_uid, v_start);
   DELETE FROM active_checkin_sessions WHERE user_id = v_uid;
 
### check_in_coach_max
@@ -26,6 +26,7 @@
   IF v_streak_id IS NULL THEN
     RETURN jsonb_build_object('checked_in', false, 'reason', 'no_coach_max_team');
   END IF;
+  PERFORM 1 FROM team_streaks WHERE id = v_streak_id FOR NO KEY UPDATE;  -- L2: before the bot row check and insert
 
   v_today := (now() AT TIME ZONE safe_user_tz(p_user_id))::date;
 
### reconcile_stale_streaks
@@ -19,6 +19,8 @@
     FROM team_streaks
     WHERE is_active = true AND current_streak > 0
       AND (last_workout_date IS NULL OR last_workout_date < v_utc_today)
+    ORDER BY id
+    FOR NO KEY UPDATE  -- L2: ascending; a streak credited meanwhile is re-checked and skipped
   LOOP
     SELECT array_agg(user_id) INTO v_member_ids
     FROM team_members
```

Live md5 after the push:

| Function | md5 |
|---|---|
| `_credit_checkin` | `b8ac5cbd2e0e0cb95ade544aa104d001` |
| `_lock_credit` | `bd6aefe4a8ad8195e68180751d6e64a8` |
| `_recompute_team_streak` | `881a274b018a8c726a46856b91b646bd` |
| `check_in_coach_max` | `ed5d082b3220ee0833816f1c1bd434d0` |
| `finish_checkin_session` | `34ff932cdfcb9f358c88676bbc81c98b` |
| `reconcile_stale_streaks` | `a629e06c27e763ddf1ef71d9eb8f0ca8` |

The unchanged `_apply_checkin_rewards` (`47185fcb…`), `process_stale_sessions` (`929c250c…`) and `submit_checkin` (`acc63caf…`) still match their pinned values.

## Apply evidence

### Before the push

- `schema_migrations` had 127 remote and 128 local versions. The only local-only version was `20261029160000`, nothing was remote-only, and the remote head was `20261029010000`.
- The dry run said `Would push 20261029160000_credit_lock_order.sql` and nothing else.

### Push

- `supabase db push` ran at 16:54:15–16:54:19 UTC.
- The dry run afterwards says "Remote database is up to date".
- The MCP `apply_migration` tool was not used.

### md5 parity

Both sides are hashed with whitespace and `;` removed: `statements` on the remote side, the local file on the other. The method first reproduces Migration A's recorded value.

```
20261028230000 remote=621ad68bc60544182b122eba3fd9bdd1 local=621ad68bc60544182b122eba3fd9bdd1 MATCH  (method check)
20261029160000 remote=7ff7264d8e834004ea1757d2ad2914cd local=7ff7264d8e834004ea1757d2ad2914cd MATCH
```

### Advisor diff

Taken at 16:53:51 (before) and 16:54:45 (after). **Nothing changed.**

| Lint | Before | After |
|---|---|---|
| `rls_enabled_no_policy` (INFO) | 4 | 4 |
| `authenticated_security_definer_function_executable` (WARN) | 36 | 36 |
| `auth_leaked_password_protection` (WARN) | 1 | 1 |
| unindexed_foreign_keys (INFO) | 17 | 17 |
| auth_rls_initplan (WARN) | 68 | 68 |
| unused_index (INFO) | 8 | 8 |
| multiple_permissive_policies (WARN) | 36 | 36 |

- The 36 functions flagged as executable by signed-in users are the same before and after. `_lock_credit` is not SECURITY DEFINER and is not client-executable, so it is not flagged.
- The full sets of performance findings are identical before and after.

### Economy snapshots

The snapshot query is `07_race/07_snapshot.sql`.

- **It excludes:** mijotest's rows and streak d557efec.
- **It adds:** `buddy_teams`, `team_members`, `streak_events` and the five race profiles.

The snapshot taken immediately before the push (16:54:15) and the one immediately after are **identical**. Both equal the control-round baseline below.

## Suite results

Run with `docs/hygiene/suite/run.sh`. Full output is in `07_suite_output_prepush.txt`, `07_suite_output_negative_control.txt` and `07_suite_output_live.txt`.

| Run | grants_fresh | economy_suite | Total |
|---|---|---|---|
| Before the push, `--with` the migration | 23/23 | 78/78 | **101 PASS, 0 FAIL** |
| Negative control: today's bodies, no migration | 22/23 | 70/78 | 9 FAIL: exactly the 07 checks (G0.1, G0.4–G0.9, G1.2, and G9.9 for `_lock_credit`) |
| Against live after the push (16:54) | 23/23 | 78/78 | **101 PASS, 0 FAIL** |

### What each group covers

| Group | Covers |
|---|---|
| G0 | Catalog: ACL, SECURITY DEFINER and `search_path` of 16 credit-path functions. The bodies of `_apply_checkin_rewards`, `process_stale_sessions`, `submit_checkin` and `purchase_shop_item` are pinned. **Lock-order body guards** cover each L0, L2 and L3 line, so a reordered lock fails the suite. |
| G1 | `_credit_checkin`: L3 is held for every non-bot member; copies and the bot take no L3; `p_streak_id`; return shape; idempotency; `p_time`. |
| G2 | `submit_checkin`: the copy condition; local day versus UTC; a copy keeps the source time; no push; no pay; the flag is cleared; `already_checked_in`. |
| G3 | `finish_checkin_session`: a Finish after a copy; payouts; `nothing_to_finish`; `too_early`; someone else's workout id (the L0 participant filter); return shape. |
| G4 | `_auto_credit`: credits once, then dedups. |
| G5 | `_apply_checkin_rewards`: base 10/10; CAP-1 dedup; the CAP-2 cases (yesterday, today, legacy suffix, straddle, teammate cap). |
| G6 | F3: no pay at join; one bonus on the first credited day; nothing on a second day or from a second inviter; the inviter reward after 2 days; an old account is never paid. |
| G7 | `purchase_shop_item`: insufficient funds; exact balance; a second purchase is refused; `FOR UPDATE` is present; the `coin_balance` CHECK raises `23514`. |
| G8 | `verify_achievement_progress` replay of `first_flame`: not unlocked at 0; unlocked once for 20 coins / 50 xp; a replay pays nothing. |
| G9 | Fresh connection, authenticated first. Direct writes are denied (`daily_team_checkins`, `coin_balance`, `xp`, `rest_tokens_available`, xp/coin transactions, `team_streaks`, `user_inventory`). 10 internal functions are not executable. anon cannot execute any economy function. Table privileges are pinned. |
| G10 | Equivalence (below). |

### Equivalence

The equivalence fixtures are from the pre-push run: old is today's live bodies, new is the migration inlined. Each snapshot covers:

- return values;
- check-in rows and streaks;
- xp/coin rows and profiles;
- logs, cancelled breaks, sessions and the schedule;
- pushes.

All seven are byte-identical:

```
eq1 normal finish              75d12f110d32e223c8dc54fecffab2ff = 75d12f110d32e223c8dc54fecffab2ff
eq2 partner credit (M6a)       b9b6de2be4cf7d25128a996900f37568 = b9b6de2be4cf7d25128a996900f37568
eq3 stale auto-complete        27ee267472b1b2a7f11daf4c1965ced2 = 27ee267472b1b2a7f11daf4c1965ced2
eq4 caps (CAP-2)               2580ea48a1d04245ea4c9208f545796e = 2580ea48a1d04245ea4c9208f545796e
eq5 submit_checkin copy        0e7895d19e0c3b7c7b271df3520aa336 = 0e7895d19e0c3b7c7b271df3520aa336
eq6 check_in_coach_max+Finish  5e5e4fd053f60a857a4219aebdc3b9e5 = 5e5e4fd053f60a857a4219aebdc3b9e5
eq7 reconcile_stale_streaks    db5f8f35f267fbe31f5fd87632ba1a65 = db5f8f35f267fbe31f5fd87632ba1a65
```

The md5 values differ between runs because each snapshot contains that run's timestamps. Within a run, old equals new.

### Rollback test

`07_rollback_test.sql` applies the migration and then the rollback in one transaction: **6/6 PASS**.

- All five bodies return to the md5 of the live dump, with their original ACL and `search_path`.
- `_lock_credit` is dropped.

### Bugs in my test code, fixed during the pre-push runs

Neither of these was a migration bug:

- **G4.1** counted `workout_logs` in the same statement that called `_auto_credit`. The statement snapshot cannot see the new row. The count is now a separate statement.
- **Missing-function crash.** A missing function made `pg_get_functiondef(…::regprocedure)` crash the whole suite. It now uses `to_regprocedure`, so that check fails on its own line.

## Concurrency test

### Setup

Accounts, all matched by id:

| Role | Account | Id |
|---|---|---|
| RACE-1 A | onboard_check1 | `81f83cdb` |
| RACE-1 B | onboard_check2 | `bc85514c` |
| CAP-RACE A' | onboard_check3 | `f0f43430` |
| CAP-RACE B' | onboard_check6 | `30d543f1` |
| CAP-RACE X | onboard_check4 | `ae240bb6` |

onboard_check5 was not touched.

How each session runs:

- Each session is its own `supabase db query` process, running as postgres with the copy flag on, so no buddy push goes out.
- It makes one `_credit_checkin(user, now(), true, now(), <fixture streak>)` call.
- A holds its transaction for about 8 s after the call. B starts about 2 s after A.

**One deviation from the design:** the fixture ids are fixed literals (teams `07070707-…-a1/a2/a3`, streaks `…-b1/b2/b3`) instead of a `_race07_fixture` table. That way no DDL ran on live.

### Results

Judged by the totals, not by wait time:

| | Control (today's bodies, 16:47–16:53) | Fix (after the push, 16:55) |
|---|---|---|
| RACE-1 A (onboard_check1) | call 0.01 s, `updated:false`, committed 16:47:26.64 | call 0.01 s, `updated:false`, committed 16:55:39.71 |
| RACE-1 B (onboard_check2) | started 16:47:20.65 (inside A's transaction), **waited 0.01 s**, `updated:false` | started 16:55:33.64 (inside A's transaction), **waited 6.09 s** (L2), `updated:true new_streak:1` |
| R streak / total / last day | **0 / 0 / –** (bug) | **1 / 1 / 2026-10-29** (fixed) |
| R payouts, xp/coins | A 0/0, B 0/0 | A 15/15 (retro 10 + coop 5), B 15/15 |
| CAP A' (onboard_check3, S1) | 0.02 s, `updated:true`, 15/15 | 0.02 s, `updated:true`, 15/15 |
| CAP B' (onboard_check6, S2) | waited 6.06 s (on X's profile row), `updated:true`, 15/15 | waited 6.01 s (L3), `updated:true`, 15/15 |
| X coins suffixed today | **110** = 90 seed + 10 (S1) + 10 (S2), over the cap (bug) | **100** = 90 seed + 10 (S1) + 0 (S2), exact (fixed) |
| X coin rows | seed 90; S1 base 10, coop 0; S2 base 10, coop 0 | seed 90; S1 base 10, coop 0; S2 base 0, coop 0 |
| Verify verdict | `race1_bug_shown: true` | `race1_fixed: true` |

As you predicted, the CAP control waited about 6 s even without the fix. It waited on X's `user_profiles` row in `award_xp`, then still paid from a stale cap read. Only the total tells the two runs apart.

### Hashes

Taken at four points:

1. control baseline (16:46);
2. after the control cleanup (16:53:44);
3. fix baseline (16:55:29);
4. after the fix cleanup (16:56:00).

All four are **identical** (13 tables):

```
buddy_teams              49 6a3d8d64756ef6bc046c25c75cf257e0
coin_transactions        66 8b4bf91c2ed6bd4bb584e54e11737c0d
daily_team_checkins    5571 17e1246842f6a263fc20179df300d483
invites                   7 c366bcb7ea899e30148bfe1b66ac01ae
race07_profiles           5 ea80476f77083617b1462c2c4e450b4b
streak_events             1 d86c49d0917977dce7bf544221574c4e
team_members             96 d427744668473aba7535a017fb78d24a
team_streaks             48 736e46064eaa6776185081c3f58b36b4
user_profiles_xp_coins   47 82a35b418b6997189776e82aee04d3ba
user_unlocked_cosmetics   0 d41d8cd98f00b204e9800998ecf8427e
workout_logs             12 5548c2be66d5521a87a6916921f76210
workouts                 24 de8bb702eb837883d9170f9dec066ea2
xp_transactions          77 ba030b16dc5313c66814da0172293d22
```

There were two committed rounds in total: the control seed at 16:47:01 and the fix seed at 16:55:30. Both cleanups passed their guard.

### Rehearsals

Each rehearsal is one transaction ending in `ROLLBACK`, run before anything was committed:

- **Pass case:** seed, the four credits one after the other, verify, cleanup. The guard passed, and the economy hashes inside the transaction equalled the pre-seed ones.
- **Trip case:** one stray coin row was left behind. The guard refused with `race07 cleanup: not back to baseline; whole cleanup rolled back`.

### The quoting bug and the whole-file check

In the first control run, both CAP sessions failed with `42601 syntax error at or near "onboard_check3"`. Their label was `'cap A' onboard_check3 on S1'`, and the apostrophe in `A'` ended the string.

**No harm done.** The error came before the credit call, the transaction aborted, and nothing was written. Live confirmed it: X had only the seed row, and S1 and S2 were at 0/0.

**Why the rehearsal missed it.** `gen_rehearsal.py` extracted only the `_credit_checkin(...)` call from each session file. It never ran the label line.

**What changed:**

- The labels became `Aprime` and `Bprime`.
- A diff against the original generator output shows only the label text changed: lines 1 and 5 of both files, and the line-8 comment in `07_cap_A.sql`.

**The whole-file check now run before any committed run:**

- Every session, seed and cleanup file is run **as the whole file** against live, with its `COMMIT;` line swapped for `ROLLBACK;`.
- The fixture state is read before and after each file.
- **Session files** stop at **line 10** with `42P01 relation "race_out" does not exist`. That line is the final `SELECT … FROM race_out`, and the temp table is gone because of the `ROLLBACK`. So the error is a side effect of the swap. It proves lines 1–9, including the credit call, ran with no syntax or quoting error.
- **Cleanup** returned `cleaned`.
- **Seed** was checked at baseline before the fix round and returned `seeded`.
- **Verify and snapshot** are read-only and had already run as whole files.
- **No rows were written** by any of these checks.

The CAP control pair was then run on the existing seed. The real files keep their `COMMIT;` line.

### Seed script

`docs/hygiene/07_race/07_race_seed.sql`, full text:

```sql
-- 07 race seed (COMMITTED in the approved rounds). As postgres. Fixture ids are fixed literals (no fixture table).
-- Accounts (matched by id): A onboard_check1 81f83cdb, B onboard_check2 bc85514c (RACE-1);
--   A' onboard_check3 f0f43430, B' onboard_check6 30d543f1, X onboard_check4 ae240bb6 (CAP-RACE).
-- Teams: R 07070707-…-a1 (A, B), streak …-b1; S1 …-a2 (A', X), streak …-b2; S2 …-a3 (B', X), streak …-b3.
-- Aborts unless all five accounts are exactly at baseline (profile row md5s read 2026-10-29 16:44 UTC).
BEGIN;
-- BODY START
SELECT set_config('app.checkin_copy', '1', true);  -- fixture rows send no buddy push
DO $guard$
BEGIN
  IF (SELECT string_agg(md5(p::text), ' ' ORDER BY id) FROM public.user_profiles p
      WHERE id IN ('81f83cdb-e09b-4f1f-8045-afa0d3d2181e', 'bc85514c-02f2-4340-90f2-d95e3f62af26', 'f0f43430-80aa-4c38-8f87-c11226bef86f',
                   '30d543f1-bb06-41c4-8522-396ed948ba35', 'ae240bb6-e629-401e-9fb6-feb1ed21cee9'))
     IS DISTINCT FROM 'ceac7404e055d8f3de55f81945402aff 47582882a823e6f714a2bdb67877d831 efb30bff79736c2bc6f93052c341a62c e28694d729e229950b5d14f208db4e97 f549813160ebe131b16e6d5d109a3798'
     OR EXISTS (SELECT 1 FROM public.xp_transactions WHERE user_id IN ('81f83cdb-e09b-4f1f-8045-afa0d3d2181e', 'bc85514c-02f2-4340-90f2-d95e3f62af26', 'f0f43430-80aa-4c38-8f87-c11226bef86f', '30d543f1-bb06-41c4-8522-396ed948ba35', 'ae240bb6-e629-401e-9fb6-feb1ed21cee9'))
     OR EXISTS (SELECT 1 FROM public.coin_transactions WHERE user_id IN ('81f83cdb-e09b-4f1f-8045-afa0d3d2181e', 'bc85514c-02f2-4340-90f2-d95e3f62af26', 'f0f43430-80aa-4c38-8f87-c11226bef86f', '30d543f1-bb06-41c4-8522-396ed948ba35', 'ae240bb6-e629-401e-9fb6-feb1ed21cee9'))
     OR EXISTS (SELECT 1 FROM public.daily_team_checkins WHERE user_id IN ('81f83cdb-e09b-4f1f-8045-afa0d3d2181e', 'bc85514c-02f2-4340-90f2-d95e3f62af26', 'f0f43430-80aa-4c38-8f87-c11226bef86f', '30d543f1-bb06-41c4-8522-396ed948ba35', 'ae240bb6-e629-401e-9fb6-feb1ed21cee9'))
     OR (SELECT count(*) FROM public.team_members WHERE user_id IN ('81f83cdb-e09b-4f1f-8045-afa0d3d2181e', 'bc85514c-02f2-4340-90f2-d95e3f62af26', 'f0f43430-80aa-4c38-8f87-c11226bef86f', '30d543f1-bb06-41c4-8522-396ed948ba35', 'ae240bb6-e629-401e-9fb6-feb1ed21cee9')) <> 5
     OR EXISTS (SELECT 1 FROM public.invites WHERE accepted_by IN ('81f83cdb-e09b-4f1f-8045-afa0d3d2181e', 'bc85514c-02f2-4340-90f2-d95e3f62af26', 'f0f43430-80aa-4c38-8f87-c11226bef86f', '30d543f1-bb06-41c4-8522-396ed948ba35', 'ae240bb6-e629-401e-9fb6-feb1ed21cee9'))
     OR EXISTS (SELECT 1 FROM public.active_checkin_sessions WHERE user_id IN ('81f83cdb-e09b-4f1f-8045-afa0d3d2181e', 'bc85514c-02f2-4340-90f2-d95e3f62af26', 'f0f43430-80aa-4c38-8f87-c11226bef86f', '30d543f1-bb06-41c4-8522-396ed948ba35', 'ae240bb6-e629-401e-9fb6-feb1ed21cee9'))
     OR EXISTS (SELECT 1 FROM public.break_day_usage WHERE cancelled_at IS NULL AND break_date >= current_date - 1 AND user_id IN ('81f83cdb-e09b-4f1f-8045-afa0d3d2181e', 'bc85514c-02f2-4340-90f2-d95e3f62af26', 'f0f43430-80aa-4c38-8f87-c11226bef86f', '30d543f1-bb06-41c4-8522-396ed948ba35', 'ae240bb6-e629-401e-9fb6-feb1ed21cee9'))
     OR EXISTS (SELECT 1 FROM public.buddy_teams WHERE id IN ('07070707-0000-4000-8000-0000000000a1', '07070707-0000-4000-8000-0000000000a2', '07070707-0000-4000-8000-0000000000a3')) THEN
    RAISE EXCEPTION 'race07 seed: baseline changed; not seeding';
  END IF;
END $guard$;

INSERT INTO public.buddy_teams (id, team_name, team_emoji, is_coach_max_team, max_members, created_by) VALUES
  ('07070707-0000-4000-8000-0000000000a1', '07-race1', '💪', false, 2, '81f83cdb-e09b-4f1f-8045-afa0d3d2181e'),
  ('07070707-0000-4000-8000-0000000000a2', '07-cap-s1', '💪', false, 2, 'f0f43430-80aa-4c38-8f87-c11226bef86f'),
  ('07070707-0000-4000-8000-0000000000a3', '07-cap-s2', '💪', false, 2, '30d543f1-bb06-41c4-8522-396ed948ba35');
INSERT INTO public.team_members (team_id, user_id, role) VALUES
  ('07070707-0000-4000-8000-0000000000a1', '81f83cdb-e09b-4f1f-8045-afa0d3d2181e', 'member'),
  ('07070707-0000-4000-8000-0000000000a1', 'bc85514c-02f2-4340-90f2-d95e3f62af26', 'member'),
  ('07070707-0000-4000-8000-0000000000a2', 'f0f43430-80aa-4c38-8f87-c11226bef86f', 'member'),
  ('07070707-0000-4000-8000-0000000000a2', 'ae240bb6-e629-401e-9fb6-feb1ed21cee9', 'member'),
  ('07070707-0000-4000-8000-0000000000a3', '30d543f1-bb06-41c4-8522-396ed948ba35', 'member'),
  ('07070707-0000-4000-8000-0000000000a3', 'ae240bb6-e629-401e-9fb6-feb1ed21cee9', 'member');
INSERT INTO public.team_streaks (id, team_id, current_streak, longest_streak, is_active) VALUES
  ('07070707-0000-4000-8000-0000000000b1', '07070707-0000-4000-8000-0000000000a1', 0, 0, true),
  ('07070707-0000-4000-8000-0000000000b2', '07070707-0000-4000-8000-0000000000a2', 0, 0, true),
  ('07070707-0000-4000-8000-0000000000b3', '07070707-0000-4000-8000-0000000000a3', 0, 0, true);
-- X already checked in today on S1 and S2, and already has 90 coins of check-in payouts suffixed today (room 10).
INSERT INTO public.daily_team_checkins (team_streak_id, user_id, check_in_date, check_in_time) VALUES
  ('07070707-0000-4000-8000-0000000000b2', 'ae240bb6-e629-401e-9fb6-feb1ed21cee9', public._credit_day('ae240bb6-e629-401e-9fb6-feb1ed21cee9', now()), now()),
  ('07070707-0000-4000-8000-0000000000b3', 'ae240bb6-e629-401e-9fb6-feb1ed21cee9', public._credit_day('ae240bb6-e629-401e-9fb6-feb1ed21cee9', now()), now());
INSERT INTO public.coin_transactions (user_id, amount, transaction_type, description, reference_id) VALUES
  ('ae240bb6-e629-401e-9fb6-feb1ed21cee9', 90, 'daily_checkin', 'race07 seed (ledger only)',
   '07070707-0000-4000-8000-0000000000b2:seed:' || public._credit_day('ae240bb6-e629-401e-9fb6-feb1ed21cee9', now()));
-- BODY END
COMMIT;
SELECT 'seeded' AS s, now()::text AS at;
```

### Cleanup script

`docs/hygiene/07_race/07_race_cleanup.sql`, full text:

```sql
-- 07 race cleanup (COMMITTED in the approved rounds), as postgres, one transaction.
-- Baseline for the five accounts: 0 xp/coin transaction rows, 0 check-in rows, 5 team_members rows (their Coach Max
-- teams), profile row md5s as in the seed. So every transaction or check-in row they now have was written by the race.
-- Deletes them, deletes the 3 fixture teams (cascades members, streaks, streak_events), restores xp/coins/level,
-- then the guard aborts the WHOLE cleanup unless all five are back to the exact baseline.
BEGIN;
-- BODY START
DELETE FROM public.xp_transactions WHERE user_id IN ('81f83cdb-e09b-4f1f-8045-afa0d3d2181e', 'bc85514c-02f2-4340-90f2-d95e3f62af26', 'f0f43430-80aa-4c38-8f87-c11226bef86f', '30d543f1-bb06-41c4-8522-396ed948ba35', 'ae240bb6-e629-401e-9fb6-feb1ed21cee9')
  AND left(reference_id, 36) IN ('07070707-0000-4000-8000-0000000000b1', '07070707-0000-4000-8000-0000000000b2', '07070707-0000-4000-8000-0000000000b3');
DELETE FROM public.coin_transactions WHERE user_id IN ('81f83cdb-e09b-4f1f-8045-afa0d3d2181e', 'bc85514c-02f2-4340-90f2-d95e3f62af26', 'f0f43430-80aa-4c38-8f87-c11226bef86f', '30d543f1-bb06-41c4-8522-396ed948ba35', 'ae240bb6-e629-401e-9fb6-feb1ed21cee9')
  AND left(reference_id, 36) IN ('07070707-0000-4000-8000-0000000000b1', '07070707-0000-4000-8000-0000000000b2', '07070707-0000-4000-8000-0000000000b3');
DELETE FROM public.daily_team_checkins WHERE team_streak_id IN ('07070707-0000-4000-8000-0000000000b1', '07070707-0000-4000-8000-0000000000b2', '07070707-0000-4000-8000-0000000000b3');
DELETE FROM public.buddy_teams WHERE id IN ('07070707-0000-4000-8000-0000000000a1', '07070707-0000-4000-8000-0000000000a2', '07070707-0000-4000-8000-0000000000a3');
UPDATE public.user_profiles SET xp = 0, coin_balance = 0, level = 1
WHERE id IN ('81f83cdb-e09b-4f1f-8045-afa0d3d2181e', 'bc85514c-02f2-4340-90f2-d95e3f62af26', 'f0f43430-80aa-4c38-8f87-c11226bef86f', '30d543f1-bb06-41c4-8522-396ed948ba35', 'ae240bb6-e629-401e-9fb6-feb1ed21cee9');
DO $guard$
BEGIN
  IF (SELECT string_agg(md5(p::text), ' ' ORDER BY id) FROM public.user_profiles p
      WHERE id IN ('81f83cdb-e09b-4f1f-8045-afa0d3d2181e', 'bc85514c-02f2-4340-90f2-d95e3f62af26', 'f0f43430-80aa-4c38-8f87-c11226bef86f',
                   '30d543f1-bb06-41c4-8522-396ed948ba35', 'ae240bb6-e629-401e-9fb6-feb1ed21cee9'))
     IS DISTINCT FROM 'ceac7404e055d8f3de55f81945402aff 47582882a823e6f714a2bdb67877d831 efb30bff79736c2bc6f93052c341a62c e28694d729e229950b5d14f208db4e97 f549813160ebe131b16e6d5d109a3798'
     OR EXISTS (SELECT 1 FROM public.xp_transactions WHERE user_id IN ('81f83cdb-e09b-4f1f-8045-afa0d3d2181e', 'bc85514c-02f2-4340-90f2-d95e3f62af26', 'f0f43430-80aa-4c38-8f87-c11226bef86f', '30d543f1-bb06-41c4-8522-396ed948ba35', 'ae240bb6-e629-401e-9fb6-feb1ed21cee9'))
     OR EXISTS (SELECT 1 FROM public.coin_transactions WHERE user_id IN ('81f83cdb-e09b-4f1f-8045-afa0d3d2181e', 'bc85514c-02f2-4340-90f2-d95e3f62af26', 'f0f43430-80aa-4c38-8f87-c11226bef86f', '30d543f1-bb06-41c4-8522-396ed948ba35', 'ae240bb6-e629-401e-9fb6-feb1ed21cee9'))
     OR EXISTS (SELECT 1 FROM public.daily_team_checkins WHERE user_id IN ('81f83cdb-e09b-4f1f-8045-afa0d3d2181e', 'bc85514c-02f2-4340-90f2-d95e3f62af26', 'f0f43430-80aa-4c38-8f87-c11226bef86f', '30d543f1-bb06-41c4-8522-396ed948ba35', 'ae240bb6-e629-401e-9fb6-feb1ed21cee9'))
     OR (SELECT count(*) FROM public.team_members WHERE user_id IN ('81f83cdb-e09b-4f1f-8045-afa0d3d2181e', 'bc85514c-02f2-4340-90f2-d95e3f62af26', 'f0f43430-80aa-4c38-8f87-c11226bef86f', '30d543f1-bb06-41c4-8522-396ed948ba35', 'ae240bb6-e629-401e-9fb6-feb1ed21cee9')) <> 5
     OR EXISTS (SELECT 1 FROM public.buddy_teams WHERE id IN ('07070707-0000-4000-8000-0000000000a1', '07070707-0000-4000-8000-0000000000a2', '07070707-0000-4000-8000-0000000000a3'))
     OR EXISTS (SELECT 1 FROM public.team_streaks WHERE id IN ('07070707-0000-4000-8000-0000000000b1', '07070707-0000-4000-8000-0000000000b2', '07070707-0000-4000-8000-0000000000b3')) THEN
    RAISE EXCEPTION 'race07 cleanup: not back to baseline; whole cleanup rolled back';
  END IF;
END $guard$;
-- BODY END
COMMIT;
SELECT 'cleaned' AS s, now()::text AS at;
```

The session files (`07_race1_A/B.sql`, `07_cap_A/B.sql`), `07_race_verify.sql`, `07_snapshot.sql` and `gen_rehearsal.py` are in the same folder.

## Incident after the fix round: shell substitution while writing this report

**What happened.** At 16:57 UTC, my first attempt to generate this file passed the report text to Python through an **unquoted** shell heredoc. Bash therefore ran every backtick-quoted span in the text as a command substitution. Most of them were just words and failed with `command not found`. Two were real commands:

- **`supabase db push`.** Remote was already up to date (128 = 128), so nothing was applied.
- **`docs/hygiene/suite/run.sh`.** This is the suite, which runs only in transactions that abort.
  - Its client process hung after the server had finished. Live `pg_stat_activity` showed no active session from it.
  - I killed the local processes at about 17:02.

The report file was never written, and no stray files were created.

**Checked at 17:02:46:**

| Check | Result |
|---|---|
| `schema_migrations` | 128, head `20261029160000` |
| Dry run | "Remote database is up to date" |
| Function bodies | the md5 values listed above |
| Economy snapshot | equal to the post-fix baseline in 12 of 13 tables |

The one difference is a single `daily_team_checkins` row. It is Coach Max's bot check-in on a Coach Max team (streak `756acc69…`), created at 17:00:02 by the hourly `coach-max-cron` (cron job 1 at 17:00, succeeded). That is an external credit event, not from this work.

**Fix.** This file was written with the editor tool, and the scripts and diffs were filled in by a Python script passed through a quoted heredoc.

## Scope

Every changed SQL line traces to RACE-1, CAP-RACE, or the owner's Q1 and Q2 decisions:

- L0 in `finish_checkin_session` (Q1).
- `ORDER BY id FOR NO KEY UPDATE` in `reconcile_stale_streaks` (Q2). It re-checks a streak that was credited while the reset waited, so the reset no longer zeroes a streak that has just been credited.

No adjacent code was refactored:

- `_apply_checkin_rewards`, `submit_checkin` and `process_stale_sessions` are unchanged. Their bodies are pinned by G0.2.
- The client is untouched.

`gen_07.py` is in the suite commit, as you agreed.

### Not done (mentioned only)

- **Dead-code batch.**
  - `check_in_coach_max_with_buddy` and `award_checkin_rewards`. Neither has a caller. If either were revived, it would take L4/L5 without L2/L3.
  - From the earlier list: `LevelService.grantMilestoneUnlock`, the `pin_client_checkin_date` trigger, the `daily_team_checkins` INSERT policy, and the redundant client `recompute_team_streak` call at `coach_max_service.dart:285`.
- **coach-max-cron (P-5).** Its direct bot-row insert can still hit a unique violation against a credit's mirror insert in a small window.
- **CRON-ORDER.** Documented above, not changed.
