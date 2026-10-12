# 05b credit-path sweep (2026-10-13)

Migration `20261013010000_credit_sweep_05b`. Probes: `docs/hygiene/05b_probes.sql`. Rollback: `docs/rollback_20261013010000.sql` (tested by `docs/hygiene/05b_rollback_test.sql`, result IDENTICAL).

## Step 1: references to objects dropped in 05c

Searched for `workout_invites`, `ready_expires_at`, `creator_popup_shown`, `workout_join_popups_enabled`, `notify_workout_invite`, `notify_workout_invite_response`, `is_user_in_active_workout`, `get_workouts_awaiting_creator_join`.

| Place | Hits |
|---|---|
| `pg_proc.prosrc` (all schemas) | none |
| `pg_policies`, `pg_trigger`, views, matviews, publications, columns, relations | none |
| `cron.job.command` | `expire-stale-workout-invites` calls `expire_stale_workout_invites()`. This matched by name only: the function updates `workouts` (pending buddy invites to expired). It is live and correct (576/576 runs succeeded in 2 days). No change. |
| `net._http_response` since 05c | 6 × 200, no errors |
| Edge functions, repo and deployed (all 5 downloaded) | none. Deployed matches repo except a trailing newline in `invite-redirect`. |
| Dart `lib/`, `test/` | filename only: `lib/pages/schedule_page.dart:9` and `test/handshake_card_test.dart:6` import `widgets/workout_invites_list.dart`, which reads `workouts.buddy_status`. Not a reference to the dropped table. No client change needed. |
| docs / seed SQL | Historical probe, rollback and backup files only (05a/05a2/05c, H1/H2, the pre-VC baseline). There is no seed file. `docs/handshake/H1_phase_b_lockdown.sql:15` mentions `ready_expires_at` in a comment only. |

No server-side fix needed.

## Step 2: `checkin_team_for_user` removed

- No dependents in `pg_depend`. No mentions in any `prosrc`, cron job, Dart, or edge function (repo and deployed).
- **What its partner-credit branch did:** the caller could name either participant of any workout (`p_target_user_id` had to be the creator or the buddy). It inserted a `daily_team_checkins` row for that person, for the person's local today, on every active streak they belong to, and ran `_apply_checkin_rewards` (XP, coins, streak) for each. It never checked workout status, start time, duration, readiness or the date, so a scheduled workout that never started was enough. 05c revoked its EXECUTE; this migration drops it.
- **Partner credit after the drop:**
  - Client-callable: only `finish_checkin_session` (M6a/FIN-1). It credits the partner only when the partner pressed "I'm here" (`*_ready`) and did not cancel, and the workout started at least 15 minutes ago and is no more than 210 minutes old (or is a real completion of at least 15 minutes).
  - Server-only: the cron `process_stale_sessions` calls `_auto_credit`, which auto-completes overrunning sessions for each participant who was ready and did not cancel. It has no client EXECUTE.
  - Probe S2.3 shows `_server_checkin` is called only by `finish_checkin_session` and `_auto_credit`, and `_apply_checkin_rewards` only by `_server_checkin` and `award_checkin_rewards` (service_role only).

## Step 3: functions executable by authenticated/anon that can write economy or progress state

Inventory covered 55 public functions executable by `authenticated`, `anon` or `PUBLIC` (none economy-writing is `anon`-executable):

- **13 trigger functions.** These can't be called through `/rpc`. They run as the invoker, so they keep EXECUTE.
- **24 functions that reach the listed tables**, directly, through callees, or through table triggers. All 24 are below.
- **18 that don't reach them:** `accept_invite`, `create_invite`, `declare_break_day`, the `get_*` readers, `is_on_break_today`, `safe_user_tz`, `search_usernames`, `can_take_rest_day`, `check_team_streak_status`, `get_random_team_name`, `get_level_for_xp`, `get_user_team_ids()`.

