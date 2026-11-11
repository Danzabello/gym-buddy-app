# Prompt 07: reward/streak test suite, RACE-1 and CAP-RACE (Step 1 design, read-only)

Date: 2026-10-29. I read the live DB with `supabase db query --linked` (SELECT and catalog reads only). Nothing was written to the DB, and no SQL or migration has been written yet. The live head is `20261029010000` (Migration B), with 127 versions in `schema_migrations`, which matches the 127 local files. The function bodies quoted below were dumped from live today. Their md5 values are in §3.4.

## 1. Test harness

### 1.1 Findings

| Question | Answer |
|---|---|
| Why does `supabase db reset` fail? | The first migration, `20260621151208_s2_s3_server_authoritative_economy.sql`, fails at line 329 with `DROP POLICY IF EXISTS … ON public.daily_team_checkins`. `IF EXISTS` only covers the policy, so on an empty database the missing table is an error. The base tables (`daily_team_checkins`, `coin_transactions`, `user_profiles`, `team_streaks`, …) predate version control. Their DDL exists only in `docs/pre_vc_schema_baseline_20260720.sql`, which is reference-only. A replay cannot get past the first file. |
| Does a local stack run? | No. Docker is installed and the daemon is active, but `docker ps` returns `permission denied … /var/run/docker.sock`: the user is not in the `docker` group. Getting into the group needs `sudo usermod -aG docker` (an owner action). Even with Docker, `db reset` fails as above. A schema-only `supabase db dump` into a local stack would also need Docker, and it would not include `vault`, `pg_net`, `cron`, the `auth.users` rows the probes join on, or the test accounts. It would also drift from live from day one. |
| pgTAP? | Available on live (`pgtap` 1.2.0) but **not installed**. Installing it means a `CREATE EXTENSION` (about 1,000 functions) on the production database. That could be done inside a rolled-back transaction, but `supabase db query` returns only the last statement's result set, so pgTAP's row-per-assertion output would be lost anyway. |
| Live reads | Working (`supabase login` valid in this shell). |

### 1.2 Recommendation: plain SQL assertions on live, in one rolled-back transaction, run with one command

This is the harness the 05a–05d and check-in probes already use. I would harden it into a suite rather than add anything new:

- `docs/hygiene/suite/economy_suite.sql`: a single `DO` block. Each group runs inside its own `BEGIN … RAISE 'undo' (P0098) … EXCEPTION` sub-block, so every group starts from live state and groups cannot leak into each other. The block ends with `RAISE EXCEPTION E'SUITE_RESULTS\n…'`, so the whole transaction aborts **even if** a `ROLLBACK` line were missing. Nothing can commit by construction.
- The helpers are the existing ones from `checkin_rpc_probes.in.sql`: `pg_temp.u(uid, sql, role)` (JWT claims plus `SET LOCAL ROLE`), `ok`/`is`, `snap()`, and the `_send_push` stub that records into `pg_temp.push_log`, so no HTTP goes out.
- `docs/hygiene/suite/grants_fresh.sql`: the grant and denied-write checks. This file runs in its **own fresh connection**, and the first call in it is the authenticated or anon one (the CLAUDE.md rule on per-session plan caching). It also ends in `RAISE`.
- `docs/hygiene/suite/run.sh`: the one command. It runs both files with `supabase db query --linked -f`, extracts the `PASS`/`FAIL` lines, and prints `N PASS, M FAIL`. It exits non-zero on any FAIL, on a crash, or when no result lines come back. `run.sh --with <migration.sql>` inlines a not-yet-applied migration at the top of the transaction (the generator pattern from `gen_checkin_rpc.py`), so the same suite tests a migration before it is pushed. Run after the push, it tests what is live.
- It needs no branch, no Docker and no pgTAP, and nothing persists.

## 2. Suite scope

