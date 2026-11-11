# Release build

```bash
flutter build apk --release --obfuscate --split-debug-info=build/symbols
```

Signs with the release keystore from `android/key.properties`. R8 minify and
resource shrinking are already on in `android/app/build.gradle.kts`.

**Warning:** `build/symbols` is needed to de-obfuscate crash stack traces
(`flutter symbolize`). `build/` is gitignored, so the symbols are never in the
repo. Archive the folder outside the repo for every build that ships, labelled
with the version. Losing it makes that release's crashes unreadable.

## Crashlytics symbols (owner runs this per release)

Native (R8) mappings upload automatically at build time via the Gradle plugin.
The Dart symbols from `--split-debug-info` do not, so after every shipped build:

```bash
firebase crashlytics:symbols:upload --app=<mobilesdk_app_id> build/symbols
```

`<mobilesdk_app_id>` is in `android/app/google-services.json`. Do this before
the build reaches users, then archive the same `build/symbols` folder outside
the repo as above. Collection is off in debug builds.
