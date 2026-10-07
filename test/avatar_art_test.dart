import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gym_buddy_app/widgets/avatars/animated_bear.dart';
import 'package:gym_buddy_app/widgets/user_avatar.dart';

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

  testWidgets('UserAvatar: bear is art and still by default', (tester) async {
    await tester.pumpWidget(_wrap(const UserAvatar(avatarId: 'bear', size: 40)));
    expect(find.byType(AnimatedBear), findsOneWidget);
    expect(find.text('🐻'), findsNothing);
    expect(tester.binding.transientCallbackCount, 0);
  });

  testWidgets('UserAvatar: bear animates only when asked', (tester) async {
    await tester.pumpWidget(_wrap(
        const UserAvatar(avatarId: 'bear', size: 40, animated: true)));
    expect(tester.binding.transientCallbackCount, greaterThan(0));
  });

  testWidgets('UserAvatar: non-bear id still renders its emoji',
      (tester) async {
    await tester.pumpWidget(_wrap(const UserAvatar(avatarId: 'wolf')));
    expect(find.text('🐺'), findsOneWidget);
    expect(find.byType(AnimatedBear), findsNothing);
  });

  testWidgets('UserAvatar: empty semanticLabel hides the bear label',
      (tester) async {
    final handle = tester.ensureSemantics();
    await tester.pumpWidget(_wrap(
        const UserAvatar(avatarId: 'bear', semanticLabel: '')));
    expect(find.bySemanticsLabel('Bear avatar'), findsNothing);
    handle.dispose();
  });
}
