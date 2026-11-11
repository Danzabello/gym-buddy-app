# Hygiene 05e report

These checks were run on live on 2026-10-27 between 16:41 and 16:49 UTC, outside the 22:55–23:15 reset window. `supabase login` was valid. No migration was needed: the only change in 05e is docs. The committed rows were the test-account writes in Check 2 (seed and race, run twice), and all of them were deleted or restored afterwards.

| Check | Result |
|---|---|
| 0 Push state | DONE: 1 unpushed commit (`0b03869`, 05d), checked before the 05e commit |
| 1 CRON-1 | DONE: the job is alive and useful, so nothing was changed. The 05d note is corrected |
| 2 RACE-2 | DONE: PASS on the second attempt (the first attempt was invalid, see below). Everything restored, hashes identical |
| 3 ACCT-1 | DONE: mijotest3 is a real account whose username is NULL |
| 4 05d re-verify | DONE: all items PASS |

## Check 0: push state
`git status` was clean. `git log origin/main..main` returned 1 commit: `0b03869` (Hygiene 05d).

## Check 1 (CRON-1): expire-stale-workout-invites
`select jobid, jobname, schedule, active, command from cron.job where jobname='expire-stale-workout-invites'`:

    12 | expire-stale-workout-invites | */5 * * * * | active=true | SELECT public.expire_stale_workout_invites();

`cron.job_run_details`, last 7 days: **2016 succeeded, 0 failed**. That is 288 runs a day × 7, every run. The earliest retained row is 2026-10-20 03:20 (the purge keeps 7 days). The 10 most recent runs were 15:55 to 16:40 UTC, every 5 minutes, each `succeeded | 1 row`.

**Why it succeeds:** case (d), the name points at a different object than expected. It is a direct SQL call, not pg_net/HTTP, so (c) is ruled out. The body has no EXCEPTION handler, so (b) is ruled out:

    CREATE OR REPLACE FUNCTION public.expire_stale_workout_invites() RETURNS integer
     LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public' AS $function$
    DECLARE v_n integer;
    BEGIN
      UPDATE workouts
      SET status = 'cancelled',
          buddy_status = CASE WHEN buddy_status = 'pending' THEN 'expired' ELSE buddy_status END,
          closed_reason = 'expired', updated_at = now()
      WHERE buddy_id IS NOT NULL AND status = 'scheduled'
        AND planned_at + interval '15 minutes' < now();
      GET DIAGNOSTICS v_n = ROW_COUNT; RETURN v_n;
    END; $function$

- **Origin:** handshake Phase A, `20261008180000_handshake_server_phase_a.sql:656-679`. That migration created the function and scheduled the job. It was written for the new `workouts.buddy_id` buddy-invite model and has nothing to do with the dropped `workout_invites` table.
- **ACL:** `{postgres=X/postgres,service_role=X/postgres}`.
- **Is it useful?** Yes. It is the only writer of `closed_reason = 'expired'` (no other function contains it). It has expired 4 workouts so far, the latest at 2026-10-12 17:50 UTC. Nothing matches right now (0 rows), which is why recent runs are no-ops.
- **Action:** none. No migration.

**Sweep for objects dropped in 05b/05c/05d** (workout_invites, notify_workout_invite, notify_workout_invite_response, is_user_in_active_workout, get_workouts_awaiting_creator_join, ready_expires_at, creator_popup_shown, workout_join_popups_enabled, checkin_team_for_user, check_duplicate_team):

| Where | Hits |
|---|---|
| cron.job commands | `expire-stale-workout-invites`. False positive: it is the substring inside the function name |
| pg_proc.prosrc (all non-system schemas) | 0 |
| pg_views / pg_matviews | 0 |
| pg_policies (qual / with_check) | 0 |
| pg_trigger functions | 0 |
| existing objects with those names | only the function `expire_stale_workout_invites` (the same substring false positive) |
| supabase/functions/ | 0 |
| lib/ | `lib/pages/schedule_page.dart:9` imports `lib/widgets/workout_invites_list.dart`. False positive: it is a UI widget fed by props, with no `.from`/`.rpc`/Supabase access |

