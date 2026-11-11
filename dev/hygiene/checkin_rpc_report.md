# Single server check-in RPC: report

Date: 2026-10-28 (UTC). Spec: `docs/hygiene/checkin_rpc_design.md` (703d054) plus the owner's Step 2 message, which takes precedence where the two differ.

## Result

Every check-in credit now goes through one server path, and clients can no longer insert check-in rows.

- **One credit function.** `finish_checkin_session` (Finish), `process_stale_sessions` (auto-complete) and the new `submit_checkin` (sync) all credit through `_credit_checkin`.
- **One date rule.** That function derives the date only through `_credit_day` (Rule 1: the user's local day at the session or workout start).
- **No client inserts.** The app no longer inserts check-in rows, and Migration B removed `authenticated`'s INSERT on `daily_team_checkins`.
- **Honor system unchanged.** Tapping Check In still counts. No proof of workout was added.

| Commit | What |
|---|---|
| 703d054 | Design doc with owner decisions |
| e9eeb60 | Migration A `20261028230000_single_server_checkin` (applied), rollback, live backups, generator, probes and probe output |
| 579634c | Client: the three direct inserts replaced by `TeamSyncService.syncAllTeamsCheckIns` → `submit_checkin` |
| 7b74661 | Client: sync snackbar shows "Check-ins synced" with no count (the build that was device-checked) |
| 431285a | Migration B `20261029010000_revoke_client_checkin_insert` (applied), rollback, post-apply probe |
| (this) | Report |

Nothing is pushed. No commit carries attribution trailers.

## Items closed

| Item | How |
|---|---|
| A-3 / F1 | The three client inserts are gone (`team_sync_service.dart:106`, `friend_service.dart:250`, `:261`). Migration B revokes INSERT, so a direct insert is now `42501`. |
| A-1 | `_recompute_team_streak` stays the only streak writer, and every human check-in row is now written by the server. Coach Max's cron row is service_role and out of scope (P-5). |
| DI-9 / FS-2 | The partner's row is created server-side by `submit_checkin`, but only when the partner already has a real row for their own local today (probe Q1). |
| DI-5 | The `Future.delayed(100ms)` and `_backfillTodaysCheckIns` are deleted. |
| FS-1 | Copies use each member's local day through `safe_user_tz` (probe Q2: Kiritimati 2026-10-29 while UTC was 2026-10-28). |
| CAP-2 | The cap counts payouts by credit day, using an exact match on the `reference_id` suffix (probes CAP.1–5, E.eq4). |
| workout_date | No change (owner decision Q1). The credit day was already server-derived from the session or workout start, and `_credit_day` now holds that rule in one place. |
| MILE-1 | Closed as moot (owner decision Q4b). There is no server grant. `LevelService.grantMilestoneUnlock` goes to the dead-code batch. |
| F3 | `create_invite_team` no longer pays at join. `_fulfil_invite_reward` pays the invitee 20 coins once per account, on its first credited row (probes F3.1–5). |

## Deviations from the design doc

1. `_credit_checkin` has a fifth parameter, `p_streak_id uuid DEFAULT NULL`. It limits a copy to one team, so `submit_checkin` writes a member's row only onto teams the caller shares with that member (§3 copy condition). Without it, copying a partner would also touch the partner's other teams. Live has exactly one overload: `_credit_checkin(uuid, timestamptz, boolean, timestamptz, uuid)`, EXECUTE `{postgres, service_role}` only (PUBLIC, anon and authenticated: false).
2. `lib/home_screen.dart:4143` changed by one line: the sync snackbar now shows the service's message ("Check-ins synced"). The per-team `updated` flag in the RPC result means "this team's streak advanced", not "a row was copied". Counting it would hide the snackbar when a copy lands but the day isn't complete yet, and would show a wrong number otherwise. The neutral wording needs the text to come from the service.
3. Test accounts: `mijotest3` exists. It is `f7c1ef63-3b93-401d-b2bb-8402ddf9a881` in both `auth.users` and `user_profiles`, with username NULL and display_name `mijotest3`. My earlier "does not exist" was wrong because I searched by username. The onboard accounts are `onboard_check1`…`6`, with the ids listed in the session log. The probes used rokitest1, testtest1, onboard_check1–4 and onboard_check6, all matched by id. The device check used onboard_check5.
4. `claude/Fix Tracker.md` is not on this machine. FS-1, FS-2 and CAP-2 follow the planner prompt's wording.

## Migration A (20261028230000), applied 22:56 UTC

### What it contains

- `_credit_day(uuid, timestamptz)`: the one credit-day formula. `process_stale_sessions` gets a `COMMENT` pointing at it, because its inline "already credited?" guards repeat the formula. Its body is unchanged (md5 `929c250c…` before and after).
- `_credit_checkin(...)`: replaces `_server_checkin` (dropped). The loop and body are the same, plus `p_time`, `p_pay` and `p_streak_id`, and it returns per-team results and xp/coins.
- `finish_checkin_session` and `_auto_credit`: only the credit-day and credit call lines changed. The public signatures are unchanged.
- `_apply_checkin_rewards`: CAP-2.
- `submit_checkin()`: SECURITY DEFINER, `search_path=public`, `auth.uid()` only, EXECUTE for authenticated only.
- `notify_buddy_checkin`: returns early when the transaction-local flag `app.checkin_copy = '1'`. Nothing else changed.
- `create_invite_team` and `_fulfil_invite_reward`: F3.

### Apply evidence

- Dry run: "Would push 20261028230000 only". `schema_migrations` had 125 remote versions against 126 local, the only local-only version was ours, nothing was remote-only, and ours sorts after `20261013020000`.
- Applied with `supabase db push`. Afterwards, the dry run says "Remote database is up to date".
- md5 parity, `schema_migrations.statements` against the local file, whitespace and `;` normalised (the same method reproduces 05d's `ea760c0e…`): `20261028230000` remote=`621ad68bc60544182b122eba3fd9bdd1` local=`621ad68bc60544182b122eba3fd9bdd1`, **MATCH**.
- Fresh-session probe (`checkin_rpc_fresh_probe.sql`, authenticated or anon only): **4/4 PASS**.
  - authenticated `submit_checkin` → `not_checked_in_today`;
  - authenticated `_credit_checkin` and `_credit_day` → 42501;
  - anon `submit_checkin` → 42501.

### Economy hashes, Migration A

`checkin_rpc_snapshot.sql` excludes mijotest's rows and the Coach Max test streak d557efec. Both snapshots were taken before the 23:05 UTC reset, at 22:56:36 and 22:56:38. They are **identical**:

```
daily_team_checkins        5531 d04ec697862996f7bb2ed85869683c5e
workout_logs                 10 29969b3d844d7568dde7bfe7332898f6
xp_transactions              73 362c102a8a62e2c9b2c30fe25fd29796
coin_transactions            62 78ca920e56f17e205de18ebc6ade5daf
team_streaks                 48 d980c67d47ac984d144ffeca4ef09a96
user_profiles_xp_coins       47 02287c3ee37df2dd4a9ea8d035fc5441
workouts                     24 de8bb702eb837883d9170f9dec066ea2
invites                       7 c366bcb7ea899e30148bfe1b66ac01ae
user_unlocked_cosmetics       0 d41d8cd98f00b204e9800998ecf8427e
```

### Security advisor diff

| Lint | Before A | After A | After B |
|---|---|---|---|
| authenticated_security_definer_function_executable (WARN) | 35 | 36 | 36 |
| rls_enabled_no_policy (INFO) | 4 | 4 | 4 |
| auth_leaked_password_protection (WARN) | 1 | 1 | 1 |

The only new finding is `public.submit_checkin()`, which is intended: it is the client RPC. Nothing was removed, and B changed nothing.

## Probes (one transaction, ROLLBACK)

`docs/hygiene/checkin_rpc_probes.sql` is generated from `checkin_rpc_probes.in.sql` with Migration A inline. Full output is in `docs/hygiene/checkin_rpc_probe_output.txt`.

**Result: 56 PASS, 0 FAIL.** (The first run had one probe-side bug, a `te` alias clashing with a plpgsql variable. It was fixed and the whole set re-run.)

`_send_push` was stubbed inside the transaction to record calls, so no HTTP went out. Test accounts were matched by id. Credit functions ran only inside the rolled-back transaction, and `workout_started_at` was never backdated: the partner fixture's workout starts at `now()` with 30 minutes recorded, and solo sessions use `active_checkin_sessions.started_at`.

```
PASS C1 anon cannot execute submit_checkin -> ERR:permission denied for function submit_checkin
PASS C2 authenticated cannot execute _credit_checkin
PASS C3 authenticated cannot execute _credit_day
PASS C4 submit_checkin: EXECUTE authenticated only (not PUBLIC/anon), SECURITY DEFINER, search_path=public
PASS C5 ACLs and search_path of every new/replaced function
PASS C6 _server_checkin dropped
PASS C7 process_stale_sessions body unchanged, COMMENT points at _credit_day
PASS E.eq1 new = old (normal finish): md5 old 238d3b43b466e84107873e5bab435d2e new 238d3b43b466e84107873e5bab435d2e
PASS E.eq2 new = old (partner credit, M6a): md5 old 87729982e01f121dcdd52302d4ff32f9 new 87729982e01f121dcdd52302d4ff32f9
PASS E.eq3 new = old (stale auto-complete via _auto_credit, then its dedup): md5 old 421cd9dd7d15d5e429611dda58ed4fdb new 421cd9dd7d15d5e429611dda58ed4fdb
PASS E.eq4 CAP-2 intended difference, today's cap -> old 5/5 new 10/10
PASS E.eq4 CAP-2 intended difference, yesterday's cap -> old 10/10 new 5/5
PASS E.eq4 nothing else differs (rows, streaks, logs, pushes)
PASS Q1.1 submit_checkin as rokitest1 (no row today): reason -> not_checked_in_today
PASS Q1.2 credited false, xp 0, coins 0
PASS Q1.3 partner row created on the new team with the partner's local date -> 2026-10-28
PASS Q1.4 copy check_in_time = source earliest time, not now() -> copy 19:55:16, now 22:55:16
PASS Q1.5 caller not copied (no real row today)
PASS Q1.6 the copy sent no push -> 0
PASS Q1.7 the copy paid nothing -> 0/0
PASS Q1.8 flag cleared when submit_checkin returns -> ''
PASS Q1.9 new team not advanced yet (caller missing) -> 0/0
PASS Q1.10 a real Finish after the copy, same transaction, still pushes rokitest1 -> onboard_check3
PASS Q1.11 Finish completes the new team's day -> 1/1
PASS Q1.12 Finish pays as before: rokitest1 +25, onboard_check3 retro share +15
PASS Q1.13 second submit_checkin the same day -> already_checked_in
PASS Q1.14 second call: rows, coins, pushes unchanged -> 0/0/0/0
PASS Q1.15 second Finish the same day -> nothing_to_finish/0
PASS Q1.16 submit_checkin return shape (no milestones_unlocked)
PASS Q2.0 fixture: onboard_check6 local date differs from the UTC date -> Pacific/Kiritimati 2026-10-29 vs UTC 2026-10-28
PASS Q2.1 Finish credit_date = the member's local date -> 2026-10-29
PASS Q2.2 submit_checkin as testtest1 (no row today) -> not_checked_in_today
PASS Q2.3 onboard_check6 copied with its own local date, not the UTC date -> 2026-10-29
PASS Q2.4 onboard_check4 (no real row today, only yesterday) not copied anywhere
PASS Q2.5 testtest1 not copied
PASS Q3.1 reason credited, credited true, xp 0, coins 0
PASS Q3.2 both members copied onto the new team -> 2
PASS Q3.3 copies complete the day, return marks the team updated -> 1/1/true
PASS Q3.4 copies paid nothing -> 0/0/0/0
PASS Q3.5 copies pushed nothing -> 0
PASS Q3.6 each copy keeps its member's earliest real check_in_time
PASS CAP.1 yesterday's cap counts yesterday-suffixed payouts -> 5/5/true
PASS CAP.2 today's cap counts today-suffixed payouts -> 5/5/true
PASS CAP.3 legacy reference (no suffix, NULL, or a near-miss suffix) is not counted -> 10/10/false
PASS CAP.4 straddling midnight: counts for yesterday, not for today -> today 10 / yesterday 5
PASS CAP.5 teammate cap by credit day, 95 coins suffixed today -> teammate paid 5
PASS CAP.5 teammate cap by credit day, 95 coins suffixed yesterday -> teammate paid 15
PASS F3.1 create_invite_team for a new invitee pays nothing at join
PASS F3.2 first credited day pays once (Finish wrote 2 rows) -> 1/20/<invite id>
PASS F3.3 a credited row on another day pays nothing more -> 1/20
PASS F3.4 second inviter, then a copied row lands: still one bonus -> credited 1/20
PASS F3.5 an existing account (created before the invite) is never paid -> 0/0
PASS B.1 before B the installed build's direct insert still works and is pinned
PASS B.2 after REVOKE: no table or column INSERT left for authenticated
PASS B.3 direct insert denied -> permission denied for table daily_team_checkins
PASS B.4 submit_checkin still works after the REVOKE (definer)
```

How the equivalence probe works:

- Phase 1 runs the old bodies on fixtures eq1–eq4. Each fixture runs in a sub-transaction that is captured and then rolled back.
- Migration A then runs inline, and phase 2 runs the new bodies on the identical fixtures.
- The snapshots compare the function return values, the check-in rows (team label, user, date, time), the streaks, the xp/coin rows (amount, type, description, reference), profiles, `workout_logs`, cancelled breaks, sessions and `buddy_checked_in` pushes.
- eq1–eq3 are byte-identical. eq4 differs only in the intended CAP-2 amounts. No credit-day difference appeared, because the formula is the same and only its location moved.

Other checks:

- **Rollback test** (`checkin_rpc_rollback_test.sql`: Migration A, then the rollback, in one transaction): **9/9 PASS**.
  - All 7 restored bodies (`_server_checkin`, `finish_checkin_session`, `_auto_credit`, `_apply_checkin_rewards`, `notify_buddy_checkin`, `create_invite_team`, `_fulfil_invite_reward`) have exactly the md5 of the live dump, with their original ACLs and `search_path`.
  - The new functions are dropped, and the `process_stale_sessions` comment is back to NULL.
- **Flag lifetime** (`checkin_rpc_flag_probe.sql`): PASS. The flag is set in one transaction, and the next transaction on the same session sees `''`.
- **`set_config` via /rpc:** `POST /rest/v1/rpc/set_config` with the anon key returns 404 `PGRST202` ("Could not find the function public.set_config…"). PostgREST exposes only the `public` schema, and `set_config` lives in `pg_catalog`, so neither anon nor authenticated can reach it through /rpc. Each /rpc request is also its own transaction, so a transaction-local flag could not carry over into a later `submit_checkin` call. Even if it could, the worst case is suppressing a push for the caller's own copied rows.

## Function body diffs (old = live dump 2026-10-28, new = live after 20261028230000)

### finish_checkin_session

```diff
@@ -78,7 +78,7 @@
   IF NOT v_sess_ok THEN
     v_start := v_wk.workout_started_at;
   END IF;
-  v_day := (v_start AT TIME ZONE v_tz)::date;
+  v_day := public._credit_day(v_uid, v_start);
@@ -91,7 +91,7 @@
-  PERFORM public._server_checkin(v_uid, v_day);
+  PERFORM public._credit_checkin(v_uid, v_start);
   DELETE FROM active_checkin_sessions WHERE user_id = v_uid;
@@ -107,10 +107,10 @@
-        v_pday := (v_wk.workout_started_at AT TIME ZONE public.safe_user_tz(v_partner))::date;
+        v_pday := public._credit_day(v_partner, v_wk.workout_started_at);
         SELECT count(*) INTO v_partner_before FROM daily_team_checkins
         WHERE user_id = v_partner AND check_in_date = v_pday;
-        PERFORM public._server_checkin(v_partner, v_pday);
+        PERFORM public._credit_checkin(v_partner, v_wk.workout_started_at);
```

### _auto_credit

```diff
 DECLARE
-  v_day date := (p_start AT TIME ZONE public.safe_user_tz(p_user))::date;
+  v_day date := public._credit_day(p_user, p_start);
 BEGIN
@@
-  PERFORM public._server_checkin(p_user, v_day);
+  PERFORM public._credit_checkin(p_user, p_start);
```

### _apply_checkin_rewards

```diff
   v_capped boolean := false;
-  v_user_tz text := public.safe_user_tz(p_user_id);
 BEGIN
@@
-  -- Daily cap check for the primary user, in THEIR OWN local day (tz3_2)
+  -- Daily cap for the primary user, counted by credit day: the date after the
+  -- last colon of reference_id (streak:day), not the day the row was created (CAP-2).
   SELECT COALESCE(SUM(amount), 0) INTO v_already_xp
   FROM xp_transactions
   WHERE user_id = p_user_id
     AND transaction_type = 'xp_award' AND description IN ('daily_checkin', 'partner_bonus')
-    AND (created_at AT TIME ZONE v_user_tz)::date = p_check_in_date;
+    AND substring(reference_id from '[^:]*$') = p_check_in_date::text;
@@ (same change for v_already_coins)
-        -- Teammate's cap window is measured in the TEAMMATE's own local day.
-        v_t_tz text := public.safe_user_tz(v_teammate.user_id);
@@
+          -- Teammate's cap window: the same credit day (CAP-2).
           SELECT COALESCE(SUM(amount), 0) INTO v_t_already_xp
@@
-            AND (created_at AT TIME ZONE v_t_tz)::date = p_check_in_date;
+            AND substring(reference_id from '[^:]*$') = p_check_in_date::text;
@@ (same change for v_t_already_coins)
```

### notify_buddy_checkin

```diff
 BEGIN
+  -- Copies written by submit_checkin are not new check-ins: no push.
+  IF current_setting('app.checkin_copy', true) = '1' THEN
+    RETURN NEW;
+  END IF;
+
   SELECT team_id INTO v_team_id FROM team_streaks WHERE id = NEW.team_streak_id;
```

### create_invite_team

```diff
   v_invite_id UUID;
-  v_invite_created TIMESTAMPTZ;
-  v_invitee_is_new BOOLEAN;
   v_now TIMESTAMPTZ := NOW();
@@
-  SELECT id, created_at INTO v_invite_id, v_invite_created
+  SELECT id INTO v_invite_id
@@
-  SELECT (u.created_at > v_invite_created) INTO v_invitee_is_new
-  FROM auth.users u WHERE u.id = p_invitee_id;
-
-  IF COALESCE(v_invitee_is_new, false) THEN
-    IF NOT EXISTS (
-      SELECT 1 FROM coin_transactions
-      WHERE transaction_type = 'invite_bonus'
-        AND reference_id = v_invite_id::text
-        AND user_id = p_invitee_id
-    ) THEN
-      PERFORM award_coins(p_invitee_id, 20, 'invite_bonus', 'Joined via buddy invite', v_invite_id::text);
-    END IF;
-  END IF;
+  -- The invitee's welcome bonus is paid on their first credited day by
+  -- _fulfil_invite_reward, once per account (F3), no longer here.
```

### _fulfil_invite_reward

```diff
   v_amount  INT;
+  v_bonus   BOOLEAN := false;
@@
     FOR UPDATE
   LOOP
+    -- F3: the invitee's own 20-coin welcome bonus, once per account for life,
+    -- paid on its first credited row after joining through an invite. The
+    -- FOR UPDATE above serialises concurrent rows for the same invitee.
+    IF NOT v_bonus
+       AND NOT EXISTS (
+         SELECT 1 FROM coin_transactions
+         WHERE user_id = NEW.user_id AND transaction_type = 'invite_bonus'
+       )
+       AND EXISTS (
+         SELECT 1 FROM auth.users u
+         WHERE u.id = NEW.user_id AND u.created_at > v_invite.created_at
+       ) THEN
+      BEGIN
+        PERFORM award_coins(NEW.user_id, 20, 'invite_bonus', 'Joined via buddy invite', v_invite.id::text);
+      EXCEPTION WHEN OTHERS THEN
+        -- Never block the check-in. No invite_bonus row, so the next row retries.
+        RAISE WARNING 'invite_bonus failed for %: %', NEW.user_id, SQLERRM;
+      END;
+      v_bonus := true;
+    END IF;
+
```

The new functions (`_credit_day`, `_credit_checkin`, `submit_checkin`) are in `supabase/migrations/20261028230000_single_server_checkin.sql`. `_credit_checkin` is `_server_checkin`'s body with the changes listed above. `gen_checkin_rpc.py` derives every replaced body from the live dumps by exact, count-checked replacements.

## Client change (579634c, 7b74661)

- `TeamSyncService.syncAllTeamsCheckIns` is now the one service method. It calls `submit_checkin` and maps reason codes to short text with no emojis:
  - `credited`: "Check-ins synced"
  - `already_checked_in`: "Already checked in today."
  - `not_checked_in_today`: "No check-in today yet."
  - `no_teams`: "No teams yet."
  - errors: "Something went wrong. Please try again."
- The RPC call is injectable for tests.
- `FriendService.acceptFriendRequest` calls the sync after `create_buddy_team`. `_backfillTodaysCheckIns` and the 100 ms delay are deleted, and so are TeamSyncService's own insert and `recompute_team_streak` follow-up.
- `lib/` now contains no direct insert into `daily_team_checkins`.
- `flutter analyze`: no issues. `flutter test`: 194 pass (the existing 189 plus 5 new in `test/team_sync_service_test.dart`).

## Device check (build 7b74661, Pixel 7a, onboard_check5 `19c3b618-ae18-4b2e-be52-cbe1de8cacbe`)

Text-only (uiautomator dump to file, logcat, DB reads by id, API logs).

| Check | Result |
|---|---|
| Install and dashboard | Installed 23:22:09 UTC. The dashboard dump shows Streaks / Check In / Coach Max, with 0 coins at baseline. |
| Normal check-in (15-minute session, then Finish) | Session started 23:26:11. `rpc/finish_checkin_session` at 23:41:25 returned 200. Row on the Coach Max team **dated 2026-10-28** (the start day, Rule 1). Streak 0 → 1. Paid 10 coins / 10 xp `daily_checkin` (ref `d3e27b25…:2026-10-28`), plus the `first_flame` achievement (20 coins / 50 xp, client-verified as before). Session row deleted. |
| Second sync, same day (23:43) | Every sync logged `submit_checkin → already_checked_in`. Rows, streaks, xp/coin transactions, profile and sessions are all **unchanged** compared with right after the Finish. |
| API logs (23:20–23:50) | `POST rpc/submit_checkin` ×7, all 200. `POST rpc/finish_checkin_session` ×1, 200. **No POST, PATCH or DELETE to `rest/v1/daily_team_checkins` from anyone** (only GET reads). The finish line appeared in the log stream about 3 minutes late (ingestion lag); the database showed it immediately. |
| logcat | 0 `FATAL` lines. |
| Friend-accept copy | Not device-testable with one phone. Covered by probes Q1, Q2 and Q3. |

## Migration B (20261029010000), applied 23:45 UTC, after "session done"

- Contents: `REVOKE INSERT ON public.daily_team_checkins FROM authenticated;`. Before it the ACL was `authenticated=ar`, with no column ACLs. The rollback (`docs/rollback_20261029010000.sql`) re-grants INSERT.
- Dry run: only `20261029010000` pending. `schema_migrations` had 126 remote versions against 127 local, the only local-only version was ours, nothing was remote-only, and the remote max was `20261028230000`. Applied with `supabase db push`. Afterwards the database is up to date.
- md5 parity: `20261029010000` remote=`c3991cd8008ee689a1140e8760ad931f` local=`c3991cd8008ee689a1140e8760ad931f`, **MATCH**.
- Economy hashes are identical before and after B, at 23:45:08 and 23:45:11:

```
daily_team_checkins        5532 f17c8104f7c5ab9390f7dc3055cb2e8e
workout_logs                 11 f8045186a0e4e797c8238cea18cae570
xp_transactions              75 8e10152d93fc98a274af60686d5af301
coin_transactions            64 4265eae576dbec205b06cd1209798342
team_streaks                 48 ac13c687970ee53a160db08f9ef4be48
user_profiles_xp_coins       47 a0cbd41614845eaf73bd6e5a16a1f26e
workouts                     24 de8bb702eb837883d9170f9dec066ea2
invites                       7 c366bcb7ea899e30148bfe1b66ac01ae
user_unlocked_cosmetics       0 d41d8cd98f00b204e9800998ecf8427e
```

  Between the A snapshots and the B snapshots, the device check added onboard_check5's +1 check-in row, +1 workout log, +2 xp rows and +2 coin rows, and changed its profile and Coach Max streak. That gap also spans the 23:05 UTC nightly streak reset, which touches `team_streaks`. Neither migration changed data.
- Denied-direct-insert re-run (`checkin_rpc_b_probe.sql`, own connection, authenticated only): **4/4 PASS**.

```
PASS B1 authenticated direct INSERT into daily_team_checkins -> 42501 permission denied for table daily_team_checkins
PASS B2 authenticated submit_checkin still answers -> ok not_checked_in_today
PASS B3 table ACL -> {postgres=arwdDxtm/postgres,anon=r/postgres,authenticated=r/postgres,service_role=arwdDxtm/postgres}
PASS B4 no table or column INSERT for authenticated
```

## Not done here (mentioned, not touched)

- **Prompt 07:**
  - RACE-1: two teammates crediting in the same instant can leave the day `day_incomplete`.
  - CAP-RACE: teammate retro payouts on two streaks can overshoot one daily cap by one payout. The CAP-1 per-(streak, day) advisory lock is unchanged.
- **Dead-code batch:**
  - `LevelService.grantMilestoneUnlock` (no INSERT grant, and the conditions table is empty);
  - `award_checkin_rewards` (no caller);
  - the `pin_client_checkin_date` trigger and the `daily_team_checkins` INSERT policy (both inert after B);
  - the redundant client `recompute_team_streak` call after `check_in_coach_max` (`coach_max_service.dart:285`).
- **Other:**
  - The coach-max-cron direct insert (service_role, P-5).
  - `WorkoutHistoryService.logWorkout` still writes a device-dated `workout_logs.workout_date`. It is history and display only.
- **Known behaviour (Q4):** streak achievements are verified only when the client calls the verifier after its own Finish. When an auto-complete or partner credit hits a milestone, the payout comes on that user's next own Finish that advances a streak.
- **Fix Tracker:** not touched (owner updates it).
