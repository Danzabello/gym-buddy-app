import 'package:flutter_test/flutter_test.dart';
import 'package:gym_buddy_app/services/dashboard_refresh.dart';
import 'package:gym_buddy_app/utils/app_dates.dart';
import 'package:timezone/data/latest.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

void main() {
  final now = DateTime(2026, 11, 17, 12);
  DateTime ago(int seconds) => now.subtract(Duration(seconds: seconds));

  test('never loaded or stale: always refresh', () {
    expect(shouldRefresh(lastLoaded: null, now: now, dirty: false), isTrue);
    expect(shouldRefresh(lastLoaded: null, now: now, dirty: false, resumed: ago(1)), isTrue);
  });

  test('tab return: only when dirty and older than 2 minutes', () {
    expect(shouldRefresh(lastLoaded: ago(121), now: now, dirty: true), isTrue);
    expect(shouldRefresh(lastLoaded: ago(120), now: now, dirty: true), isFalse);
    expect(shouldRefresh(lastLoaded: ago(3600), now: now, dirty: false), isFalse);
    expect(shouldRefresh(lastLoaded: ago(5), now: now, dirty: true), isFalse);
  });

  test('resume: only after more than 5 minutes in the background', () {
    expect(shouldRefresh(lastLoaded: ago(3600), now: now, dirty: false, resumed: ago(301)), isTrue);
    expect(shouldRefresh(lastLoaded: ago(3600), now: now, dirty: true, resumed: ago(300)), isFalse);
    // Old data but a short trip to another app: no refresh.
    expect(shouldRefresh(lastLoaded: ago(3600), now: now, dirty: false, resumed: ago(10)), isFalse);
  });

  test('fresh and clean: no refresh', () {
    expect(shouldRefresh(lastLoaded: ago(1), now: now, dirty: false), isFalse);
  });

  group('midnight rollover', () {
    setUpAll(tzdata.initializeTimeZones);
    late tz.Location dublin;
    setUp(() => dublin = tz.getLocation('Europe/Dublin'));
    DateTime at(int day, int h, int m, [int s = 0]) =>
        tz.TZDateTime(dublin, 2026, 11, day, h, m, s);

    test('same day: no refresh', () {
      expect(shouldRefresh(lastLoaded: at(17, 0, 1), now: at(17, 23, 59), dirty: false, zone: dublin), isFalse);
    });

    test('date changed: refresh, even clean and only minutes old', () {
      expect(shouldRefresh(lastLoaded: at(17, 23, 58), now: at(18, 0, 1), dirty: false, zone: dublin), isTrue);
    });

    test('date changed while hidden: the next show refreshes', () {
      // The tab-return call (no resumed): clean data, 30 s old.
      expect(shouldRefresh(lastLoaded: at(17, 23, 59, 45), now: at(18, 0, 0, 15), dirty: false, zone: dublin), isTrue);
    });

    test('date changed at a resume after 10 seconds away: refresh', () {
      expect(
          shouldRefresh(
              lastLoaded: at(17, 23, 50), now: at(18, 0, 0, 5), dirty: false, resumed: at(17, 23, 59, 55), zone: dublin),
          isTrue);
    });

    test('the profile timezone decides, not the device', () {
      final auckland = tz.getLocation('Pacific/Auckland'); // UTC+13 in November
      final loaded = DateTime.utc(2026, 11, 17, 10, 30); // 23:30 on the 17th in Auckland
      final now = DateTime.utc(2026, 11, 17, 11, 30); // 00:30 on the 18th in Auckland
      expect(shouldRefresh(lastLoaded: loaded, now: now, dirty: false, zone: auckland), isTrue);
      // Same two instants in Dublin (UTC+0): one day, no refresh.
      expect(shouldRefresh(lastLoaded: loaded, now: now, dirty: false, zone: dublin), isFalse);
    });

    test('the boundary is exactly 00:00:00 local', () {
      final lastMs = at(17, 23, 59, 59).add(const Duration(milliseconds: 999));
      expect(dayChanged(lastMs, at(18, 0, 0), zone: dublin), isTrue);
      expect(dayChanged(at(18, 0, 0), at(18, 0, 0, 30), zone: dublin), isFalse);
      // No profile zone: the device's own calendar (the localTodayString frame).
      expect(dayChanged(DateTime(2026, 11, 17, 23, 59, 59), DateTime(2026, 11, 18)), isTrue);
      expect(dayChanged(DateTime(2026, 11, 18), DateTime(2026, 11, 18, 0, 0, 1)), isFalse);
    });

    test('localTodayString still reads this device', () {
      expect(localTodayString(), localDateString(DateTime.now()));
    });
  });
}
