import 'package:flutter_test/flutter_test.dart';
import 'package:timezone/data/latest.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;
import 'package:gym_buddy_app/home_screen.dart';

// The danger countdown belongs to the buddy's day, not to UTC and not to the
// viewer's. These are the two zones the UTC version got most wrong.
void main() {
  setUpAll(tzdata.initializeTimeZones);

  tz.Location auckland() => tz.getLocation('Pacific/Auckland'); // +13 in Jan
  tz.Location losAngeles() => tz.getLocation('America/Los_Angeles'); // -8

  test('one instant, two correct local deadlines', () {
    // 05:30 UTC — the old UTC gate saw hour 5 and showed no card at all, while
    // both of these buddies were already inside their own evening.
    final instant = DateTime.utc(2026, 1, 15, 5, 30);

    // 18:30 on the 15th in Auckland: 5h30m to its midnight.
    expect(
      dangerRemainingAt(tz.TZDateTime.from(instant, auckland())),
      const Duration(hours: 5, minutes: 30),
    );
    // 21:30 on the 14th in Los Angeles: 2h30m to its midnight.
    expect(
      dangerRemainingAt(tz.TZDateTime.from(instant, losAngeles())),
      const Duration(hours: 2, minutes: 30),
    );
  });

  test('silent before the local cutoff', () {
    // 00:00 UTC: 13:00 in Auckland, 16:00 the previous day in Los Angeles —
    // afternoon in both, so neither is in danger yet.
    final instant = DateTime.utc(2026, 1, 15);
    expect(dangerRemainingAt(tz.TZDateTime.from(instant, auckland())), isNull);
    expect(dangerRemainingAt(tz.TZDateTime.from(instant, losAngeles())), isNull);
  });

  test('opens exactly at the local cutoff hour', () {
    final zone = auckland();
    expect(dangerRemainingAt(tz.TZDateTime(zone, 2026, 1, 15, 17, 59)), isNull);
    expect(
      dangerRemainingAt(tz.TZDateTime(zone, 2026, 1, 15, 18)),
      const Duration(hours: 6),
    );
  });
}