There are no live leftovers.

**Correction:** the 05d report said "no action is needed" for this job based only on run status, without looking at the command. The conclusion turns out to be right, but for the reason above, which 05d had not shown. A correction note has been added to `05d_report.md`.

## Check 2 (RACE-2): overdraw test with committed rows
**This was a real overdraw test that wrote committed rows to testtest1 on live. It was approved ("GO") before it ran, and everything was restored afterwards.**

- **Account:** testtest1 `cf4946f5-f921-4e81-bbf4-88d574e8baf5`, level 1.
- **Baseline:**
  - `coin_balance` 0; 0 `user_inventory` rows; 0 `coin_transactions` rows (sum 0).
  - Full-row md5 `f4ab2b5b2b471a05b917be8b4bbedcc2`; `user_inventory` table md5 `e26cb0e9a45c6f092caa383360f0e7fd` (n=6).
  - Economy hashes as below.
- **Items:** both available, cost > 0, unlock_level 1, no achievement requirement, not owned.
  - item1 is Star Streak, `78594031-1074-46ed-b80b-a1cbcb7043b0`, cost 150 (session A).
  - item2 is Early Adopter, `9eeca178-1353-406d-8671-54e59bdcf26d`, cost 100 (session B).
  - Seed is max = 150; 150 + 100 > 150.
- **Side effects:** no triggers on `user_inventory` or `coin_transactions`, and no FKs reference them. Both id columns are `gen_random_uuid()`, so no sequences are consumed.
- **Scripts:** `05e_race_seed.sql` (direct UPDATE as postgres, no credit function, aborts if the baseline has changed), `05e_race_A.sql`, `05e_race_B.sql`, `05e_race_verify.sql`, `05e_race_cleanup.sql` (one transaction that aborts unless testtest1 is back to balance 0 with 0 rows). Each session is its own connection: authenticated testtest1 via JWT claims, with results captured in a session temp table.

**Attempt 1 was invalid (my shell error).** The `&` backgrounded the line that set the output-path variable, so session B's redirect failed and **B never ran**. Session A ran alone: Star Streak succeeded and committed at 16:47:32, leaving balance 0, 1 inventory row and 1 ledger row of -150. That is not a race. I ran the approved cleanup, confirmed that the economy hashes, the `user_inventory` hash and testtest1's row md5 all equalled the baseline, and repeated the same approved seed and race.

**Attempt 2: PASS.**

| | call start (UTC) | call returned | wait | result | committed |
|---|---|---|---|---|---|
| A (Star Streak 150) | 16:48:19.863 | 16:48:19.867 | 0.00 s | `{"success": true, "new_balance": 0}` | 16:48:27.876 (after ~8 s hold) |
| B (Early Adopter 100) | 16:48:21.909 | 16:48:27.877 | **5.97 s** | `{"success": false, "reason": "insufficient_funds", "balance": 0, "cost": 100}` | 16:48:27.878 |

B blocked on A's row lock and returned 1 ms after A committed. It saw the committed balance of 0 and was refused.

Verify (`05e_race_verify.sql`): `coin_balance` 0, which equals 150 - 150 and is never below 0. 1 inventory row (Star Streak). 1 ledger row (`shop_purchase:-150:78594031-…`). `pass = true`.

**Before the race fix (05d control):** the same two-session shape at balance 0 had B wait 0.00 s. Without the lock, both calls would read 150 and both purchases would pass the balance check.

**Cleanup (both attempts):** the 1 `user_inventory` row and the 1 `shop_purchase` `coin_transactions` row were deleted, identified as testtest1's rows for the two probe item ids (the baseline had none). `coin_balance` was restored to 0. Final state: `coin_balance=0 inv=0 tx=0`.

