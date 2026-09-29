# CLAUDE.md

Flutter (Dart, Material 3) app on **Supabase** (Postgres + Auth + Realtime) and **Firebase** (FCM push).

## Commands
```bash
flutter analyze && flutter test
supabase functions deploy <name>   # coach-max-cron, delete-account, invite-redirect, send-notification, workout-overtime-cron
```
`db reset` fails (see Migrations).

## Architecture
- `lib/main.dart`: loads `.env`, inits Firebase (mobile only) + Supabase, mounts `AuthWrapper`. It checks `user_profiles.onboarding_completed` and routes to `SplashScreen` or `HomeScreen`. Deep links (`app_links`) are intercepted here; invite codes go through `InviteService.storePendingInviteCode`.
- `lib/home_screen.dart`: 5-tab shell (Dashboard, Friends `FriendsPageModern`, Schedule, Shop, Profile).
- `lib/services/`: plain Dart classes calling `Supabase.instance.client` directly. All business logic lives here.
- `lib/onboarding/legacy/` is superseded; don't extend it.
- Theming: `AppColors` ThemeExtension. Use `AppColors.of(context).x` or Material colour slots.

### Non-obvious service facts
- `WorkoutService` spans two tables: `workouts` and `active_checkin_sessions`.
- `TeamStreakService` defines `TeamMember`, `CheckInStatus`, `TeamStreak` at the top of the file.
- `PresenceService` is a singleton on channel `gym_buddy_presence`. `join()` on auth, `leave()` on sign-out.
- `InviteService` uses the `create_invite` RPC. Share links point at the `invite-redirect` Edge Function.
- Coach Max has fixed UUID `00000000-0000-0000-0000-000000000001`.

### Environment
Secrets are in `.env` (Flutter asset via `flutter_dotenv`): `SUPABASE_URL`, `SUPABASE_ANON_KEY`. Edge Functions read `SUPABASE_SERVICE_ROLE_KEY` from the Supabase vault.

## Supabase rules
**EXECUTE grants must be explicit.** New `public` functions are PUBLIC-executable, and `ALTER DEFAULT PRIVILEGES` does not suppress this on the live instance (verified on PG17.6). For each new client-facing or `SECURITY DEFINER` function (not trigger functions or service_role-only helpers), put the `REVOKE EXECUTE … FROM PUBLIC, anon` and `GRANT EXECUTE … TO authenticated` (anon only if truly needed) in the same migration that creates or replaces it, re-stating them whenever you replace it. Add `SET search_path = public` to every `SECURITY DEFINER` function in that migration.
```sql
REVOKE EXECUTE ON FUNCTION public.<fn>(<args>) FROM PUBLIC, anon;
GRANT  EXECUTE ON FUNCTION public.<fn>(<args>) TO authenticated;  -- anon only if truly needed
```

**Account deletion** goes through the `delete-account` Edge Function (service_role deletes `user_profiles`, then `auth.admin.deleteUser`). A postgres-owned `SECURITY DEFINER` RPC cannot delete `auth.users` when called as `authenticated`, so the old `delete_own_account` RPC only ever removed the profile. Call sites: `AuthWrapper._cleanupOrphanedAccount`, `login_screen` orphan cleanup, onboarding retry.

**Testing permissions:** run the trusted call in a clean session. PL/pgSQL caches plans per session, so an earlier more-privileged call can make a later `SET ROLE authenticated` call wrongly succeed. Verify with a fresh authenticated-only call.

**Migrations:** `supabase/migrations/` and live history are reconciled, but a from-scratch replay / `db reset` fails. The base tables (`team_members`, `user_profiles`, `friendships`, …) predate version control. Their DDL is in `docs/pre_vc_schema_baseline_20260720.sql`, which is REFERENCE ONLY and never applied. Don't retime the baseline migration `20260628000000` to fix ordering; it only moves the failure. `migration repair` is metadata-only (never runs SQL).

**Known gap:** leaked-password protection is off (needs Pro plan). Enable it before public launch.

## Rules
- **Coach Max gradient** `0xFF1D4ED8` → `0xFF7C3AED` is scoped to his badge/avatar. Never change or tokenise it; it doesn't follow the accent skin and isn't app-wide. This is the only permitted raw hex. Everything else uses `AppColors`/`colorScheme`. Warm/orange is for the primary CTA only.
- One page at a time: touch only the file asked about.
- UI changes: show or describe the plan and wait for approval before code.
- Commit before starting anything new.
- Widgets referencing `AppColors.of(context)`/`Theme.of(context)` can't be `const`.
