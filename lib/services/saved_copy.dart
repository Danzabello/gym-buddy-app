/// The saved copy of what a screen last showed, so the next open paints it at
/// once and refreshes behind it. Plan: dev/audits/cache_first_plan.md.
///
/// It only fills the first paint. Reading it is not a load: callers must not
/// touch `TabRefresh.lastLoaded`, so the first show still refetches.
///
/// One entry per data class under `sc1:<userId>:<class>`, each holding the
/// schema version, its owner, when it was saved and the local date and zone
/// it was saved on. Anything wrong with an entry (other owner, other version,
/// too old, saved on an earlier day when [read] asks for the same day,
/// corrupt) reads as "nothing saved" and the entry is deleted. No tokens,
/// secrets or emails go in the payloads.
library;

import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:timezone/data/latest.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

import '../utils/app_dates.dart';
import '../utils/crash_report.dart';
import 'dashboard_refresh.dart' show dayChanged;

/// Longest a class may be shown from the saved copy (owner decision
/// 2026-11-17). Classes that carry "today" also pass `sameDay` to [SavedCopy.read].
const kSavedMaxAgeFriends = Duration(days: 3);
const kSavedMaxAgeShop = Duration(days: 7);
const kSavedMaxAgeProfile = Duration(days: 7);
const kSavedMaxAgeSchedule = Duration(hours: 12);
const kSavedMaxAgeDashboard = Duration(days: 3);

/// Whether an auth event must wipe the saved copy: an explicit sign-out, or a
/// sign-in as someone other than the saved owner. Never a token refresh, the
/// initial session, a user update, or an error from a failed refresh.
@visibleForTesting
bool savedCopyShouldWipe(AuthChangeEvent event, String? eventUserId, String? owner) =>
    event == AuthChangeEvent.signedOut ||
    (event == AuthChangeEvent.signedIn &&
        eventUserId != null &&
        owner != null &&
        eventUserId != owner);

/// Waits for a first refresh, at most [limit], then goes on whether it ended,
/// failed or is still running: the server decides what the tap does. [delay]
/// is the timer, so a test can pass its own.
Future<void> awaitConfirmed(
  Future<void>? pending, {
  Duration limit = const Duration(seconds: 3),
  Future<void> Function(Duration)? delay,
}) async {
  if (pending == null) return;
  final done = Completer<void>();
  void finish() {
    if (!done.isCompleted) done.complete();
  }

  // The timer is cancelled when the refresh ends first, so none is left over.
  final timer = delay == null ? Timer(limit, finish) : null;
  delay?.call(limit).then((_) => finish(), onError: (_) => finish());
  pending.then((_) => finish(), onError: (_) => finish());
  await done.future;
  timer?.cancel();
}

class SavedCopy {
  static const prefix = 'sc1:';
  static const ownerKey = 'sc1:owner';
  static const version = 1;
  static const maxEntryChars = 256 * 1024;
  static const maxTotalChars = 512 * 1024;

  static String _key(String uid, String cls) => '$prefix$uid:$cls';

  /// A test's stand-in for the signed-in user.
  @visibleForTesting
  static String? Function()? uidOverride;

  /// The signed-in user's id, read when called; null when signed out.
  static String? get uid {
    if (uidOverride != null) return uidOverride!();
    try {
      return Supabase.instance.client.auth.currentUser?.id;
    } catch (_) {
      return null; // no Supabase client (a widget test)
    }
  }

  /// Wipes on a sign-out or a change of user, once at start and then on auth
  /// events. Call after Supabase.initialize.
  static void start() {
    unawaited(_wipeIfOtherUser(uid));
    unawaited(_removeLegacy());
    Supabase.instance.client.auth.onAuthStateChange.listen((state) async {
      try {
        final prefs = await SharedPreferences.getInstance();
        if (savedCopyShouldWipe(state.event, state.session?.user.id, prefs.getString(ownerKey))) {
          await wipe();
        }
      } catch (_) {}
    }, onError: (_) {}); // a failed refresh arrives as an error: it wipes nothing
  }

  /// The dashboard's old cache key, shared by every account: gone for good.
  static Future<void> _removeLegacy() async {
    try {
      await (await SharedPreferences.getInstance()).remove('dashboard_cache');
    } catch (_) {}
  }

