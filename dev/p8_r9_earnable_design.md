# P8 R9-EARNABLE: make feeling_lucky and comeback_king earnable (Stage 1 design)

Date 2026-11-21. Stage 1 only: nothing written to code, no migration, nothing applied. Owner decision D7: earnable, not hidden.

## 0. Where the brief disagrees with live state or CLAUDE.md (owner decisions)

| # | Brief says | Live / CLAUDE.md says | My recommendation |
|---|---|---|---|
| A | Update the G0 pin for `verify_achievement_progress` | No body pin exists. G0.1 checks ACL, SECURITY DEFINER and search_path only; G0.2 and G0.13 pin other functions | Add a new check, G0.14, pinning `verify_achievement_progress` and `record_randomiser_use` in the same commit as the migration. Take the md5 from `pg_get_functiondef` in a rolled-back rehearsal |
| B | comeback_king "derived purely from `streak_events`" | `streak_events` records losses only (`kind` own/friend, `lost_streak`). There is no "new day" event | Losses from `streak_events`, the new day from the team's active `team_streaks.current_streak >= 1` (section 3) |
| C | "lost streak of 7 or more" | Catalogue description: "Start a new streak after losing one **over** 7 days" | `>= 7` (it matches your suite cases). Say if you want `> 7` |
| D | Client change: only the randomiser call | Nothing in `lib/` ever verifies `comeback_king`; the client only verifies fixed id lists | Add `'comeback_king'` to the list in `checkStreakAchievements` (one line, no visible change) |
| E | Read karpathy-guidelines | CLAUDE.md: "Coding style: the Ponytail plugin, not karpathy-guidelines" | Follow CLAUDE.md (Ponytail). I did not load karpathy |
| F | Commit on the current branch | Current branch is `main`. CLAUDE.md: one branch per prompt, created from main | Create `fix/p8-r9-earnable` from main and commit there |
| G | Security advisor unchanged after apply | Any new SECURITY DEFINER RPC callable by `authenticated` adds one lint 0029 WARN (now 34; the verifier is already one of them) | Expect 34 to 35 WARN, nothing else. A new table would also add one INFO (rls_enabled_no_policy, now 9); the recommended option avoids that |
| H | Run the suite on live in Stage 2 | Memory note of 2026-11-17: no synthetic data or probes on live until you say "reindex now" | The suite is rolled back and small, and your brief asks for it. Confirm the hold does not cover it |

## 1. Live reads (all read-only)

**Catalogue (`achievements`)**
- `feeling_lucky`: "Feeling Lucky", "Use the workout randomiser", category `fun`, target 1, 10 coins, 25 xp.
- `comeback_king`: "Comeback King", "Start a new streak after losing one over 7 days", category `streak`, target 1, 40 coins, 100 xp.
- No `shop_items` row is gated on either id (0 rows).

**`verify_achievement_progress(text)`**
- md5 `181f6922beb937e7019dbecfa20e1352`, as expected. SECURITY DEFINER, `search_path=public`, ACL postgres/authenticated/service_role. 252 lines, saved for the rollback.
- It hardcodes ids in an `IF … ELSIF p_achievement_id IN (…)` chain, one branch per id group. Each branch sets `v_real_progress`. Anything else hits `ELSE RAISE 'achievement_not_server_verifiable'` (line 205), which is where both ids land today.
- `target_value` is read once from `achievements` (line 24). Then `v_clamped := LEAST(progress, target)` and `v_did_unlock := progress >= target`.
- Payment is gated twice: `already_unlocked` (line 35) and the ledger check on `reference_id = 'achievement_<id>'` (line 233).
- Ids with a fixed threshold and target 1 compute 0 or 1 inside the branch (`personal_best`: `best_streak >= 2`). comeback_king follows that pattern.
- The account-age guard (line 209, streak/loyalty/coop) never blocks a target of 1.

**`award_achievement_rewards(text)`** has a live `feeling_lucky` branch. It pays when a `user_achievements` row is unlocked and no xp ledger row exists. `authenticated` holds only SELECT on `user_achievements` (one select-own policy), so a client cannot reach that branch. I leave it untouched. After the client change nothing in the app calls this function; dropping it can be a separate item.

**`streak_events`**
- Columns: id, user_id, team_id, kind (`own` | `friend`), lost_streak, missed_user_id, created_at, seen_at.
- Unique on (team_id, user_id, lost_streak, UTC date of created_at). `authenticated` has SELECT only.
- One writer, `_record_streak_loss`, which skips losses under 2. It writes one row per non-bot team member: `own` for each misser, `friend` for the rest. It is called from two places:
  1. `reconcile_stale_streaks` (nightly): sets `current_streak = 0` and records the loss.
  2. `_recompute_team_streak`: a mutually complete day after an invalid gap sets `current_streak = 1` and records the loss **in the same transaction**. So the new day and the loss land together.
- `team_streaks` is written only by those two functions. There is one active row per team (unique partial index).

