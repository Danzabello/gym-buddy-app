# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Commands

```bash
# Run app (connected device or emulator required)
flutter run

# Analyze / lint
flutter analyze

# Run tests
flutter test
flutter test test/widget_test.dart   # single file

# Fetch/update packages
flutter pub get

# Build
flutter build apk           # Android APK
flutter build appbundle     # Android AAB (Play Store)
flutter build ios           # iOS (requires macOS + Xcode)

# Supabase Edge Functions
supabase functions deploy coach-max-cron
supabase functions deploy invite-redirect
supabase functions deploy send-notification
supabase start              # local Supabase stack
```

## Architecture

Flutter (Dart, Material 3) mobile app backed by **Supabase** (Postgres + Auth + Realtime) and **Firebase** (push notifications via FCM).

### Entry point & navigation
`lib/main.dart` — loads `.env`, initialises Firebase (mobile-only) and Supabase, then mounts `AuthWrapper`. The wrapper checks `user_profiles.onboarding_completed` and routes to either `SplashScreen` (unauthenticated / incomplete onboarding) or `HomeScreen`. Deep links (`app_links`) are intercepted here; invite codes are stashed via `InviteService.storePendingInviteCode`.

`lib/home_screen.dart` — 5-tab bottom-nav shell: **Dashboard**, **Friends** (`FriendsPageModern`), **Schedule**, **Shop** (`ShopPage`), **Profile**.

### Layer conventions
| Path | Role |
|------|------|
| `lib/services/` | All Supabase calls and business logic. Each service is a plain Dart class that accesses `Supabase.instance.client` directly. |
| `lib/widgets/` | Reusable UI components (bottom sheets, cards, pickers, toasts). |
| `lib/pages/` | Full-screen pages (Achievements, Shop, Workout History, Notification Settings). |
| `lib/onboarding/` | Onboarding flow (SplashScreen → OnboardingValueProps → OnboardingBasicInfoNew). `legacy/` contains superseded screens. |
| `lib/theme/` | `AppTheme` (Material 3 + custom `AppColors` extension for light/dark tokens), `ThemeProvider` (ChangeNotifier consumed via `provider`). |
| `lib/data/` | Static Dart data files (e.g. `coach_tips.dart`). |
| `supabase/functions/` | Deno/TypeScript Edge Functions. |

### Theming
Custom colours live in `AppColors` (a `ThemeExtension`). Access them with `AppColors.of(context).cardBackground` etc. Never use raw hex values in widgets — use `AppColors.of(context)` or standard Material colour slots.

### Key services
- **`WorkoutService`** — check-in sessions, workout CRUD, buddy-join flow. Two tables: `workouts` and `active_checkin_sessions`.
- **`TeamStreakService`** — team streak logic; models `TeamMember`, `CheckInStatus`, `TeamStreak` are defined at the top of this file.
- **`XpService`** / **`LevelService`** / **`CoinService`** — XP award pipeline, level-up detection, in-app currency.
- **`AchievementService`** — loyalty and activity achievements.
- **`PresenceService`** — singleton; uses Supabase Realtime presence on channel `gym_buddy_presence`. Call `join()` on auth and `leave()` on sign-out.
- **`InviteService`** — generates invite codes via the `create_invite` RPC, builds share links pointing to the `invite-redirect` Edge Function.
- **`CoachMaxService`** — schedules and sends messages for the AI coach. Coach Max has a fixed UUID: `00000000-0000-0000-0000-000000000001`.
- **`NotificationService`** — wraps FCM + `flutter_local_notifications`.

### Supabase Edge Functions
| Function | Purpose |
|----------|---------|
| `coach-max-cron` | Scheduled job: creates daily `coach_max_schedule` entries and dispatches coach messages. |
| `invite-redirect` | Handles invite URL; redirects to App Store / Play Store or deep link. |
| `send-notification` | Sends FCM push notifications server-side. |

### Environment
Secrets are in `.env` (bundled as a Flutter asset via `flutter_dotenv`). Required keys: `SUPABASE_URL`, `SUPABASE_ANON_KEY`. Edge Functions read `SUPABASE_SERVICE_ROLE_KEY` from the Supabase secrets vault.

