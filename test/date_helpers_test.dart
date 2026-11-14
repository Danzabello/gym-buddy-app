import 'package:flutter_test/flutter_test.dart';
import 'package:gym_buddy_app/services/break_day_service.dart';
import 'package:gym_buddy_app/utils/app_dates.dart';
import 'package:gym_buddy_app/utils/workout_time.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

// Pins the client date helpers as they stood at the start of the client
// refactor (refactor/client-2026-11).
void main() {
  test('localTodayString is the device-local date as YYYY-MM-DD', () {
    final now = DateTime.now();
    final expected = '${now.year.toString().padLeft(4, '0')}-'
        '${now.month.toString().padLeft(2, '0')}-'
        '${now.day.toString().padLeft(2, '0')}';
    expect(localTodayString(), expected);
    expect(localTodayString(), matches(RegExp(r'^\d{4}-\d{2}-\d{2}$')));
  });

  group('BreakDayService.getWeekStart', () {
    // The client is never called: getWeekStart is pure date arithmetic.
    final service = BreakDayService(
      client: SupabaseClient('https://example.supabase.co', 'anon'),
    );

    test('every day of a week maps to its Monday', () {
      // 2026-11-09 is a Monday.
      for (var day = 9; day <= 15; day++) {
        expect(service.getWeekStart(DateTime(2026, 11, day)),
            DateTime(2026, 11, 9),
            reason: '2026-11-$day');
      }
      expect(service.getWeekStart(DateTime(2026, 11, 16)), DateTime(2026, 11, 16));
    });

    test('the time of day is dropped', () {
      expect(service.getWeekStart(DateTime(2026, 11, 9, 0, 0, 1)),
          DateTime(2026, 11, 9));
      expect(service.getWeekStart(DateTime(2026, 11, 15, 23, 59, 59)),
          DateTime(2026, 11, 9));
    });

    test('weeks cross month and year boundaries', () {
      expect(service.getWeekStart(DateTime(2026, 11, 1)), DateTime(2026, 10, 26));
      expect(service.getWeekStart(DateTime(2027, 1, 1)), DateTime(2026, 12, 28));
      expect(service.getWeekStart(DateTime(2024, 3, 3)), DateTime(2024, 2, 26));
    });
  });

  group('whenText', () {
    final now = DateTime(2026, 11, 14, 12, 0); // a Saturday

    test('today, tomorrow, then the weekday name', () {
      expect(whenText(DateTime(2026, 11, 14, 18, 0), now), 'Today 18:00');
      expect(whenText(DateTime(2026, 11, 15, 7, 30), now), 'Tomorrow 07:30');
      expect(whenText(DateTime(2026, 11, 16, 9, 5), now), 'Mon 09:05');
      expect(whenText(DateTime(2026, 11, 20, 0, 0), now), 'Fri 00:00');
    });

    test('a past day shows its weekday name', () {
      expect(whenText(DateTime(2026, 11, 13, 6, 0), now), 'Fri 06:00');
    });

    test('the day is counted by calendar date, not by 24 hours', () {
      final lateNow = DateTime(2026, 11, 14, 23, 59);
      expect(whenText(DateTime(2026, 11, 15, 0, 1), lateNow), 'Tomorrow 00:01');
    });
  });

  test('formatDuration shows minutes under an hour, then hours and minutes', () {
    expect(formatDuration(0), '0m');
    expect(formatDuration(15), '15m');
    expect(formatDuration(59), '59m');
    expect(formatDuration(60), '1h');
    expect(formatDuration(90), '1h 30m');
    expect(formatDuration(120), '2h');
    expect(formatDuration(185), '3h 5m');
  });

  group('startsInText', () {
    test('rounds up to the minute, at least one', () {
      expect(startsInText(Duration.zero), '1m');
      expect(startsInText(const Duration(seconds: -30)), '1m');
      expect(startsInText(const Duration(seconds: 1)), '1m');
      expect(startsInText(const Duration(seconds: 61)), '2m');
      expect(startsInText(const Duration(minutes: 14)), '14m');
      expect(startsInText(const Duration(minutes: 59, seconds: 1)), '1h 00m');
    });

    test('hours and padded minutes', () {
      expect(startsInText(const Duration(hours: 1)), '1h 00m');
      expect(startsInText(const Duration(hours: 2, minutes: 14)), '2h 14m');
      expect(startsInText(const Duration(hours: 25, minutes: 5)), '25h 05m');
    });
  });
}