Callees `award_xp`, `award_coins`, `_apply_checkin_rewards`, `_server_checkin`, `_auto_credit`, `award_checkin_rewards`, `_recompute_team_streak`, `_finish_coach_max_checkin` and `_record_streak_loss` are service_role/postgres only (probe S3.2).

All 24 are SECURITY DEFINER with `search_path=public` pinned.

| Function | Guard | Member/participant check | Pays without real workout? | Caller | Verdict |
|---|---|---|---|---|---|
| accept_workout_invite | uid NOT NULL; `_hs_lock` participant; must be buddy | yes | no (state only) | Dart handshake_service | SAFE |
| award_achievement_rewards | uid NOT NULL; delegates to verify except `feeling_lucky`, which needs an unlocked row nothing can create | own rows | see verify | Dart | SAFE |
| cancel_workout | uid; participant; must be creator | yes | no | Dart | SAFE |
| cant_make_it | uid; participant; must be buddy | yes | no | Dart | SAFE |
| change_workout_time | uid; participant; must be creator | yes | no | Dart | SAFE |
| check_in_coach_max | `auth.uid() = p_user_id`; schedule row due | own Coach Max team | Coach Max's row only; no XP/coins | Dart coach_max_service | SAFE |
| check_in_coach_max_with_buddy | `auth.uid() = p_user_id`; needs the user's own check-in today | own Coach Max team | Coach Max's row only; accepts a self-inserted row (F2) | **none** (client moved to finish_checkin_session in b99b0b2) | NEEDS-DECISION |
| complete_workout | uid; participant; in_progress; ≥ 15 server-measured minutes | yes | no | Dart | SAFE |
| create_buddy_team | uid; accepted friendship with `p_friend_id` | yes | no (empty streak) | Dart | SAFE |
| create_invite_team | `auth.uid() = p_invitee_id`; accepted invite from `p_inviter_id` | yes (invite) | yes: 20 coins `invite_bonus` per inviter, no activity gate (F3) | Dart onboarding | NEEDS-DECISION |
| decline_workout_invite | uid; participant; must be buddy | yes | no | Dart | SAFE |
| ensure_coach_max_team | uid NOT NULL; caller only | self | no (empty streak) | Dart | SAFE |
| finish_checkin_session | uid; real session or eligible workout (FIN-1 gates) | yes | no | Dart | SAFE |
| go_solo | uid; participant; must be creator | yes | no | Dart | SAFE |
| im_here | uid; participant; planned window −5/+15 min | yes | no | Dart | SAFE |
| leave_workout | uid; participant | yes | no | Dart | SAFE |
| mark_notice_seen | uid; own rows; seen flags only | self | no | Dart | SAFE |
| nudge_workout | uid; participant; window; rate limit | yes | no | Dart | SAFE |
| purchase_shop_item | uid; level/achievement locks; balance | self | no (spends) | Dart | SAFE |
| recompute_team_streak | member of the streak's team (or service role) | yes | yes, combined with a direct `daily_team_checkins` INSERT (F1) | Dart (3 sites), coach-max-cron | NEEDS-DECISION |
| register_device_token | uid; own token; takes over the token from another user (device handoff) | self | no | Dart | SAFE |
| remove_friend | uid; must be friends | yes | no (deletes) | Dart | SAFE |
| verify_achievement_progress | uid; recomputes progress from tables; pays once per achievement | self | indirectly: streak/coop achievements read `daily_team_checkins` and `team_streaks`, which F1 can inflate | Dart | NEEDS-DECISION (follows F1) |
| cleanup_workout_sessions | trigger function, not callable via `/rpc` | n/a | n/a | trigger on workouts | SAFE |

Counts: SAFE 19, UNGUARDED-USED 0, UNGUARDED-UNUSED 0, NEEDS-DECISION 4 (check_in_coach_max_with_buddy, create_invite_team, recompute_team_streak, verify_achievement_progress). No revokes were made: nothing was both unguarded and unused.

