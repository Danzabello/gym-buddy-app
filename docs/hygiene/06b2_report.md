# 06b-2: V5 onboarding with Coach Max as guide

Client only. No migration, RLS or edge function change. No push. Four local commits.

```
e0bde11 onboarding: single host with persistent Coach Max layer and slide/hop transitions
fa6fb58 onboarding: sign up, avatar, border, identity and buddy steps
20bdff6 onboarding: streak explainer, notifications and all-set steps
(this commit) onboarding: remove obsolete steps from the new-user flow
```

(Commit 4 also carries this report, so its hash is not listed; `git log -4` is authoritative.)

## Read this first: three things that differ from the brief

**1. The account is created at step 1, the profile at step 5.** Before this change nothing touched Supabase Auth until "Finish setup". The username availability check ran *before* any account existed, as `anon`. Live `anon` has no SELECT on `user_profiles` (probed read-only: `42501 permission denied`), so on the live database the old username step could only ever show "Error checking username" and block Next. A client-only fix is to create the auth user at step 1 so the check runs signed in (probed as `authenticated`: works). That is what the flow does now. Consequences:

- Step 1 "Create account" calls `signUp`. If that fails it tries `signIn` with the same credentials. No profile row: resume (continue at step 2). Profile row with `onboarding_completed = true`: sign out again and show the same generic message as any other failure (no email enumeration). Half-made profile (older build): same delete-account-and-retry the old code did.
- The single profile insert (all columns, `onboarding_completed = true`), timezone sync, push init, `ensure_coach_max_team`, deep-link invite pairing and the intro's friend requests all happen at the **step 5 CTA**, the same moment the old "Finish setup" ran them. Nothing is written at steps 2 to 4. No half profile.
- `onboarding_completed` is therefore set at step 5, **not** at "Let's train". It cannot be set later: `main.dart` treats a stored `false` as an orphan and deletes the account (`_cleanupOrphanedAccount`). "Let's train" only navigates Home. There was never a separate completion write.
- Back is offered on steps **3 to 5**. Step 2 follows the sign-up that created the account (button hidden, as the brief asked). Steps 6, 7 and All set follow the profile write, so Back is hidden and Android back is swallowed there. NEEDS-DECISION if you want Back on 6 and 7.
- Resume at step 2: `SplashScreen._getStarted` routes a signed-in user straight to the host at step 2. This covers "signed up at step 1, never finished" (no profile row, `checkOnboardingStatus` returns null, `main.dart` shows Splash). I did **not** touch `main.dart`. The case "profile row exists with `onboarding_completed = false`" is still deleted by `main.dart`; no new code creates such a row. NEEDS-DECISION only if you want that branch changed (it is the DI-7 / S4 audit path).
- Email confirmation: the code needs an immediate session. If confirmation were enabled, `signUp` returns no session and step 1 shows the generic "We could not complete your signup" message (before: the final step failed with "Could not save profile"). I could not read the live auth setting from here.

**2. Step 3 has no free ring colours to offer.** Ring colours are `shop_items` rows with `category = 'ring_color'` (read through `CoinService.getShopItems`, readable by `anon`). Live: 9 rows, none free. Two cost 0 but need an achievement (Molten Bronze: Century Club, Crown Gold: Year of the Beast); the rest cost 150 to 400 coins and some need a level. Owning and equipping a ring goes through `user_inventory`, which a new account cannot write. So step 3 is built from the data and works as specified, but today shows one swatch: "Classic" (the default ring, `AppColors.avatarRing`), and the first two locked rings with their real unlock text (achievement name, `Level N`, or `N coins in Shop`, the same rules as the Wardrobe ring screen). The choice is held in the draft and drives the preview colours; **nothing about ring colour is persisted** (`avatar_border` is written as `'simple'`, which is the style column). A free starter ring needs a server-side grant: out of scope here. NEEDS-DECISION.

