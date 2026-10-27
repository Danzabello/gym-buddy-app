# Hygiene 05d report

Migration `supabase/migrations/20261013020000_hygiene_05d.sql`, applied on live with `supabase db push` on 2026-10-27. Before this, the latest applied version was 20261013010000 (05b). Rollback: `docs/rollback_20261013020000.sql`. This was a server-only change: no Dart changes, no rebuild needed.

## Fix 1: check_in_coach_max_with_buddy. DONE
No caller found:
- `lib/`, `supabase/functions/`, `test/`: 0 hits. Repo-wide, the only hits are `docs/` and the migrations that created it. `git log -S` on `lib/` puts the last caller removal at b99b0b2.
- `pg_proc.prosrc`: one hit, `_finish_coach_max_checkin`. It is a comment ("the instant-mirror path (check_in_coach_max_with_buddy) can fire …"), not a call.
- Triggers (`pg_trigger.tgfoid`), views, policies, `cron.job`: 0 hits.

Change: `REVOKE EXECUTE … FROM PUBLIC, anon, authenticated`. The function is kept.
- ACL before: `{postgres=X/postgres,authenticated=X/postgres,service_role=X/postgres}`
- ACL after: `{postgres=X/postgres,service_role=X/postgres}`

## Fix 2: purchase_shop_item race. DONE
- `coin_balance` is stored in `public.user_profiles`.
- Change: `PERFORM 1 FROM user_profiles WHERE id = v_caller FOR UPDATE;` runs right after the `unauthenticated` check, so before the ownership, gate and balance checks. The diff against the captured `pg_get_functiondef` is those lines only. SECURITY DEFINER, `search_path=public`, the level and achievement gates, `already_owned`, `award_coins` ledger write and inventory insert are unchanged. REVOKE PUBLIC, anon and GRANT authenticated are re-stated. The ACL is unchanged.
- Audit of writers of `coin_balance`, done before the constraint:
  - The only function that writes it is `award_coins` (service_role/postgres only). No trigger on `user_profiles` writes it (`scrub_team_names_on_profile_delete`, `trg_validate_user_timezone`).
  - There is no client column grant on it. Dart only reads it (`coin_service.dart`). Edge functions: 0 hits.
  - `award_coins` callers: `_apply_checkin_rewards` ×3, `award_achievement_rewards`, `verify_achievement_progress`, `create_invite_team` (20), `_fulfil_invite_reward`. All use positive or config amounts (achievement `coin_reward` min 0). The only negative delta is `purchase_shop_item` (-cost, shop `cost` min 0), behind its balance check.
  - `coin_transactions` with amount < 0: only `shop_purchase`. There are no revival, refund or other negative paths.
- Violating rows before adding the constraint: 0 negative, 0 null (min 0). `user_profiles_coin_balance_nonneg CHECK (coin_balance >= 0)` was added NOT VALID and then VALIDATED in the same migration, behind a DO guard that aborts if any row is < 0. Live: `convalidated = true`.

## Fix 3: rest_tokens_available. DONE
- No writes from the client or edge functions: 0 hits in `lib/` or `supabase/functions/`, and Android/iOS have none either. Server: `get_current_weekly_commitment` and `can_take_rest_day` match "rest_token", but they read `weekly_commitments.rest_tokens_remaining`, not this column.
- Grant shape: `user_profiles` relacl is `{postgres=arwdDxtm/postgres,authenticated=d/postgres,service_role=arwdDxtm/postgres}`. There is no table-level UPDATE; UPDATE is column-level, so a column REVOKE takes effect.
- Change: `REVOKE UPDATE (rest_tokens_available) ON public.user_profiles FROM authenticated`. Column INSERT was left as it was.
- authenticated UPDATE columns, before (22): age, avatar_border, avatar_id, current_weekly_goal, custom_streak_order, display_name, fitness_goals, fitness_level, gender, id, last_check_in_date, looking_for_buddy, onboarding_completed, preferred_streak_sort, preferred_workout_style, preferred_workout_time, rest_tokens_available, timezone, updated_at, username, weekly_commitment_active, workout_days_per_week
- After (21): the same list without rest_tokens_available. Column ACL went from `{authenticated=aw/postgres}` to `{authenticated=a/postgres}`.

