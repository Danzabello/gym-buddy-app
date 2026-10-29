import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gym_buddy_app/services/achievement_service.dart' show AchievementUnlockResult;
import 'package:gym_buddy_app/services/workout_history_service.dart';
import 'package:gym_buddy_app/theme/accent_theme_provider.dart';
import 'package:gym_buddy_app/theme/app_theme.dart';
import 'package:gym_buddy_app/widgets/workout_history_sheet.dart';
import 'package:gym_buddy_app/widgets/workout_selection_modal.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

int sheetPushes = 0;

class _SheetCounter extends NavigatorObserver {
  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) {
    if (route is ModalBottomSheetRoute) sheetPushes++;
  }
}

Future<void> _open(WidgetTester t, Future<void> Function(BuildContext) show) async {
  sheetPushes = 0;
  SharedPreferences.setMockInitialValues({});
  t.view.physicalSize = const Size(1080, 3000);
  t.view.devicePixelRatio = 2;
  addTearDown(t.view.reset);
  await t.pumpWidget(ChangeNotifierProvider(
    create: (_) => AccentThemeProvider(),
    child: MaterialApp(
      navigatorObservers: [_SheetCounter()],
      theme: ThemeData(extensions: [AppColors.fromAccent(AccentPalette.emeraldInk)]),
      home: Scaffold(body: Builder(builder: (c) => TextButton(onPressed: () => show(c), child: const Text('open')))),
    ),
  ));
  await t.tap(find.text('open'));
  await t.pump();
  await t.pump(const Duration(milliseconds: 400));
}

void main() {
  testWidgets('custom duration Start: a second tap during the close animation starts once', (t) async {
    final picked = <int>[];
    final template = WorkoutTemplate(
        id: 't1', name: 'Bench', category: 'strength', defaultDurationMinutes: 30, emoji: 'B', isSystemTemplate: true);
    await _open(t, (c) => showModalBottomSheet(
          context: c,
          isScrollControlled: true,
          builder: (_) => WorkoutSelectionModal(
            loadTemplates: () async => [template],
            onWorkoutSelected: (tpl, mins, notes, results) => picked.add(mins),
          ),
        ));
    await t.tap(find.text('Strength'));
    await t.pump();
    await t.tap(find.text('Bench'));
    await t.pump();
    await t.pump(const Duration(milliseconds: 400));

    // Two presses delivered before the next frame, as two quick taps can be.
    // (A real tap on a closing route is also swallowed by the framework, so
    // call the handler directly to test the latch itself.)
    final start = t.widget<ElevatedButton>(find.widgetWithText(ElevatedButton, 'Start Workout'));
    start.onPressed!();
    start.onPressed!();
    await t.pump(const Duration(milliseconds: 500));
    expect(picked, [30]);
  });

  testWidgets('history sheet Schedule: a second tap during the close animation opens one sheet', (t) async {
    await _open(t, (c) => WorkoutHistorySheet.show(c,
        buddyUserId: 'b1', buddyDisplayName: 'Sam', buddyAvatarId: 'lion'));
    expect(find.text('Schedule Workout'), findsOneWidget);

    final button = t.widget<ElevatedButton>(
        find.ancestor(of: find.text('Schedule Workout'), matching: find.byType(ElevatedButton)));
    button.onPressed!();
    button.onPressed!();
    await t.pump(const Duration(milliseconds: 500));
    // The history sheet itself plus exactly one Quick Schedule sheet.
    expect(sheetPushes, 2);
  });

  testWidgets("random Let's Go: two quick presses select one workout", (t) async {
    final picked = <int>[];
    var checks = 0;
    final template = WorkoutTemplate(
        id: 't1', name: 'Bench', category: 'strength', defaultDurationMinutes: 30, emoji: 'B', isSystemTemplate: true);
    await _open(t, (c) => showModalBottomSheet(
          context: c,
          isScrollControlled: true,
          builder: (_) => WorkoutSelectionModal(
            loadTemplates: () async => [template],
            checkFeelingLucky: () async { checks++; return <AchievementUnlockResult>[]; },
            onWorkoutSelected: (tpl, mins, notes, results) => picked.add(mins),
          ),
        ));
    await t.tap(find.text('Feeling Lucky?'));
    await t.pump();
    await t.pump(const Duration(milliseconds: 400));

    // Two presses before the next frame, as two quick taps can be. Calling the
    // handler directly tests the latch itself; a real tap on a closing route
    // is also swallowed by the framework.
    final go = t.widget<GestureDetector>(
        find.ancestor(of: find.text("Let's Go!"), matching: find.byType(GestureDetector)).first);
    go.onTap!();
    go.onTap!();
    await t.pump(const Duration(milliseconds: 500));
    expect(picked.length, 1);
    expect(checks, 1);
  });
}
