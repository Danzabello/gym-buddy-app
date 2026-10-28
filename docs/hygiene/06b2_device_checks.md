# 06b-2 device checks

Pixel `34061JEHN24896`, `com.gymbuddy.app` 1.0.0 (plain release build, installed 2026-10-28 21:08), main at `e07c860`. Text only: `uiautomator dump` to a file and parsed, `dumpsys`, `logcat`. No screenshots, no install, no uninstall, no push, no code change.

## Result: 9 PASS, 1 FAIL

| # | Check | Result | Evidence |
|---|---|---|---|
| 1 | Fresh sign-up path, Splash to Home | PASS | Walked with `onboardcheck1`. Every page showed the right title, `Step N of 6` (pages 1 to 6; the All set page has none), the bubble label `Coach Max · AI coach`, and the Max badge node `Coach Max, AI coach`. Badge sizes in the dump: 265 px (92 dp) on step 1, 184 px (64 dp) on steps 2, 3, 4, 6, 127 px (44 dp) in the streak chip, 449 px (156 dp) on All set. The AI chip is drawn inside the badge and excluded from accessibility, so its presence is inferred from the badge being 64 dp or larger; at 44 dp it is hidden by design. Titles seen: "Your streak starts with a buddy", "Pick your buddy", "Your identity", "Who's your buddy?", "Two rings. One streak." (bubble line 2, cards and "Miss a day..." line all present), "Keep your streak alive", "You're all set!". Ended on Home. |
| 2 | DB after finishing | PASS | Read-only SQL for `81f83cdb-e09b-4f1f-8045-afa0d3d2181e`: exactly 1 `user_profiles` row, `onboarding_completed = true`, `display_name 'Check Tester'`, `age 27`, `username 'onboard_check1'`, `avatar_id 'bear'`, `avatar_border 'simple'` (the column default, not written to), `fitness_level 'beginner'`, `looking_for_buddy true`, `preferred_workout_style 'both'`, `gender` and `fitness_goals` NULL, one Coach Max team membership. Before the buddy-step button the row count was 0. |
| 3 | Mismatched / weak password | PASS | Confirm `Different999` vs `Onboard12345`: "Passwords do not match", stayed on step 1. Password and confirm `abc`: "At least 8 characters required" under both fields, stayed on step 1. `auth.users` count for `onboardcheck%` was 0 after both. |
| 4 | Back behaviour | PASS | Step 1 has no Back button. Step 2: no Back button, Android back does nothing (still `Step 2 of 6`). Step 3: Back visible, Android back goes to step 2. Step 4: Back visible, Android back goes to step 3 with name, age and username kept ("Available" still shown). Steps 5, 6 and All set: no Back button, Android back does nothing. |
| 5 | Notifications | PASS | Permission revoked with `pm revoke` (`granted=false`) before starting. Account `onboardcheck2`: on arriving at step 6, tapping "Not now", reaching All set and Home, and after a force-stop and relaunch, no `permissioncontroller` window appeared and `POST_NOTIFICATIONS` stayed `granted=false`; the notification step did not reappear. Account `onboardcheck3`: arriving at step 6 showed no dialog; tapping the "Turn on notifications" button opened `GrantPermissionsActivity` ("Allow Gym Buddy to send you notifications?"); I tapped Allow and it went to `granted=true` (the state the device started in). Existing account: the device was signed in as `testing1234` (not `mijotest`); a cold start went straight to Home with no notification step. I did not test `mijotest` itself (no password). |
| 6 | Text scale 1.3 | PASS (with a note) | `font_scale 1.3`, walked steps 1 to 6 and All set with `onboardcheck3`: no node outside the 1080x2400 screen, every primary button fully on screen (e.g. "Turn on notifications" 1917-2084, "Not now" 2084-2222), no exceptions. Restored to 1.0. Note: a release build does not log RenderFlex overflows (that assertion is debug-only), so the evidence is node bounds, not logcat. On step 6 at 1.3 the second and third rows sit behind the pinned footer until scrolled (see "Needs your eyes"). |
| 7 | Reduced motion | PASS (text part) | `animator_duration_scale` and `transition_animation_scale` set to 0, app relaunched, walked all pages with `onboardcheck4` and `onboardcheck5`. A dump taken right after a tap already showed the next page at its final bounds with the bubble label present (in normal mode the bubble appears over a second later). On the streak step the first dump already showed bubble line 2, both cards, "Miss a day and the streak resets." and Max in the chip. No FATAL and no exceptions in logcat. Restored both to 1. |
| 8 | Force-quit after step 1 | FAIL (half) | `onboardcheck2` (id `bc85514c-02f2-4340-90f2-d95e3f62af26`) signed up and reached step 2, then `am force-stop` and relaunch. **Get started: PASS**, it reached `Step 2 of 6` (avatar). **Sign in: FAIL.** Force-stop, relaunch, "Already have an account? Sign in", correct credentials: the login screen showed "Could not verify your account. Please try again." instead of the avatar step. Cause below. |
| 9 | Duplicate email | PASS | Sign-up with `onboardcheck1@example.com` and a different password showed exactly "We could not complete your signup. Please check your details and try again, or sign in if you already have an account." and stayed on step 1. After a force-stop and relaunch the app showed Splash (signed out). |
| 10 | Logcat | PASS | Four logcat captures covering the sign-up walk, the 1.3 walk and both reduced-motion walks: 0 `FATAL EXCEPTION`, 0 unhandled Flutter exceptions, 0 overflow lines. Only `E` lines mentioning the package are Android `WindowOrganizerController`/`TransitionChain` messages from force-stop and relaunch. Crashlytics: `I FirebaseCrashlytics: Initializing Firebase Crashlytics 19.4.4 for com.gymbuddy.app` on cold start. The captures between check 8 and check 9 were cleared repeatedly, so those moments are covered only by the later captures. |