## Probes
- `docs/hygiene/05d_probes.sql`: one transaction with the migration inline, ending in RAISE, so all of it rolls back. Permission probes run first, before any privileged call in the session. **17/17 PASS.** Afterwards, live showed no constraint and an unchanged ACL, confirming the rollback.
  - Run 1 had 16 PASS and 1 FAIL (F3.2). The cause was the probe, not the grants: `SET preferred_workout_time = preferred_workout_time` reads a column that authenticated cannot SELECT (LIVE-10 allowlist). F3.2 was rewritten to the avatar picker payload (`avatar_id`, `avatar_border`, `updated_at`) plus `display_name` and `looking_for_buddy`, and it passed.
  - F1: authenticated and anon calls give `42501 permission denied for function`. service_role and postgres keep EXECUTE. `check_in_coach_max` as mijotest returned `{"checked_in": true, "already_done": true}`, no error.
  - F2: 99 coins with cost 100 returned insufficient_funds, balance still 99, no inventory row. 100 coins with cost 100 succeeded, balance 0, inventory row and -100 `shop_purchase` ledger row written. An immediate second purchase (cost 150) returned insufficient_funds, balance 0. Rebuying an owned item returned already_owned. A direct `UPDATE coin_balance = -1`: as postgres it gave `23514` (CHECK); as authenticated it gave `42501`. The def contains FOR UPDATE, and ACL, search_path and DEFINER are unchanged. The constraint is validated.
  - F3: authenticated UPDATE of rest_tokens_available gives `42501`. The avatar picker payload updates 1 row. 21 UPDATE columns remain, INSERT is unchanged.
- `docs/hygiene/05d_fresh_probe.sql`: run after apply on its own connection, authenticated only. **3/3 PASS** (with_buddy denied, rest_tokens UPDATE denied, avatar payload updates 1 row).
- Two-session race (`docs/hygiene/05d_race_A.sql` / `_B.sql`): testtest1 at its committed balance of 0. Session A calls `purchase_shop_item` and holds its transaction open for 8s. B starts about 2s later. Both get insufficient_funds, so nothing is written, and both RAISE, so both roll back.
  - Before apply: B's call took 0.00s (no lock).
  - After apply: B's call took 5.33s. It waited for A's row lock, so per-user purchases now serialise.
  - Not tested: an actual overdraw attempt with real coins, because it would need a committed balance on a test account. It is covered by the serialisation result plus the CHECK.
- `docs/hygiene/05d_rollback_test.sql`: rollback applied inside a rolled-back transaction. **4/4 PASS.** The purchase def md5 is identical to the pre-change capture. The ACL entries are identical, though re-GRANT appends `authenticated` at the end, so the order differs. The rest_tokens ACL is identical and the constraint is gone.

## Snapshots
- Economy hashes (`docs/hygiene/economy_snapshot.sql`), before vs after apply: **identical.**
  - h=886b65c53656fded08dc54d4871befb7 | n=5567 | t=daily_team_checkins
  - h=c60486dc8fefd2536c1f1aaa98c2eda3 | n=17 | t=workout_logs
  - h=df4e1370aca270f8415d9abbef1a7dc8 | n=111 | t=xp_transactions
  - h=0d94ba937f3f1498bd58cc76f32a7472 | n=101 | t=coin_transactions
  - h=bd57b7f0a45bd3477d04d45d13e82e48 | n=40 | t=team_streaks
  - h=014aa29848c6fba4f55619bab9a88693 | n=39 | t=user_profiles_xp_coins
  - h=f55b509c3641f2482d0096257e775a84 | n=57 | t=workouts
- Advisors:
  - Security: `authenticated_security_definer_function_executable` went from 36 to 35. Only `check_in_coach_max_with_buddy` dropped out. `rls_enabled_no_policy` (4) and `auth_leaked_password_protection` (1) are unchanged. No new findings.
  - Performance: 129 findings before and after, identical line for line (68 auth_rls_initplan, 36 multiple_permissive_policies, 17 unindexed_foreign_keys, 8 unused_index).
- md5 parity: `schema_migrations.statements` vs the local file, with whitespace and `;` normalised (method checked first on 05b and 05c, both MATCH): 20261013020000 remote=ea760c0e9835c4421141da6f50a7c7e9 local=ea760c0e9835c4421141da6f50a7c7e9 MATCH. `db push --dry-run` after apply says "Remote database is up to date".

## Skipped
- mijotest3 has no row in `user_profiles` (by username), so it was not used. The probes used testtest1 and mijotest.
- INSERT on `rest_tokens_available` is still granted (not in scope). If nothing ever inserts it, it can be revoked the same way.

## Noticed, not fixed
- `lib/services/level_service.dart` `_applyXp` does a client `update({'xp', 'level'})` on `user_profiles` and a client insert into `xp_transactions`. authenticated has no UPDATE on xp or level, so this would fail with 42501. Its only entry point, `awardWorkoutXP`, has no callers, so it is dead code and could be deleted.
- `cron.job` `expire-stale-workout-invites` still runs after 05c dropped `workout_invites`. It succeeds (576 runs in 2 days, all succeeded), so no action is needed.
