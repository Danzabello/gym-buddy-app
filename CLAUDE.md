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

### Onboarding / orphaned-account cleanup
If a user authenticates but never completes onboarding (`onboarding_completed = false`), `AuthWrapper` calls the `delete_own_account` RPC and signs them out, allowing re-registration with the same email.