### Supabase function EXECUTE grants (must be explicit)
New functions in `public` are PUBLIC-executable by default. `ALTER DEFAULT PRIVILEGES ... REVOKE EXECUTE ON FUNCTIONS FROM PUBLIC` does **not** suppress this on the live instance (verified on PG17.6, with the REVOKE correctly targeting `postgres` — the same role that creates migration functions), so the default cannot be relied on to lock functions down. Every new client-facing or `SECURITY DEFINER` function must, in its own migration, explicitly:
```sql
REVOKE EXECUTE ON FUNCTION public.<fn>(<args>) FROM PUBLIC, anon;
GRANT  EXECUTE ON FUNCTION public.<fn>(<args>) TO authenticated;   -- add anon only if unauthenticated access is truly needed
```
Also pin `SET search_path = public` on every `SECURITY DEFINER` function at creation.

### Known security gaps (accepted for now — revisit before public launch)
- **Leaked-password protection is OFF** (advisor WARN `auth_leaked_password_protection` stays active). It requires the Supabase **Pro plan**; the project is on Free tier. Before public launch: upgrade plan, then enable in Dashboard → Authentication → Sign In / Providers → Email → "Prevent the use of leaked passwords" (checks new/changed passwords against HaveIBeenPwned). Decided 2026-07-20 (Group E).

### Account deletion
Deleting a user (self-serve delete, or orphaned-account cleanup when `onboarding_completed = false`) goes through the **`delete-account` Edge Function** (service_role → deletes `user_profiles`, then `auth.admin.deleteUser`; no manual FK clearing — `workouts.started_by_user_id` / `cancel_requested_by` are `ON DELETE SET NULL`, and all inbound FKs to `user_profiles` are `CASCADE`/`SET NULL`, migrations `20260718110000` + `20260718113000`). A postgres-owned `SECURITY DEFINER` RPC **cannot** delete `auth.users` when called via the `authenticated` role, so the old `delete_own_account` RPC only ever removed `user_profiles` — never the auth user. Call sites: `AuthWrapper._cleanupOrphanedAccount`, `login_screen` orphan cleanup, onboarding retry.

### Testing DB permissions — avoid plan-cache false-positives
Permission-check tests must run **clean**: no prior call from a more-privileged role in the **same session/transaction** before the call whose result you trust. PL/pgSQL caches query plans per session — a first call as `postgres` warms the plan and a later `SET ROLE authenticated` call can wrongly succeed. This is exactly why `delete_own_account` looked fixed when it wasn't. Verify with a fresh, authenticated-only call.

### Migration history & schema baseline (Group F, reconciled 2026-07-20)
`supabase/migrations/` and live `supabase_migrations.schema_migrations` are fully reconciled (40 aligned, 0 drift). But **`supabase db reset` / a from-scratch replay does NOT work** and must not be relied on:
- **All base tables predate version control** (`team_members`, `buddy_teams`, `break_day_usage`, `user_profiles`, `friendships`, `team_streaks`, and more) — created by **no migration**. A fresh replay fails at the very first migration (`INSERT INTO coin_transactions` against a table nothing created). Their DDL + the ~18 pre-VC functions and 10 triggers live **only** in the reference doc [`docs/pre_vc_schema_baseline_20260720.sql`](docs/pre_vc_schema_baseline_20260720.sql) — **REFERENCE ONLY, never a migration, never applied**.
- The reconciled RLS baseline `20260628000000` was updated to match current live, so its `team_members` policy now **forward-references `user_created_team()`** (created later by `20260628215741`). A strict timestamp-ordered replay would fail there (verified) — inert today because such a replay is already impossible per the point above.
- **Do not** try to "fix" the ordering by retiming the baseline: it just relocates the failure (`server_enforced_weekly_break_limit` bare-`DROP`s a policy the reconciled baseline no longer creates). Resolving ordering is in-scope only for a real from-scratch-migrations initiative that also writes the pre-VC base-table DDL.
- The baseline is safe on the two paths that matter: `db push` skips it (recorded applied) and a manual replay against live is a verified no-op.
- `migration repair <version> --status applied|reverted` is **metadata-only** (updates the tracking table, never runs SQL) — the tool used to reconcile version-stamp drift.

## Rules

- **Brand gradient** is `Color(0xFF1D4ED8)` → `Color(0xFF7C3AED)`. Never change this. Warm/orange tones are only for the primary CTA button.
- **Never use `const`** on widgets that reference `AppColors.of(context)` or `Theme.of(context)` — it causes a compile error.
- **One page at a time.** Only touch the file explicitly asked about. No collateral changes.
- **Mockup approval before code.** For any UI change, describe or show the plan first and wait for approval.
- **Commit before starting anything new.**
