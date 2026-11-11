# Single server check-in RPC: design (Step 1, read-only)

Date: 2026-10-28. Live DB read with `supabase db query --linked` (SELECTs only). Live migration head is `20261013020000`, the same as local. Nothing was written to the DB or to code.

Revision 2 (same day) records the owner's answers to Q1–Q7 (§14) and the follow-up confirmations (§15).

## 0. Sources and item definitions

`claude/Fix Tracker.md` does not exist on this machine. I searched the repo, `~/.claude` and the whole filesystem. FS-1, FS-2 and CAP-2 below therefore use the planner prompt's wording. A-1, A-3, DI-5, DI-9 and F1/F3 are quoted from the files where I found them.

From `docs/audits/audit-2026-09-29.md`:

- **A-1** (line 68): "A-1 five streak writers | PARTIAL | server `recompute_team_streak` is the only streak writer; client still inserts check-ins from 3 places (P3 Duplication)"
- **A-3** (line 70): "A-3 three check-in-all-teams paths | OPEN | `checkInAllTeams`, TeamSyncService backfill and FriendService backfill (P3)"
- **DI-5** (line 95): "DI-5 delay band-aid | OPEN | `Future.delayed` at `friend_service.dart:141`"
- **DI-9** (line 137): "DI-9 FriendService writes for partner | OPEN | `_backfillTodaysCheckIns` inserts a row with `user_id` = the *other* user (`friend_service.dart:295-311`); RLS rejects it, so one side's backfill silently fails"
- Refactor line (line 533): "Single server check-in RPC; delete the 3 client check-in/backfill paths (A-1, A-3, DI-9, DI-5) | L | Opus"

From `docs/hygiene/05b_sweep.md`:

- **F1** (line 75): "direct check-in plus recompute advances a streak with no workout (open audit item A-3, table grant, not a function). `authenticated` has INSERT on `daily_team_checkins` … Fixing this needs the client backfill inserts removed (`team_sync_service.dart:106`, `friend_service.dart:250,261`) and the INSERT grant/policy dropped."
- **F3** (line 80): "invitee bonus is per inviter with no activity gate. As rokitest1: `accept_invite` for codes from testtest4 and testtest1, then `create_invite_team` for each, paid +40 coins (2 `invite_bonus` rows) … a new user can farm 20 coins per inviter."

From memory notes (`project_live24_sessions.md`):

- **MILE-1**: "streak milestone cosmetics (30/60/90/100) are granted only by the app (LevelService.grantMilestoneUnlock), so a server auto-complete on a milestone day misses the cosmetic."

From the planner prompt (no local source found):

- **FS-1**: backfill dates are computed in UTC.
- **FS-2**: the friend check-in row insert is rejected by RLS.
- **CAP-2**: the daily cap counts the creation day, not the credit day.

The A-3 line numbers in the prompt are still correct: `team_sync_service.dart:106`, `friend_service.dart:250` and `:261`. The fourth path from the audit, `team_streak_service.dart:409` (`checkInAllTeams` → `_checkInToTeam`), is already gone. `checkInAllTeams` now calls `finish_checkin_session` (`team_streak_service.dart:349`).

## 1. Every current writer of `daily_team_checkins` and every credit path (live)

