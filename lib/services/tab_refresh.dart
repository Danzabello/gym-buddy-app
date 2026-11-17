/// Per-tab refresh state for the kept-alive home tabs. Owner decision
/// 2026-11-17; the choices are recorded in
/// dev/audits/tabs_keepalive_decisions.md (the dashboard's in
/// dev/audits/dashboard_keepalive_decisions.md).
library;

import 'package:flutter/foundation.dart';
import 'package:timezone/timezone.dart' as tz;

import 'dashboard_refresh.dart';

/// The home tabs, in page order: the index is the shell's PageView page.
enum AppTab { schedule, friends, dashboard, shop, profile }

/// The tab on screen, written by the home shell. Null outside the shell (a
/// widget test that pumps one page), and then every tab counts as shown.
final ValueNotifier<AppTab?> shownTab = ValueNotifier(null);

bool isShown(AppTab tab) => shownTab.value == null || shownTab.value == tab;

/// The user's profile timezone (user_profiles.timezone), which decides when
/// a new day starts. The dashboard publishes it from the read its load
/// already makes; null until then or when unset, and then the device's
/// calendar is used.
tz.Location? profileZone;

/// When one tab last loaded and whether something it shows has changed.
/// The dashboard keeps its own load time and dirty flag; only its stale flag
/// lives here ([dashboardStale]).
class TabRefresh {
  /// When the last load started; null when it never loaded or it failed.
  DateTime? lastLoaded;

  /// A write made elsewhere changed what this tab shows: refetch on its next
  /// show, whatever the data's age.
  bool stale = false;

  /// Something may have changed (another person's action, a coin credit):
  /// refetch on a show once the data is also more than 2 minutes old.
  bool dirty = false;

  /// Whether to refetch now ([shouldRefresh]). [resumed] is when the app
  /// went to the background, passed only on a resume.
  bool due(DateTime now, {DateTime? resumed}) => shouldRefresh(
        lastLoaded: stale ? null : lastLoaded,
        now: now,
        dirty: dirty,
        resumed: resumed,
        zone: profileZone,
      );

  /// Runs a load: stamps it as started and clears stale and dirty, then
  /// forgets the stamp if the load throws, so the next show retries.
  Future<T> track<T>(Future<T> Function() load, {DateTime? now}) async {
    lastLoaded = now ?? DateTime.now();
    stale = false;
    dirty = false;
    try {
      return await load();
    } catch (_) {
      lastLoaded = null;
      rethrow;
    }
  }

  /// A load that swallowed its error (or came back empty where data must
  /// exist): retry on the next show.
  void failed() => lastLoaded = null;
}

final Map<AppTab, TabRefresh> tabRefresh = {
  for (final t in AppTab.values) t: TabRefresh(),
};

/// After a successful write made off these tabs that changes what they show.
void markStale(Set<AppTab> tabs) {
  for (final t in tabs) {
    tabRefresh[t]!.stale = true;
  }
}

/// After a signal that what these tabs show may have changed.
void markDirty(Set<AppTab> tabs) {
  for (final t in tabs) {
    tabRefresh[t]!.dirty = true;
  }
}

/// Set by a write made off the dashboard that changes what it shows (see
/// [markStale] callers); the dashboard refetches the next time it is shown,
/// and any dashboard load clears it.
bool get dashboardStale => tabRefresh[AppTab.dashboard]!.stale;
set dashboardStale(bool value) => tabRefresh[AppTab.dashboard]!.stale = value;
