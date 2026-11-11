# H2 findings (listed, not fixed unless stated)

- Launcher icon is still the stock Flutter logo (no icon asset exists in the project; Play Store blocker). Only brand-style image: assets/animations/branding/streak_flame_static_fallback.png (an animation fallback, not an icon).
- Handshake notifications get Android's SILENT flag after the first few (probably the system's auto-bundling or cooldown); not confirmed to mute sound or vibration.
- send-notification dedupe is check-then-insert: two simultaneous identical pushes can both pass. Manually changing workouts.last_nudge_at also fires a nudge push (trigger), so backdating it in tests sends a push.
- MessagingStyle left avatar rejected: the avatar shrinks to an inline icon, the title doubles ("name: name"), the system folds it into the bundle and drops the large icon. Grouping every push as a child with a summary was also tried and reverted: a lone child renders like a normal notification (avatar on the right) and Android hides its summary. A real left avatar needs a native conversation shortcut (Kotlin).
- Fixed in this work: flutter_local_notifications cancel() threw "Missing type parameter" in release builds (R8); ProGuard keep rules added in android/app/proguard-rules.pro.
- Force-stopped app: FCM accepts the message but nothing is delivered, now or after reopening (unchanged behaviour).
- The app reopens the active workout's timer sheet when returning to the Dashboard (existing behaviour; appeared right after a push tap).
- A freshly installed build is "stopped" and signed out until launched and signed in; no pushes reach it until then.
- time_to_start skips anyone who already tapped and the whole workout if either person is out.
- Kind-colour raw hex lives in one const map (kindColors) in notification_service.dart, owner-approved.
