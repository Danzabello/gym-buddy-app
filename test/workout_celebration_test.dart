import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gym_buddy_app/widgets/workout_celebration.dart';

void main() {
  testWidgets('isShowing follows show and hide', (tester) async {
    late BuildContext ctx;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (c) {
            ctx = c;
            return const Scaffold();
          },
        ),
      ),
    );
    expect(WorkoutCelebration.isShowing, isFalse);
    final done = WorkoutCelebration.show(ctx, workoutType: 'Cardio');
    await tester.pump();
    expect(WorkoutCelebration.isShowing, isTrue);
    WorkoutCelebration.hide();
    expect(WorkoutCelebration.isShowing, isFalse);
    await done;
    // Let the 4 s auto-dismiss timer and the confetti timers run out.
    await tester.pump(const Duration(seconds: 5));
    expect(WorkoutCelebration.isShowing, isFalse);
  });
}
