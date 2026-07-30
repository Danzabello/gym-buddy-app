# Gym Buddy — Architecture Map

Originally generated 2026-07-05 from the actual codebase (`lib/`, `supabase/`) and the live Supabase project `jwpbunulswiihkzpjopy` (schema, `pg_proc`, `pg_policies`, `pg_trigger`, `cron.job`, deployed Edge Functions). Structured for diagramming: each row is a node with its edges.

> **Not a current snapshot.** This is the 2026-07-05 generation with individual rows hand-patched since. The `user_profiles`, `friend_requests`, `team_members`, `daily_team_checkins` and `invites` rows in §3 were corrected on 2026-07-27 to match live after the security fixes of that date; every other row still reflects 2026-07-05 and may be stale. Verify against `pg_policies` / `pg_proc` before relying on any RLS or function detail here. Rows corrected on a given date cite the commit that changed the behaviour.

---

## 1. Screens / Pages

Full-screen routes. Modal sheets/dialogs that carry real logic are listed separately below.

| Screen | File | Purpose | Entered from | Navigates to |
|---|---|---|---|---|
| `AuthWrapper` | `lib/main.dart` | Root router; checks session + `user_profiles.onboarding_completed`; deep-link (`app_links`) interception; deletes orphaned accounts via `delete_own_account` | App launch | `SplashScreen` (no session), `OnboardingValueProps` (incomplete onboarding), `HomeScreen` (complete) |
| `SplashScreen` | `lib/onboarding/splash_screen.dart` | Branding / entry | `AuthWrapper` (unauthenticated) | `LoginScreen` |
| `LoginScreen` | `lib/login_screen.dart` | Email/Google sign-in; orphan-account cleanup (`delete_own_account`) | `SplashScreen`, sign-out from `HomeScreen` | `SignUpScreen`, `AuthWrapper` re-route on success |
| `SignUpScreen` | `lib/signup_screen.dart` | Account creation | `LoginScreen` | back to auth flow → `OnboardingValueProps` |
| `OnboardingValueProps` | `lib/onboarding/onboarding_value_props.dart` | 3-slide value pitch; buddy search/invite teaser | `AuthWrapper` (authenticated, onboarding incomplete) | `OnboardingBasicInfoNew` |
| `OnboardingBasicInfoNew` | `lib/onboarding/onboarding_basic_info_new.dart` | 5-step wizard (username → avatar → goals → buddy prefs → confirmation); saves profile; redeems pending invite (`create_invite_team`); sends queued friend requests | `OnboardingValueProps` | `HomeScreen` (`pushAndRemoveUntil`) |
| `HomeScreen` (shell) | `lib/home_screen.dart` | 5-tab bottom-nav shell + central fire check-in button | `AuthWrapper`, onboarding completion | Tabs below; `LoginScreen` on sign-out |
| ├ `DashboardPage` | `lib/home_screen.dart:143` | Streak cards, check-in button, break-day section, Coach Max widget, workout invites, join-workout popups | HomeScreen tab 1 | `WorkoutCheckInSheet`, `WorkoutSelectionModal`, `_AllStreaksDialog`, `_WeeklyPlanDialog`, `CustomStreakSelector` |
| ├ `FriendsPageModern` | `lib/widgets/friends_page_modern.dart` | Buddy list with presence + break-day badges; friend requests; nudges; invite links | HomeScreen tab 2 | `_SearchBuddiesPage`, `_AddBuddiesPage`, `BuddyProfileSheet`, `ProfileViewDialog` |
| ├ `SchedulePage` | `lib/home_screen.dart:5348` | Scheduled/upcoming workouts; complete/cancel; ready-check flow | HomeScreen tab 3 | `ScheduleWorkoutSheet`, `QuickScheduleSheet`, `WorkoutCelebration` |
| ├ `ShopPage` | `lib/pages/shop_page.dart` | Coin shop; buy/equip cosmetics | HomeScreen tab 4 | (purchase dialogs) |
| └ `ProfilePage` | `lib/home_screen.dart:6330` | Profile, XP bar, settings menu | HomeScreen tab 5 | `AchievementsPage`, `NotificationSettingsPage`, `AvatarPickerScreen`, `LoginScreen` (sign-out) |
| `AchievementsPage` | `lib/pages/achievements_page.dart` | Achievement grid, progress-first stats, verify/claim rewards | `ProfilePage` (home_screen:6520) | detail sheet (`_Sheet`) |
| `NotificationSettingsPage` | `lib/pages/notification_settings_page.dart` | Notification category toggles + quiet hours | `ProfilePage` (two entries, home_screen:6542/6772) | — |
| `WorkoutHistoryPage` | `lib/pages/workout_history_page.dart` | Calendar + list of logged workouts | Dashboard/Profile history entry | `WorkoutHistorySheet` |
| `AvatarPickerScreen` | `lib/widgets/avatar_picker_screen.dart` | Avatar + border picker (level/shop gated) | `ProfilePage`, `OnboardingBasicInfoNew` | — |
| Legacy onboarding | `lib/onboarding/legacy/*` | Superseded flow (BasicInfo → UsernameAvatar → Goals → BuddyPreferences) | not routed from live flow | `HomeScreen` |

