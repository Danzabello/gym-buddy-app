import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gym_buddy_app/onboarding/onboarding_host.dart';
import 'package:gym_buddy_app/onboarding/onboarding_value_props.dart';
import 'package:gym_buddy_app/theme/app_theme.dart';

Future<void> _pump(WidgetTester tester) async {
  tester.view.physicalSize = const Size(1080, 2340);
  tester.view.devicePixelRatio = 3;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(MaterialApp(
    theme: AppTheme.fromAccent(AccentPalette.emeraldInk),
    builder: (c, w) => MediaQuery(
      data: MediaQuery.of(c).copyWith(disableAnimations: true),
      child: w!,
    ),
    home: const OnboardingValueProps(),
  ));
  await tester.pumpAndSettle();
}

/// Icon card, title and body rects of the slide showing [icon] and [title].
List<Rect> _layout(WidgetTester tester, IconData icon, String title) {
  final card = find
      .ancestor(of: find.byIcon(icon), matching: find.byType(Container))
      .first;
  final titleRect = tester.getRect(find.text(title));
  final body = find.byWidgetPredicate((w) =>
      w is Text && w.style?.fontSize == 15 && w.textAlign == TextAlign.center);
  return [tester.getRect(card), titleRect, tester.getRect(body)];
}

const _body1 =
    'Pair up with a friend and build a streak together, one workout at a time.';
const _body2 =
    'No premium tiers. Every ring, border and skin is unlocked by playing, not paying.';
const _body3 =
    'Pick a real buddy or team up with Coach Max while you wait — either way, someone is checking in with you.';

void main() {
  testWidgets('slide 1 has no search and no Skip, only Continue', (tester) async {
    await _pump(tester);
    expect(find.text('Find your buddy'), findsOneWidget);
    expect(find.text(_body1), findsOneWidget);
    expect(find.byIcon(Icons.local_fire_department), findsOneWidget);
    expect(find.text('Continue'), findsOneWidget);
    expect(find.text('Find my friends'), findsNothing);
    expect(find.text('Skip for now'), findsNothing);
    expect(find.byType(TextField), findsNothing);
    expect(find.byIcon(Icons.search), findsNothing);
    expect(find.byType(OutlinedButton), findsNothing);
  });

  testWidgets('Continue walks slides 1 to 3, which keep their content',
      (tester) async {
    await _pump(tester);
    final s1 = _layout(tester, Icons.local_fire_department, 'Find your buddy');

    await tester.tap(find.text('Continue'));
    await tester.pumpAndSettle();
    expect(find.text('Earn cosmetics, not paywalls'), findsOneWidget);
    expect(find.text(_body2), findsOneWidget);
    expect(find.byIcon(Icons.palette), findsOneWidget);
    expect(find.text('Continue'), findsOneWidget);
    final s2 = _layout(tester, Icons.palette, 'Earn cosmetics, not paywalls');

    // Slide 1 now uses slide 2's layout: 40 from the card to the title, 12
    // to the body (the card's y differs only because the bodies differ in
    // length and the group is centred).
    for (final s in [s1, s2]) {
      expect(s[1].top - s[0].bottom, 40);
      expect(s[2].top - s[1].bottom, 12);
    }
    expect(s1[0].left, s2[0].left);

    await tester.tap(find.text('Continue'));
    await tester.pumpAndSettle();
    expect(find.text('Never train alone'), findsOneWidget);
    expect(find.text(_body3), findsOneWidget);
    expect(find.byIcon(Icons.handshake), findsOneWidget);

    await tester.tap(find.text('Get started'));
    await tester.pumpAndSettle();
    expect(find.byType(OnboardingHost), findsOneWidget);
  });

  testWidgets('dots and swiping still move between slides', (tester) async {
    await _pump(tester);
    await tester.tap(find.byType(AnimatedContainer).at(2));
    await tester.pumpAndSettle();
    expect(find.text('Never train alone'), findsOneWidget);

    await tester.tap(find.byType(AnimatedContainer).at(0));
    await tester.pumpAndSettle();
    expect(find.text('Find your buddy'), findsOneWidget);

    await tester.fling(find.byType(PageView), const Offset(-300, 0), 1000);
    await tester.pumpAndSettle();
    expect(find.text('Earn cosmetics, not paywalls'), findsOneWidget);
  });
}
