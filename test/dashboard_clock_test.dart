import 'dart:io';

import 'package:flutter/widgets.dart';
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

  // The dashboard itself cannot be pumped in a test (its State reads
  // Supabase.instance and opens a realtime channel), so these pump a stand-in
  // page built from the same ClockPart the dashboard uses: one part with no
  // `select`, like the danger countdown and the feed ages, and one with a
  // `select`, like the tray (coach tip, week day, status slot).
  group('clock parts', () {
    late DateTime now;
    late ValueNotifier<int> minute;
    late CoachTipRotation tips;
    late int pageBuilds, ageBuilds, tipBuilds;
    final checkedInAt = DateTime(2026, 11, 15, 14);

    int tipNow() => tips.indexAt(now, coachTips.length);
    String tipText(int i) => coachTips[i]['tip'] as String;

    void tick([Duration step = const Duration(minutes: 1)]) {
      now = now.add(step);
      minute.value++;
    }

    Widget page() => Directionality(
          textDirection: TextDirection.ltr,
          child: Builder(builder: (context) {
            pageBuilds++;
            return Column(children: [
              ClockPart(
                tick: minute,
                clock: () => now,
                builder: (_, now) {
                  ageBuilds++;
                  return Text('${now.difference(checkedInAt).inMinutes}m ago');
                },
              ),
              ClockPart(
                tick: minute,
                clock: () => now,
                select: (now) => tips.indexAt(now, coachTips.length),
                builder: (_, now) {
                  tipBuilds++;
                  return Text(tipText(tips.indexAt(now, coachTips.length)));
                },
              ),
            ]);
          }),
        );

    setUp(() {
      now = DateTime(2026, 11, 15, 14, 5);
      minute = ValueNotifier<int>(0);
      tips = CoachTipRotation();
      pageBuilds = ageBuilds = tipBuilds = 0;
    });

    testWidgets('a minute tick rebuilds the time value and not the page',
        (tester) async {
      await tester.pumpWidget(page());
      final tip = tipText(tipNow());
      expect(find.text('5m ago'), findsOneWidget);
      expect(find.text(tip), findsOneWidget);

      for (var i = 0; i < 30; i++) {
        tick();
        await tester.pump();
      }

      expect(pageBuilds, 1, reason: 'the page never rebuilds on a tick');
      expect(ageBuilds, 31, reason: 'the time value rebuilds on every tick');
      expect(find.text('35m ago'), findsOneWidget);
      expect(tipBuilds, 1, reason: 'the tip is not rebuilt inside its hour');
      expect(find.text(tip), findsOneWidget);
    });

    testWidgets('the tip part rebuilds only on a tick where the tip changed',
        (tester) async {
      await tester.pumpWidget(page());
      var shown = tipNow();
      var changes = 0;

      for (var hour = 0; hour < 24; hour++) {
        tick(const Duration(hours: 1));
        await tester.pump();
        if (tipNow() != shown) {
          shown = tipNow();
          changes++;
        }
        expect(tipBuilds, 1 + changes);
        expect(find.text(tipText(shown)), findsOneWidget);
      }

      expect(changes, greaterThan(12));
      expect(pageBuilds, 1);
    });

    testWidgets('only a resume from the background redraws the tip',
        (tester) async {
      await tester.pumpWidget(page());
      final before = tipNow();

      // The dashboard's resume handler: tell the rotation, then tick.
      tips.onResumed();
      minute.value++;
      await tester.pump();
      expect(tipBuilds, 1, reason: 'the app never left the screen');

      tips.onHidden();
      tips.onResumed();
      minute.value++;
      await tester.pump();
      // A redraw can land on the tip that was showing (1 in coachTips.length),
      // so this holds for any tip count: the part rebuilds exactly when the
      // draw differs. That the draw is a fresh one is pinned above, in
      // 'a resume from the background draws a fresh tip, once'.
      final fresh = tipNow();
      expect(tipBuilds, fresh == before ? 1 : 2);
      expect(find.text(tipText(fresh)), findsOneWidget);
      expect(pageBuilds, 1);
    });

    testWidgets('a rebuild from above reads the clock, and never moves the tip',
        (tester) async {
      await tester.pumpWidget(page());
      final tip = tipText(tipNow());

      for (var i = 1; i <= 20; i++) {
        now = now.add(const Duration(minutes: 1)); // no tick
        await tester.pumpWidget(page());
      }

      expect(pageBuilds, 21);
      expect(find.text('25m ago'), findsOneWidget);
      expect(find.text(tip), findsOneWidget);
    });

    testWidgets('a tick compares with what the part was built from',
        (tester) async {
      // Like the status slot: the selected value depends on the clock and on
      // which buddy is focused. A is in its danger window from the start, B
      // enters it at 14:07.
      bool inDanger(String buddy, DateTime now) =>
          buddy == 'A' || now.minute >= 7;
      var builds = 0;
      Widget slot(String buddy) => Directionality(
            textDirection: TextDirection.ltr,
            child: ClockPart(
              tick: minute,
              clock: () => now,
              select: (now) => inDanger(buddy, now),
              builder: (_, now) {
                builds++;
                return Text(inDanger(buddy, now) ? 'danger' : 'feed');
              },
            ),
          );

      await tester.pumpWidget(slot('A'));
      expect(find.text('danger'), findsOneWidget);

      await tester.pumpWidget(slot('B')); // the wheel moved to B, no tick
      expect(find.text('feed'), findsOneWidget);
      expect(builds, 2);

      tick(); // 14:06, B still outside
      await tester.pump();
      expect(builds, 2);

      tick(); // 14:07, B enters: same value A had at the last tick
      await tester.pump();
      expect(find.text('danger'), findsOneWidget);
      expect(builds, 3);
    });

    testWidgets('a removed part stops listening', (tester) async {
      await tester.pumpWidget(page());
      await tester.pumpWidget(const SizedBox());
      tick();
      await tester.pump();
      expect(ageBuilds, 1);
      expect(tester.takeException(), isNull);
    });
  });

  // The page's own wiring, read from the source because the page cannot be
  // pumped. A tripwire, not a proof: every line that names the tick must be
  // one of these four, so the minute timer only fires it and it is only ever
  // handed to the four ClockParts. A page-level listener on it fails here.
  // The timer also runs the midnight check, which never calls setState: it
  // only starts a load once the date has changed.
  test('the dashboard minute timer fires the tick and the midnight check only', () {
    final source = File('lib/home/dashboard_page.dart').readAsStringSync();
    final lines = source
        .split('\n')
        .where((l) => RegExp(r'\b_minute\b').hasMatch(l))
        .map((l) => l.trim())
        .toList();
    expect(lines.toSet(), {
      'final _minute = ValueNotifier<int>(0);',
      '_minute.value++;', // the minute timer and the resume handler
      '_minute.dispose();',
      'tick: _minute,',
    });
    expect(lines.where((l) => l == 'tick: _minute,').length, 4,
        reason: 'tray, standalone week card, danger card, feed age');
    expect(lines.where((l) => l == '_minute.value++;').length, 2);
    expect(lines.length, 8);

    final timer = RegExp(
        r'_countdownTimer = Timer\.periodic\(const Duration\(minutes: 1\), \(_\) \{\s*'
        r'_minute\.value\+\+;\s*_refreshIfNewDay\(\);\s*\}\);');
    expect(timer.hasMatch(source), isTrue);
    final start = source.indexOf('void _refreshIfNewDay() {');
    final body = source.substring(start, source.indexOf('\n  }', start));
    expect(body, isNot(contains('setState')));
    expect(body, contains('dayChanged('));
  });
}
