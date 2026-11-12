# CLAUDE.md

Flutter (Dart, Material 3) app on **Supabase** (Postgres + Auth + Realtime) and **Firebase** (FCM push).

## Commands
```bash
flutter analyze && flutter test
# release: see dev/release_build.md (archive build/symbols per shipped build)
supabase functions deploy <name>   # ASK FIRST. coach-max-cron, delete-account, invite-redirect, send-notification, stale-accounts-cron, workout-overtime-cron
```
`db reset` fails (see Migrations).

## Architecture
- `lib/main.dart`: loads `.env`, inits Firebase (mobile only) + Supabase, mounts `AuthWrapper`. It reads the onboarding state (`AuthService.onboardingState`, from `user_profiles.onboarding_completed`) and routes to `HomeScreen` (complete), `OnboardingHost` (unfinished account, resumed) or `SplashScreen` (signed out, or state unknown). Deep links (`app_links`) are intercepted here; invite codes go through `InviteService.storePendingInviteCode`.
- `lib/home_screen.dart`: 5-tab shell (Schedule, Friends `FriendsPageModern`, Dashboard, Shop, Profile). Opens on Dashboard.
- `lib/services/`: plain Dart classes calling `Supabase.instance.client` directly. All business logic lives here.
- Theming: `AppColors` ThemeExtension. Use `AppColors.of(context).x` or Material colour slots.

### Non-obvious service facts
- `WorkoutService` spans two tables: `workouts` and `active_checkin_sessions`.
- `TeamStreakService` defines `TeamMember`, `CheckInStatus`, `TeamStreak` at the top of the file.
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

**Table grants must be explicit.** New `public` tables get `anon` and `authenticated` grants from default privileges, so every migration that creates a table must enable RLS, `REVOKE ALL … FROM anon`, `REVOKE TRUNCATE … FROM authenticated`, and grant only the privileges the client needs.

**Grant traps.** A column-level `REVOKE` does nothing against a table-level grant: revoke the table privilege, then grant the safe columns back. `REVOKE INSERT, UPDATE (col)` revokes table-level INSERT: write `INSERT (col), UPDATE (col)`. Reason: the first left the economy columns writable until 2026-07-17, and the second nearly broke the onboarding upsert on 2026-10-01.

**Replacing a function.** Before `CREATE OR REPLACE FUNCTION`, diff the new body against `pg_get_functiondef` on live and account for every removed line. Reason: migration `20261008200000` replaced `process_stale_sessions` and dropped its pushes, so solo check-ins got none until `20261105120000`.

**Account deletion** goes through the `delete-account` Edge Function (service_role deletes `user_profiles`, then `auth.admin.deleteUser`). A postgres-owned `SECURITY DEFINER` RPC cannot delete `auth.users` when called as `authenticated`, so the old `delete_own_account` RPC only ever removed the profile. Call site: `AccountPage` (self-serve delete). Unfinished accounts (no profile row, or `onboarding_completed` false, which a Join on the buddy step writes early) are resumed at step 2 and never deleted at sign-in. The daily `stale-accounts-daily` job (`stale-accounts-cron` Edge Function, same two steps) deletes them 30 days after creation or last sign-in, whichever is later. It never deletes paired accounts, Coach Max, or a row with a NULL flag.

**Testing permissions:** run the trusted call in a clean session. PL/pgSQL caches plans per session, so an earlier more-privileged call can make a later `SET ROLE authenticated` call wrongly succeed. Verify with a fresh authenticated-only call.

**Migrations:** `supabase/migrations/` and live history are reconciled (local files and remote versions match one-to-one, and `supabase db push --dry-run` should say "up to date"), but a from-scratch replay / `db reset` fails. The base tables (`team_members`, `user_profiles`, `friendships`, …) predate version control. Their DDL is in `dev/pre_vc_schema_baseline_20260720.sql`, which is reference only: do not apply it or place it in `supabase/migrations/`, because it is a record for a from-scratch rebuild and not an executable step (its header has the detail). Don't retime the baseline migration `20260628000000` to fix ordering; it only moves the failure. Applying a migration is ASK FIRST (see [Permission tiers](#permission-tiers)). Apply migrations with the CLI (`supabase db query --linked -f <file>`, then `migration repair --status applied <version>`), never the MCP `apply_migration` tool: it stamps its own version, which causes drift. `supabase db push` is also fine when `--dry-run` lists only the new file. Never run `migration repair --status reverted` on existing versions: it deletes history and `db push` would re-run the local files. `migration repair` is metadata-only (never runs SQL). Files in supabase/migrations/ that match an already-applied remote version are history records, not to be edited or re-run.

