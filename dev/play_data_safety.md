# Play Data Safety: draft answers for Gym Buddy

Draft for the Play Console form. It is based on what the code, the edge functions and the migrations do (checked 2026-11-11, branch `privacy-pass`),
and for Firebase products on Firebase's own guidance: https://firebase.google.com/docs/android/play-data-disclosure. Nothing here is legal advice and
nothing was checked against the live database.

Play URLs to enter:

- Privacy policy: `https://danzabello.github.io/gym-buddy-app/privacy-policy.html`
- Account deletion page: `https://danzabello.github.io/gym-buddy-app/delete-account.html`
- In-app deletion: Profile, Account, Delete Account (typed DELETE).

How to read the table. **Collected** means the app or our backend receives it. **Shared** uses Play's meaning, a transfer to a third party. Firebase says it
does not transfer the data below to third parties except sub-processors that help provide Firebase services; Supabase is our own back end. Other users
seeing your profile inside the app is not sharing in Play's sense. **Optional** means the user can use the app without providing it.
"Unsure" rows are listed again at the end.

## Data types

| Data type (Play category) | Collected | Shared | Purpose | Optional | Encrypted in transit | User can ask for deletion | Notes |
|---|---|---|---|---|---|---|---|
| Email address (Personal info) | Yes | No | Account management, App functionality | No, needed to sign in | Yes | Yes | The address typed at sign-up, or the one on the Google account. |
| Name (Personal info) | Yes | No | App functionality, Account management | No | Yes | Yes | The display name the user types. For Google sign-in, Supabase also stores the name Google puts in the token; the app never reads it. |
| User IDs (Personal info) | Yes | No | App functionality, Account management | No | Yes | Yes | Account id, username, and for Google sign-in the Google account id stored by Supabase. |
| Age (Personal info, "Other info") | Yes | No | App functionality (the 16 and over check) | No | Yes | Yes | Play category unsure. Never visible to other users. |
| Google profile picture web address (Photos, unsure) | Yes, Google sign-in only | No | None: stored with the sign-in account and not used | Yes, only with Google sign-in | Yes | Yes, deleted with the account | A web address, not a stored photo. The app never reads it. Unsure how Play classifies it. |
| Fitness info (Health and fitness) | Yes | No | App functionality | No | Yes | Yes | Workouts (type, date, planned and actual duration), check-ins, streaks, break days. No weight, heart rate, calories, sleep or other measurements. |
| App interactions (App activity) | Yes | No | App functionality | No | Yes | Yes | XP, level, coins, cosmetics, achievements, friend and buddy actions, nudges. |
| Other user-generated content (App activity) | Yes | No | App functionality | Yes | Yes | Yes | Optional workout notes, up to 500 characters. |
| Other in-app messages (Messages) | Yes | No | App functionality | No | Yes | Yes | The text of each notification, kept in the app's inbox for 7 days, then deleted. Unsure Play counts this as messages. |
| Device or other IDs: push token (FCM) | Yes | No | App functionality | Yes, only if notifications are allowed | Yes | Yes | Removed at log-out and at account deletion. Firebase: FCM also collects the app version for topic subscription, and a Firebase user agent that is never linked to a user or device identifier. |
| Device or other IDs: Crashlytics installation id | Yes | No | Crash reporting (see note) | No | Yes | No | Firebase: a Crashlytics installation UUID used to measure how many users a crash affects. Not linked to the account. |
| Crash logs (App info and performance) | Yes | No | Crash reporting (see note) | No | Yes | No | Firebase, automatic: stack traces and relevant application state when the app crashes. Not linked to the account by the app. |
| Diagnostics (App info and performance) | Yes | No | Crash reporting (see note) | No | Yes | No | Firebase, automatic: point-in-time device metadata (model, OS version) when the app crashes. |
| IP address, invite links only | Yes, by our server when someone opens an invite link in a browser (not by the app) | No | Fraud prevention, security and compliance | No | Yes | Deleted automatically 10 to 11 minutes after the request | Needs the purge job in `20261111200000_purge_invite_lookup_attempts.sql` to be applied. Play category unsure, closest is Device or other IDs. |

Crash reporting purpose: Firebase states the purpose as "to enable crash reporting and crash management services" and does not name a Play purpose label.
Choose in the Console between App functionality and Analytics; either is defensible for crash diagnostics.

## Not collected

| Data type | Answer | Why |
|---|---|---|
| Approximate or precise location | No | No location permission in the built manifest. The phone's timezone name (for example Europe/Dublin) is stored for streak days; it is not a position. Unsure whether you want to treat the timezone name as approximate location; the policy states it as a timezone. |
| Contacts, calendar | No | No permission, no code. |
| Photos and videos from the device, audio, files | No | No camera, microphone or storage permission. Avatars are preset images shipped in the app. |
| Financial info, purchases | No | Coins are virtual and earned in the app. There is no billing library. |
| Web browsing, search history | No | None. |
| Health info beyond fitness activity | No | None. |
| Advertising ID | Not used | No AD_ID permission in the built manifest, no ads, no analytics SDK. |

## Firebase and Google products

- **Crashlytics.** Automatic (not optional): stack traces, relevant application state, device metadata, installation UUID. Depends on use: custom keys, logs and
  free-text user ids that a developer attaches. The app attaches none (no custom keys, logs or user id are set anywhere in `lib/`). It records two kinds of
  error: uncaught Flutter and async errors, and one named non-fatal ("startup read timed out: <name>", which carries no personal text). An error's own message
  can carry an identifier, such as an account id or username in a failed request; this is why the policy says so.
- **Firebase Cloud Messaging.** Delivery is the purpose. Per Firebase: app version for topic subscription; the Firebase user agent is never linked to a user or
  device identifier. No BigQuery export and no Google Analytics are in the app, so Firebase's "depends on usage" items for those do not apply. What our server
  sends in each push is in the policy, section 3 (including the sender's account id on nudges).
- **Google Sign-In.** The app uses `google_sign_in` (Credential Manager) and passes only the ID token to Supabase. It is not Firebase Authentication, so the
  Firebase Authentication rows (IP addresses, user agent, Firebase user id) do not apply. What the app receives through Supabase is the email, name,
  picture address and Google account id, covered by the rows above. Google's own processing as the identity provider is Google's.
- **Google Play install referrer.** Read once per install; only an exact invite code is kept, on the device, until used or onboarding finishes.

## Security practices

| Question | Answer | Basis |
|---|---|---|
| Data encrypted in transit | Yes | HTTPS only; cleartext traffic is off in `network_security_config.xml`; Firebase encrypts the data on its list in transit using HTTPS. |
| Users can request data deletion | Yes | In the app, and by email through the deletion page; within 30 days. |
| Committed to the Play Families Policy | No | The app is for ages 16 and over. |
| Independent security review | No | Not claimed. |

## To confirm in the Console

1. Play category for age, the Google picture address, the invite-link IP address, and the in-app notification text.
2. Purpose label for crash data: App functionality or Analytics.
3. Whether the timezone name should count as approximate location (this draft says no).
4. That transfers to Firebase and Supabase as service providers are not "sharing" under the current Play wording.
5. Re-check this table whenever an SDK is added (the built manifest was checked on a release build of the `google-signin` branch).