Every existing probe is folded into one group per function. The fixtures are the probe fixtures: test accounts matched by id, `rokitest1` 5e67f64d, `testtest1` cf4946f5, onboard_check1/2/3/4/6, and `mijotest3` f7c1ef63 only where 05c used it. onboard_check5 (19c3b618) and mijotest are never touched. Probes that only made sense once (05b/05c data deletions, 05c dry run) are dropped, and their *invariants* are kept as assertions (for example, "the dropped functions are still gone").

| Group | Assertions (source probes) |
|---|---|
| G1 `_credit_checkin` | Writes a row on each active team, `ON CONFLICT` is a no-op, `p_pay=false` pays 0, `p_streak_id` limits the credit to one team, `p_time` is stored, the break for the day is cancelled, the Coach Max mirror row is written, the return shape is right (checkin_rpc Q1–Q3, E.eq1). **New for 07:** the advisory locks for streaks and caps are held after the call (`pg_locks`). |
| G2 `submit_checkin` | The copy condition (a partner with a real row today is copied, a member with no row today is not), local day rather than UTC (Kiritimati fixture), a copy keeps the source's earliest `check_in_time`, the `app.checkin_copy` flag gives no push and is cleared after the call, copies pay 0, a second call returns `already_checked_in`, the return shape has no `milestones_unlocked` (Q1.1–Q3.6). |
| G3 `finish_checkin_session` | FIN-1: `too_early`, `nothing_to_finish`, the 3h30 / 3h40 windows, leavers, and a second Finish (05d, checkin_rpc Q1.10–Q1.15). M6a partner credit uses the partner's local day. The return shape is the installed build's. |
| G4 `_auto_credit` / `process_stale_sessions` | An auto-complete is credited once (dedup through `workout_logs.auto_completed`). The body md5 of `process_stale_sessions` is pinned, and so is its comment pointing at `_credit_day` (E.eq3, C7). |
| G5 `_apply_checkin_rewards` | Base, coop and milestone amounts. Caps: CAP-2 (CAP.1–5: yesterday, today, legacy suffix, straddle, teammate cap). CAP-1: retro dedup by `reference_id`. |
| G6 `create_invite_team` / `_fulfil_invite_reward` (F3) | Nothing is paid at join, the first credited day pays exactly one 20-coin bonus, a second day or a second inviter pays nothing, an account created before the invite is never paid (F3.1–5), and the inviter's reward still needs 2 or more distinct days. |
| G7 `purchase_shop_item` | The `FOR UPDATE` lock is present, insufficient funds is refused, the `coin_balance` CHECK holds (`23514`), ACL, search_path (05d F2, 05e C2). |
| G8 `verify_achievement_progress` | Replay: on a fixture with a known `best_streak`, the call unlocks exactly the expected achievements once, and a second call pays nothing. |
| G9 grants (fresh connection) | Direct INSERT on `daily_team_checkins` gives `42501` (B1, B4). `UPDATE coin_balance` and `rest_tokens_available` give `42501` (05d F2/F3, 05e C1). Direct writes to `xp_transactions`, `coin_transactions`, `team_streaks` and `user_unlocked_cosmetics` give `42501` or are filtered by RLS (05a, 05a2). anon cannot execute any economy function. authenticated cannot execute the internal helpers (`award_xp`, `award_coins`, `_apply_checkin_rewards`, `_credit_checkin`, `_credit_day`, `check_in_coach_max_with_buddy`, `award_checkin_rewards`, the new `_lock_credit`) (05b S3, checkin_rpc C1–C5). The ACL, `SECURITY DEFINER` and `search_path` matrix of every function above is pinned against a literal expected table. |
| G10 equivalence | See §5. |

The check-in probes stay byte-for-byte where the function did not change. I expect about 90 assertions in total.

## 3. Lock order

### 3.1 The two races, re-confirmed in the live bodies

