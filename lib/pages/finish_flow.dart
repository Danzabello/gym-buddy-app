import 'dart:async';

import 'package:flutter/material.dart';

import '../services/achievement_service.dart';
import '../services/handshake_service.dart';
import '../services/team_streak_service.dart';
import '../widgets/streak_complete_sheet.dart';
import '../widgets/workout_celebration.dart';

enum FinishResult { done, creditPending, failed }

/// complete_workout, then finish_checkin_session, then the old after-check-in
/// follow-ups (achievements, milestones, celebration, streak sheet). With
/// [completed] only the credit call is repeated (a cut-short earlier finish).
Future<FinishResult> finishWorkout(
  BuildContext context,
  HandshakeService svc, {
  required String id,
  required int minutes,
  bool completed = false,
  String type = 'Workout',
  String? name,
}) async {
  final messenger = ScaffoldMessenger.of(context);
  void toast(String t) => messenger.showSnackBar(SnackBar(content: Text(t)));
  try {
    final res = await svc.finish(id, minutes, alreadyCompleted: completed);
    final r = await TeamStreakService().applyFinishResult(res);
    if ((r['teams_updated'] as int? ?? 0) > 0) {
      unawaited(AchievementService()
          .checkWorkoutAchievements(durationMinutes: minutes, workoutType: type));
    }
    if (!context.mounted) return FinishResult.done;
    if (!completed) {
      WorkoutCelebration.show(context, workoutType: type, duration: minutes, buddyName: name);
    }
    if (r['partner_bonus_earned'] == true) {
      await Future.delayed(const Duration(milliseconds: 400));
      if (context.mounted) await StreakCompleteSheet.show(context);
    }
    return FinishResult.done;
  } on CreditPending {
    toast('Workout saved, but your streak credit did not go through.');
    return FinishResult.creditPending;
  } catch (e) {
    toast(HandshakeError.from(e).message(name: name));
    return FinishResult.failed;
  }
}