**Randomiser (Flutter)**
- Lives in `lib/widgets/workout_selection_modal.dart`. `_randomise` and `_reRoll` pick a random template and a random duration (15/30/45/60) locally. `_acceptRandom` (line 159) awaits `checkFeelingLucky`, closes the sheet and passes the results up.
- `checkFeelingLucky` (`achievement_service.dart:387`) calls `_upsertProgress('feeling_lucky', 1)`. That tries a direct `user_achievements` upsert, which the grants reject, and the catch returns null.
- So today the randomiser writes nothing to the server, and the workout it starts carries no trace of the randomiser.

**Client UI**
- `dashboard_page.dart:4248` already shows `AchievementToast` for whatever `_acceptRandom` returns. Today it is always empty. After the change the existing toast shows "Feeling Lucky" once, through the existing widget and call site, with no layout change.
- The streak checks (`team_streak_service.dart:526`) run fire-and-forget and discard their results. A comeback_king unlock therefore pays with no toast.
- `achievements_page.dart` is generic: catalogue rows plus own rows, unlocked rows sorted by `unlockedAt`, and no per-id code. Both ids will move to Unlocked by themselves.

## 2. feeling_lucky

**Record (recommended, option B): `user_achievements.progress` for feeling_lucky, written by one new RPC.**
- No DDL and no grant or RLS change.
- `user_achievements` already exists, has the `(user_id, achievement_id)` unique key, and is not client-writable.
- The shop trigger on that table acts only on `unlocked_at` going from NULL to set, so a progress-only write does nothing.

```sql
CREATE OR REPLACE FUNCTION public.record_randomiser_use()
 RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE v_caller uuid := auth.uid();
BEGIN
  IF v_caller IS NULL THEN RAISE EXCEPTION 'unauthenticated'; END IF;
  -- ponytail: capped at target_value, so spam cannot pass the target; add a per-day bound (needs a date column) if target ever goes above 1.
  INSERT INTO user_achievements (user_id, achievement_id, progress)
  SELECT v_caller, a.id, 1 FROM achievements a WHERE a.id = 'feeling_lucky'
  ON CONFLICT (user_id, achievement_id) DO UPDATE
    SET progress = LEAST(COALESCE(user_achievements.progress, 0) + 1,
                         (SELECT target_value FROM achievements WHERE id = 'feeling_lucky'));
END $$;
REVOKE EXECUTE ON FUNCTION public.record_randomiser_use() FROM PUBLIC, anon;
GRANT  EXECUTE ON FUNCTION public.record_randomiser_use() TO authenticated;
```

- **Idempotent and bounded:** each call adds at most 1, and the value never exceeds `target_value`. A holder's row stays as it is.
- **Pays nothing itself.** The verifier pays from this value; the client never supplies a number.
- **Option A (not recommended):** a new `randomiser_uses` table. It needs RLS, `REVOKE ALL FROM anon, authenticated` (ASK FIRST: table grants), and adds an advisor INFO, for the same result.
- **Honest limit:** the randomiser is client-only, so the server cannot prove it was used. Any signed-in user can call the RPC once and earn 25 xp / 10 coins, once per account. That is the same trust level as the intent of the old client upsert, but now bounded and paid once.

## 3. comeback_king

Rule: the caller holds a `streak_events` row (either kind) with `lost_streak >= 7`, and that team's active streak now has `current_streak >= 1`.

Why this holds on both loss paths:
- In the reconcile path, the loss leaves the streak at 0. Only a newly credited day raises it.
- In the recompute path, the loss row and day 1 are written together.
- So `current_streak >= 1` after the loss row exists can only mean a new streak day happened since.
- No date comparison is needed, so there is no UTC-versus-local off-by-one.

**STRICT reset and who qualifies:**
- STRICT resets the team streak for both members, and `_record_streak_loss` writes a row for every non-bot member. The partner who did not miss holds a `friend` row with the same `lost_streak`.
- A new team day needs both members (AND-gate), so both qualify on the same day.
- Coach Max teams record the loss for the user, so a solo comeback counts too. That matches the other streak achievements, which count every team.
- If you want only the member who missed: add `AND e.kind = 'own'`.

**Residual:** the check runs only from the fire-and-forget streak check after each credited day. If that call fails and the streak is lost again before the next check-in, the comeback is not seen. This is acceptable for a once-only flavour badge.

## 4. Exact verifier change

Two `ELSIF` branches go between line 203 (end of `special_path_robot`) and line 205 (`ELSE`). **No line is removed or changed**; lines 1 to 204 and 205 to 252 stay byte for byte. The comment at lines 226-232 still names the `award_achievement_rewards` feeling_lucky branch, which stays.