**Hash comparison after the final cleanup: identical to the baseline.**

    h=886b65c53656fded08dc54d4871befb7 | n=5567 | t=daily_team_checkins
    h=c60486dc8fefd2536c1f1aaa98c2eda3 | n=17 | t=workout_logs
    h=df4e1370aca270f8415d9abbef1a7dc8 | n=111 | t=xp_transactions
    h=0d94ba937f3f1498bd58cc76f32a7472 | n=101 | t=coin_transactions
    h=bd57b7f0a45bd3477d04d45d13e82e48 | n=40 | t=team_streaks
    h=014aa29848c6fba4f55619bab9a88693 | n=39 | t=user_profiles_xp_coins
    h=f55b509c3641f2482d0096257e775a84 | n=57 | t=workouts
    user_inventory e26cb0e9a45c6f092caa383360f0e7fd n=6 (baseline identical)
    testtest1 full row md5 f4ab2b5b2b471a05b917be8b4bbedcc2 (baseline identical)

**CHECK re-confirm** (`05e_check_probe.sql`, own connection, authenticated call first, rolled back): 2/2 PASS.
- authenticated `UPDATE coin_balance` gave `42501 permission denied for table user_profiles`.
- postgres `UPDATE coin_balance = -1` gave `23514 … violates check constraint "user_profiles_coin_balance_nonneg"`.

## Check 3 (ACCT-1): mijotest3
`user_profiles where username or display_name ilike '%mijo%'`, as id | username | display_name | created_at | is_bot:

    6dfac56a-74a1-4a60-b7fa-e200338350f3 | mijotest | mijotest  | 2025-11-19 20:39 | false
    8f399b74-d1e1-4236-a3d3-3bd7eea78e69 | NULL     | mijotest2 | 2025-11-19 20:59 | false
    f7c1ef63-3b93-401d-b2bb-8402ddf9a881 | NULL     | mijotest3 | 2025-11-19 21:07 | false
    a1c875ae-59c2-4bed-b2ba-cf11ff23b397 | NULL     | mijotest4 | 2025-11-19 21:30 | false
    1d9154d6-f734-42bc-992f-80580a84c365 | NULL     | mijotest6 | 2025-11-20 16:53 | false

**mijotest3 is a real, complete account** (`f7c1ef63-…`): it has an auth user (created 2025-11-19 21:07:05) and a profile row. Its `username` is NULL and the name lives only in `display_name`. 05d searched by username, which is why it found nothing. Separately, the auth email of `c5e5f12c-5e6e-40a1-9a05-aedc3b017a66` (display_name "Doroda") matches '%mijo%'; the email is not printed.

**Totals:** 51 auth users and 39 profiles.

Auth users with no `user_profiles` row (orphans: 13, ids and created_at only):

    0f733117-cd2c-4be9-9571-fadef853d8d4 2025-09-24   adf35e30-c156-46d5-b227-32cb61d84e81 2025-09-25
    3efc778e-fa38-410a-9e92-6c56d9091453 2025-09-25   8cdf7235-ecc2-4471-902d-63f16e4a94ac 2025-09-25
    c596f1c0-8dcf-4e99-be0f-e3e5f3d514a7 2025-11-06   a9f7da7d-551a-438f-834a-a17a6d07c09e 2025-11-06
    229d9bcd-3f44-4ac7-b77d-1d9bb01bd06c 2025-11-06   3e013677-5d3d-4b99-abaf-5af89886aab2 2025-12-15
    c8880ff2-1e5a-4fa1-b595-9362e4e99ddf 2025-12-15   ec90e934-c797-4b0d-b677-1161e692f5a4 2026-03-14
    e4efdd7a-222d-494f-84b6-dab5229caaf0 2026-03-15   40395069-0273-474e-888c-5caeb2935b8f 2026-03-15
    56b4a556-8105-40d9-bcf3-49c312461f73 2026-03-16

Profiles with no auth user: 1, Coach Max `00000000-0000-0000-0000-000000000001` (is_bot, expected).

