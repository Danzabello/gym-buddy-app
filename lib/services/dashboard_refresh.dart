/// When the kept-alive dashboard refetches its data. Owner decision
/// 2026-11-17; the choices are recorded in
/// dev/audits/dashboard_keepalive_decisions.md.
library;

import 'package:timezone/timezone.dart' as tz;

import '../utils/app_dates.dart';

export 'tab_refresh.dart';

/// Whether the dashboard should refetch now.
///
/// [lastLoaded] is when the last load started, or null when it never loaded
/// or a write made elsewhere left it stale ([dashboardStale]). [resumed] is
/// when the app went to the background, passed only on a resume; without it
/// this is a return from another tab. [dirty] is set by Realtime events and
/// finished check-ins since that load. [zone] is the user's profile timezone
/// (null: this device), which decides when a new day starts ([dayChanged]).
bool shouldRefresh({
  required DateTime? lastLoaded,
  required DateTime now,
  required bool dirty,
  DateTime? resumed,
  tz.Location? zone,
}) {
  if (lastLoaded == null) return true;
  if (dayChanged(lastLoaded, now, zone: zone)) return true;
  if (resumed != null) return now.difference(resumed) > const Duration(minutes: 5);
  return dirty && now.difference(lastLoaded) > const Duration(minutes: 2);
}

/// Whether local midnight in [zone] (null: this device) passed between
/// [lastLoaded] and [now]: the dashboard's "today" state is then out of date.
bool dayChanged(DateTime lastLoaded, DateTime now, {tz.Location? zone}) =>
    localDateString(lastLoaded, zone: zone) != localDateString(now, zone: zone);