```sql
  ELSIF p_achievement_id = 'feeling_lucky' THEN
    -- Written only by record_randomiser_use, capped at target_value; authenticated cannot write user_achievements.
    SELECT COALESCE(MAX(progress), 0) INTO v_real_progress
    FROM user_achievements WHERE user_id = v_caller AND achievement_id = 'feeling_lucky';

  ELSIF p_achievement_id = 'comeback_king' THEN
    SELECT (CASE WHEN EXISTS (
      SELECT 1 FROM streak_events e
      JOIN team_streaks ts ON ts.team_id = e.team_id AND ts.is_active
      WHERE e.user_id = v_caller AND e.lost_streak >= 7 AND ts.current_streak >= 1
    ) THEN 1 ELSE 0 END) INTO v_real_progress;
```

**Why `COALESCE(MAX(…), 0)`:** a bare `SELECT … INTO` with no row sets NULL. `LEAST(NULL, 1)` is 1 and `NULL >= 1` is NULL, so `IF NOT v_did_unlock` would fall through and pay.

The migration re-states `REVOKE … FROM PUBLIC, anon` and `GRANT … TO authenticated` for the verifier, plus SECURITY DEFINER and `SET search_path = public`, as in `20261115170000`.

## 5. Lock order

Unchanged, no new lock.
- The new verifier branches are plain SELECTs with no row locks. The pay path after them (L5 user_achievements write, ledger, award_xp/award_coins) is untouched.
- `record_randomiser_use` does one L5 row write on `user_achievements` and takes no other lock. It is not on a credit path.
- G0.4 to G0.12 are unaffected.

## 6. Suite (Stage 2, inlined with `--with`)

New block in `economy_suite.sql`, using the existing `pg_temp.u` / `pg_temp.team` / `_credit_checkin` fixtures:
- **R9.1** feeling_lucky with no use: `unlocked=false`, progress 0, nothing paid.
- **R9.2** one `record_randomiser_use` then verify: unlocked, paid 10 coins / 25 xp.
- **R9.3** replay verify: `already_unlocked`, nothing paid.
- **R9.4** five RPC calls: progress stays 1 (capped).
- **R9.5** comeback_king with a 6-day loss row plus a credited new day: not unlocked.
- **R9.6** a 7-day loss row (via `_record_streak_loss`) with the streak at 0: not unlocked.
- **R9.7** the same after a new credited day: unlocked, paid 40 coins / 100 xp, once.
- **R9.8** replay pays 0.
- **R9.9** both team members qualify. If you choose own-only, this becomes "the friend does not".

Other checks:
- `grants_fresh.sql` G9.12: add `record_randomiser_use` to the anon list. Plus a direct check that anon calling it fails.
- G0.1 unchanged. New G0.14 pins both bodies.

## 7. Client change (Stage 2)

`lib/services/achievement_service.dart` only:
- `checkFeelingLucky`: call `record_randomiser_use` (on error, log and return `[]`), then `_verifyAndUnlock('feeling_lucky')`.
- Delete `_upsertProgress`. Its only caller goes, and `flutter analyze` would flag it as unused.
- Add `'comeback_king'` to the `checkStreakAchievements` id list (decision D).
- No widget change and no new text.
- Round trips on the accept tap stay at 3 (RPC, verify, catalogue read; today it is two reads and a rejected upsert).
- `test/pop_then_act_test.dart` stubs `checkFeelingLucky` through the seam, so it is unaffected.

## 8. Existing users

- No backfill.
- Holders of feeling_lucky keep it: the verifier returns `already_unlocked` before any branch, and the RPC cap leaves their rows alone.
- Current holder count: **could not verify** without reading `user_achievements` (a user table). The tracker says 3 on 2026-11-16.

## 9. Files and rollback (Stage 2)

- `supabase/migrations/20261121120000_r9_earnable_achievements.sql`: new RPC, verifier replaced, grants re-stated.
- `dev/rollback_20261121120000.sql`:
  - restores the live verifier body byte for byte (md5 `181f6922…`) with its grants;
  - `DROP FUNCTION public.record_randomiser_use()`;
  - deletes feeling_lucky rows that are still locked (`unlocked_at IS NULL`).
  - Payouts made in between stay.
- Also changed: `dev/hygiene/suite/economy_suite.sql` (G0.14 and R9 block), `dev/hygiene/suite/grants_fresh.sql` (G9.12), `lib/services/achievement_service.dart`.
- One commit for the migration, the suite pin and the client change.
- Apply: `supabase db push --dry-run` (must list only this file), then `supabase db query --linked -f <file>`, then `supabase migration repair --status applied 20261121120000`, then the dry run again.

## 10. Risks and what I could not verify

- **feeling_lucky** is earnable by a direct RPC call without using the randomiser (section 2). The amount is small and paid once.
- **comeback_king** has the missed-verification residual described in section 3.
- **Holder count:** not verified (user table).
- **Coach Max check-ins:** I did not trace whether they reach `checkStreakAchievements`. If they do not, a solo comeback pays only at the next buddy-team check-in.
- **Pre-existing, outside this item:** `authenticated` holds DELETE on `team_streaks` (G9.13 pins it). For comeback_king that can only remove a user's own evidence; it cannot fake a comeback.
