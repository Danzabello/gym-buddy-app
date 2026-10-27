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