**Lock order for credit paths** (prompt 07, `dev/hygiene/07_design.md` §3). Take locks in this order, ascending key order within a level. Every added lock carries a `-- L<n>` comment, and `dev/hygiene/suite/run.sh` (G0) fails if a body reorders them.

| Level | Lock | Key order |
|---|---|---|
| L0 | `workouts` row (`finish_checkin_session` with a workout id; handshake RPCs via `_hs_lock`) | one row |
| L1 | `active_checkin_sessions` row(s) | own row; cron: `SKIP LOCKED`, then `ORDER BY id` |
| L2 | `team_streaks` rows `FOR NO KEY UPDATE` (`_lock_credit`, `_recompute_team_streak`, `check_in_coach_max`, `reconcile_stale_streaks`) | streak id |
| L3 | `pg_advisory_xact_lock(hashtext('checkin_cap'), hashtext(user_id::text))`, paying credits only (`_lock_credit`) | lock key |
| L4 | `checkin_rewards:<streak>:<day>` advisory (`_apply_checkin_rewards`, CAP-1) | per streak |
| L5 | row writes: check-in unique key, `user_profiles`, transactions, `invites FOR UPDATE`, schedule, logs | n/a |

Known residual: `process_stale_sessions` takes L1 before L0 (CRON-ORDER, pre-existing; a cycle aborts one side with 40P01).

**Known gap:** leaked-password protection is off (needs Pro plan). Enable it before public launch.

## Working style
The owner is the only developer and wants fewer stops (owner, 2026-11-12). These lines apply to every session.
- Say in one line what you are about to do before you start. Give a short update every few tool calls. Close with a recap that makes sense to a reader who saw none of the tool calls: what changed, what you verified and how, what is left, what you need from the owner. Plain full sentences, key points first.
- Finish the whole task. A turn does not end with a list of what remains or an offer to continue: do the next part.
- Plans: post the plan, then proceed. Wait for an answer only when the plan contains an owner decision or an ASK FIRST action.
- Obstacles (errors, timeouts, failing tools, empty results): diagnose, retry with a fix, continue. Stop only for a real blocker: a decision only the owner can make, a missing approved mockup (stop at that item only), or an action in NEVER or ASK FIRST.
- Where you must ask, prepare everything first (the exact command, the verification steps), put the question in the recap, and carry on with the work that does not depend on the answer.
- Subagents: for parallel read-only searches or an independent review of your own diff, run on Sonnet. Edits stay in the main session. Reason: owner preference, no recorded cause.
- Model and effort: Fable 5.2 at high effort by default, medium for mechanical work, xhigh only when a task measurably needs it. The "Opus" and "Sonnet-medium" labels in older `dev/` trackers are history; use only their size.

## Permission tiers
Three lists. A rule that already lives in another section is linked, not repeated. An action in no list and under no rule is FREE when it is local to the repo and reversible (name it in the recap); otherwise it is ASK FIRST. `.claude/settings.local.json` (local, not in git) enforces part of these lists; where it and this file disagree, the stricter one holds.

