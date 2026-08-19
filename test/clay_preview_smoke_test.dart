// Throwaway companion to lib/screens/home_screen_clay_preview.dart.
// Delete both together. Catches render/overflow errors the device launch
// can't reach, because the preview sits behind auth.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gym_buddy_app/theme/app_theme.dart';
import 'package:gym_buddy_app/screens/home_screen_clay_preview.dart';

void main() {
  testWidgets('clay preview renders on all three accents, no overflow',
      (tester) async {
    tester.view.physicalSize = const Size(1080, 2400); // Pixel 7a
    tester.view.devicePixelRatio = 2.625;
    addTearDown(tester.view.reset);

    for (final accent in AccentTheme.values) {
      await tester.pumpWidget(MaterialApp(
        theme: AppTheme.fromAccent(AccentPalette.forTheme(accent)),
        home: const HomeScreenClayPreview(),
      ));
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull, reason: 'accent: ${accent.name}');
      expect(find.text('INVITE A BUDDY TO WORKOUT'), findsOneWidget);
      expect(find.text('0 DAY STREAK'), findsOneWidget);
      expect(find.text('Coach Max'), findsWidgets);
      // Friends-only picker: the current user must never appear here.
      expect(find.textContaining('YOU'), findsNothing);
    }
  });

  testWidgets('star badge toggles', (tester) async {
    await tester.pumpWidget(MaterialApp(
      theme: AppTheme.fromAccent(AccentPalette.emeraldInk),
      home: const HomeScreenClayPreview(),
    ));
    await tester.pumpAndSettle();

    expect(find.byIcon(Icons.star_border_rounded), findsOneWidget);
    await tester.tap(find.byIcon(Icons.star_border_rounded));
    await tester.pumpAndSettle();
    expect(find.byIcon(Icons.star_rounded), findsOneWidget);
  });
}
