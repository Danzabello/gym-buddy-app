import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gym_buddy_app/services/workout_service.dart';
import 'package:gym_buddy_app/theme/accent_theme_provider.dart';
import 'package:gym_buddy_app/theme/app_theme.dart';
import 'package:gym_buddy_app/widgets/quick_schedule_sheet.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

WorkoutService svc(List<Map<String, dynamic>> rows, {Object? fail}) => WorkoutService(
      userId: () => 'me',
      insert: (r) async {
        if (fail != null) throw fail;
        rows.add(r);
      },
    );

Future<String?> create(WorkoutService s, {String? buddy}) => s.createWorkout(
    workoutType: 'Strength', date: DateTime(2026, 10, 12), time: '10:00:00',
    buddyId: buddy, buddyName: buddy == null ? null : 'Sam');

void main() {
  // The server (already_in_workout at I'm here, overlap on accept) owns the
  // one-at-a-time rule; creating never looks at running workouts.
  test('creating succeeds with no client-side busy check, solo or with a buddy', () async {
    final rows = <Map<String, dynamic>>[];
    expect(await create(svc(rows)), isNull);
    expect(await create(svc(rows), buddy: 'b1'), isNull);
    expect(rows.length, 2);
    expect(rows.last['buddy_status'], 'pending');
  });

  test('every failure is a plain sentence, never a code or "Error:"', () async {
    final raw = RegExp(r'[A-Z]+_[A-Z]+|Error:|_');
    final cases = <Object, String>{
      const PostgrestException(message: 'invite_cap_reached'):
          'Sam has too many invites waiting. Try again later.',
      const PostgrestException(message: 'daily_workout_limit_reached'):
          'You have reached the workout limit for today.',
      const PostgrestException(message: 'something_new_and_odd'): 'Something went wrong. Try again.',
      Exception('socket closed'): 'Something went wrong. Try again.',
    };
    for (final e in cases.entries) {
      final got = await create(svc([], fail: e.key), buddy: 'b1');
      expect(got, e.value);
      expect(raw.hasMatch(got!), isFalse, reason: got);
    }
    expect(await WorkoutService(userId: () => null).createWorkout(
        workoutType: 'Strength', date: DateTime(2026), time: '10:00:00'), 'Please sign in again.');
  });

  Future<void> pumpSheet(WidgetTester t, WorkoutService s) async {
    SharedPreferences.setMockInitialValues({});
    t.view.physicalSize = const Size(1080, 3000);
    t.view.devicePixelRatio = 2;
    addTearDown(t.view.reset);
    await t.pumpWidget(ChangeNotifierProvider(
      create: (_) => AccentThemeProvider(),
      child: MaterialApp(
        theme: ThemeData(extensions: [AppColors.fromAccent(AccentPalette.emeraldInk)]),
        home: Scaffold(
          body: QuickScheduleSheet(buddyUserId: 'b1', buddyDisplayName: 'Sam', workoutService: s),
        ),
      ),
    ));
    await t.pump();
  }

  testWidgets('the sheet shows the friendly cap sentence and no raw code', (t) async {
    await pumpSheet(t, svc([], fail: const PostgrestException(message: 'invite_cap_reached')));
    await t.tap(find.byType(ElevatedButton).last);
    await t.pump();
    await t.pump(const Duration(milliseconds: 300));
    expect(find.text('Sam has too many invites waiting. Try again later.'), findsOneWidget);
    expect(find.textContaining('Error'), findsNothing);
    expect(find.textContaining('invite_cap_reached'), findsNothing);
  });

  testWidgets('the sheet creates while a workout is running and says so plainly', (t) async {
    final rows = <Map<String, dynamic>>[];
    await pumpSheet(t, svc(rows));
    await t.tap(find.byType(ElevatedButton).last);
    await t.pump();
    await t.pump(const Duration(milliseconds: 300));
    expect(rows.length, 1);
    expect(find.textContaining('IN_WORKOUT'), findsNothing);
    expect(find.textContaining('Error'), findsNothing);
  });
}