**All non-bot users (38), the list for LAUNCH-CLEAN**, as id | username | display_name | created:

    1. 01931108-299b-40c3-a306-bf526ab6e81c | ∅ | Zello | 2025-09-25
    2. dbc1216b-11dd-4bab-8d89-16fc423a9358 | ∅ | lukibear | 2025-09-26
    3. e77c99b9-d9fe-4a80-abf4-c8103919ace8 | ∅ | friend1 | 2025-10-01
    4. 380d0d9b-7c26-43b4-8057-bf018fb5bf59 | ∅ | friend2 | 2025-10-01
    5. c5e5f12c-5e6e-40a1-9a05-aedc3b017a66 | ∅ | Doroda | 2025-10-02
    6. 9155e9ff-3a7a-48e4-af7e-a9a923ed6c1f | ∅ | max | 2025-10-15
    7. dfaeac50-0476-45c8-b7b1-0f08df78bb6e | ∅ | max2 | 2025-10-15
    8. 3c7f73a4-ffb1-4fca-ad87-05cfe35cc878 | ∅ | max3 | 2025-10-15
    9. 7b469dba-545b-4753-a6e7-46a70ed612a3 | ∅ | ts4 | 2025-11-06
    10. 0a1d1bf6-6d7f-476f-9b13-1e17d37491cf | ∅ | ManziMuscleMan | 2025-11-07
    11. ef7c4f33-b9e1-46ee-8ae4-cfbf23858cda | ∅ | ts10 | 2025-11-10
    12. eedf1324-b99a-483f-a864-ad6a278e873f | ∅ | ts11 | 2025-11-10
    13. 591e569a-557b-4bd3-bdcd-1ab86cfb98d0 | ∅ | newaccount | 2025-11-14
    14. c01a4460-e84b-4b1a-ae45-f96bc9a4898f | ∅ | newaccount2 | 2025-11-14
    15. 5415e3be-1399-4009-918d-e764a6db199e | ∅ | newtestaccount | 2025-11-16
    16. 07960b8c-300b-44cb-89dd-93f3f38099b8 | ∅ | newtestaccount2 | 2025-11-16
    17. 2b61ae0f-655f-4111-b754-b18e00afe9d8 | ∅ | newtestaccount3 | 2025-11-16
    18. 931c0905-7ad7-4585-8ce6-d3bd24722272 | ∅ | newtestaccount4 | 2025-11-16
    19. 2a5c7f3e-85c5-4e47-b1f0-d1b5f3d40161 | ∅ | newtestaccount5 | 2025-11-16
    20. 033a3df0-74ea-47b5-8452-7dba9d7f5784 | ∅ | testimage | 2025-11-16
    21. dacb9893-9c7d-4564-8433-2a9abc186e3f | ∅ | testtest | 2025-11-18
    22. 6dfac56a-74a1-4a60-b7fa-e200338350f3 | mijotest | mijotest | 2025-11-19
    23. 8f399b74-d1e1-4236-a3d3-3bd7eea78e69 | ∅ | mijotest2 | 2025-11-19
    24. f7c1ef63-3b93-401d-b2bb-8402ddf9a881 | ∅ | mijotest3 | 2025-11-19
    25. a1c875ae-59c2-4bed-b2ba-cf11ff23b397 | ∅ | mijotest4 | 2025-11-19
    26. 1d9154d6-f734-42bc-992f-80580a84c365 | ∅ | mijotest6 | 2025-11-20
    27. 12cfd0da-bb8e-4e54-83d6-bd4735decaa8 | ∅ | newsetup | 2025-12-15
    28. 5ead0cad-0601-4ac4-a813-016940b0ab3b | piiiipa | onboarding | 2025-12-30
    29. 5e5c9752-7ff9-4b67-8800-915c2515d88b | sophtest | sophtest | 2026-03-14
    30. cf4946f5-f921-4e81-bbf4-88d574e8baf5 | testtest1 | testtest1 | 2026-03-14
    31. 068f10c8-3b6c-4a5d-8864-6f93c0149029 | testtest4 | testtest4 | 2026-03-15
    32. 64de5abb-df2e-4d87-b80a-4dc70742df86 | testtest6 | testtest6 | 2026-03-15
    33. 8ba545a4-caf8-4f56-941a-82bd9ddd942a | invitetest | invitetest | 2026-04-29
    34. a216c75b-3daf-4c3f-8fa3-375de0a653ed | princemj | prince MJ | 2026-05-24
    35. 7c8158ca-763c-410f-9378-4fe81eb201bb | test12345 | test12345 | 2026-06-28
    36. 6c21da10-7c38-46f8-85a9-5810285b1206 | saveprofile | saveprofile | 2026-06-30
    37. 5e67f64d-16e3-4b09-9b00-ddc49df8c3f6 | rokitest1 | rokitest | 2026-09-02
    38. 6ef4e82e-a54d-4b91-8ce4-b5f179a65f66 | newesttest | newesttest | 2026-09-29

