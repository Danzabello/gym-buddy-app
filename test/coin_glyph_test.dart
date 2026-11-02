import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gym_buddy_app/theme/app_theme.dart';
import 'package:gym_buddy_app/widgets/coin_glyph.dart';

Widget host(Widget child) => MaterialApp(
  theme: AppTheme.fromAccent(AccentPalette.emeraldInk),
  home: Scaffold(body: Center(child: child)),
);

void main() {
  testWidgets('builds at every size with no overflow and no semantics', (
    tester,
  ) async {
    final handle = tester.ensureSemantics();
    for (final s in [13.0, 16.0, 20.0, 24.0, 32.0, 56.0]) {
      await tester.pumpWidget(
        host(Row(mainAxisSize: MainAxisSize.min, children: [CoinGlyph(size: s)])),
      );
      expect(tester.takeException(), isNull, reason: 'size $s');
      expect(tester.getSize(find.byType(CoinGlyph)), Size.square(s));
      final node = find.descendant(
        of: find.byType(CoinGlyph),
        matching: find.byType(Semantics),
      );
      // ExcludeSemantics is the only thing allowed inside; no labelled node.
      for (final e in node.evaluate()) {
        expect((e.widget as Semantics).properties.label, isNull);
      }
      expect(
        tester.getSemantics(find.byType(CoinGlyph)).label,
        isEmpty,
        reason: 'size $s',
      );
    }
    handle.dispose();
  });

  testWidgets('sizes up to 20 use the small face', (tester) async {
    for (final (s, small) in [(20.0, true), (21.0, false), (13.0, true)]) {
      await tester.pumpWidget(host(CoinGlyph(size: s)));
      final p = tester
          .widget<CustomPaint>(
            find.descendant(
              of: find.byType(CoinGlyph),
              matching: find.byType(CustomPaint),
            ),
          )
          .painter! as CoinGlyphPainter;
      expect(p.small, small, reason: 'size $s');
    }
  });

  test('painter repaints when warn changes', () {
    const a = CoinGlyphPainter(warn: Color(0xFFF59E0B), small: true);
    const b = CoinGlyphPainter(warn: Color(0xFFD97706), small: true);
    expect(b.shouldRepaint(a), isTrue);
    expect(a.shouldRepaint(const CoinGlyphPainter(warn: Color(0xFFF59E0B), small: true)), isFalse);
    expect(a.shouldRepaint(const CoinGlyphPainter(warn: Color(0xFFF59E0B), small: false)), isTrue);
  });

  test('flame path ends where the design says', () {
    final m = CoinGlyphPainter.flame().computeMetrics().toList();
    expect(m, hasLength(1));
    final b = CoinGlyphPainter.flame().getBounds();
    expect(b.top, closeTo(11.5, 0.01));
    expect(b.bottom, closeTo(34.1, 0.01)); // 26.8 + 7.3 at the arc's lowest point
    expect(b.right, closeTo(31.3, 0.1));
    expect(b.left, closeTo(16.7, 0.1));
    // The arc is the lower half of a circle centred (24, 26.8): its midpoint
    // is straight below the centre.
    final t = m.single;
    var found = false;
    for (var d = 0.0; d < t.length; d += 0.05) {
      final p = t.getTangentForOffset(d)!.position;
      if ((p.dx - 24).abs() < 0.05 && (p.dy - 34.1).abs() < 0.05) found = true;
    }
    expect(found, isTrue);
  });
}
