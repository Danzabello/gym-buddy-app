import 'package:flutter_test/flutter_test.dart';
import 'package:gym_buddy_app/data/coach_tips.dart';
import 'package:gym_buddy_app/home/dashboard_clock.dart';

// Large enough that two independent draws landing on the same index would be
// a real defect and not chance. The draws are deterministic either way.
const _many = 1 << 30;

void main() {
  group('hour bucket', () {
    test('every moment of one wall-clock hour shares a bucket', () {
      final start = hourBucketOf(DateTime(2026, 11, 15, 14));
      expect(hourBucketOf(DateTime(2026, 11, 15, 14, 30)), start);
      expect(hourBucketOf(DateTime(2026, 11, 15, 14, 59, 59, 999)), start);
    });

    test('the next hour is the next bucket', () {
      expect(
        hourBucketOf(DateTime(2026, 11, 15, 15)),
        hourBucketOf(DateTime(2026, 11, 15, 14, 59, 59, 999)) + 1,
      );
    });
  });

  group('coach tip pick', () {
    test('the same hour and seed give the same tip across many calls', () {
      final first = pickCoachTip(hourBucket: 500000, seed: 0, count: 50);
      for (var i = 0; i < 1000; i++) {
        expect(pickCoachTip(hourBucket: 500000, seed: 0, count: 50), first);
      }
    });

    test('the pick is always a valid index, for any tip count', () {
      for (var count = 1; count <= 60; count++) {
        for (var hour = 0; hour < 200; hour++) {
          final i = pickCoachTip(hourBucket: 490000 + hour, seed: 3, count: count);
          expect(i, inInclusiveRange(0, count - 1));
        }
      }
    });

    test('the next hour may change the tip', () {
      final day = {
        for (var h = 0; h < 24; h++)
          pickCoachTip(hourBucket: 500000 + h, seed: 0, count: coachTips.length),
      };
      expect(day.length, greaterThan(12), reason: 'a day shows many tips');
    });

    test('a new seed draws again inside the same hour', () {
      expect(
        pickCoachTip(hourBucket: 500000, seed: 1, count: _many),
        isNot(pickCoachTip(hourBucket: 500000, seed: 0, count: _many)),
      );
    });
  });

  group('coach tip rotation', () {
    final two = DateTime(2026, 11, 15, 14, 5);

    test('the tip does not depend on how often it is read', () {
      final tips = CoachTipRotation();
      final first = tips.indexAt(two, _many);
      for (var rebuild = 0; rebuild < 1000; rebuild++) {
        // A rebuild reads the clock again, a little later in the same hour.
        final now = two.add(Duration(milliseconds: rebuild * 3000));
        expect(tips.indexAt(now, _many), first);
      }
    });

    test('a resume that never left the screen keeps the tip', () {
      final tips = CoachTipRotation();
      final before = tips.indexAt(two, _many);
      tips.onResumed(); // inactive -> resumed: a shade or a permission dialog
      tips.onResumed();
      expect(tips.indexAt(two, _many), before);
    });

    test('a resume from the background draws a fresh tip, once', () {
      final tips = CoachTipRotation();
      final before = tips.indexAt(two, _many);

      tips.onHidden();
      expect(tips.indexAt(two, _many), before, reason: 'hiding alone changes nothing');

      tips.onResumed();
      final fresh = tips.indexAt(two, _many);
      expect(fresh, isNot(before));

      tips.onResumed(); // a second resume with no new background trip
      expect(tips.indexAt(two, _many), fresh);
    });

    test('a resume in a later hour changes the tip without a background trip', () {
      final tips = CoachTipRotation();
      final before = tips.indexAt(two, _many);
      tips.onResumed();
      expect(tips.indexAt(two.add(const Duration(hours: 1)), _many), isNot(before));
    });
  });
}
