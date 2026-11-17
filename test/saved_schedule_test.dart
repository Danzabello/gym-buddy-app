import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gym_buddy_app/pages/schedule_deps.dart';
import 'package:gym_buddy_app/pages/schedule_page.dart';
import 'package:gym_buddy_app/services/handshake_service.dart';
import 'package:gym_buddy_app/services/saved_copy.dart';
import 'package:gym_buddy_app/services/tab_refresh.dart';
import 'package:gym_buddy_app/theme/app_theme.dart';
import 'package:gym_buddy_app/widgets/workout_schedule_card.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _me = 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa';

Map<String, dynamic> _workout() {
  final planned = DateTime.now().toUtc().add(const Duration(hours: 2));
  return {
    'state': 'scheduled',
    'workout_id': 'w1',
    'workout_type': 'Strength',
    'i_am_creator': true,
    'planned_at': planned.toIso8601String(),
    'window_opens_at': planned.subtract(const Duration(minutes: 5)).toIso8601String(),
    'planned_duration_minutes': 45,
    'workout_started_at': null,
    'goal_at': null,
    'last_nudge_at': null,
    'other_person': {'id': 'u2', 'display_name': 'Alexandra', 'avatar_id': 'lion', 'ring_color': null},
  };
}

/// A page whose first refresh never ends, so what shows is the first paint.
ScheduleDeps _hangingDeps() => ScheduleDeps(
      svc: HandshakeService(rpc: (fn, p) => Completer<Map<String, dynamic>>().future),
      listen: (_) => () {},
      loadMe: () async => const Person(name: 'Me'),
      loadStreak: () async => 0,
      listIds: () => Completer<List<String>>().future,
      completed: (_) => const Text('Recent completed workouts'),
    );

Widget _app(Widget home) => MaterialApp(
      theme: ThemeData(extensions: [AppColors.fromAccent(AccentPalette.emeraldInk)]),
      home: home,
    );

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    SavedCopy.uidOverride = () => _me;
    shownTab.value = null;
  });
  tearDown(() => SavedCopy.uidOverride = null);

  testWidgets('with a saved copy the rows show before the first refresh ends', (t) async {
    await t.runAsync(() => SavedCopy.write(_me, 'schedule', {
          'head': WorkoutCardData(state: 'none', serverNow: DateTime.now().toUtc()).toSaved(),
          'rows': [_workout()],
        }));
    await t.pumpWidget(_app(SchedulePage(deps: _hangingDeps())));
    await t.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
    await t.pump();
    expect(find.byType(CircularProgressIndicator), findsNothing);
    expect(find.textContaining('Alexandra'), findsWidgets);
  });

  testWidgets('another user\'s saved copy is not shown', (t) async {
    await t.runAsync(() => SavedCopy.write('bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb', 'schedule', {
          'head': WorkoutCardData(state: 'none', serverNow: DateTime.now().toUtc()).toSaved(),
          'rows': [_workout()],
        }));
    await t.pumpWidget(_app(SchedulePage(deps: _hangingDeps())));
    await t.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
    await t.pump();
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    expect(find.textContaining('Alexandra'), findsNothing);
  });

  testWidgets('nothing saved: the spinner stays until the refresh ends', (t) async {
    await t.pumpWidget(_app(SchedulePage(deps: _hangingDeps())));
    await t.pump();
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
  });
}
