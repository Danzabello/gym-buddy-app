import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gym_buddy_app/home_screen.dart';
import 'package:gym_buddy_app/theme/app_theme.dart';

// The 99+ cap is shared by all four numeric displays on the profile page
// (three Lifetime Stats blocks + every category count row), so it is tested
// once here rather than per field. Three digits are reachable in normal play:
// Century Lifter is 100 workouts, Century Club is a 100-day streak.
//
// The reveal is a custom themed OverlayEntry (not the framework Tooltip), so
// dismissal is a deterministic tap rather than a timer — which is what makes
// the tap-away and no-timeout cases below testable at all.
//
// The bubble reads AppColors, and AppColors.of asserts the extension is
// present — so the host needs a real app theme, exactly as production does
// (the overlay always sits under MaterialApp's theme).
Widget _host(Widget child, {ThemeData? theme}) => MaterialApp(
      theme: theme ?? AppTheme.light,
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

  testWidgets('tapping outside dismisses the bubble immediately',
      (tester) async {
    await tester.pumpWidget(_host(const CappedCount(value: 142, style: _style)));

    await tester.tap(find.byType(CappedCount));
    await tester.pumpAndSettle();
    expect(find.text('142'), findsOneWidget);

    // Far corner, well away from both the value and the bubble.
    await tester.tapAt(const Offset(20, 20));
    await tester.pumpAndSettle();

    expect(find.text('142'), findsNothing);
    expect(find.text('99+'), findsOneWidget, reason: 'the value itself stays');
  });

  testWidgets('the bubble does NOT self-dismiss on a timer', (tester) async {
    // The old framework Tooltip vanished after 3s. This is the regression
    // guard for that behaviour being gone.
    await tester.pumpWidget(_host(const CappedCount(value: 142, style: _style)));

    await tester.tap(find.byType(CappedCount));
    await tester.pumpAndSettle();

    await tester.pump(const Duration(seconds: 10));
    expect(find.text('142'), findsOneWidget);

    // Clean up so the test does not end with a live overlay entry.
    await tester.tapAt(const Offset(20, 20));
    await tester.pumpAndSettle();
  });

  testWidgets('tapping the value again closes the bubble', (tester) async {
    await tester.pumpWidget(_host(const CappedCount(value: 142, style: _style)));

    final valueCentre = tester.getCenter(find.byType(CappedCount));

    await tester.tap(find.byType(CappedCount));
    await tester.pumpAndSettle();
    expect(find.text('142'), findsOneWidget);

    // Tapped by coordinate, not by finder: while the bubble is open the
    // full-screen catcher is above everything, so this tap lands on the
    // catcher rather than on the value's own GestureDetector. The bubble
    // closes either way, which is all the user cares about — but a
    // find.byType tap here would log a "hit test missed" warning and would be
    // asserting a path that touch input never actually takes.
    await tester.tapAt(valueCentre);
    await tester.pumpAndSettle();
    expect(find.text('142'), findsNothing);
  });

  testWidgets('99 and below render exactly, and reveal nothing on tap',
      (tester) async {
    await tester.pumpWidget(_host(const CappedCount(value: 99, style: _style)));

    expect(find.text('99'), findsOneWidget);
    expect(find.text('99+'), findsNothing);

    await tester.tap(find.byType(CappedCount));
    await tester.pumpAndSettle();

    // Still exactly one — the label itself, with no bubble added behind it.
    expect(find.text('99'), findsOneWidget);
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

  testWidgets('the bubble renders under an accent theme too', (tester) async {
    // Emerald Ink is what the device runs; fromAccent supplies a different
    // AppColors instance than AppTheme.light, so this covers the token lookup
    // on the palette the screenshots were taken against.
    await tester.pumpWidget(_host(
      const CappedCount(value: 142, style: _style),
      theme: AppTheme.fromAccent(AccentPalette.emeraldInk),
    ));

    await tester.tap(find.byType(CappedCount));
    await tester.pumpAndSettle();

    expect(find.text('142'), findsOneWidget);
    expect(tester.takeException(), isNull);

    await tester.tapAt(const Offset(20, 20));
    await tester.pumpAndSettle();
    expect(find.text('142'), findsNothing);
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
