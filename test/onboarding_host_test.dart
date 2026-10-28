import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gym_buddy_app/onboarding/onboarding_host.dart';
import 'package:gym_buddy_app/onboarding/onboarding_max.dart';
import 'package:gym_buddy_app/theme/app_theme.dart';

Widget _app(Widget child) => MaterialApp(
      theme: AppTheme.fromAccent(AccentPalette.emeraldInk),
      home: Scaffold(body: child),
    );

void main() {
  testWidgets('step bar: 7 segments, filled up to the step, labelled',
      (tester) async {
    final handle = tester.ensureSemantics();
    await tester.pumpWidget(_app(const ObSegmentBar(step: 3)));
    await tester.pumpAndSettle();

    final fills = [
      for (var i = 1; i <= 7; i++)
        ((tester.widget<AnimatedContainer>(find.byKey(ValueKey('segment$i')))
                    .decoration as BoxDecoration)
                .color)
    ];
    expect(fills.length, 7);
    expect(fills.take(3).toSet().length, 1);
    expect(fills.skip(3).toSet().length, 1);
    expect(fills.first, isNot(fills.last));
    expect(find.bySemanticsLabel('Step 3 of 7'), findsOneWidget);
    handle.dispose();
  });

  test('Max anchor table: side and size per page', () {
    const sides = [
      MaxSide.left, MaxSide.right, MaxSide.left, MaxSide.right,
      MaxSide.left, MaxSide.right, MaxSide.left, MaxSide.centre,
    ];
    const sizes = [92.0, 64, 64, 64, 64, 64, 64, 156];
    for (var i = 0; i < kStepSpots.length; i++) {
      final stop = kMaxStops[kStepSpots[i]]!;
      expect(stop.side, sides[i], reason: 'page ${i + 1} side');
      expect(stop.size, sizes[i], reason: 'page ${i + 1} size');
    }
    expect(kMaxStops[MaxSpot.streakChip]!.size, 44);
    expect(maxTravel(0, 1), 1);
    expect(maxTravel(1, 0), -1);
    expect(maxTravel(6, 7), 1);
  });

  testWidgets('AI chip shows from 52dp up', (tester) async {
    await tester.pumpWidget(_app(const Row(children: [
      SizedBox.square(dimension: 64, child: CoachMaxBadge()),
      SizedBox.square(dimension: 44, child: CoachMaxBadge()),
    ])));
    expect(find.text('AI'), findsOneWidget);
  });
}
