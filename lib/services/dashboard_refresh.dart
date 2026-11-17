/// When the kept-alive dashboard refetches its data. Owner decision
/// 2026-11-17; the choices are recorded in
/// dev/audits/dashboard_keepalive_decisions.md.
library;

/// Whether the dashboard should refetch now.
///
/// [lastLoaded] is when the last load started, or null when it never loaded
/// or a write made elsewhere left it stale ([dashboardStale]). [resumed] is
/// when the app went to the background, passed only on a resume; without it
/// this is a return from another tab. [dirty] is set by Realtime events and
/// finished check-ins since that load.
bool shouldRefresh({
  required DateTime? lastLoaded,
  required DateTime now,
  required bool dirty,
  DateTime? resumed,
}) {
  if (lastLoaded == null) return true;
  if (resumed != null) return now.difference(resumed) > const Duration(minutes: 5);
  return dirty && now.difference(lastLoaded) > const Duration(minutes: 2);
}

/// Set by a write made off the dashboard that changes what it shows: a
/// finished check-in or workout, a workout action, a buddy team made or
/// removed, an item equipped, an avatar or a nickname changed. The dashboard
/// refetches the next time it is shown; any dashboard load clears it.
bool dashboardStale = false;