Nothing was modified.

## Check 4: 05d re-verified on live

| Item | Result | Evidence |
|---|---|---|
| `user_profiles_coin_balance_nonneg` validated | PASS | `pg_constraint`: `convalidated=true CHECK ((coin_balance >= 0))` |
| purchase_shop_item lock before the balance check | PASS | `position('FOR UPDATE' in prosrc)=428` < `position('< v_cost')=1888` |
| purchase_shop_item DEFINER / search_path / ACL | PASS | `prosecdef=true`, `{search_path=public}`, `{postgres=X/postgres,authenticated=X/postgres,service_role=X/postgres}` (no PUBLIC, no anon) |
| check_in_coach_max_with_buddy ACL | PASS | `{postgres=X/postgres,service_role=X/postgres}` |
| rest_tokens_available UPDATE revoked | PASS | `has_column_privilege(...,'UPDATE')=false`; attacl `{authenticated=a/postgres}` (INSERT still granted, as reported) |
| 21 remaining UPDATE columns | PASS | age, avatar_border, avatar_id, current_weekly_goal, custom_streak_order, display_name, fitness_goals, fitness_level, gender, id, last_check_in_date, looking_for_buddy, onboarding_completed, preferred_streak_sort, preferred_workout_style, preferred_workout_time, timezone, updated_at, username, weekly_commitment_active, workout_days_per_week |
| Security advisors | PASS | authenticated_security_definer_function_executable 35, rls_enabled_no_policy 4, auth_leaked_password_protection 1 (unchanged) |
| Performance advisors | PASS | 129 findings, identical line for line to 05d's after-state |
| Latest migration | PASS | `max(version) = 20261013020000` |
| md5 parity | PASS | `20261013020000 remote=ea760c0e9835c4421141da6f50a7c7e9 local=ea760c0e9835c4421141da6f50a7c7e9 MATCH` (normalised method from 05d) |
| `db push --dry-run` | PASS | "Remote database is up to date." |
| 05d files tracked | PASS | `git ls-files`: 05d_fresh_probe.sql, 05d_probes.sql, 05d_race_A.sql, 05d_race_B.sql, 05d_report.md, 05d_rollback_test.sql, docs/rollback_20261013020000.sql |

## Dead-code leftovers (listed, not fixed)
- `lib/services/level_service.dart:79` `awardWorkoutXP` → `:97` calls `_applyXp` (defined at `:184`). The client `update({'xp','level'})` at `:207` and the `xp_transactions` insert at `:213` would get 42501. Callers across `lib/`, `test/` and `integration_test/`: none (the only other hit is the comment at `:7`).
- `user_profiles.rest_tokens_available`: column-level INSERT is still granted to authenticated (`{authenticated=a/postgres}`). Nothing reads or writes the column.
- `public.check_in_coach_max_with_buddy(uuid)`: still exists, has no client grants (`{postgres=X/postgres,service_role=X/postgres}`) and no callers. Candidate for a DROP; the only reference is a comment in `_finish_coach_max_checkin`.

## Noticed, not fixed
- 13 auth users have no profile row (listed above). Worth handling in LAUNCH-CLEAN alongside the test profiles.
- 26 of the 38 non-bot profiles have `username` NULL. Any check or cleanup that matches on username alone will miss them, as 05d did.
