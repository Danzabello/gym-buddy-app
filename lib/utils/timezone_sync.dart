import 'package:flutter/foundation.dart';
import 'package:flutter_timezone/flutter_timezone.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:gym_buddy_app/utils/debug_logger.dart';

/// Reads the device's IANA timezone and stores it on the signed-in user's
/// profile (`user_profiles.timezone`).
///
/// This is what lets the server resolve each user's own local "today" for
/// check-in dating, streak-day completion, the reward-cap window, and the
/// Coach Max firing window (per-user timezone rework, Option B).
///
/// Best-effort and non-blocking: any failure is swallowed, and the DB trigger
/// coerces an unexpected value to the 'Europe/Dublin' fallback. Call it on
/// every launch and on login (people travel / swap devices), and once at the
/// end of onboarding for brand-new profiles.
///
/// [stored] is the zone already on the profile (from the launch read); when it
/// equals the device zone the write is skipped, since the update would fire
/// the validation trigger for nothing. Null (unknown) always writes.
/// [deviceZone] and [write] exist so tests can drive it.
Future<void> syncDeviceTimezone({
  String? stored,
  Future<String> Function()? deviceZone,
  Future<void> Function(String userId, String iana)? write,
  String? userId,
}) async {
  try {
    userId ??= Supabase.instance.client.auth.currentUser?.id;
    if (userId == null) return;

    final String iana;
    try {
      // flutter_timezone v5: getLocalTimezone() -> TimezoneInfo(.identifier)
      iana = deviceZone != null
          ? await deviceZone()
          : (await FlutterTimezone.getLocalTimezone()).identifier;
    } catch (e) {
      // Couldn't read the device zone — leave the last-known/stored value be
      // rather than clobbering it with a fallback.
      if (kDebugMode) debugLog('⚠️ Could not read device timezone: $e');
      return;
    }

    if (stored == iana) return;

    await (write ?? _writeTimezone)(userId, iana);

    if (kDebugMode) debugLog('🕒 Synced device timezone: $iana');
  } catch (e) {
    if (kDebugMode) debugLog('⚠️ Timezone sync failed: $e');
  }
}

Future<void> _writeTimezone(String userId, String iana) => Supabase.instance.client
    .from('user_profiles')
    .update({'timezone': iana})
    .eq('id', userId);
