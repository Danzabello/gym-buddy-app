Gym Buddy launcher icon set (Duo Ring)

1. Copy res/mipmap-* folders into android/app/src/main/res/ (merge, overwrite ic_launcher*.png).
2. mipmap-anydpi-v26/ic_launcher.xml is the adaptive icon (API 26+), with monochrome layer for Android 13 themed icons.
3. AndroidManifest already points to @mipmap/ic_launcher; add android:roundIcon="@mipmap/ic_launcher_round" if missing.
4. Play Console: upload playstore/ic_launcher_512.png as the app icon (512x512, 32-bit PNG).

Adaptive layers: 108dp canvas. Mark sits inside the 66dp safe zone. Disc is cropped by the launcher mask on purpose.