- **RACE-1.** `_credit_checkin` inserts the caller's row, then calls `_recompute_team_streak`, which reads `team_streaks` **without a lock** and checks the AND-gate against its own snapshot. Two teammates crediting at the same instant each miss the other's uncommitted row, so both get `day_incomplete` and the streak row is never updated. The next day's credit then sees a 2-day gap and resets the streak to 1, so RACE-1 costs a streak, not only a day.
  - A **Coach Max variant** exists. `coach-max-cron` inserts the bot's row in one request and calls `recompute_team_streak` in a second request. That recompute does not see the user's uncommitted row, and the user's recompute may not see the bot's row.
- **CAP-RACE.** The only reward lock is `pg_advisory_xact_lock(hashtext('checkin_rewards:' || streak || ':' || day))`. Teammate X, credited retroactively on streak S1 by A and on S2 by B at the same time, has their cap read twice under two different locks, so X ends up one payout over 100 coins / 1000 xp.

### 3.2 Fixed global order

Every credit transaction takes locks only in this level order. Within a level, locks are taken in ascending key order, in **one statement per transaction**, before anything in a later level.

| Level | Lock | Key order | New? |
|---|---|---|---|
| L0 | `workouts` row `FOR NO KEY UPDATE` (Finish with `p_workout_id` only) | one row | **Q1 below** |
| L1 | `active_checkin_sessions` row(s) | Finish: the caller's own; cron: `SKIP LOCKED` batch, then `ORDER BY id FOR UPDATE` | existing |
| L2 | `team_streaks` rows `FOR NO KEY UPDATE` | streak id ascending | **new (RACE-1)** |
| L3 | `pg_advisory_xact_lock(hashtext('checkin_cap'), hashtext(user_id::text))`, paying credits only. This is the two-key form, so it is a separate lock space from the single-key CAP-1 lock. | lock key ascending (`hashtext(user_id::text)`), so two users whose ids hash to the same key still cannot form a cycle | **new (CAP-RACE)** |
| L4 | `checkin_rewards:<streak>:<day>` advisory (CAP-1) | per streak | existing, unchanged |
| L5 | row writes: `daily_team_checkins` unique key, `break_day_usage`, `user_profiles` (award_xp/coins), transaction rows, `invites FOR UPDATE` (trigger T2), `coach_max_schedule`, `workout_logs` | n/a | existing |

Why these choices:

- **`FOR NO KEY UPDATE`, not `FOR UPDATE`.** It is the same lock the existing `UPDATE team_streaks` in `_recompute_team_streak` takes, so a transaction never upgrades a lock it already holds. It also does not conflict with the `FOR KEY SHARE` that every FK-checked insert into `daily_team_checkins` takes on the parent streak. `FOR UPDATE` would conflict with that, which is the classic child-insert-then-lock-parent deadlock.
- **L3 per user, not per user per day.** The cap sums are per credit day, so a per-day key would be enough for correctness. A per-user key also orders the `user_profiles` row locks that `award_xp`/`award_coins` take in L5. With a per-day key, two credits for the same teammate on two different credit days (this happens near midnight across time zones) could take X's and Y's profile rows in opposite orders. The cost is that two credits sharing a teammate serialise for a few milliseconds even on different days. Your example said "per-user-per-day". This is the one place I deviate, and the alternative is a single word.
- **L3 covers the non-bot members of every L2 streak**, taken before the first insert. `_apply_checkin_rewards` pays the primary and the teammates who have a row on that streak for that day. All of them are members of the locked streaks (§3.5 edge 3).
- **L4 never waits any more** on live paths. Every caller of `_apply_checkin_rewards` already holds L2 for that streak. It stays as it is, and so does `_apply_checkin_rewards` (no change).

### 3.3 Every function that takes any of these locks, and what changes

