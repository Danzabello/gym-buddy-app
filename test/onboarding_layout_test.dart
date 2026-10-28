import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gym_buddy_app/onboarding/onboarding_host.dart';
import 'package:gym_buddy_app/theme/app_theme.dart';

void main() {
  // Small phone, large text: the content area must scroll, its last widget
  // must scroll fully clear, and the pinned button must sit below the
  // scroll area rather than over it.
  testWidgets(
    'steps 1 to 6 scroll clear of the pinned button at text scale 1.3',
    (tester) async {
      tester.view.physicalSize = const Size(1080, 1920);
      tester.view.devicePixelRatio = 3;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.fromAccent(AccentPalette.emeraldInk),
          builder: (c, w) => MediaQuery(
            data: MediaQuery.of(c).copyWith(
              disableAnimations: true,
              textScaler: const TextScaler.linear(1.3),
            ),
            child: w!,
          ),
          home: const OnboardingHost(),
        ),
      );
      final host = tester.state<OnboardingHostState>(
        find.byType(OnboardingHost),
      );

      for (var i = 0; i < 6; i++) {
        if (i > 0) host.go(i);
        await tester.pump(const Duration(milliseconds: 600));
        await tester.pump(const Duration(milliseconds: 600));

        final scroll = find.byType(SingleChildScrollView);
        expect(scroll, findsOneWidget, reason: 'page ${i + 1} scrolls');
        final viewport = tester.getRect(scroll);
        final position = tester
            .state<ScrollableState>(
              find
                  .descendant(of: scroll, matching: find.byType(Scrollable))
                  .first,
            )
            .position;
        position.jumpTo(position.maxScrollExtent);
        await tester.pump();

        final content = tester.getRect(
          find.descendant(of: scroll, matching: find.byType(Column)).first,
        );
        expect(
          content.bottom,
          lessThanOrEqualTo(viewport.bottom - 16 + 0.5),
          reason:
              'page ${i + 1}: last widget scrolls clear of the viewport edge',
        );

        final buttons = find.byType(ElevatedButton);
        if (i > 0) {
          final pinned = tester.getRect(buttons.last);
          expect(
            viewport.bottom,
            lessThanOrEqualTo(pinned.top),
            reason: 'page ${i + 1}: scroll area ends above the pinned button',
          );
          expect(pinned.bottom, lessThanOrEqualTo(1920 / 3 + 0.5));
        }
      }
    },
  );
}