| # | Path | Who runs it | Writes | Date source | Pays rewards | Notes |
|---|---|---|---|---|---|---|
| C1 | `TeamSyncService.syncAllTeamsCheckIns` → insert `team_sync_service.dart:106`, then `recompute_team_streak` `:187` | client, on every home load (`home_screen.dart:4130`) | caller's own row on each team missing today | client `localTodayString()`, then re-pinned by trigger T1 | no | Copies today's check-in to teams joined later. A-3 / F1. |
| C2 | `FriendService._backfillTodaysCheckIns` → insert `friend_service.dart:250` (self) | client, after `acceptFriendRequest` (`friends_page_modern.dart:1546`) | caller's row on the new team | the lookup uses a **UTC** date (`:191-193`), then re-pinned by T1 | no | FS-1: the lookup can miss the local-day check-in. Preceded by `Future.delayed(100ms)` at `:141` (DI-5). |
| C3 | same → insert `friend_service.dart:261` (partner) | client | the **partner's** row | UTC | no | RLS `user_id = auth.uid()` rejects it (FS-2 / DI-9). The partner's side never lands. |
| T1 | trigger `pin_client_checkin_date` → `_pin_client_checkin_date()` (prompt 01) | BEFORE INSERT, only when `current_user IN (authenticated, anon)` | forces `check_in_date = now()` local day and `check_in_time = now()` | `safe_user_tz(NEW.user_id)` | no | Dead for clients once Migration B lands. Kept (it is harmless and a dead-code item). |
| S1 | `_server_checkin(p_user_id, p_day)` (internal, `service_role` only) | `finish_checkin_session` ×2 and `_auto_credit` | one row per active team, `ON CONFLICT DO NOTHING` | `p_day` from the caller | yes, via `_apply_checkin_rewards` when `_recompute_team_streak` says `updated` | Today this already **is** the shared credit function. It also cancels the day's break and mirrors Coach Max. |
| S2 | `finish_checkin_session(p_workout_id)` | client (Check In → Finish, Workout Schedule Finish) | via S1 for the caller, and for the partner (M6a) | `(v_start AT TIME ZONE tz)::date`: session start or `workout_started_at` (server clock), so Rule 1 already holds | yes | FIN-1 gate: ≥15 min, ≤3h30 (≤3h40 completed). |
| S3 | `process_stale_sessions(p_now)` → `_auto_credit(user, start, …)` → S1 | cron (service_role) | via S1 | `_auto_credit`: `(p_start AT TIME ZONE tz)::date` | yes | `_auto_credit` also writes `workout_logs`. |
| S4 | `_finish_coach_max_checkin(streak, user, day)` | S1, `check_in_coach_max`, (`check_in_coach_max_with_buddy`, service_role only since 05d) | Coach Max's row | caller's day | no (recompute only) | Bot row. Coach Max is excluded from the AND-gate. |
| S5 | `check_in_coach_max(p_user_id)` | client `coach_max_service.dart:219`, which then also calls `recompute_team_streak` `:285` | via S4 | server `now()` local day | no | Guard: `auth.uid() = p_user_id`. |
| S6 | `coach-max-cron` Edge Function | service_role | direct insert of Coach Max's row (`index.ts:227`), then `recompute_team_streak` (`:436`) | `coach_max_schedule.scheduled_date` | no | Not a human credit. Unaffected by Migration B (service_role). Out of scope: P-5 single scheduler. |
| S7 | `create_buddy_team`, `ensure_coach_max_team`, `create_invite_team` | client | **no** check-in rows (teams, members and streak only) | n/a | `create_invite_team` pays the invitee 20 coins (F3) | Advisory locks: `create_buddy_team` on the pair, `ensure_coach_max_team` on `coach_max_team:uid`. |
| S8 | `_recompute_team_streak` (internal) and `recompute_team_streak` (public wrapper, member check) | S1, S4, C1, C2, S5, S6 | `team_streaks` only | `p_check_in_date` from the caller | no | Sole streak writer (A-1). Reads `daily_team_checkins`, `break_day_usage` and `team_streaks.last_workout_date`. |
| S9 | `_apply_checkin_rewards(user, streak, day)` (internal) | S1 only | xp/coin transactions for the user and owed teammates | `p_check_in_date` | yes | **CAP-1 lock**: `pg_advisory_xact_lock(hashtext('checkin_rewards:' || streak || ':' || day))` (migration `20261005163755`). Dedup by `reference_id = streak:day`. |
| S10 | `award_checkin_rewards(streak, day)` | service_role only (no client caller) | via S9 | caller | yes | Dead to clients. Dead-code item, not touched. |
| T2 | trigger `on_checkin_fulfil_invite_reward` → `_fulfil_invite_reward()` | AFTER INSERT on every row | inviter reward once the invitee has ≥2 distinct check-in days | n/a | yes (inviter) | |
| T3 | trigger `on_buddy_checkin` → `notify_buddy_checkin()` | AFTER INSERT on every row | push to the team's other member | n/a | no | See §15 Q2b. |

