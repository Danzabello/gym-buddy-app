// Guards the two AI-disclosure tags. These are the only thing separating
// Coach Max from a real buddy in the UI, so the checks that matter are:
// the letters actually render, and the corner badge's border falls back
// sanely when no AppColors extension is in scope (onboarding/gradient use).

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:gym_buddy_app/widgets/ai_disclosure_tag.dart';

Widget _host(Widget child) => MaterialApp(home: Scaffold(body: Center(child: child)));

void main() {
  testWidgets('both tags render the letters AI', (tester) async {
    await tester.pumpWidget(_host(
      const Column(
        mainAxisSize: MainAxisSize.min,
        children: [AiCornerBadge(), AiInlinePill()],
      ),
    ));

    expect(find.text('AI'), findsNWidgets(2));
  });

  testWidgets('corner badge survives a theme with no AppColors extension',
      (tester) async {
    await tester.pumpWidget(_host(const AiCornerBadge()));

    expect(tester.takeException(), isNull);
    final box = tester.widget<Container>(
      find.ancestor(of: find.text('AI'), matching: find.byType(Container)).first,
    );
    expect((box.decoration as BoxDecoration).border, isNotNull);
  });

  testWidgets('explicit borderColor wins over the fallback', (tester) async {
    await tester.pumpWidget(_host(
      const AiCornerBadge(borderColor: Color(0xFF123456)),
    ));

    final box = tester.widget<Container>(
      find.ancestor(of: find.text('AI'), matching: find.byType(Container)).first,
    );
    final border = (box.decoration as BoxDecoration).border as Border;
    expect(border.top.color, const Color(0xFF123456));
  });

  testWidgets('scale shrinks the type but keeps it legible', (tester) async {
    await tester.pumpWidget(_host(const AiInlinePill(scale: 0.9)));

    final text = tester.widget<Text>(find.text('AI'));
    expect(text.style!.fontSize, closeTo(8.1, 0.001));
    expect(text.style!.fontSize, greaterThanOrEqualTo(8.0));
  });
}