### NEVER
- **`git push`**: any remote, any branch, any flag. Local branches and commits are FREE. Reason: owner preference, no recorded cause.
- **Git worktrees**: none, for any purpose. Use the prompt's branch in the main folder ([Rules](#rules), Branches). Reason: owner's ways-of-working rule.
- **`flutter run`, `flutter install`, uninstalling the app**: on any device or emulator, any build. Reason: owner preference, no recorded cause.
- **Screenshots**: no `screencap` in any form. If a visual check is truly needed, name the screen and let the owner look. Reason: owner preference, no recorded cause.
- **Secret values in output**: do not print the value of an `.env` key, the service-role key, a token or a vault entry in chat, reports, commits or logs. Refer to it by name. Reason: this repo is public on GitHub; no incident on record.
- **Credit or streak functions outside a rolled-back transaction**: on the live project, a call to any function on a credit path ([Supabase rules](#supabase-rules), Lock order) runs inside a transaction that ends in `ROLLBACK`, as `dev/hygiene/suite/run.sh` does. Reason: on live they pay real coins and move real streaks.
- **Applying a migration or deploying an Edge Function without the owner's go-ahead**: the go-ahead names that file or function, and an earlier one does not carry over. Ask as in ASK FIRST. Reason: the linked project is the live one, and its history must match `supabase/migrations/` one-to-one ([Supabase rules](#supabase-rules), Migrations).
- **Granting `SELECT` on the private `user_profiles` columns**: to `authenticated` or `anon`, at table or column level. The allowlist is in `supabase/migrations/20261012210000_profile_visibility.sql`, and clients read their own private columns through `get_my_profile`. Reason: owner decision 2026-10-12, other users see discovery fields only.
- **Attribution in commits or PRs**: no `Co-Authored-By`, no session links ([Rules](#rules), commit subjects). Reason: the global settings blank it, and history has had none since 2026-09-28.
- **UI code without an approved mockup**: any UI change. With an approved mockup, post the plan and proceed. Without one, write the UI spec, stop at that item, and carry on with the rest. Reason: no throwaway work on a rejected design.
- **Emojis in pushes, toasts or dialogs**: text the app shows or sends. Reason: owner preference, no recorded cause.
- Also NEVER, with scope and reason where they live: the MCP `apply_migration` tool and `migration repair --status reverted` on existing versions ([Supabase rules](#supabase-rules), Migrations); a function body that reorders credit locks (Lock order); and, under [Rules](#rules), report text or backticks in an unquoted heredoc or a `-m` message, a tap near a destructive control on a real account, and any change to the Coach Max gradient.

### ASK FIRST
Name the exact action each time: the command, the file or function, and what it changes. One answer covers one action.
- Applying a migration to the live project ([Supabase rules](#supabase-rules), Migrations, has the steps).
- Deploying an Edge Function (`supabase functions deploy <name>`).
- Any `supabase db` command that is not in FREE.
- Any `flutter pub` subcommand other than `get`, and adding a dependency to any manifest.
- Changing a table grant or an RLS policy, including inside a migration: name the table, the role and the privilege ([Supabase rules](#supabase-rules) has the grant rules).
- Deleting files outside the repo.

### FREE
- Reading any file (secret values stay out of output) and editing repo files.
- Creating the prompt's branch from `main` in the main folder.
- Local commits on the working branch once `flutter analyze` and `flutter test` pass.
- `flutter analyze`, `flutter test`, `deno test`, `flutter pub get`.
- `dev/hygiene/suite/run.sh`, with `--with <migration.sql>` for an unapplied migration. It runs only rolled-back transactions.
- Read-only Supabase queries and logs, `supabase db push --dry-run` and `supabase migration list`. A read-only `supabase db query` still raises a permission prompt, because the permission file cannot tell a `SELECT` from a write. That prompt is the owner's check on the command, not a reason to stop the task.
- Text-only adb checks: `uiautomator dump` to a file then grep, `dumpsys`, `logcat`.

## Rules
- **Coach Max gradient** `0xFF1D4ED8` → `0xFF7C3AED` is scoped to his badge/avatar. Do not change its values, tokenise it or use it elsewhere. Reason: it doesn't follow the accent skin and isn't app-wide.
- **Raw hex** is permitted in two places: the Coach Max gradient and the avatar illustration colours (`lib/widgets/avatars/`). Everything else uses `AppColors`/`colorScheme`. Reason: owner preference, no recorded cause.
- Warm/orange is for the primary CTA only. Reason: owner preference, no recorded cause.
- One page at a time: a request about one page changes only that page. A prompt that spans files changes what it needs and nothing else. Reason: tight, reviewable diffs with no surprise side effects.
- Branches: one branch per prompt, named in the prompt, created from `main` in the main folder. Worktrees are in the NEVER tier.
- Commit your own work before starting something new. Reason: each unit of work stays clean and reversible.
- Widgets referencing `AppColors.of(context)`/`Theme.of(context)` can't be `const`.
- Write reports, and any text that contains backticks, with the Write tool, and commit with `git commit -F <file>`. Reason: an unquoted heredoc ran `supabase db push` and the suite on 2026-10-29, and a `-m` message ran its backticked words as commands.
- Before any `adb shell input tap`, read the element's bounds from a `uiautomator dump`. Never tap near a destructive control on an account that is not a test account. Reason: guessed coordinates triggered two real account deletions.
- Theme work: build and check in Emerald Ink. Do not change the values of Signal Blue or Lime Spark. When a new token is added, give the other two skins a placeholder equal to the Emerald Ink value so the app compiles. Reason: only Emerald Ink is being designed, but all three skins must keep compiling.
- Coding style: the Ponytail plugin, not karpathy-guidelines. Reason: one guide, so advice on tests and dead code does not conflict.
- Commit subjects are one plain sentence, no type prefix, no attribution (no Co-Authored-By, no session links). Reason: it matches the history since October 2026 and the blank attribution in the global settings.
- `docs/` is the public website (GitHub Pages). Working files (reports, audits, rollbacks, probes) go in `dev/`. A `docs/` path that a prompt gives for a working file means the same path under `dev/`. Reason: Pages served the working files until commit f44a77e moved them out.
- `CLAUDE.md` is public on GitHub. Do not add security gaps or internal weaknesses to it; they go in the tracker under `dev/audits/`, which is kept out of git. Reason: owner instruction, 2026-11-12.
