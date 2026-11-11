# Prompt 06b report

Status: A DONE, B DONE, C DONE (with scope note), D DONE. Nothing run on a device.

## Prechecks
- Onboarding's real last step: `_OnboardingBuddyPrefsState._finish()` saves the profile and does `pushAndRemoveUntil(_OnboardingConfirmation)` (onboarding_basic_info_new.dart, ~line 850). The confirmation screen's "Let's train" button ran `_goHome()` -> `HomeScreen`. The rationale screen now sits between the two.
- Callers of `NotificationService.initialize()`: main.dart:135 (every launch with a session), login_screen.dart:149 (after sign-in), onboarding_basic_info_new.dart ~918 (after profile insert). Only `initialize()` itself called `requestPermission`.
- Local store: `shared_preferences ^2.5.3` (already used by invite_service, login lockout, accent theme).
- OS settings: `app_settings ^5.1.1` already present and used in the Settings page.
- Versions: firebase_core 3.15.2, firebase_messaging 15.2.10, AGP 8.9.1, Kotlin 2.1.0, Gradle 8.12. Google services plugin was already applied (classpath 4.4.0).

## Call sites
Before: 3 callers of `initialize()`, each of which showed the OS dialog.
After: the same 3 callers still call `initialize()`, which now only reads `getNotificationSettings` and sets up listeners/token when already granted. The only `FirebaseMessaging.requestPermission` is inside `NotificationService.requestPermissionFromUser()`, called from the rationale screen button and the Settings banner / switch taps. A grant calls the same setup, so listeners and token register in that session.
Behaviour change: an account that denied at the OS level no longer gets a token row saved at launch (it used to).

## Android back (kept consistent)
Steps 2-5 pop to the previous step. Step 1 (replaced signup) and the confirmation screen (pushAndRemoveUntil) have nothing underneath, so back leaves the app. The rationale screen is pushed over the confirmation screen, so back returns to the confirmation screen (like the earlier steps). No custom handling.

## Item A (commit 1)
Files: services/notification_service.dart, onboarding/onboarding_notifications.dart (new), onboarding/onboarding_basic_info_new.dart (hook in `_goHome`), onboarding/onboarding_theme.dart (`ObPrimaryButton`).
Seen flag: `notif_rationale_seen_<userId>` in shared_preferences. Per user so a second new account on the same device still gets the screen. The screen is only reachable from the confirmation screen, so login and app start never show it; the flag is also checked there.
Token deviations (no exact token): clay surface `#1B4C40` -> `claySurface`; CTA label `#111827` -> `AppColors.readableForeground(streakOrange)` (resolves to that ink); darker orange shadow -> HSL lightness -0.18 of `streakOrange`.
Also moved `onTokenRefresh.listen` under the existing `_listening` guard so repeated setup does not stack listeners.

## Item B (commit 2)
File: pages/notification_settings_page.dart.
- Android FCM only reports authorized/denied, never "not determined". "Permanently denied" is detected by timing: a denial returned in under 400 ms means no dialog was shown, so the Settings page opens `AppSettings`. Heuristic; confirm on device.
- Removed: the white-on-gradient hero banner (not in the spec). Emoji tile icons replaced by outlined Material icons. "Social" renamed "Buddy activity".
- Kept: Save button/action, quiet-hours time rows and info chip, "Live check-in banner". That last one is an in-app setting, not an OS notification, so it is not gated by the OS state or drawn off; it sits at the bottom of the first group.
- Switch outline `#4A8F78` has no token: used `AppColors.info` (`#5FA396`, nearest hue). Needs an owner decision on a real token.
- Pre-existing and left: Save button label and saved-snackbar icon use `Colors.white` (white on orange is about 3.6:1).
- Writes to the database are unchanged.