| Function | Today | After 07 | Change |
|---|---|---|---|
| `_lock_credit(p_users uuid[], p_pay boolean, p_streak_id uuid DEFAULT NULL)` **(new, internal)** | n/a | L2: one `PERFORM … FROM team_streaks ts JOIN team_members … WHERE tm.user_id = ANY(p_users) AND ts.is_active [AND ts.id = p_streak_id] ORDER BY ts.id FOR NO KEY UPDATE OF ts`. Then, if `p_pay`, L3 in a `FOR` loop over the distinct non-bot members of those streaks, ordered by id. | about 20 lines. Not SECURITY DEFINER, `search_path=public`, EXECUTE service_role only (revoked from PUBLIC, anon, authenticated). |
| `_credit_checkin` | L5 then recompute (unlocked read), L4 inside rewards | `PERFORM public._lock_credit(ARRAY[p_user_id], p_pay, p_streak_id);` as its first statement | +1 line |
| `_recompute_team_streak` | first `SELECT … FROM team_streaks` unlocked | the same SELECT gets `FOR NO KEY UPDATE`. A no-op for callers that already hold L2. For `coach-max-cron`'s and the client's `recompute_team_streak`, it makes the recompute wait for an in-flight credit and then see its row, which closes the Coach Max variant. | +1 line |
| `finish_checkin_session` | L1 (own session), then caller credit, then partner credit (M6a): two separate lock groups | before the first `_credit_checkin`: `PERFORM public._lock_credit(CASE WHEN v_wk_ok THEN ARRAY[v_uid, v_wk.user_id, v_wk.buddy_id] ELSE ARRAY[v_uid] END, true);`. The union of both users' L2 and L3 is taken once and in order (NULL buddy is ignored). The two later `_credit_checkin` calls then re-take locks already held (no-ops). | +1 line, plus L0 if Q1 = yes (+3 lines) |
| `check_in_coach_max` | `_finish_coach_max_checkin` inserts the bot row (plain INSERT, no `ON CONFLICT`), then recomputes | L2 on its Coach Max streak right after the streak lookup, **before** the `already_done` check | +1 line. **Required** once `_recompute_team_streak` locks: without it, check_in_coach_max inserts the bot row and then waits in recompute, while a concurrent credit holding L2 waits on that bot row's unique key, which is a deadlock. With it, the two serialise and the loser sees `already_done`, or the credit sees the bot row and skips the mirror. |
| `reconcile_stale_streaks` (cron `:05` hourly; this is "the 23:05 nightly reset") | `UPDATE team_streaks` row by row in scan order | its loop query gets `ORDER BY id`, so its L2 locks ascend like everyone else's | +1 line (see Q2) |
| `submit_checkin` | loop `ORDER BY ts.id, m.user_id`; each copy calls `_credit_checkin(…, p_pay=false, p_streak_id)` | unchanged. Its L2 locks already ascend one streak per call, and copies pay nothing, so it takes no L3. | none |
| `process_stale_sessions` → `_auto_credit` → `_credit_checkin` | several users per cron transaction | unchanged. Each `_auto_credit` takes its user's L2 and L3 group through `_credit_checkin`. | none (residual §3.5) |
| `_finish_coach_max_checkin` | bot row insert, then recompute | unchanged. Every live caller now holds L2 first. | none |
| `_apply_checkin_rewards` | L4, then L5 | unchanged (L2 and L3 are held by its callers) | none |
| `coach-max-cron` Edge Function | direct bot insert (autocommit), then a separate `recompute_team_streak` request | unchanged. The insert holds nothing afterwards, and the recompute takes a single L2. | none |
| `check_in_coach_max_with_buddy`, `award_checkin_rewards` | service_role only, **no caller** | unchanged. Dead-code batch: either one, if ever called again, would take L4/L5 without L2/L3. | none, mentioned |
| `purchase_shop_item`, `create_buddy_team`, `ensure_coach_max_team`, `accept_invite`, `create_invite_team` | one `user_profiles` row, or pair/team advisory, or `invites` row | none of them takes L2 or L3, and each holds a single lock group | none |

Public signatures, return shapes, payout amounts, cap values (1000 xp / 100 coins) and the credit-day rules are untouched. The functions replaced are `_credit_checkin`, `_recompute_team_streak`, `finish_checkin_session`, `check_in_coach_max` and `reconcile_stale_streaks`. The only new function is `_lock_credit`.

