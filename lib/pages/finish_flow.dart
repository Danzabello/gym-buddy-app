import 'dart:async';

import 'package:flutter/material.dart';

import '../services/achievement_service.dart';
import '../services/handshake_service.dart';
import '../services/team_streak_service.dart';
import '../widgets/streak_complete_sheet.dart';
import '../widgets/workout_celebration.dart';

enum FinishResult { done, creditPending, failed }

/// The after-finish steps, so a test can swap them for fakes.
class FinishHooks {
  final Future<Map<String, dynamic>> Function(Map<String, dynamic> finishResult) apply;
  final void Function(String type, int minutes) achievements;
  final Future<void> Function(BuildContext, String type, int minutes, String? buddy) celebrate;
  final Future<void> Function(BuildContext) streakSheet;
  const FinishHooks({
    required this.apply, required this.achievements, required this.celebrate, required this.streakSheet});

  static final live = FinishHooks(
    apply: TeamStreakService().applyFinishResult,
    achievements: (type, minutes) => unawaited(
        AchievementService().checkWorkoutAchievements(durationMinutes: minutes, workoutType: type)),
    celebrate: (c, type, minutes, buddy) =>
        WorkoutCelebration.show(c, workoutType: type, duration: minutes, buddyName: buddy),
    streakSheet: StreakCompleteSheet.show,
  );
}

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
  FinishHooks? hooks,
}) async {
  final messenger = ScaffoldMessenger.of(context);
  void toast(String t) => messenger.showSnackBar(SnackBar(content: Text(t)));
  try {
    final res = await svc.finish(id, minutes, alreadyCompleted: completed);
    final h = hooks ?? FinishHooks.live;
    final r = await h.apply(res);
    if ((r['teams_updated'] as int? ?? 0) > 0) h.achievements(type, minutes);
    // Celebration, then the streak sheet, each until dismissed: the caller
    // only moves on (e.g. closes the page) after this returns.
    if (!completed && context.mounted) await h.celebrate(context, type, minutes, name);
    if (r['partner_bonus_earned'] == true && context.mounted) await h.streakSheet(context);
    return FinishResult.done;
  } on CreditPending {
    toast('Workout saved, but your streak credit did not go through.');
    return FinishResult.creditPending;
  } catch (e) {
    toast(HandshakeError.from(e).message(name: name));
    return FinishResult.failed;
  }
}