## Item C (commit 3)
Files: signup_screen.dart, login_screen.dart, onboarding/onboarding_theme.dart, onboarding/onboarding_basic_info_new.dart. `widgets/avatar_picker_screen.dart` NOT touched (the step-3 wrapper scaffold and header are restyled; the picker body already uses AppColors).
- Shared widgets added: `obInputDecoration`, `ObTextField` (rebuilt), `ObHeading`, `ObStepHeader`, `ObStepFooter`, `ObBackButton`, `ObVisibilityButton`, `ObErrorBanner`, `ObLinkButton`. Login's private `_Label`, `_Field` and dumbbell logo were deleted (logo is not in the spec).
- Tokens without an exact match: input outline `#4A8F78` -> `info`; hint `#8FAA9C` -> `subtleText`; fill `#123329` -> `inputFill` (`#123328`).
- Username helper: real rules are 3-20 chars, letters/numbers/underscores, no leading/trailing underscore. Copy is "3 to 20 characters. Letters, numbers and underscores. No underscore at the start or end."
- Step 1 shows its back button only when the route can pop (it cannot today).
- Login keeps "Forgot password?". Its fade/slide entrance is skipped when `disableAnimations` is set.
- NEEDS-DECISION: steps 4 (goals) and 5 (buddy prefs) share the file and the old white/blue look; there was no mockup, so they got a mechanical token swap only (same layout, same copy, same chips). Left alone: the "You're all set" confirmation screen (blue-purple gradient, celebration emoji) and the Coach Max badge gradient inside step 5 (`kGradient`). `kObBlue/kObPurple/kGradient*` stay defined in onboarding_theme.dart for those two.
- Existing emoji in the goals/style chips and the confirmation screen were left.

## Item D (commit 4)
- `firebase_crashlytics ^4.3.0` (resolved with firebase_core unchanged at 3.15.2).
- Gradle files changed: `android/build.gradle.kts` (added `firebase-crashlytics-gradle:3.0.2`; bumped `google-services` 4.4.0 -> 4.4.2, which plugin 3.x requires), `android/app/build.gradle.kts` (applied `com.google.firebase.crashlytics`).
- main.dart: collection disabled when `kDebugMode`; `FlutterError.onError` -> `recordFlutterFatalError`; `PlatformDispatcher.onError` -> `recordError(fatal: true)`, returns true. No user id, no custom keys, no logs.
- Data the SDK collects by default (from package docs): crash and non-fatal stack traces, device model/OS version/orientation/free memory and disk, app version, and the Crashlytics installation UUID. No analytics SDK added.
- Timeouts (new `_startupRead` helper in main.dart): `NotificationService.initialize()` 10 s, `checkOnboardingStatus` 15 s, `scheduleCoachMaxCheckIn` 15 s. A timeout reports a non-fatal with the read name only and returns null. Not wrapped: dotenv/Firebase init (local), `Supabase.initialize` (no useful fallback), deep-link reads (local).
- What the user sees on a timeout today: onboarding-status timeout -> null -> "unknown" branch -> `SplashScreen` (welcome), account untouched, signing in again re-runs the check. The other two just continue. No retry screen added (needs a mockup).
- docs/release_build.md: 26 lines, adds the `firebase crashlytics:symbols:upload --app=<mobilesdk_app_id> build/symbols` step (owner runs it) and the archive reminder.
- No test crash triggered.

## Verification
- `flutter analyze`: no issues (whole lib/); no pre-existing warnings.
- `flutter test`: 174 passed.
- Build: `flutter build apk --release --target-platform android-arm64 --obfuscate --split-debug-info=build/symbols` OK, 28.5 MB, signed with the release key (cert CN=Daniels Zabello), `build/symbols` has the 3 `.symbols` files. Crashlytics mapping task ran in the build without error.
- Manifest: package `com.gymbuddy.app`, POST_NOTIFICATIONS present. Permissions: INTERNET, ACCESS_NETWORK_STATE, RECEIVE_BOOT_COMPLETED, VIBRATE, POST_NOTIFICATIONS, WAKE_LOCK, c2dm RECEIVE, plus the app's DYNAMIC_RECEIVER_NOT_EXPORTED_PERMISSION. I did not keep a pre-change APK to diff, so I cannot say which of these Crashlytics itself contributes; none is dangerous.
- grep: `.requestPermission(` only in notification_service.dart. Raw `Color(0x...)` in touched files: none added. `Colors.white` scaffolds left: none (remaining `Colors.white` are the pre-existing Settings Save button/snackbar and the confirmation screen).
- Not verified: anything visual, text scale 1.3x, the 400 ms denial heuristic, switch animation.