**3. Step 6 arc sides vs chip sides.** The brief puts the user chip on the left and Max's chip on the right, but says the orange half fills "from the top counter-clockwise", which is the left half, and the green half is therefore the right. Built literally: green half clockwise from the top (right), orange half counter-clockwise (left), chips in the lower left and right corners of the ring box (outside the stroke), so the halves and the chips do not visually pair up. If the intent was that each half sits beside its own chip, swap the two arc directions in `_TwoHalves` (one line). NEEDS-DECISION.

## Prechecks

1. **Structure before.** Separate pushed routes: `SplashScreen` -> `OnboardingValueProps` (collects friends to invite) -> `SignUpScreen` (validation only, no DB) -> `OnboardingBasicInfoNew` ("About you": name, age, gender) -> `_OnboardingUsername` -> `_OnboardingAvatarPicker` (`AvatarPickerScreen`: avatar + border style) -> `_OnboardingGoals` (goals, level) -> `_OnboardingBuddyPrefs` (looking_for_buddy, workout style, "Finish setup") -> `_OnboardingConfirmation` -> (06b) `OnboardingNotifications`. All in `onboarding_basic_info_new.dart` except sign-up, splash, value props and notifications. DB writes: none until "Finish setup", then in order: `auth.signUp`, one `user_profiles` insert (display_name, username, age, gender, avatar_id, avatar_border, fitness_goals, fitness_level, looking_for_buddy, preferred_workout_style, onboarding_completed = true), timezone sync, `NotificationService.initialize()`, `ensure_coach_max_team`, pending deep-link invite, friend requests. The username check was a read, before auth.
2. **Email confirmation / completed flag.** See above. The real flag is `user_profiles.onboarding_completed`, written in the profile insert, read by `AuthService.checkOnboardingStatus` (true: Home; false: orphan, account deleted; null on error or no row: Splash).
3. **Readers of the removed values.** `fitness_level`: `friends_page_modern` (`?? 'BEGINNER'`), `profile_view_dialog._formatLevel` (null gives "Beginner"), plain selects in `workout_service` / `friend_service`. `looking_for_buddy`: selected in `friend_service`, never filtered on. `fitness_goals`, `preferred_workout_style`, `gender`: no reader in `lib/` or the edge functions. Nothing crashes on null or default. Values written now: `fitness_level 'beginner'`, `looking_for_buddy true`, `preferred_workout_style 'both'` (the removed screens' own defaults); `fitness_goals` and `gender` not sent (NULL).
4. **Buddy mechanisms.** Coach Max: `CoachMaxService.initializeCoachMaxForUser` -> `ensure_coach_max_team` RPC (idempotent), run for everyone at the step 5 CTA, so Invite users also have him until the friend joins. Invite: `InviteService.createInviteLink()` -> `create_invite` RPC -> link via the `invite-redirect` function; shared with `SharePlus.instance.share` as in `friends_page_modern.dart`. `share_plus ^13.1.0` is already in `pubspec.yaml`: no new package.
5. **Avatars / rings.** Avatars: `lib/data/avatar_catalog.dart` (starters wolf, bear, lion; unlock text per earnable). Existing picker copy: "Pick your icon — unlock more as you level up". Rings: see item 2 above.
6. **All set.** Body copy reused verbatim: "Your profile is ready. Coach Max is waiting. Time to build some streaks." Android back before: pushed routes popped to the previous step; the first route (sign-up, About you) and the confirmation exited the app. Now: step 1 pops, or goes to Splash if nothing to pop to; step 2 swallowed; steps 3 to 5 go back one step; steps 6, 7, All set swallowed.
7. **APIs.** `AnimatedCoachMax({size, mood: CoachMaxMood.idle|happy|worried, animate})`. `AnimatedBear({size, mood: BearMood, animate})`. `UserAvatar({avatarId, size, animated, bare, semanticLabel})`.
8. **Tokens.** See "Tokens" below.

## Status per item

| Item | Status |
|---|---|
| Host, single Max layer, anchors, slide/hop, squash, bubble delay, reduced motion | DONE |
| Step bar (7 segments, "Step N of 7"), back button 48x48 | DONE (Back on 3 to 5 only, see above) |
| 1 Sign up (terms checkbox removed, single legal line, links) | DONE |
| 2 Avatar | DONE |
| 3 Border | DONE as far as the data allows; NEEDS-DECISION (no free rings, nothing persisted) |
| 4 Identity (live preview, availability check) | DONE; helper text uses the real rule, see below |
| 5 Buddy (Invite / Coach Max) | DONE |
| 6 Streak explainer | DONE; NEEDS-DECISION (arc sides) |
| 7 Notifications (gold bell, rows, request only from the button) | DONE |
| All set | DONE |
| Resume at step 2 | DONE for the no-profile case; main.dart orphan delete untouched (see above) |
| Google sign-in | not added; the bottom block of step 1 is in the scroll body so a button can go under "Create account" and only the legal line and log-in link move down |
| Obsolete steps removed | DONE (commit 4) |

## Details worth knowing

- **Username helper text.** The brief's line says dots are allowed; the real rule (`InputValidators.username`, the formatter and the server check) is letters, numbers and underscores, 3 to 20, no leading or trailing underscore. Kept the existing text: "3 to 20 characters. Letters, numbers and underscores. No underscore at the start or end."
- **Avatar hint.** Existing copy is "Pick your icon — unlock more as you level up"; the hint under the row reads "Unlock more as you level up" (the same wording without the lead that duplicates the headline).
- **Step 2 bubble** uses the chosen avatar's name ("Lion is a great start.").
- **Old terms checkbox** lived in `SignUpScreen._next` (`_acceptTerms`, error "Please accept the Terms of Service and Privacy Policy.") and in the `Checkbox` row. Both are gone. Terms and Privacy open the same two GitHub Pages URLs in the browser.
- **`signup_screen.dart`** is now a ten-line shim that returns `OnboardingHost`, so `login_screen.dart` and `onboarding_value_props.dart` are unchanged.
- **`ObFieldLabel`** went from 14 to 13 to match the brief; this also affects the log-in screen's labels.
- **Writes that moved:** the whole profile write (and signUp) moved from "Finish setup" to two places: signUp to step 1, everything else stays at the final form step (now step 5). `updated_at` is now written with `.toUtc()`.
- **Invite flow:** account and profile are saved first, then the link is created and the share sheet opened; a failure or a dismissed sheet still continues to step 6 with a snackbar message. Step 6's right card always says Coach Max; the data model agrees (Coach Max team exists for everyone until a friend is paired).
- **Notifications:** the OS dialog is requested only by `NotificationService.requestPermissionFromUser()` from the "Turn on notifications" button; "Not now" only writes the seen flag. The old `OnboardingNotifications` widget and `notificationRationaleSeen()` were deleted; `markNotificationRationaleSeen()` is the one remaining helper.

## Tokens

Added one: `AppColors.aqua` (`#67E8F9`, Coach Max ring and AI chip), in `lib/theme/app_theme.dart`.

Reused rather than added (values differ slightly from the brief):

| Brief | Used | Value |
|---|---|---|
| gold `#F5B73B` | `AppColors.warn` (= `AccentPalette.gold` on Emerald Ink) | `#FBBF24` |
| field fill `#123329` | `inputFill` | `#123328` |
| hint `#8FAA9C` | `subtleText` (what `obInputDecoration` already uses) | `#B9CFC3` (brighter) |
| border `#5FA396` | `info` | `#5FA396` |
| background / chip text `#0B1F1A` | `scaffoldBackgroundColor` | `#0B1F1A` |
| cream | `colorScheme.onSurface` | `#F8E7C9` |
| CTA label `#111827` | `readableForeground(streakOrange)` | `#111827` |

The bell's pale highlight and dark clapper are derived from the gold token (lerp to white, HSL lightness). No raw `Color(0x...)` was added outside the theme file.

## Files touched

New in `lib/onboarding/`: `onboarding_host.dart`, `onboarding_max.dart`, `onboarding_max_layer.dart`, `onboarding_draft.dart`, `onboarding_account.dart`, `onboarding_step_signup.dart`, `_avatar`, `_border`, `_identity`, `_buddy`, `_streak`, `_notify`, `_allset`. Changed: `onboarding_theme.dart` (label size), `splash_screen.dart` (resume), `onboarding_notifications.dart` (trimmed), `onboarding_basic_info_new.dart` (trimmed to the three helpers `test/onboarding_profile_insert_test.dart` imports), `lib/signup_screen.dart` (shim), `lib/theme/app_theme.dart` (aqua). Test: `test/onboarding_host_test.dart` (step bar segments and label, Max side/size table and travel direction, AI chip threshold).

## Unreferenced now (not deleted)

- `lib/widgets/avatar_picker_screen.dart` (`AvatarPickerScreen`): only mentioned in comments and in `data/avatar_catalog.dart`.
- In `onboarding_theme.dart`: `ObStepHeader`, `ObStepFooter`, `ObHeader`, `ObBottomNav`, `ObGradientButton`, `ObGhostButton`, `ObProgressDots`, `kGradient`, `kGradientDiag`, `kObBlue`, `kObPurple` (nothing outside this file references any of them; `ObStepHeader` and `ObStepFooter` lost their last users in this change, the rest were already dead or only fed those).
- Nothing in `lib/` pushes About you, Goals or Buddy preferences any more (they were classes in `onboarding_basic_info_new.dart`, removed in commit 4; no file was deleted).

## Other uses of the protected Coach Max gradient (`#1D4ED8` to `#7C3AED`) and the old AI chip colour

Left alone, listed for your decision:

- `lib/home_screen.dart`: 566 (`_kBrandGradient`), 4908-4909, 4966-4967, 6517, 6594
- `lib/widgets/profile_view_dialog.dart`: 223-224, 382-383 (also 24)
- `lib/widgets/custom_streak_selector.dart`: 394, 479
- `lib/widgets/friends_page_modern.dart`: 1031, 1071, 1762 (also 513-514, 55, 1135 for plain purple)
- Old AI chip colour (`_kAiTagBackground #2C2C34`, white text): `lib/widgets/ai_disclosure_tag.dart` (`AiCornerBadge`, `AiInlinePill`), used from `lib/home_screen.dart`.
- The old blue/purple `kGradient` in `onboarding_theme.dart` is no longer used by any screen.

## Verification

- `flutter analyze` (whole project): no issues. `flutter test`: 177 passed (3 new).
- Throwaway widget smoke test (not committed): host driven through all 8 pages with the real step widgets, at text scale 1.0 and 1.3, with and without `disableAnimations`, 1080x2200 at 3x: no exceptions or overflow. Supabase was a dead local URL, so the ring list was empty in that run.
- Release build: `flutter build apk --release --target-platform android-arm64 --obfuscate --split-debug-info=build/symbols`: `build/app/outputs/flutter-apk/app-release.apk`, 28.4 MB (28,432,351 bytes), signed with the release key (`CN=Daniels Zabello, O=Gym Buddy`, SHA-256 `c4734c65...409f295`), not the debug key. Symbols in `build/symbols` (12 MB).
- Greps: no raw `Color(0x...)` in any new or changed onboarding file (the only addition in `lib/theme/app_theme.dart` is the `aqua` token); no emoji in new strings; `requestPermission` only reachable through `NotificationService.requestPermissionFromUser()`; no Google code; no route to About you, Goals or Buddy preferences.
- Not verified on a device: flight arcs, timings, the bell animation and the live ring list. Those need your install.

## Unrelated things noticed

- Before this change, a fresh sign-up on live was effectively blocked at the username step (anon cannot read `user_profiles`). Worth checking whether the build you last installed could actually register a new user.
- `AuthService.signUp` swallows the exception and always returns "Sign up failed. Please try again.", so the old `contains('user_already_exists')` branches in the previous finish code never ran.
- `main.dart` deletes an authenticated account whose profile row has `onboarding_completed = false` (DI-7 / S4 path). Fine while nothing writes that value, but it is a landmine for any future "complete later" design.
- `macos/Flutter/GeneratedPluginRegistrant.swift` still shows as modified (Crashlytics plugin lines from `flutter pub get`); left alone as agreed.
- Nine local commits are ahead of `origin/main` (these four plus five earlier ones).
