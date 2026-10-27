# Prompt 06: Play Store blockers, part 1

| Item | Status |
|---|---|
| A1 Launcher icon | DONE |
| A2 App label | DONE |
| A3 Package / namespace | DONE |
| B1 Google button | DONE |
| B2 Chat "coming soon" | NEEDS-DECISION (no edit made) |
| B3 Best streak | DONE |
| B4 Placeholder unlock nodes | DONE |
| C Obfuscated release build | DONE |

Pre-flight: `git status --short` showed only `android_icons/` untracked.

## A1 Icon
- Source `android_icons/` found (`ic_launcher_512.png`, `mipmap-anydpi-v26/ic_launcher.xml`). `playstore/ic_launcher_512.png` is 512x512 8-bit/color RGBA (32-bit); the 1024 master is RGBA too.
- Existing mipmaps were only `ic_launcher.png` x5 (no webp, no template foreground/background). Nothing removed; the five PNGs were overwritten.
- Added `ic_launcher_{background,foreground,monochrome,round}.png` per density and `mipmap-anydpi-v26/ic_launcher{,_round}.xml` (adaptive icon with background, foreground and monochrome).
- Manifest: `android:roundIcon="@mipmap/ic_launcher_round"` added.
- pubspec assets are `.env`, `assets/animations/`, `assets/animations/branding/`; nothing bundles `android_icons/` or `assets/store/`. APK has 0 entries for either.
- `android_icons/` committed as a source set.

## A2 Label
`android:label="Gym Buddy"` as a literal (project has no strings.xml). `MaterialApp title` is already `'Gym Buddy'`. Notification channel names are already human-readable. No other user-visible hits.

## A3 Package
- `applicationId` was already `com.gymbuddy.app` (both build types inherit defaultConfig). `namespace` changed from `com.example.gym_buddy_app`.
- `MainActivity.kt` moved with `git mv` to `kotlin/com/gymbuddy/app/`, package line fixed. It is the only Kotlin/Java source (`GeneratedPluginRegistrant.java` is generated).
- `google-services.json` (gitignored) has client entries for both `com.example.gym_buddy_app` and `com.gymbuddy.app`. Nothing edited. The stale example entry is harmless.
- Package-id hits and action:
  - `build.gradle.kts` namespace: fixed.
  - `MainActivity.kt` package: fixed.
  - `docs/audits/audit-2026-09-29.md` (3 lines): historical audit text, left.
  - `ios/`, `macos/`, `windows/`, `linux/` (`com.example...` bundle ids and `gym_buddy_app` names): out of scope (Android only), left.
  - `web/` titles: left.
  - Channel ids (`gym_buddy_*`) are app-level strings, not tied to the package. No method channels, intent actions or FileProvider authorities exist. `supabase/functions` has no `com.example`.
- Intent filters, signing config and `key.properties` untouched.
- **Install consequence:** `applicationId` was already `com.gymbuddy.app`, so this prompt did not change the installed package id. Only `namespace` and the Kotlin package moved. The old `com.example` app (if still on the phone) is a separate app: uninstall it yourself. Installing over an existing `com.gymbuddy.app` build works only if it was signed with the same key; otherwise uninstall first and sign in again. **The Play package id is permanent after the first upload; this is the last moment to change it.**

## B1 Google button
`lib/signup_screen.dart`: removed `_GoogleButton`, `_GoogleLogo`, `_GooglePainter`, `_Divider` and the spacing around them. No Google button or text in `login_screen.dart`, onboarding files, or anywhere else in `lib/`.

## B2 Chat coming-soon: NEEDS-DECISION
Not an isolated button. `_openBuddyChat` (`lib/widgets/friends_page_modern.dart`, ~L1106) is the "coming soon" snackbar, reached from four places:
1. Buddy options sheet "Message / Open your chat" row (+ its divider), ~L474.
2. Tapping a buddy card, ~L836 (`onTap: _openChat`).
3. The search icon in the buddies header (~L616) opens `_SearchBuddiesPage`, whose purpose is "find a buddy and message them"; its rows call `_openBuddyChat` and show a chat icon (~L1353, L1391).
4. The `_openChat` wrapper (~L388).
Removing 1+2 only leaves a search page that still shows the snackbar; removing 3 removes a whole page and header icon, which is beyond "remove the chat action and nothing else". Tell me: remove all four (search page + header icon too), or only 1, 2 and the rows' tap/icon?

## B3 Best streak
Removed the second summary tile, its `SizedBox`, and `_bestStreak()`. The remaining "Checked in today" tile is a lone `Expanded` in a `Row`, so it now spans the full width. No layout change made beyond that; say if you want it narrower.

## B4 Placeholder unlock nodes
`kShowPlaceholderUnlockNodes = false` in `lib/pages/wardrobe/avatar_unlock_tree_screen.dart`. Gates: the two Social "Coming soon" nodes, the hardcoded Seasonal Creature node, the Social connectors, and the Special tier-2 connector. Node positions are fixed coordinates in a fixed-size canvas, so real nodes did not move and no pan/zoom bounds are affected. `isSocialPlaceholder` branches are kept (reachable when the flag is true).

## C Release build
`flutter build apk --release --obfuscate --split-debug-info=build/symbols` -> `app-release.apk` 66.0 MB. `build/symbols` produced (arm64, arm, x64). `build/` is gitignored (`/build/`). Doc: `docs/release_build.md`; CLAUDE.md pointer added.
- Build printed "ELF library contains unobfuscated DWARF debugging information ... use --strip". Not acted on (not asked); the symbols folder is still produced.
- Signing (apksigner): Verifies; v2 scheme true (v1 false, fine for minSdk 24+); signer CN=Daniels Zabello, O=Gym Buddy; SHA-256 `c4734c65...409f295`. This is the release keystore, not the Android debug cert.

## APK inspection (aapt2)
- `package: name='com.gymbuddy.app' versionCode='1' versionName='1.0.0'`
- `application-label:'Gym Buddy'`
- Manifest: `icon=@0x7f0c0000` (mipmap/ic_launcher), `roundIcon=@0x7f0c0004`.
- `mipmap/ic_launcher` has 5 PNG densities plus an anydpi-v26 XML (`res/BW.xml`, resource names are shortened by R8), whose tree has `background`, `foreground` and `monochrome`.
- `com.example` in the whole extracted APK: no hits.
- `gym_buddy_app`: only in the three `libapp.so` (Dart AOT snapshot: `package:gym_buddy_app/...` import URIs and a `.dart_tool` path), the legitimate Dart package name.

## Checks
- `flutter analyze` on the 3 touched files: no issues. `flutter test`: all 174 passed.
