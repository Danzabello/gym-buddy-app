import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gym_buddy_app/home_screen.dart';

// The 99+ cap is shared by all four numeric displays on the profile page
// (three Lifetime Stats blocks + every category count row), so it is tested
// once here rather than per field. Three digits are reachable in normal play:
// Century Lifter is 100 workouts, Century Club is a 100-day streak.
Widget _host(Widget child) => MaterialApp(
      home: Scaffold(body: Center(child: child)),
    );

const _style = TextStyle(fontSize: 24, fontWeight: FontWeight.w800);

void main() {
  testWidgets('a stat value of 142 caps to 99+ and reveals 142 on tap',
      (tester) async {
    await tester.pumpWidget(_host(const CappedCount(value: 142, style: _style)));

    expect(find.text('99+'), findsOneWidget);
    expect(find.text('142'), findsNothing);

    await tester.tap(find.byType(CappedCount));
    await tester.pumpAndSettle();

    expect(find.text('142'), findsOneWidget);
  });

  testWidgets('a category count of 108 caps to 99+ and reveals 108 on tap',
      (tester) async {
    await tester.pumpWidget(_host(const CappedCount(value: 108, style: _style)));

    expect(find.text('99+'), findsOneWidget);
    expect(find.text('108'), findsNothing);

    await tester.tap(find.byType(CappedCount));
    await tester.pumpAndSettle();

    expect(find.text('108'), findsOneWidget);
  });

  testWidgets('99 and below render exactly, with no tooltip', (tester) async {
    await tester.pumpWidget(_host(const CappedCount(value: 99, style: _style)));

    expect(find.text('99'), findsOneWidget);
    expect(find.text('99+'), findsNothing);
    expect(find.byType(Tooltip), findsNothing);
  });

  testWidgets('the tap target clears 44x44 whether or not the value is capped',
      (tester) async {
    // Reserved for every value, not just capped ones — otherwise a card with
    // one capped and one uncapped stat would render them at different heights.
    for (final value in [7, 99, 142]) {
      await tester
          .pumpWidget(_host(CappedCount(value: value, style: _style)));
      final size = tester.getSize(find.byType(CappedCount));
      expect(size.width, greaterThanOrEqualTo(44.0),
          reason: 'width too small for value $value');
      expect(size.height, greaterThanOrEqualTo(44.0),
          reason: 'height too small for value $value');
    }
  });

  testWidgets('the capped label is underlined as a tappability cue',
      (tester) async {
    await tester.pumpWidget(_host(const CappedCount(value: 142, style: _style)));

    final capped = tester.widget<Text>(find.text('99+'));
    expect(capped.style?.decoration, TextDecoration.underline);
    expect(capped.style?.decorationStyle, TextDecorationStyle.dotted);

    await tester.pumpWidget(_host(const CappedCount(value: 42, style: _style)));
    final plain = tester.widget<Text>(find.text('42'));
    expect(plain.style?.decoration, isNot(TextDecoration.underline));
  });
}
