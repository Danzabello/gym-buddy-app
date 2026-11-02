import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gym_buddy_app/pages/wardrobe/wardrobe_tile.dart';
import 'package:gym_buddy_app/theme/app_theme.dart';
import 'package:gym_buddy_app/widgets/coin_glyph.dart';

Widget host({Widget? leading, String caption = '50 in Shop', double width = 100}) =>
    MaterialApp(
      theme: AppTheme.fromAccent(AccentPalette.emeraldInk),
      home: Scaffold(
        body: Center(
          child: SizedBox(
            width: width,
            child: WardrobeTile(
              preview: const SizedBox(width: 44, height: 44),
              label: 'Gold',
              selected: false,
              locked: true,
              accentColor: Colors.amber,
              caption: caption,
              captionLeading: leading,
            ),
          ),
        ),
      ),
    );

void main() {
  testWidgets('without captionLeading the caption is plain text', (t) async {
    await t.pumpWidget(host());
    expect(find.text('50 in Shop'), findsOneWidget);
    expect(find.byType(CoinGlyph), findsNothing);
    expect(
      find.descendant(of: find.byType(WardrobeTile), matching: find.byType(Row)),
      findsNothing,
    );
  });

  testWidgets('with captionLeading the glyph sits left of the text', (t) async {
    await t.pumpWidget(host(leading: const CoinGlyph(size: 11)));
    expect(find.text('50 in Shop'), findsOneWidget);
    final glyph = t.getRect(find.byType(CoinGlyph));
    final text = t.getRect(find.text('50 in Shop'));
    expect(glyph.right + 3, closeTo(text.left, 0.01));
    expect(glyph.size, const Size.square(11));
  });

  testWidgets('the leading glyph does not change the tile height', (t) async {
    await t.pumpWidget(host());
    final plain = t.getSize(find.byType(WardrobeTile)).height;
    await t.pumpWidget(host(leading: const CoinGlyph(size: 11)));
    expect(t.getSize(find.byType(WardrobeTile)).height, plain);
  });

  testWidgets('a long caption still ellipsizes beside the glyph', (t) async {
    await t.pumpWidget(host(
      leading: const CoinGlyph(size: 11),
      caption: '1234567890 in Shop and a very long tail',
      width: 70,
    ));
    expect(t.takeException(), isNull);
    final tile = t.getRect(find.byType(WardrobeTile));
    expect(t.getRect(find.byType(CoinGlyph)).right, lessThanOrEqualTo(tile.right));
    expect(t.getRect(find.textContaining('Shop')).right, lessThanOrEqualTo(tile.right));
  });
}