## Check 8 failure: cause

Not guessed, reproduced. For an account with no profile row:

- Server (REST, same token as the app): `POST /rest/v1/rpc/get_my_profile` with `Accept: application/vnd.pgrst.object+json` returns 406 `PGRST116`, details "The result contains 0 rows". Without that header it returns `200 []`.
- `postgrest` 2.7.0 `maybeSingle()` on an RPC (POST) sends the object header and only turns a 406 into `null` when the details say "Results contain 0 rows" (its `_handleMaybeSingleError`). This PostgREST says "The result contains 0 rows", so the exception is thrown.
- `AuthService.onboardingState()` (commit 158719e) catches it and returns `unknown`, so the login screen shows the old error and never reaches the new `noProfile` branch.

Same flaw, not exercised on the device: `createOnboardingAuthUser()` (step 1 fallback) uses the same `maybeSingle()` and treats `row == null` as "resume". Someone who signs up again with the same email and password after quitting at the avatar step would hit the catch, be signed out, and see "Something went wrong creating your account." Get started is unaffected because it checks only whether a session exists.

Proposed smallest fix (not applied, needs your OK): read the RPC as a list instead, e.g. `final rows = await rpc('get_my_profile').select('onboarding_completed'); if (rows.isEmpty) return OnboardingState.noProfile;`, in both `AuthService.onboardingState()` and `createOnboardingAuthUser()`. Alternative: catch `PostgrestException` with `code == 'PGRST116'`. `checkOnboardingStatus()` and `main.dart` would keep behaving as today.

## Setup notes

- Preconditions held: "Confirm email" is OFF (sign-up returned a session and `email_confirmed_at` was set on the new users).
- `supabase login` was not run: it is interactive and the CLI was already authenticated (`supabase projects list` and `db query --linked` worked).
- To start a fresh sign-up I had to sign out of the account the device was using, `testing1234`. You will need to sign back in. `mijotest` was not touched.
- `pm revoke` was used to reset the notification permission; it is back to `granted=true`, as at the start. `font_scale` is 1.0 and both animation scales are 1.
- The app is left signed in as `onboardcheck5` at Home.

## Test accounts (for LAUNCH-CLEAN)

All `@example.com`, password `Onboard12345` except where noted, all have completed profiles.

| Email | User id | Username | Used for |
|---|---|---|---|
| onboardcheck1 | `81f83cdb-e09b-4f1f-8045-afa0d3d2181e` | onboard_check1 | checks 1, 2, 4, 9 (password was changed only in the rejected duplicate attempt, which did nothing) |
| onboardcheck2 | `bc85514c-02f2-4340-90f2-d95e3f62af26` | onboard_check2 | checks 5 (Not now), 8; finished through the resume path |
| onboardcheck3 | `f0f43430-80aa-4c38-8f87-c11226bef86f` | onboard_check3 | checks 5 (Turn on), 6 |
| onboardcheck4 | `ae240bb6-e629-401e-9fb6-feb1ed21cee9` | onboard_check4 | check 7 |
| onboardcheck5 | `19c3b618-ae18-4b2e-be52-cbe1de8cacbe` | onboard_check5 | check 7 (streak step state) |

## Odd things

- After "Let's train" every new account lands on Home with a "workout plan" dialog (Cancel / Set Plan) over the dashboard. It also reappeared after a relaunch until cancelled. Pre-existing, not part of this change.
- The first adb tap on "Turn on notifications" hit the body sentence, which contains the same words; harmless, but a text-matching test script must target the button.
- A cold start with a revoked permission and an unfinished account showed no permission dialog at launch.

## Needs your eyes (text checks cannot judge these)

- Max's flights: arc shape, apex height, the squash on landing, the happy face during and 700 ms after a flight, the drop-in on first entrance, the hop from the top-left slot into the right chip.
- Page slides: direction (new page from the side Max is leaving), the 600 ms feel, the outgoing fade.
- Whether the bubble really appears 350 ms after Max lands and not before.
- Step 6 ring: green left half filling counter-clockwise from the top, orange right half clockwise, chips on the ring line, the flame lighting and pulsing, the dashed slot.
- Step 7 bell: swing and decay, clapper, ring waves, the "1" badge pop and fade, tile glow.
- All set: halo pulse, rise-in stagger, Max happy for 2.2 s.
- Step 6 at text scale 1.3: the "Streak at risk" and "Workout reminders" rows end up behind the pinned buttons until you scroll. Not clipped, but check it reads acceptably.
- Reduced motion: that it is a clean cross-fade rather than a hard cut.