Grants today (live): `authenticated` has table INSERT on `daily_team_checkins`, plus column-level INSERT on all 6 columns. INSERT policy: `user_id = auth.uid()` and the streak is one of the caller's teams. The only unique key is `(team_streak_id, user_id, check_in_date)`.

## 2. Live findings that changed the brief

1. **`workouts.workout_date` does not feed streaks, caps or achievements** (confirmed in §15 Q1). The credit day already comes from `workout_started_at` (server clock, pinned by `_clamp_client_workout_writes`) in the user's tz, with the 3h30 window: that is Rule 1. **Decision: no workout_date change.**
2. **MILE-1 is moot.** `cosmetic_unlock_conditions` has 0 rows and `user_unlocked_cosmetics` has 0 rows. The client grant is dead: `authenticated` has no INSERT grant or policy on `user_unlocked_cosmetics`. Streak cosmetics unlock through `shop_items.unlock_achievement_id` and the server-side `verify_achievement_progress`. **Decision: no server milestone grant.** `LevelService.grantMilestoneUnlock` goes on the dead-code list and is not deleted.
3. **F3 pays the invitee.** `create_invite_team` pays the invitee 20 coins once per accepted invite, so once per inviter. The inviter's reward is already gated on ≥2 check-in days. **Decision:** §8.
4. **Every client insert today is a backfill or sync, never a first credit.** **Decision: `submit_checkin` is sync only** (§3).

## 3. RPC name, signature and semantics

`public.submit_checkin() RETURNS jsonb`. The name does not collide with anything live. It takes no parameters and uses `auth.uid()` only. It is `SECURITY DEFINER` with `SET search_path = public`, EXECUTE is granted to `authenticated` only, and it is revoked from PUBLIC and anon.

**Copy condition (exact):** the caller is `c = auth.uid()`. For each active team `T` (`team_streaks.is_active`) where `c` is in `team_members`, and for each member `m` of `T` with `m <> Coach Max`:

- `d_m := _credit_day(m, now())`, which is `m`'s own local today;
- write a row for `(T, m, d_m)` **iff** `EXISTS (SELECT 1 FROM daily_team_checkins WHERE user_id = m AND check_in_date = d_m)` on any team, **and** `T` has no row for `(m, d_m)` yet.

So a row for someone other than the caller is written only when that member already has a row for their own local today. Coach Max is never a source or a target. A break day is not a row, so it is never copied. Before Migration B the source row could be an F1 self-insert, which is the same exposure as today. After B every source row comes from a server credit path.

- **check_in_time of a copy** = `min(check_in_time)` of `m`'s existing rows for `d_m`, not `now()`. A 22:30 copy of an 18:00 check-in is stored as 18:00, so it cannot earn `night_owl` / `early_bird` / `in_sync` that the real row did not. This is not awkward: `_credit_checkin` takes the stored time as a separate parameter (§5).
- **Rewards:** a copy pays nothing (`p_pay => false`, Q3). The streak still recomputes. A later credit by a teammate still pays this member the retro share through `_apply_checkin_rewards`, as today.
- **Push:** a copy sends no push (§15 Q2b).

Both client sites call it: home load (replacing C1) and right after `create_buddy_team` on accept (replacing C2 and C3 and the `Future.delayed`, which closes DI-5). FS-1 (local day, not UTC), FS-2 and DI-9 (the server writes the partner row) are closed by the condition above.

## 4. Return shape

```
{
  "credited": bool,          -- at least one new row written for the caller
  "reason": text,            -- 'credited' | 'already_checked_in' | 'not_checked_in_today' | 'no_teams'
  "credit_date": date,       -- caller's local day
  "streak": int,             -- highest current_streak across the caller's active teams
  "xp": int, "coins": int,   -- caller's payout from this call (always 0: copies pay nothing)
  "teams": [{"streak_id", "team_id", "updated", "new_streak"}]
}
```