  static Future<void> _wipeIfOtherUser(String? currentUid) async {
    try {
      final owner = (await SharedPreferences.getInstance()).getString(ownerKey);
      if (currentUid != null && owner != null && owner != currentUid) await wipe();
    } catch (_) {}
  }

  /// Deletes every saved entry and the owner mark; other keys stay.
  static Future<void> wipe() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      for (final k in prefs.getKeys().where((k) => k.startsWith(prefix)).toList()) {
        await prefs.remove(k);
      }
    } catch (_) {}
  }

  static bool _tzReady = false;
  static tz.Location? _zone(String? name) {
    if (name == null) return null;
    try {
      if (!_tzReady) {
        tzdata.initializeTimeZones();
        _tzReady = true;
      }
      return tz.getLocation(name);
    } catch (_) {
      return null; // unknown zone: the device calendar decides the day
    }
  }

  /// The saved payload of [cls] for [uid], run through [parse], or null when
  /// nothing usable is saved. [sameDay]: only if no local midnight (in the
  /// zone it was saved with) has passed since. [parse] throwing means
  /// corrupt: the entry is deleted.
  static Future<T?> read<T>(
    String? uid,
    String cls, {
    required Duration maxAge,
    required T Function(Object data) parse,
    bool sameDay = false,
    DateTime? now,
  }) async {
    if (uid == null) return null;
    final key = _key(uid, cls);
    SharedPreferences? prefs;
    try {
      prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(key);
      if (raw == null) return null;
      final m = jsonDecode(raw) as Map<String, dynamic>;
      final t = now ?? DateTime.now();
      final saved = DateTime.fromMillisecondsSinceEpoch(m['savedAt'] as int, isUtc: true);
      final ok = m['v'] == version &&
          m['owner'] == uid &&
          !saved.isAfter(t.toUtc()) && // the clock moved back
          t.toUtc().difference(saved) <= maxAge &&
          (!sameDay || !dayChanged(saved, t, zone: _zone(m['zone'] as String?)));
      if (!ok) {
        await prefs.remove(key);
        return null;
      }
      return parse(m['data'] as Object);
    } catch (e, st) {
      reportNonFatal(e, st, 'saved_copy_corrupt');
      try {
        await prefs?.remove(key);
      } catch (_) {}
      return null;
    }
  }

  /// Saves [payload] (JSON-encodable server rows) as [cls] for [uid]. Skipped
  /// over the size cap: half a list is worse than none. Never throws.
  static Future<void> write(
    String? uid,
    String cls,
    Object payload, {
    tz.Location? zone,
    DateTime? now,
  }) async {
    if (uid == null) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      if (prefs.getString(ownerKey) != uid) {
        await wipe(); // another user's copy never survives into this one
        await prefs.setString(ownerKey, uid);
      }
      final t = now ?? DateTime.now();
      final raw = jsonEncode({
        'v': version,
        'owner': uid,
        'savedAt': t.toUtc().millisecondsSinceEpoch,
        'date': localDateString(t, zone: zone),
        'zone': zone?.name,
        'data': payload,
      });
      final key = _key(uid, cls);
      if (raw.length > maxEntryChars) return;
      var total = raw.length;
      for (final k in prefs.getKeys()) {
        if (k.startsWith(prefix) && k != key && k != ownerKey) {
          total += prefs.getString(k)?.length ?? 0;
        }
      }
      if (total > maxTotalChars) return;
      await prefs.setString(key, raw);
    } catch (_) {}
  }

  /// The user id the saved copy belongs to, or null when nothing is saved.
  static Future<String?> owner() async {
    try {
      return (await SharedPreferences.getInstance()).getString(ownerKey);
    } catch (_) {
      return null;
    }
  }

  /// Whether [uid] was saved as having finished onboarding (written only
  /// after a definite complete answer). It is rewritten on every such launch,
  /// so the 90 days only lapse for an account that is not used.
  static Future<bool> onboarded(String? uid) async =>
      await read<bool>(uid, 'onboarded',
          maxAge: const Duration(days: 90), parse: (d) => (d as Map)['onboarded'] == true) ??
      false;

  static Future<void> saveOnboarded(String? uid) =>
      write(uid, 'onboarded', {'onboarded': true});

  /// Deletes one class (for example after a list-changing write).
  static Future<void> drop(String? uid, String cls) async {
    if (uid == null) return;
    try {
      await (await SharedPreferences.getInstance()).remove(_key(uid, cls));
    } catch (_) {}
  }
}