Key modal sheets/dialogs (logic-bearing):

| Modal | File | Opened by | Talks to |
|---|---|---|---|
| `WorkoutCheckInSheet` | `lib/widgets/workout_checkin_sheet.dart` | Dashboard check-in button | `active_checkin_sessions`, `workouts` (timer session lifecycle), `WorkoutService` |
| `WorkoutSelectionModal` | `lib/widgets/workout_selection_modal.dart` | Dashboard check-in (no active session) | `WorkoutHistoryService`, `AchievementService` |
| `ScheduleWorkoutSheet` / `QuickScheduleSheet` | `lib/widgets/...` | SchedulePage / Dashboard | `WorkoutService`, `FriendService` |
| `JoinWorkoutPopup` (+ Missed/BuddyCompleted variants) | `lib/widgets/join_workout_popup.dart` | `WorkoutJoinChecker` polling on Dashboard | `WorkoutService` |
| `BreakDaySection` | `lib/widgets/break_day_section.dart` | Dashboard | `BreakDayService` → `declare_break_day` |
| `BuddyProfileSheet` / `ProfileViewDialog` | `lib/widgets/...` | FriendsPageModern | `friend_nicknames`, `user_profiles`, team tables |
| `CoachMaxWidget` | `lib/widgets/coach_max_widget.dart` | Dashboard | `CoachMaxService` |
| `LevelUpSheet` / `StreakCompleteSheet` / `AchievementToast` / `WorkoutCelebration` | `lib/widgets/...` | Post-check-in events | `LevelService`, `AchievementService` |
| `_WeeklyPlanDialog` | `lib/home_screen.dart:7523` | Dashboard (Monday / no plan) | `BreakDayService.setWeeklyBreakPlan` |

---

## 2. RPCs (Postgres functions, `public` schema)

### Called directly from the Flutter client