### 3.4 Live md5 values today (`md5(pg_get_functiondef)`; the rollback restores these)

```
_credit_checkin          6b96429f2c9bd74af229aeca79541bb0
_recompute_team_streak   d924df92c84adc0fe82b2e80ec5577cb
finish_checkin_session   74eee93e25530e4071bc1cd4ccf15e4a
check_in_coach_max       93d0cd778b8e863ad490e34c5af26ce6
reconcile_stale_streaks  124947b1c46d74fc7bb859b520ec23a1
_apply_checkin_rewards   47185fcbc9c873ef46ebdce0bdde70f6   (not replaced; pinned by the suite)
process_stale_sessions   929c250cf1b7e98ad9c9d593d786ba32   (not replaced; pinned)
submit_checkin           acc63cafafd56afa8a0ebd7503510739   (not replaced; pinned)
```

### 3.5 Deadlock analysis

**Rule:** a transaction that takes all of its L2 and then all of its L3 in one ascending pass cannot be part of a cycle on L2/L3 with another such transaction. For a cycle, one side would have to hold a higher key while waiting on a lower one, and an ascending pass never does that. L4 is now uncontended. L5 rows are touched only while the L3 lock of every member whose profile they belong to is held (edge 2 is the exception).

| Pair | Result |
|---|---|
| Two teammates crediting at once (RACE-1) | Both take L2 on the shared streak, so the second waits. Its next statements see the first's committed row, the day completes, it pays, and the first gets its retro share. **Fixed.** |
| Teammate X paid on S1 and S2 at once (CAP-RACE) | Both take L3(X), so the second waits and its cap sums see the first's payout. **Fixed.** |
| Finish with partner (M6a) against the partner's own sync, Finish or cron credit | The Finish locks the union of both users' L2 and L3 in one pass, so there is no cycle. |
| A user credit against `coach-max-cron` | The cron insert autocommits. Its recompute takes a single L2, waits, and then sees the user's row. **Fixed (Coach Max variant).** |
| A user credit against `check_in_coach_max` | Both take L2 first. **No cycle** (and the existing unique-violation error on the bot row goes away). |
| A user credit against `reconcile_stale_streaks` | Both lock streaks in ascending order, so there is no cycle (needs the `ORDER BY`). |

**Residual cycles (not introduced by 07, and Postgres detects them):** Postgres aborts one side with `40P01` after `deadlock_timeout` (1 s), and nothing is half-written.

