import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gym_buddy_app/widgets/avatars/animated_bear.dart';

Widget _wrap(Widget child) =>
    MaterialApp(home: Scaffold(body: Center(child: child)));

void main() {
  testWidgets('still bear runs no ticker', (tester) async {
    await tester.pumpWidget(_wrap(const AnimatedBear(size: 40, animate: false)));
    expect(tester.binding.transientCallbackCount, 0);
  });

  testWidgets('animated bear ticks, and stops when animate flips off',
      (tester) async {
    await tester.pumpWidget(_wrap(const AnimatedBear(size: 40)));
    expect(tester.binding.transientCallbackCount, greaterThan(0));
    await tester.pumpWidget(_wrap(const AnimatedBear(size: 40, animate: false)));
    expect(tester.binding.transientCallbackCount, 0);
  });
}