**Confused-deputy check** (DEFINER, executable by authenticated, takes a user id): `check_in_coach_max`, `check_in_coach_max_with_buddy`, `create_invite`, `create_invite_team(p_invitee_id)`, `get_user_streaks` and `get_favourite_categories` compare the id to `auth.uid()`. `create_buddy_team` and `remove_friend` require a friendship with it. `create_invite_team(p_inviter_id)` requires an accepted invite from that inviter. `safe_user_tz`, `get_teammate_timezones` and `get_team_checkin_order` filter by team membership or friendship. No unguarded case.

### Findings for decision (probe output in `05b_probes.sql`, all rolled back)

- **F1: direct check-in plus recompute advances a streak with no workout (open audit item A-3, table grant, not a function).** `authenticated` has INSERT on `daily_team_checkins`. The RLS policy only requires your own row in your own team, and the trigger pins the date to today. As mijotest, with no session and no workout: `INSERT INTO daily_team_checkins (team_streak_id, user_id) VALUES ('8bef7476…', mijotest)` then `rpc recompute_team_streak('8bef7476…', today)` returned `{"updated": true, "old_streak": 1, "new_streak": 2}`. On a Coach Max team the bot is excluded from the AND-gate, so a solo user can do this every day. Buddy teams need the partner's row for the day too.
  - No XP or coins are paid directly: `_apply_checkin_rewards` only runs from `_server_checkin`. That function then skips the day (`ON CONFLICT DO NOTHING`), so a later real finish earns nothing for that day.
  - The inflated rows still feed `verify_achievement_progress`: streak, coop, `early_bird`/`night_owl`, `dynamic_duo` and `coach_max_grad` pay XP and coins. They also feed `_fulfil_invite_reward`, which pays the inviter 20 coins once the invitee has 2 distinct check-in days.
  - Fixing this needs the client backfill inserts removed (`team_sync_service.dart:106`, `friend_service.dart:250,261`) and the INSERT grant/policy dropped. That is a client change, so it was not done here.
- **F2: `check_in_coach_max_with_buddy` has no client caller.** It is guarded (`forbidden` for another user, probe S3.3), but it accepts the self-inserted row from F1 and writes Coach Max's check-in. Recommend revoking EXECUTE from authenticated in a follow-up. It was not changed because the verdict rule only revokes unguarded-unused functions.
- **F3: invitee bonus is per inviter with no activity gate.** As rokitest1: `accept_invite` for codes from testtest4 and testtest1, then `create_invite_team` for each, paid +40 coins (2 `invite_bonus` rows). A repeat call for the same inviter paid nothing. Fixture: both invites were backdated to one minute before rokitest1's signup to simulate a fresh account, because `accept_invite` only accepts invites under 7 days old. With throwaway inviter accounts, a new user can farm 20 coins per inviter. Inviters are not paid at accept time (S3.4).

### Other observations (tracker, not changed)

- `purchase_shop_item` takes no lock. Two concurrent purchases of different items can both pass the balance check, and `coin_balance` has no `>= 0` constraint, so the balance can go negative. The same item is protected by the unique `(user_id, shop_item_id)` index.
- `user_profiles.rest_tokens_available` is client-updatable at column level. No server function reads it today.
- `coach_max_schedule` INSERT is client-allowed (own rows). A user without a cron-created row can insert one with an early `scheduled_time`, then `check_in_coach_max` writes Coach Max's check-in immediately. That gives no XP. `special_path_robot` (avatar unlock, 0 XP / 0 coins) counts `has_checked_in`.
- No Dart or edge caller: `can_take_rest_day`, `check_team_streak_status`, `get_current_weekly_commitment`, `get_random_team_name` (INVOKER, read-only) and `get_team_checkin_order` (DEFINER, read-only, guarded). These are candidates for a revoke/drop pass. `safe_user_tz` has no client caller but must keep EXECUTE, because invoker triggers (`_pin_client_checkin_date`, `_set_workout_planned_at`) and `is_on_break_today` call it as `authenticated`.
