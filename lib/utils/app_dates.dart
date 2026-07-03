/// Canonical date helpers for anything that becomes a server-side date key.
///
/// Per-user timezone rework (Option B): every `check_in_date` / `break_date` /
/// dedup-window "today" is the ACTING USER'S OWN local calendar date. For code
/// running on the user's device, the device's local date IS that date —
/// `user_profiles.timezone` is synced from this device on every launch
/// (timezone_sync.dart), and the server resolves the same frame via
/// `safe_user_tz()`.
///
/// Server-side actors (buddy-proxy check-ins, the Coach Max cron, the hourly
/// reconcile job) resolve a user's tz from `user_profiles.timezone` instead —
/// see safe_user_tz() in the migrations. Client and server therefore agree on
/// each user's day boundary as long as the stored tz is fresh, which the
/// every-launch sync guarantees up to the accepted travel-staleness window.
library;

/// Today's date on this device as `YYYY-MM-DD` — the signed-in user's own
/// local "today", matching the server's
/// `(now() AT TIME ZONE safe_user_tz(user))::date` for this user.
String localTodayString() {
  final now = DateTime.now();
  return DateTime(now.year, now.month, now.day)
      .toIso8601String()
      .split('T')[0];
}