| RPC | Called by (client) | Reads | Writes | Returns |
|---|---|---|---|---|
| `award_achievement_rewards(p_achievement_id)` | `AchievementService` | `achievements`, `user_achievements` | `user_achievements`, XP/coins via `award_xp`/`award_coins` | jsonb |
| `award_checkin_rewards(p_streak_id, p_check_in_date)` | `TeamStreakService._incrementStreak` | `daily_team_checkins`, `team_members`, `team_streaks` | delegates to `_apply_checkin_rewards` | jsonb (`did_level_up`, `new_level`, `already_awarded`) |
| `checkin_team_for_user(p_target_user_id, p_workout_id)` | `TeamStreakService.checkInAllTeamsForUser` (buddy-workout completion in `home_screen.dart:5719/5736`) | `workouts` (validates real participation), `team_members` | `daily_team_checkins`, `team_streaks` | int (teams checked in) |
| `create_buddy_workout_sessions(...)` | `WorkoutService` (ready-check start) | — | `active_checkin_sessions` (one row per participant) | void |
| `create_invite(p_inviter_id)` | `InviteService.createInvite` | — | `invites` | text (code) |
| `create_invite_team(p_inviter_id, p_invitee_id)` | `OnboardingBasicInfoNew._createBuddyTeam` | — | `buddy_teams`, `team_members` (both users), `team_streaks` | uuid (team_id) |
| `declare_break_day()` | `BreakDayService.declareBreakDay` (`BreakDaySection`, Dashboard) | `weekly_break_plans`, `break_day_usage` (advisory-locked count) | `break_day_usage` (upsert, server-computed local date) | jsonb (`success`, `used`, `max`, `reason`) |
| `delete_own_account()` | `AuthWrapper`, `LoginScreen`, `OnboardingBasicInfoNew` (orphan cleanup) | — | deletes `user_profiles` + cascading user data + auth user | void |
| `get_level_for_xp(total_xp)` | `XpService`, `LevelService` | `level_definitions` | — | int |
| `get_user_streaks(p_user_id)` | `TeamStreakService.getAllUserStreaks` (viewer-tz aware) | `buddy_teams`, `team_streaks`, `team_members`, `daily_team_checkins`, `user_profiles`, `workouts`, `check_ins` | — | json (all streaks + members + today's check-ins) |
| `get_workouts_awaiting_creator_join(creator_id)` | `WorkoutService.getWorkoutsAwaitingCreatorJoin` (`WorkoutJoinChecker`) | `workouts`, `user_profiles` | — | table (join-window rows) |
| `is_on_break_today(p_user_id)` | `home_screen.dart:2335`, `friends_page_modern.dart:135` (break badges) | `break_day_usage` | — | boolean |
| `is_user_in_active_workout(check_user_id)` | `WorkoutService` | `active_checkin_sessions`, `workouts` | — | boolean |
| `purchase_shop_item(p_shop_item_id)` | `CoinService.purchaseItem` (`ShopPage`) | `shop_items`, `user_profiles` (balance) | `user_profiles.coin_balance`, `coin_transactions` (via `award_coins`), `user_inventory` | jsonb |
| `recompute_team_streak(p_streak_id, p_check_in_date)` | `TeamStreakService._incrementStreak`, `TeamSyncService`, `CoachMaxService`; also `coach-max-cron` Edge Fn and `reconcile_stale_streaks` | `daily_team_checkins`, `break_day_usage`, `team_members`, `workouts` | `team_streaks` (current/best/longest, dates) | jsonb (`updated`, `new_streak`, `old_best_streak`, `new_best_streak`, `reason`) |
| `remove_friend(p_friend_id)` | `FriendService.removeFriend` | — | atomically deletes `friendships`, shared `buddy_teams`, `team_members`, `team_streaks`, `daily_team_checkins` | boolean |
| `verify_achievement_progress(p_achievement_id)` | `AchievementService` (server-side validation before unlock) | `achievements`, `user_achievements`, `workouts`, `daily_team_checkins`, `team_streaks`, `team_members`, `buddy_teams`, `friendships`, `coin_transactions`, `user_inventory`, `user_profiles` | — | jsonb |

### Internal / helper functions (not called from client)

| Function | Invoked by | Touches |
|---|---|---|
| `_apply_checkin_rewards(p_user_id, p_streak_id, p_check_in_date)` | `award_checkin_rewards`, `checkin_team_for_user` (symmetric retro rewards) | writes `xp_transactions`, `coin_transactions`, `user_profiles` (xp, level, coin_balance); reads `daily_team_checkins`, `team_streaks`; daily reward cap enforced |
| `award_xp` / `award_coins` | reward RPCs above | `xp_transactions`/`coin_transactions`, `user_profiles`, `level_definitions`, `user_unlocked_cosmetics`, `cosmetic_unlock_conditions` |
| `reconcile_stale_streaks()` | pg_cron job `reconcile-stale-streaks-hourly` | per-member-tz STRICT reset sweep; reads `team_streaks`, `team_members`, `daily_team_checkins`, `break_day_usage`; updates `team_streaks` |
| `safe_user_tz(p_user_id)` | all tz-aware RPCs, `declare_break_day` | `user_profiles.timezone` (fallback `Europe/Dublin`) |
| `get_user_team_ids()` / `user_created_team()` | RLS policies (`team_members`, `buddy_teams`) | `team_members`, `buddy_teams` |
| `get_team_checkin_order`, `get_random_team_name`, `get_current_weekly_commitment`, `can_take_rest_day` | legacy / unused from current client | `daily_team_checkins`, `team_names`, `weekly_commitments` |

### Trigger functions

| Function | Trigger | Table / event | Effect |
|---|---|---|---|
| `backfill_team_checkins_on_creation` | `trigger_backfill_checkins_on_team_creation` | `buddy_teams` INSERT | seeds `daily_team_checkins`/`team_streaks` for new team |
| `check_duplicate_team` | `prevent_duplicate_teams` | `team_members` INSERT | blocks duplicate 2-person teams |
| `cleanup_workout_sessions` | `trigger_cleanup_workout_sessions` | `workouts` UPDATE | deletes `active_checkin_sessions` when workout completes/cancels |
| `notify_friend_request` / `notify_friend_accepted` | `on_friend_request` / `on_friend_accepted` | `friendships` INSERT / UPDATE | `net.http_post` → `send-notification` Edge Fn (service-role key from Vault) |
| `notify_workout_invite` / `notify_workout_invite_response` | `on_workout_invite` / `on_workout_invite_response` | `workout_invites` INSERT / UPDATE | `net.http_post` → `send-notification` |
| `notify_buddy_checkin` | `on_buddy_checkin` | `daily_team_checkins` INSERT | `net.http_post` → `send-notification` (buddy checked in) |
| `notify_streak_update` | `on_streak_update` | `team_streaks` UPDATE | `net.http_post` → `send-notification` (milestones) |
| `validate_user_timezone` | `trg_validate_user_timezone` | `user_profiles` INSERT/UPDATE | rejects invalid IANA tz names |
| `update_updated_at_column` | `update_team_streaks_updated_at` | `team_streaks` UPDATE | touch `updated_at` |

---

## 3. Tables (all RLS-enabled)

| Table | Key columns | RLS summary | Touched by RPCs |
|---|---|---|---|
| `user_profiles` | `id (uuid=auth.uid)`, `username`, `display_name`, `avatar_id`, `avatar_border`, `xp`, `level`, `coin_balance`, `timezone`, `onboarding_completed`, `is_bot` | SELECT: any authenticated; UPDATE/INSERT: own row only, **and `xp` / `level` / `coin_balance` / `is_bot` are column-revoked from `authenticated`** — writable only by SECURITY DEFINER RPCs (Group A, `1bd0b7a`; `UPDATE(id)` restored for onboarding upsert in `d53802a`) | `_apply_checkin_rewards`, `award_xp`, `award_coins`, `purchase_shop_item`, `delete_own_account`, `safe_user_tz`, `verify_achievement_progress`, notify_* triggers |
| `friendships` | `id`, `user_id`, `friend_id`, `status (pending/accepted)` | SELECT/DELETE: either party; UPDATE (accept): recipient only; INSERT: authenticated | `remove_friend`, `verify_achievement_progress`; triggers `notify_friend_request`/`accepted` |
| `friend_requests` | **DROPPED 2026-07-27** (`fa6a380`) | — | Was a SECURITY DEFINER view over `friendships`, readable by `anon` — an unauthenticated leak of every pending friend request. Do not recreate; read `friendships` directly. |
| `buddy_teams` | `id`, `team_name`, `team_emoji`, `is_coach_max_team`, `max_members`, `created_by` | SELECT: creator or member (via `get_user_team_ids`); INSERT: authenticated; UPDATE/DELETE: creator | `create_invite_team`, `remove_friend`, `user_created_team`; trigger `backfill_team_checkins_on_creation` |
| `team_members` | `id`, `team_id`, `user_id`, `role`, `is_favorite` | SELECT: own teams via `get_user_team_ids()`; INSERT (both `TO authenticated`): self (`auth.uid() = user_id`) or team creator (`user_created_team(team_id)`). The old PUBLIC "System can insert Coach Max" policy was dropped in `a5245e7` — it let anyone, including `anon`, add Coach Max to any team; the creator policy already covers the legitimate onboarding path. INSERT revoked from `anon` | `create_invite_team`, `checkin_team_for_user`, `recompute_team_streak`, `remove_friend`, `get_user_team_ids`; trigger `check_duplicate_team` |
| `team_streaks` | `id`, `team_id`, `current_streak`, `best_streak`, `longest_streak`, `last_workout_date`, `is_active`, `is_favorite` | SELECT/UPDATE/INSERT: team members | `recompute_team_streak`, `award_checkin_rewards`, `checkin_team_for_user`, `reconcile_stale_streaks`, `create_invite_team`, `remove_friend`; triggers `notify_streak_update`, `updated_at` |
| `daily_team_checkins` | `id`, `team_streak_id`, `user_id`, `check_in_date (user-local date)`, `check_in_time`; unique (streak,user,date) | SELECT: own/teammates/friends; UPDATE: own; INSERT: own row into own team (`user_id = auth.uid()` AND streak's team in caller's teams), or Coach Max's row into a team the caller belongs to (`"Coach Max check-in for own team"`, `TO authenticated`, same membership subquery). The old PUBLIC "Coach Max can check in" policy — which checked only that the row *was* Coach Max, never who was inserting, letting `anon` check Coach Max into any team — was replaced in `a5245e7`; INSERT also revoked from `anon` | `checkin_team_for_user`, `recompute_team_streak`, `award_checkin_rewards`, `_apply_checkin_rewards`, `reconcile_stale_streaks`, `get_user_streaks`, `remove_friend`; trigger `notify_buddy_checkin` |
| `workouts` | `id`, `user_id (creator)`, `buddy_id`, `workout_type`, `workout_date/time`, `status`, `buddy_status`, `planned/actual_duration_minutes`, `workout_started_at/completed_at`, `creator_ready`, `buddy_ready`, `ready_expires_at`, cancel/join flags | SELECT/UPDATE: creator or buddy; INSERT/DELETE: creator | `checkin_team_for_user` (validation), `get_workouts_awaiting_creator_join`, `is_user_in_active_workout`, `get_user_streaks`, `verify_achievement_progress`; trigger `cleanup_workout_sessions`; cron `reset-expired-ready` |
| `active_checkin_sessions` | `id`, `user_id`, `workout_type/emoji`, `planned_duration`, `started_at`, `linked_workout_id`, `workout_id` | SELECT/UPDATE/DELETE: own or linked-workout buddy; INSERT: self or workout buddy | `create_buddy_workout_sessions`, `is_user_in_active_workout`; trigger `cleanup_workout_sessions` deletes |
| `workout_invites` | `id`, `sender_id`, `recipient_id`, `scheduled_for`, `message`, `status` | SELECT/UPDATE: sender or recipient; INSERT: sender; DELETE: sender | triggers `notify_workout_invite(_response)` |
| `weekly_break_plans` | `id`, `user_id`, `week_start_date (local Monday)`, `max_break_days` | all ops: own rows | `declare_break_day` (reads cap) |
| `break_day_usage` | `id`, `user_id`, `break_date (user-local)`, `declared_at`, `cancelled_at`; unique (user,date) | SELECT: own + streak partners; UPDATE (cancel)/DELETE: own; INSERT: **RPC only** (no client INSERT policy) | `declare_break_day`, `is_on_break_today`, `recompute_team_streak`, `reconcile_stale_streaks` |
| `invites` | `id`, `code`, `inviter_id`, `status`, `accepted_by`, `accepted_at` | SELECT: owner-scoped only (`auth.uid() = inviter_id OR auth.uid() = accepted_by`); INSERT: own (`auth.uid() = inviter_id`); **no UPDATE and no DELETE policy** — accepting goes through the `accept_invite` RPC, which locks the row `FOR UPDATE`. Changed in `0baf96d` (Group C): the old policies allowed any authenticated user to read invites by code and UPDATE them, i.e. enumerate and hijack | `create_invite`, `accept_invite`; read by `invite-redirect` Edge Fn (service role) |
| `coach_max_schedule` | `id`, `user_id`, `scheduled_date (user-local)`, `scheduled_time`, `has_checked_in`, `checked_in_at` | SELECT/INSERT/UPDATE: own | written by `coach-max-cron` Edge Fn (service role) |
| `xp_transactions` | `id`, `user_id`, `amount`, `transaction_type`, `reference_id` | SELECT: own; INSERT: service/definer only | `award_xp`, `_apply_checkin_rewards`, `award_achievement_rewards` |
| `coin_transactions` | `id`, `user_id`, `amount`, `transaction_type`, `reference_id` | SELECT: own | `award_coins`, `_apply_checkin_rewards`, `purchase_shop_item`, `verify_achievement_progress` |
| `level_definitions` | `level`, `xp_required`, `title` (99 rows) | public read | `get_level_for_xp`, `award_xp` |
| `shop_items` | `id`, `name`, `category`, `cost`, `emoji`, `asset_id`, `is_available`, `unlock_level` | SELECT: available items | `purchase_shop_item` |
| `user_inventory` | `id`, `user_id`, `shop_item_id`, `equipped` | SELECT/UPDATE/INSERT: own | `purchase_shop_item`, `verify_achievement_progress` |
| `cosmetic_unlock_conditions` / `user_unlocked_cosmetics` | unlock rules / granted cosmetics | public read / own rows | `award_xp` (level+milestone unlocks) |
| `achievements` | `id (text)`, `name`, `category`, `rarity`, `xp_reward`, `coin_reward`, `target_value` (46 rows) | public read | `award_achievement_rewards`, `verify_achievement_progress` |
| `user_achievements` | `id`, `user_id`, `achievement_id`, `unlocked_at`, `progress` | ALL: own rows | `award_achievement_rewards`, `verify_achievement_progress` |
| `workout_templates` | `id`, `name`, `category`, `default_duration_minutes`, `is_system_template`, `created_by` | SELECT: system or own; INSERT/UPDATE: own | — (client direct) |
| `workout_logs` | `id`, `user_id`, `workout_date`, `workout_name/category/emoji`, durations, `buddy_id`, `team_id`, `intensity_rating` | SELECT/INSERT/UPDATE: own | — (client direct via `WorkoutHistoryService`) |
| `device_tokens` | `id`, `user_id`, `token`, `platform` | ALL: own | read by `send-notification` Edge Fn |
| `notification_settings` | `user_id`, `notif_social/workouts/streaks/coach_max`, quiet hours | ALL: own | read by `send-notification` + `coach-max-cron` |
| `notification_log` | `id`, `user_id`, `notification_type`, `batch_key`, `sent_at` | service role ALL; own SELECT | written by `send-notification` (dedup) |
| `friend_nicknames` | `id`, `user_id`, `friend_id`, `nickname` | ALL: own (setter only) | — (client direct via `NicknameService`) |
| `buddy_nudges` | `id`, `sender_id`, `receiver_id`, `nudge_date` | INSERT/SELECT: sender | — (client direct via `NudgeService`) |
| `team_names` | `id`, `name`, `category`, `emoji` | public read | `get_random_team_name` (legacy) |
| `check_ins`, `daily_check_ins`, `weekly_commitments` | legacy check-in system (0 rows) | own rows | `get_user_streaks` (check_ins mention), `can_take_rest_day`, `get_current_weekly_commitment` (legacy) |
| `*_backup` (friendships, buddy_teams, team_streaks, team_members, daily_team_checkins) | migration backups (0 rows) | admin-only (`false` policy) | — |

---

## 4. Edge Functions (Deno, deployed)

| Function | Trigger | Calls | Writes |
|---|---|---|---|
| `coach-max-cron` | pg_cron `coach-max-hourly` (`0 * * * *`) via `net.http_post` (service-role bearer from Vault) | reads `team_members`+`buddy_teams` (Coach Max teams), `user_profiles.timezone`, `coach_max_schedule`, `notification_settings`, `team_streaks`, `daily_team_checkins`; calls RPC `recompute_team_streak`; POSTs `send-notification` | inserts `coach_max_schedule` (per-user local date, random time in 07:00–17:00 local / outside quiet hours); inserts Coach Max rows into `daily_team_checkins`; updates `coach_max_schedule.has_checked_in`. Part 3: 18:00 UTC streak-danger notifications |
| `send-notification` | HTTP POST from: DB `notify_*` triggers (`net.http_post`), `coach-max-cron`, client `NudgeService.functions.invoke` | authz: service-role key OR caller JWT must be target/friend/teammate; reads `notification_settings` (quiet hours, category), `notification_log` (batch_key dedup), `device_tokens`; FCM v1 API (Firebase service account JWT) | `notification_log` |
| `invite-redirect` | HTTP GET on shared invite link (`?code=XXX`) | reads `invites` + inviter `user_profiles` (service role) | none; 302 → `danzabello.github.io/gym-buddy-app/invite.html?code=…&inviter=…` (Play Store CTA + code stashed in localStorage) |
| `send-friend-request-notification` | deployed (v2) but **not referenced** by repo, triggers, or client — legacy; friend-request pushes now go through `notify_friend_request` trigger → `send-notification` | — | — |

---

## 5. Cron jobs (pg_cron)

| Job | Schedule | Action |
|---|---|---|
| `coach-max-hourly` (jobid 1) | `0 * * * *` | `net.http_post` → `coach-max-cron` Edge Function (service-role key from Vault) |
| `reset-expired-ready` (jobid 2) | `*/5 * * * *` | inline SQL: `UPDATE workouts SET creator_ready=false, buddy_ready=false, ready_expires_at=NULL WHERE ready expired AND status='scheduled'` |
| `reconcile-stale-streaks-hourly` (jobid 5) | `5 * * * *` | `SELECT public.reconcile_stale_streaks()` (per-member-tz STRICT streak reset sweep) |

---

## 6. Client services (`lib/services/`)

| Service | RPCs called | Tables (direct) | Used by |
|---|---|---|---|
| `WorkoutService` | `get_workouts_awaiting_creator_join`, `is_user_in_active_workout`, `create_buddy_workout_sessions` | `workouts`, `active_checkin_sessions` | HomeScreen (Dashboard/Schedule), `WorkoutCheckInSheet`, `QuickScheduleSheet`, `ScheduleWorkoutSheet`, `WorkoutJoinChecker`, `CompletedWorkoutsSection` |
| `TeamStreakService` | `get_user_streaks`, `recompute_team_streak`, `award_checkin_rewards`, `checkin_team_for_user` | `team_streaks`, `team_members`, `buddy_teams`, `daily_team_checkins`, `coin_transactions` | HomeScreen, `FriendsPageModern`, `CustomStreakSelector` |
| `TeamSyncService` | `recompute_team_streak` | `daily_team_checkins`, `team_members` | HomeScreen (Realtime streak sync) |
| `BreakDayService` | `declare_break_day` | `weekly_break_plans`, `break_day_usage`, `user_profiles` | HomeScreen, `BreakDaySection` |
| `FriendService` | `remove_friend` | `friendships`, `user_profiles`, `buddy_teams`, `team_members`, `team_streaks`, `daily_team_checkins` | HomeScreen, `FriendsPageModern`, `ScheduleWorkoutSheet`, onboarding |
| `InviteService` | `create_invite` | `invites` | `FriendsPageModern`, onboarding, `main.dart` (deep-link stash) |
| `WorkoutInviteService` | — | `workout_invites`, `workouts` | `WorkoutInvitesCard` |
| `CoachMaxService` | `recompute_team_streak` | `coach_max_schedule`, `buddy_teams`, `team_members`, `team_streaks`, `daily_team_checkins` | `CoachMaxWidget`, onboarding, login, `main.dart` |
| `AchievementService` | `verify_achievement_progress`, `award_achievement_rewards` | `achievements`, `user_achievements`, `workouts`, `daily_team_checkins`, `team_streaks`, `team_members`, `friendships`, `coin_transactions`, `user_inventory` | `AchievementsPage`, `AchievementToast`, `FriendsPageModern`, `WorkoutSelectionModal`, `main.dart`, TeamStreakService (post-check-in) |
| `XpService` | `get_level_for_xp` | `xp_transactions`, `user_profiles`, `level_definitions`, `user_unlocked_cosmetics`, `cosmetic_unlock_conditions` | LevelService pipeline |
| `LevelService` | `get_level_for_xp` | same as XpService | `XpProgressBar`, `LevelUpSheet`, `AvatarPickerScreen`, `AchievementsPage`, HomeScreen |
| `CoinService` | `purchase_shop_item` | `coin_transactions`, `shop_items`, `user_inventory`, `user_profiles` | `ShopPage` |
| `WorkoutHistoryService` | — | `workout_logs`, `workout_templates` | `WorkoutHistoryPage`, `WorkoutCalendar`, `WorkoutHistoryList`, `WorkoutSelectionModal`, HomeScreen |
| `NotificationService` | — (Edge Fn via triggers) | `device_tokens`, `notification_settings` | `main.dart`, `LoginScreen`, `NotificationSettingsPage` |
| `NudgeService` | — (invokes `send-notification` Edge Fn directly) | `buddy_nudges`, `user_profiles` | `FriendsPageModern` |
| `NicknameService` | — | `friend_nicknames` | HomeScreen, `BuddyProfileSheet` |
| `PresenceService` (singleton) | — (Realtime presence channel `gym_buddy_presence`) | — | HomeScreen, `FriendsPageModern` |
| `AuthService` | — | Supabase Auth | `LoginScreen`, `SignUpScreen`, onboarding |

---

## 7. Key flows (ordered sequences)

### 7.1 Manual check-in (dashboard fire button)
1. `DashboardPage` fire button → `_checkIn()` (`home_screen.dart:2550`)
2. `WorkoutCheckInSheet.getActiveSession()` → reads `active_checkin_sessions` (or `_adoptLiveBuddyWorkoutSession()` reads in-progress `workouts`)
3. No session → `WorkoutSelectionModal` (pick type/duration from `workout_templates`) → `WorkoutCheckInSheet` timer starts → inserts `active_checkin_sessions`
4. Timer done → `onCheckInComplete`: if session linked to a `workouts` row → `WorkoutService.completeWorkoutWithDuration` (UPDATE `workouts.status='completed'` → trigger `cleanup_workout_sessions` deletes session)
5. `TeamStreakService.checkInAllTeams()` → cancels today's break if any (`break_day_usage.cancelled_at`), logs `workout_logs` via `WorkoutHistoryService`, INSERTs `daily_team_checkins` (own local date) per team → trigger `notify_buddy_checkin` → `send-notification` Edge Fn → FCM to buddy
6. Per team, when all members participated (checked in or on break) → RPC `recompute_team_streak` → UPDATE `team_streaks` → trigger `notify_streak_update`
7. RPC `award_checkin_rewards` → `_apply_checkin_rewards` → `xp_transactions` + `coin_transactions` + `user_profiles` (xp/level/coins, daily-capped)
8. Back in UI: `AchievementService` checks (fire-and-forget, `verify_achievement_progress`/`award_achievement_rewards`) → `AchievementToast`; `LevelUpSheet` if leveled; milestone cosmetic unlock via `LevelService`; `_loadStreakData()` refresh

### 7.2 Buddy workout completion (scheduled workout)
1. `SchedulePage` → workout created via `ScheduleWorkoutSheet` (INSERT `workouts` with `buddy_id`) → trigger-less; buddy sees invite via `workout_invites` (trigger `notify_workout_invite` → push)
2. Both users ready-check (`creator_ready`/`buddy_ready`, `ready_expires_at`; stale flags reset by cron `reset-expired-ready` every 5 min)
3. Start → RPC `create_buddy_workout_sessions` → `active_checkin_sessions` rows for both participants; `workouts.status='in_progress'`
4. Non-starter gets join window → `WorkoutJoinChecker` polls RPC `get_workouts_awaiting_creator_join` → `JoinWorkoutPopup`
5. Completion (`home_screen.dart:5657`): `WorkoutService.completeWorkoutWithDuration` → UPDATE `workouts` → trigger `cleanup_workout_sessions`
6. `WorkoutCelebration` → for current user: `TeamStreakService.checkInAllTeams()` (flow 7.1 steps 5–8); for the non-cancelling partner: RPC `checkin_team_for_user(partner, workoutId)` — server validates the partner really participated in that `workouts` row, INSERTs their `daily_team_checkins` across teams, recomputes streaks, applies their rewards symmetrically

### 7.3 Buddy invite flow
1. `FriendsPageModern` (or onboarding) → `InviteService.createInviteLink()` → RPC `create_invite` → INSERT `invites` → share URL `…/functions/v1/invite-redirect?code=X`
2. Recipient opens link → `invite-redirect` Edge Fn reads `invites`+`user_profiles` → 302 to GitHub Pages invite.html (Play Store CTA, code in localStorage)
3. Recipient installs/opens app → deep link caught in `main.dart` (`app_links`) → `InviteService.storePendingInviteCode` (SharedPreferences)
4. After signup, `OnboardingBasicInfoNew` final step → `consumePendingInviteCode` → `InviteService.acceptInvite` (UPDATE `invites` status='accepted') → RPC `create_invite_team(inviter, invitee)` → INSERT `buddy_teams` + 2× `team_members` + `team_streaks` → trigger `backfill_team_checkins_on_creation`
5. → `HomeScreen`; both users now share a team streak

### 7.4 Break day flow
1. Monday / no plan → `_WeeklyPlanDialog` → `BreakDayService.setWeeklyBreakPlan` → upsert `weekly_break_plans` + `user_profiles.current_weekly_goal`
2. `BreakDaySection` (Dashboard) "take a break" → `BreakDayService.declareBreakDay()` → RPC `declare_break_day` (advisory lock; server computes today in `safe_user_tz`; checks weekly cap against `weekly_break_plans`; upsert `break_day_usage`) — direct client INSERT blocked by RLS
3. Buddies see badge: `is_on_break_today(p_user_id)` RPC from `home_screen`/`friends_page_modern`; partners can read `break_day_usage` via RLS partner policy
4. Streak safety: `recompute_team_streak` / `reconcile_stale_streaks` count an uncancelled break day as participation
5. User works out anyway → `checkInAllTeams` auto-calls `cancelBreakDay` (UPDATE `break_day_usage.cancelled_at`)

### 7.5 Coach Max cron flow
1. pg_cron `coach-max-hourly` (hourly) → `net.http_post` → `coach-max-cron` Edge Fn (service role)
2. Part 1: for each human member of a `is_coach_max_team` — compute member's local today (`user_profiles.timezone`) → INSERT `coach_max_schedule` with random time in active window (respects `notification_settings` quiet hours)
3. Part 2: schedules due (local date+time passed) → INSERT Coach Max row (`user_id = 00000000-…-0001`) into `daily_team_checkins` on the member's local date → mark `has_checked_in` → if human already checked in today → RPC `recompute_team_streak` → POST `send-notification` (motivational message)
4. Part 3 (18:00 UTC only): active streaks with no human check-in today → POST `send-notification` "Streak in Danger"
5. Client: `CoachMaxWidget` reads `coach_max_schedule`/`daily_team_checkins` via `CoachMaxService` to render Coach Max state

### 7.6 Friend request flow (in-app)
1. `FriendsPageModern` → `_SearchBuddiesPage`/`_AddBuddiesPage` → `FriendService.sendFriendRequest` → INSERT `friendships (status='pending')` → trigger `notify_friend_request` → `send-notification` → FCM
2. Recipient accepts → UPDATE `friendships.status='accepted'` (RLS: recipient only) → trigger `notify_friend_accepted` → push to requester
3. Buddy team creation for streaks happens separately (invite flow or in-app pairing)
4. Remove friend → RPC `remove_friend` → atomic delete of friendship + shared team/streak/check-in rows

### 7.7 Shop purchase flow
1. `ShopPage` → `CoinService.purchaseItem` → RPC `purchase_shop_item` (server-authoritative: validates `shop_items.cost` vs `user_profiles.coin_balance`, level gate)
2. → UPDATE `user_profiles.coin_balance`, INSERT `coin_transactions`, INSERT `user_inventory`
3. Equip → UPDATE `user_inventory.equipped` → avatar/border reflected via `user_profiles` + `UserAvatar` widget

### 7.8 Push notification pipeline (all paths converge)
1. Producers: DB `notify_*` triggers (`net.http_post` + Vault service-role key) | `coach-max-cron` | `NudgeService` (client `functions.invoke`)
2. `send-notification` Edge Fn: authz (service key or friend/teammate JWT) → `notification_settings` (category + quiet hours) → `notification_log` batch_key dedup → `device_tokens` → FCM v1 → INSERT `notification_log`

### 7.9 Hourly streak reconcile
1. pg_cron `reconcile-stale-streaks-hourly` (`5 * * * *`) → `reconcile_stale_streaks()`
2. For each active `team_streaks` not touched today (per member's own tz, STRICT mode): if yesterday's participation (check-ins ∪ break days) incomplete → reset `current_streak` → UPDATE `team_streaks` → trigger `notify_streak_update`
