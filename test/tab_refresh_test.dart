import 'package:flutter_test/flutter_test.dart';
import 'package:gym_buddy_app/services/dashboard_refresh.dart';
import 'package:timezone/data/latest.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

void main() {
  final now = DateTime(2026, 11, 17, 12);
  DateTime ago(int seconds) => now.subtract(Duration(seconds: seconds));

  setUp(() {
    for (final r in tabRefresh.values) {
      r
        ..lastLoaded = null
        ..stale = false
        ..dirty = false;
    }
    shownTab.value = null;
    profileZone = null;
  });

  test('never loaded: due; a load clears stale and dirty and is not due', () async {
    final r = tabRefresh[AppTab.friends]!;
    expect(r.due(now), isTrue);
    r
      ..stale = true
      ..dirty = true;
    expect(await r.track(() async => 7, now: ago(1)), 7);
    expect((r.lastLoaded, r.stale, r.dirty), (ago(1), false, false));
    expect(r.due(now), isFalse);
  });

  test('stale: due on the next show whatever the age', () {
    final r = tabRefresh[AppTab.shop]!..lastLoaded = ago(1);
    markStale({AppTab.shop});
    expect(r.due(now), isTrue);
    // Only the tabs named are marked.
    expect(tabRefresh[AppTab.profile]!.stale, isFalse);
  });

  test('dirty: due only once older than 2 minutes', () {
    final r = tabRefresh[AppTab.profile]!..lastLoaded = ago(120);
    markDirty({AppTab.profile});
    expect(r.due(now), isFalse);
    r.lastLoaded = ago(121);
    expect(r.due(now), isTrue);
    r.dirty = false;
    expect(r.due(now), isFalse);
  });

  test('resume: due only after more than 5 minutes away', () {
    final r = tabRefresh[AppTab.schedule]!..lastLoaded = ago(3600);
    expect(r.due(now, resumed: ago(300)), isFalse);
    expect(r.due(now, resumed: ago(301)), isTrue);
    r.dirty = true; // dirty does not count on a resume
    expect(r.due(now, resumed: ago(10)), isFalse);
  });

  test('a load that throws or fails is retried on the next show', () async {
    final r = tabRefresh[AppTab.friends]!;
    await expectLater(r.track(() async => throw StateError('offline'), now: ago(1)), throwsStateError);
    expect(r.lastLoaded, isNull);
    expect(r.due(now), isTrue);
    await r.track(() async {}, now: ago(1));
    r.failed();
    expect(r.due(now), isTrue);
  });

  test('a new day in the profile timezone makes a tab due', () {
    tzdata.initializeTimeZones();
    profileZone = tz.getLocation('Pacific/Auckland'); // UTC+13 in November
    final r = tabRefresh[AppTab.shop]!;
    // 10:30 and 11:30 UTC straddle midnight in Auckland.
    r.lastLoaded = DateTime.utc(2026, 11, 17, 10, 30);
    expect(r.due(DateTime.utc(2026, 11, 17, 10, 59)), isFalse);
    expect(r.due(DateTime.utc(2026, 11, 17, 11, 30)), isTrue);
  });

  test('dashboardStale reads and writes the dashboard entry only', () {
    expect(dashboardStale, isFalse);
    markStale({AppTab.dashboard});
    expect(dashboardStale, isTrue);
    dashboardStale = false;
    expect(tabRefresh[AppTab.dashboard]!.stale, isFalse);
    dashboardStale = true;
    expect(tabRefresh.entries.where((e) => e.value.stale).map((e) => e.key), [AppTab.dashboard]);
  });

  test('shown: every tab outside the shell, one tab inside it', () {
    expect(AppTab.values.every(isShown), isTrue);
    shownTab.value = AppTab.shop;
    expect(AppTab.values.where(isShown), [AppTab.shop]);
    expect(AppTab.values.map((t) => t.index), [0, 1, 2, 3, 4]);
  });
}