`milestones_unlocked` was removed (Q4). `finish_checkin_session` keeps its current return shape unchanged, because the installed build parses it (`applyFinishResult`).

## 5. One internal credit function

- `_credit_day(p_user_id uuid, p_at timestamptz) RETURNS date` = `(p_at AT TIME ZONE safe_user_tz(p_user_id))::date`. This is **the** date derivation, and its body carries a comment naming the other copy of the formula. `process_stale_sessions` is not replaced (Q7), so Migration A adds `COMMENT ON FUNCTION process_stale_sessions` stating that its inline `(start AT TIME ZONE safe_user_tz(u))::date` guards must stay equal to `_credit_day`. Each place then points at the other.
- `_credit_checkin(p_user_id uuid, p_at timestamptz, p_pay boolean DEFAULT true, p_time timestamptz DEFAULT now()) RETURNS jsonb` replaces `_server_checkin`. It keeps the same loop and body (cancel the day's break, insert `ON CONFLICT DO NOTHING`, recompute, rewards if `updated`, Coach Max mirror), with these changes:
  - the day comes from `_credit_day(p_user_id, p_at)`;
  - `check_in_time = p_time` (`now()` for every existing caller, so their behaviour is unchanged; the source time for copies);
  - `p_pay = false` skips `_apply_checkin_rewards`;
  - it returns per-team results plus summed xp/coins instead of `void`;
  - there is no milestone grant;
  - it is not SECURITY DEFINER (like `_server_checkin`), search_path is pinned, and EXECUTE goes to service_role only.
- Call sites switch to it, and their public signatures stay unchanged:
  - `finish_checkin_session`: `v_day := _credit_day(v_uid, v_start)`, `v_pday := _credit_day(v_partner, v_wk.workout_started_at)`, and the two `PERFORM _server_checkin(...)` calls become `_credit_checkin(uid, start)`. Nothing else in the body changes.
  - `_auto_credit`: `v_day := _credit_day(...)`, then `_credit_checkin(p_user, p_start)`.
  - `submit_checkin`: `_credit_checkin(m, now(), p_pay => false, p_time => src_time)` per §3.
- `_server_checkin` is dropped in Migration A after its 3 callers move. The rollback recreates it exactly as dumped.

## 6. CAP-2: cap by credit day

Today the four cap sums in `_apply_checkin_rewards` (primary xp/coins and teammate xp/coins) filter by `(created_at AT TIME ZONE tz)::date = p_check_in_date`.

Fix: compare the text after the **last** colon of `reference_id` with the date exactly, `substring(reference_id from '[^:]*$') = p_check_in_date::text`. There is no `LIKE`. Every `daily_checkin` and `partner_bonus` row written by this function carries `reference_id = '<streak uuid>:<YYYY-MM-DD>'`. Legacy rows without the suffix (or with a NULL reference) never match, which only affects old days. Amounts and caps (1000 xp, 100 coins) are unchanged.

Step 2 probes:

- yesterday's cap (a credit for yesterday counts only yesterday-suffixed rows);
- today's cap;
- a legacy reference with no suffix (not counted);
- a straddle: a workout started 23:50 and finished after midnight. Its payouts are created today but suffixed yesterday, so they count against yesterday's cap and not today's.

## 7. MILE-1: closed as moot

There is no server grant (§2.2). How the achievement verifier is triggered is in §15 Q4.

## 8. F3: invitee bonus

**Decision: once per invitee lifetime, on the first credited day, in `_fulfil_invite_reward`.**

- `create_invite_team`: delete the payment block only (same signature, teams and friendship unchanged, grants re-stated).
- `_fulfil_invite_reward` (AFTER INSERT trigger on `daily_team_checkins`, already looping `NEW.user_id`'s accepted invites `FOR UPDATE`): when `NEW.user_id` has **no** `coin_transactions` row with `transaction_type = 'invite_bonus'`, and one of its accepted invites passes the "is new" test, pay 20 coins `invite_bonus` once, with `reference_id` = that invite id.

The exact test and the bound are in §15 Q5.

## 9. Idempotency

- Rows: the unique `(team_streak_id, user_id, check_in_date)` key with `ON CONFLICT DO NOTHING; CONTINUE WHEN NOT FOUND` (unchanged), so a second call writes no rows.
- Streak: `_recompute_team_streak` returns `already_today`.
- Money: `_apply_checkin_rewards` dedups on `reference_id = streak:day` under the CAP-1 lock, and the invitee bonus dedups on "any `invite_bonus` row for this user".
- A second `submit_checkin` the same day returns `credited=false, reason='already_checked_in'` and the current streak, and pays 0. A second Finish is already `nothing_to_finish` (FIN-1).

## 10. Lock order

No new lock. Per credit, in order:

1. `finish_checkin_session` only: the caller's `active_checkin_sessions` row `FOR UPDATE`. `process_stale_sessions` only: session and workout rows `FOR UPDATE SKIP LOCKED`.
2. The `daily_team_checkins` unique-key row lock taken by the INSERT, team by team.
3. The `team_streaks` row lock (UPDATE in `_recompute_team_streak`).
4. The **CAP-1** advisory lock `checkin_rewards:streak:day`.
5. `user_profiles` and transaction rows (award_xp / award_coins).
6. AFTER INSERT triggers: `invites` rows `FOR UPDATE` (T2), push (T3).

Deadlock check: concurrent credits for the same user collide on the unique key at step 2 and serialise; the loser hits `CONTINUE` and pays nothing. Two finishers of one shared workout: the first credits both (M6a) and the second blocks on the first's uncommitted rows, then conflicts. `submit_checkin` takes only steps 2–6. Two concurrent invitee-bonus checks for one user serialise on the `invites FOR UPDATE` rows in T2, so the second sees the first's `invite_bonus` row.

There is one theoretical cycle: a multi-user transaction (stale cron, or finish with M6a) touching shared teams in a different order from a concurrent one. Postgres detects it and aborts one side, and nothing is half-written. It is not introduced here: `_server_checkin` has it today.

**Deferred to prompt 07 (owner decision Q6):** RACE-1 (two teammates crediting in the same instant each miss the other's uncommitted row, leaving the day `day_incomplete`) and CAP-RACE (teammate retro payouts on two streaks can overshoot that teammate's daily cap by one payout).

## 11. Historical rows

Nothing historical is rewritten:

- no backfill of past check-ins;
- no streak recompute of past days;
- no retroactive invitee bonuses (live today: 0 accepted invites whose invitee is "new", so 0 are pending; 0 users hold more than one `invite_bonus` row);
- no change to existing `reference_id`s.

Rows written by old client backfills stay as they are. The CAP-2 change only affects caps computed from now on.

## 12. Migration split

**Migration A (additive; the installed build keeps working):**

- `_credit_day`, `_credit_checkin`, then drop `_server_checkin`.
- `finish_checkin_session` replaced, with only the call-site lines changed and grants re-stated.
- `_auto_credit` replaced.
- `COMMENT ON FUNCTION process_stale_sessions` (formula pointer).
- `_apply_checkin_rewards` (CAP-2, exact suffix).
- `submit_checkin` (new; REVOKE PUBLIC, anon; GRANT authenticated).
- `notify_buddy_checkin` (skip copies, §15 Q2b).
- `create_invite_team` (bonus block removed, grants re-stated) and `_fulfil_invite_reward` (invitee bonus).
- Every SECDEF function gets `search_path` pinned. Internal functions are revoked from PUBLIC, anon and authenticated.
- `docs/rollback_<A>.sql` drops the new functions and recreates `_server_checkin` and every replaced body **exactly as dumped from live on 2026-10-28**, with their grants. The comment on `process_stale_sessions` is reset to NULL.

The installed build still inserts directly (C1–C3) and still works, because INSERT is still granted.

**Step 2 probe set** (one transaction, ROLLBACK, test accounts matched by id):

- the denied direct insert (simulated with B's REVOKE inside the transaction);
- the idempotent second call;
- the UTC versus local date case;
- the copy condition, including a member with no row today who is **not** copied;
- a copy's `check_in_time` equal to the source;
- a copy sending no push;
- the CAP-2 cases from §6;
- the F3 gate (first credited day pays once, a second day and a second inviter pay nothing, an old account pays nothing).

There is also an **equivalence probe**, run in the same rolled-back transaction: the old bodies (from the dump) and the new bodies on identical fixtures (a normal finish, a partner credit, a stale auto-complete), showing identical check-in rows, streaks and payouts except for the intended CAP-2 and credit-day differences. The run also includes a security-advisor diff and economy table-hash snapshots before and after. These exclude the 23:05 UTC nightly reset, mijotest's real check-ins and the Coach Max test streak `d557efec`. The report includes an old-versus-new diff of every replaced function body.

**Migration B (after the Step 4 device check):** `REVOKE INSERT ON public.daily_team_checkins FROM authenticated`. A table-level REVOKE also removes the 6 column-level INSERT grants, which I will verify with `information_schema.column_privileges` (there is a known column-list trap from LIVE-23/25). The INSERT policy and trigger T1 are left alone as dead-code items. `docs/rollback_<B>.sql` re-grants.

Versions: new timestamps (`20261028…`) sort after the live head `20261013020000`. They are applied with `supabase db push` after a dry-run and a `schema_migrations` check.

## 13. Out of scope (mentioned, not touched)

Dead-code batch candidates:

- `LevelService.grantMilestoneUnlock` (no INSERT grant, and the conditions table is empty);
- `award_checkin_rewards` (no caller);
- the `pin_client_checkin_date` trigger and the `daily_team_checkins` INSERT policy, after B.

Other items left alone:

- `coach_max_service.dart:285`: a redundant client `recompute_team_streak` after `check_in_coach_max`, which already recomputes.
- `recompute_team_streak` stays client-executable. After B it can only recompute from real rows.
- The coach-max-cron direct insert (P-5).
- `WorkoutHistoryService.logWorkout` writes a device-dated `workout_logs.workout_date` (history only).

## 14. Owner decisions (2026-10-28)

| Q | Decision |
|---|---|
| Q1 | (a) No workout_date change. |
| Q2 | Sync only (§3). |
| Q3 | Copies pay nothing. |
| Q4 | (b) No server milestone grant. MILE-1 closed as moot. `grantMilestoneUnlock` goes on the dead-code list. Q4b moot. |
| Q5 | Invitee bonus once per lifetime on the first credited day, in `_fulfil_invite_reward`. Payment removed from `create_invite_team`. |
| Q6 | RACE-1 and CAP-RACE stay in prompt 07. |
| Q7 | `process_stale_sessions` is not replaced. Only `_auto_credit` moves. Both formula places carry a pointer comment. |

## 15. Confirmations

**Q1. No streak, cap or achievement reads `workouts.workout_date` or `workout_logs.workout_date`.**

- Live server side, every function that reads either column:
  - `_set_workout_planned_at` (planned_at from the scheduled date);
  - `change_workout_time` (reschedule);
  - `get_pending_notice` and `mark_notice_seen` (auto-complete notice);
  - `_auto_credit` (dedup of its own `auto_completed` log rows);
  - `get_favourite_categories` (reads `workout_logs`, not the date).
- `verify_achievement_progress` reads neither. Its workout branches use `workouts.status`, `actual_duration_minutes`, `workout_type` and, for `iron_will`, `workout_completed_at`. Its streak, coop and time branches read `team_streaks` and `daily_team_checkins`.
- `_recompute_team_streak`, `reconcile_stale_streaks` and `get_user_streaks` read `team_streaks.last_workout_date`, which only the server writes.
- Caps (`_apply_checkin_rewards`, `_enforce_workout_daily_cap`) use transaction rows and `workout_completed_at`.
- Client: `workout_service.dart:110` (today's scheduled list), `:195` (ordering) and `:224/230` (`getWorkoutStats` this-week/this-month counts), plus history and notice widgets. These are display only. No Edge Function reads either column.

**Q2a. check_in_time.** A copy carries the source's earliest `check_in_time` for that member's day (§3), so it cannot create a new time-of-day qualification. A related point: copies also cannot add a distinct check-in **date** for `_fulfil_invite_reward`'s ≥2-days test, because a copy is always on a day the member already has.

**Q2b. Push.** `notify_buddy_checkin` fires per inserted row and calls `_send_push(other member, 'buddy_checked_in', …, ref = team_id, sender = NEW.user_id)`.

- **Who gets it:** the other member of the team the copy landed in.
  - When the caller's own row is copied, the partner gets "<caller> checked in".
  - When the partner's row is copied, the **caller** gets "<partner> checked in".
  - On a Coach Max team the recipient is the bot, which has no device token, so nothing is sent.
- **Dedup:** `send-notification` batches on `(recipient, batch_key = 'buddy_checked_in_<team_id>')` within 60 minutes. A copy lands on a team that had no row for that member today (usually a team created minutes ago), so there is no earlier send under that key. **The dedup does not absorb it.**
- **Recommendation: suppress.** A copy is not a new event, and the real check-in may have been hours ago. `submit_checkin` sets a transaction-local flag (`set_config('app.checkin_copy', 'on', true)`, reset after the loop), and `notify_buddy_checkin` returns early when `current_setting('app.checkin_copy', true) = 'on'`. Credits from finish and stale never set it, so their pushes are unchanged. A client cannot set this flag through PostgREST, and even if it could, it would only silence its own copies. This is included in Migration A unless you say otherwise.

**Q2c. Condition for writing another member's row.** `m` is a non-Coach-Max member of an active team that the caller belongs to, **and** `m` already has a `daily_team_checkins` row dated `_credit_day(m, now())` (their own local today) on some team, **and** this team has no such row. A Step 2 probe covers it: a fresh buddy team of two test accounts where A has a real row today and B has none, or only yesterday's. After `submit_checkin` as A, A's row is copied and B gets **no** row. A then calls it again with B holding a row today, and B's row is copied with B's original `check_in_time`. (No SQL is written yet, per your instruction. The probe runs in Step 2.)

**Q4. How the achievement verifier is triggered.** `verify_achievement_progress` runs **only** when the client calls it (`AchievementService._verifyAndUnlock`). There is no cron, trigger or app-open sweep. Streak achievements (and the `unlock_achievement_id` cosmetics they unlock) are checked in `TeamStreakService._afterStreakUpdate`, which runs only for teams whose `updated = true` in **that client's own** `finish_checkin_session` result.

Known behaviour: when a stale auto-complete or a partner credit (M6a) advances a streak to a milestone, the user's streak achievement is **not** paid on their next app open. It is paid on their next own Finish that advances a streak. The verifier re-derives `best_streak ≥ target`, so it catches up then, and nothing is lost.

**Q5a. "Is new", exactly.** It is the invitee's own account, `NEW.user_id`, with an `invites` row `i` where `i.accepted_by = NEW.user_id AND i.status = 'accepted'`, and `auth.users.created_at (NEW.user_id) > i.created_at`. In other words, the account was created after that invite was issued. This is the same test `create_invite_team` and `_fulfil_invite_reward` use today. `accept_invite` only accepts `pending` invites under 7 days old, so "new" means the account was created within that invite's 7-day window.

**Q5b. Bound.** The payment is gated on "no `invite_bonus` row exists for this user", so it is at most **one 20-coin payment per account for life**, whatever the number of invites, teams, copies or check-in days. A copied row can be the insert that pays, for example when a day-0 account already checked in, then accepts an invite and the sync copies its row. That is still the single payment.

An existing account with history that accepts a later invite fails the "is new" test, because its `created_at` is before the invite, so it is **never** paid. Accounts already paid under the old rule have an `invite_bonus` row and are never paid again.