1. **Two buddies pressing Finish on the same shared workout at the same instant.** This is pre-existing, and the 10/28 design (§10) understated it. Today, each Finish holds its own session row (L1) and inserts its own rows, then its M6a step inserts the partner's rows and deletes the partner's session. Each waits on the other, which is a **deadlock today**. The 07 union lock alone does not fix this, because both already hold an L1 session row before L2. **L0 fixes it:** lock the `workouts` row before the session SELECT, so the second Finish waits, then sees its session deleted and its rows present, and returns a normal result with `checked_in: 0`. See **Q1**.
2. **Trigger-paid invite bonuses.** `_fulfil_invite_reward` can lock the `user_profiles` row of an **inviter who is not a member** of any locked streak (L5 outside L3). A cycle needs two such payments crossing over two inviters at the same instant. I consider it theoretical.
3. **A former member** (left the team but still has a row for that day) is paid without L3. This is the same exposure as today, and only for that person.
4. **CRON-ORDER** (owner decision 2026-10-29: keep L0, leave `process_stale_sessions` untouched). `process_stale_sessions` takes session rows first (`SKIP LOCKED` batch, then the partners' sessions `FOR UPDATE`) and only then updates the `workouts` row. That is the reverse of L0. `finish_checkin_session` (with L0), `im_here`, `leave_workout`, `complete_workout`, `go_solo`, `cancel_workout`, `cant_make_it`, `change_workout_time` and `nudge_workout` all lock the workout first (`_hs_lock`). The order is **pre-existing**: the cron already has it against `complete_workout` and `leave_workout`. It is **narrow**: a cycle needs a Finish (or a handshake call) on a shared workout during the same cron run that auto-completes that workout at 3h30. And it is **harmless on failure**: Postgres aborts one side with `40P01`, nothing is half-written, and the cron retries 5 minutes later.
5. **`process_stale_sessions`** credits several users in one transaction, one ordered group per user. A cycle needs the cron to credit U1 and then U2 while a client credit by someone who shares teams with both runs at the same instant. If the cron is the victim, the whole run rolls back (pushes go through `pg_net`'s transactional queue, so they roll back too) and the next run 5 minutes later retries. If the client is the victim, the Finish returns an error and a retry succeeds. Making it fully ordered would mean restructuring the cron loop, which is out of scope.

## 4. Concurrency test plan (committed rows; not run until you approve)

The 05e RACE-2 shape: a baseline, a guarded seed, two sessions as separate `supabase db query --linked -f` processes started from **two explicit commands** (not a `&` line that also sets a variable, the 05e attempt-1 mistake), a read-only verify, a guarded cleanup, and hash comparison.

**Accounts** (all have 0 xp, 0 coins, level 1, Europe/Dublin, 1 active streak each, 0 accepted invites as invitee, 0 breaks, 0 sessions, as read today):

- RACE-1: onboard_check1 `81f83cdb-e09b-4f1f-8045-afa0d3d2181e` (A) and onboard_check2 `bc85514c-02f2-4340-90f2-d95e3f62af26` (B).
- CAP-RACE: onboard_check3 `f0f43430-80aa-4c38-8f87-c11226bef86f` (A'), onboard_check6 `30d543f1-bb06-41c4-8522-396ed948ba35` (B'), and onboard_check4 `ae240bb6-e629-401e-9fb6-feb1ed21cee9` (X).
- Not used: onboard_check5, mijotest, mijotest3, rokitest1, testtest1, newesttest.

**Call:** `public._credit_checkin(<user>, now(), true, now(), <fixture streak id>)` as `postgres`. This is the function where both races live, and `p_streak_id` keeps the credit off each account's real Coach Max team. A Finish-path test would need a session started 15 or more minutes earlier, which means backdating, so it is not done. The Finish union lock is covered by the suite (G1/G3 `pg_locks`) and by the L0 decision. Each session sets `app.checkin_copy = '1'` (transaction-local), so `notify_buddy_checkin` sends no push. A 0→1 streak fires no `notify_streak_update` push (that trigger only fires at 0 or at 7/14/30/50/100).

**Seed** (`07_race_seed.sql`, one transaction as postgres). It aborts unless all five accounts still have the baseline shape above, with no rows on any `07`-named team:

- RACE-1: `buddy_teams` R (team_name `07-race1`, not Coach Max), with `team_members` A and B, and `team_streaks` R (`current_streak` 0, `is_active`).
- CAP-RACE:
  - teams S1 (A', X) and S2 (B', X), each with its members and an active streak at 0;
  - X's `daily_team_checkins` rows on S1 and S2 for X's local today (inserted with the copy flag on; the pin trigger skips postgres; X has no invites, so T2 pays nothing);
  - one `coin_transactions` row for X: 90 coins, `daily_checkin`, `reference_id = '<S1 id>:seed:<today>'`. The suffix after the last colon is today, so the cap counts it. The ledger row only: `coin_balance` is not touched.
- All fixture ids are generated in the seed and written to a one-row table, `public._race07_fixture`, created and dropped by the scripts with RLS enabled and every client grant revoked. The other scripts read the ids from there, so nothing is matched by name.

**Sessions:**

| | Session 1 (t=0) | Session 2 (t≈2 s) |
|---|---|---|
| RACE-1 | `_credit_checkin(A, …, R)`, then `pg_sleep(8)`, then COMMIT | `_credit_checkin(B, …, R)`, then COMMIT |
| CAP-RACE | `_credit_checkin(A', …, S1)`, then `pg_sleep(8)`, then COMMIT | `_credit_checkin(B', …, S2)`, then COMMIT |

Each records `clock_timestamp()` before and after the call and the jsonb result.

**Expected, before the fix (control):**

- RACE-1: B waits about 0 s. Both results show `updated:false`, R stays at `current_streak` 0, and no payouts are written.
- CAP-RACE: B' waits about 0 s. X's coins suffixed today total **110**.

**Expected, after the fix:**

- RACE-1: B waits about 6 s. B's result shows `updated:true, new_streak:1`. R is at 1 with `last_workout_date` today. B is paid 15 xp / 15 coins (base + coop), and A is retro-paid 15 / 15.
- CAP-RACE: B' waits about 6 s. X's coins suffixed today total exactly **100**. X's second retro rows exist with amount 0, which the existing code writes to record that the payout was considered.

**Cleanup** (`07_race_cleanup.sql`, one transaction as postgres; it aborts and rolls back unless the end state equals the baseline):

1. Delete `xp_transactions` and `coin_transactions` rows whose `user_id` is one of the five ids **and** whose `reference_id` starts with a fixture streak id. The baseline has 0 transaction rows for all five, so this is everything they gained.
2. Delete `daily_team_checkins` on the fixture streaks.
3. Delete the fixture `buddy_teams`. This cascades to `team_members`, `team_streaks` and `streak_events`. `workout_logs.team_id` is `NO ACTION`, but the fixture writes no logs.
4. Restore `xp`, `coin_balance` and `level` of the five profiles to the baseline values captured in the seed.
5. Drop `_race07_fixture`.
6. Guard: the five full `user_profiles` rows have the same md5 as at baseline, and there are 0 transaction rows, 0 check-in rows and 0 `07` teams for the five.

The economy snapshot (`checkin_rpc_snapshot.sql`, which excludes mijotest's rows and streak d557efec) is taken at baseline, after the cleanup of each round, and around the migration push. It must be identical. I would also add `buddy_teams` and `team_members` counts to the snapshot for this run.

**Rounds.** I recommend two committed rounds:

1. The **control round** against today's live bodies, to prove the test can fail. Cleanup and hash check follow.
2. The **fix round** after the migration is pushed. Cleanup and hash check follow.

That is 4 committed credit calls per round. See **Q3**.

**When:** outside 22:55–23:15 UTC and away from `:00` (coach-max-cron) and `:05` (reconcile). `process_stale_sessions` (every 5 minutes) cannot see the fixture: no sessions, no workouts.

**What could go wrong:**

| Risk | Mitigation |
|---|---|
| A session errors or the shell drops one session (the 05e attempt-1 mistake) | The verify detects a missing result. The cleanup is keyed on fixture ids and is the same for partial runs. Repeat only after the cleanup and hash check pass. |
| Level-up or `updated_at` changes on profiles | Step 4 of the cleanup restores xp, coins and level. `user_profiles` has no `updated_at` trigger (its only triggers are tz validation and the delete scrub), and the full-row md5 guard catches anything else. |
| A push reaches a test device | `notify_buddy_checkin` is suppressed by the flag, and no streak milestone is reached. None of the five accounts is signed in on the owner's phone. |
| `_fulfil_invite_reward` pays an inviter | All five have 0 accepted invites as invitee, and the seed guard aborts if that changes. |
| The cron touches the fixture | reconcile skips streaks with `current_streak = 0` or `last_workout_date = today`, and the run is scheduled away from `:05`. |
| An 8 s lock hold blocks real users | L2 and L3 are taken on fixture streaks and the five test accounts only. |
| A deadlock inside the test | It cannot happen with these lock sets. If one appears, it is a finding, cleanup still runs, and I report it. |
| hashtext collision on an L3 key | The only effect is extra waiting. |
| Clock or tz rollover during the run | The run happens well away from Dublin midnight. The seed and cleanup use the stored ids, not dates. |

## 5. Proving no single-session behaviour change

- **Equivalence probe** (the checkin_rpc E.eq pattern, inside the suite's transaction). Phase 1 runs **today's live bodies** on the fixtures, with each fixture captured and then rolled back in a sub-block. The migration is then inlined, and phase 2 runs the new bodies on the identical fixtures. The `snap()` comparison covers return values, check-in rows (team, user, date, time), streaks, the xp/coin rows (amount, type, description, reference), profiles, `workout_logs`, cancelled breaks, sessions and pushes. Fixtures:
  - eq1: a normal Finish;
  - eq2: a partner credit (M6a);
  - eq3: a stale auto-complete through `_auto_credit`;
  - eq4: the CAP-2 cases;
  - eq5: a `submit_checkin` copy;
  - eq6: `check_in_coach_max`;
  - eq7: `reconcile_stale_streaks` on a broken and an intact fixture streak.
- **Expected: all seven byte-identical.** Unlike Migration A, there is no intended difference, because a lock never changes what a single session computes.
- **Body diffs.** For each of the five replaced functions, the diff against the dump has to be exactly the lock lines listed in §3.3, and the generator asserts this with count-checked replacements. The rollback test applies the migration and then the rollback in one transaction, and checks that all five bodies md5-match §3.4 with the original ACLs and search_path, and that `_lock_credit` is dropped.

## 6. Step 2 deliverables (after approval)

1. Migration `20261029xxxxxx_credit_lock_order.sql` and `docs/rollback_<version>.sql`, which restores the five bodies exactly as dumped on 2026-10-29 with their grants and drops `_lock_credit`. EXECUTE grants are re-stated for every replaced client-facing or definer function, and search_path is pinned.
2. Before the push: the suite with `--with` the migration (PASS everywhere), the equivalence probe, the rollback test, the `schema_migrations` check (127 = 127, head `20261029010000`), a dry run, then the control race round.
3. `supabase db push`. Then md5 parity of `statements` against the local file, the security and performance advisor diff, the snapshots, the fresh-session grants file, the suite against live, and the fix race round.
4. Commits: the migration with its rollback; the suite (with `run.sh`); the report `07_report.md`. They are separate, plain, carry no trailers, and are not pushed.

## 7. Questions

- **Q1. L0 workout-row lock in `finish_checkin_session`?** It fixes the pre-existing deadlock where two buddies press Finish at once on one shared workout (§3.5, residual 1): 3 lines at the top of the function. Without it, that case stays a 40P01 for one of the two. The loser's credit is still written by the winner's M6a step, but the loser sees an error. **Recommend yes.** It traces to the lock order, but it fixes a deadlock that 07 did not introduce, so I am asking.
- **Q2. `reconcile_stale_streaks` lost update.** Its loop reads `current_streak` and `last_workout_date` without a lock and then runs `UPDATE … SET current_streak = 0 WHERE id = …`. If a credit advances the streak while the reset is waiting on it, the reset still zeroes the streak that was just credited. That is a separate race, neither RACE-1 nor CAP-RACE. The fix is to change the loop query from `ORDER BY id` to `ORDER BY id FOR NO KEY UPDATE`, which re-checks `last_workout_date < today` on the locked row. **Include it in this migration, or leave it for later?** The `ORDER BY id` part is needed for the lock order either way.
- **Q3. Control round:** run the race test against today's bodies first, to prove it fails without the fix (recommended), or only the fix round?
- **Q4. L3 key:** per user (recommended, §3.2) or per user per day, as in your example?

## 8. Mentioned, not touched

- Dead-code batch, adding to the existing list:
  - `check_in_coach_max_with_buddy` and `award_checkin_rewards`. Neither has a caller, and both would bypass L2/L3 if revived.
- coach-max-cron: there is still a small window where its direct bot insert races a credit's mirror insert and gets a unique violation (P-5, pre-existing).
- `process_stale_sessions` multi-user ordering (§3.5, residual 4).
