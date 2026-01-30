import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'join_workout_popup.dart';
import '../services/workout_service.dart';

/// Service that checks for workouts waiting for the creator to join
/// Call this when the app opens or when returning to the home screen
class WorkoutJoinChecker {
  static final WorkoutService _workoutService = WorkoutService();
  static final SupabaseClient _supabase = Supabase.instance.client;

  /// Check if there are any workouts waiting for the creator to join
  /// Shows popup for the first one that hasn't been shown yet
  static Future<void> checkForPendingJoins(BuildContext context) async {
    try {
      // Check if popups are enabled in settings
      final popupsEnabled = await _arePopupsEnabled();
      if (!popupsEnabled) {
        if (kDebugMode) print('ℹ️ Workout join popups disabled in settings');
        return;
      }

      // Get workouts awaiting creator join
      final awaitingWorkouts = await _workoutService.getWorkoutsAwaitingCreatorJoin();
      
      if (awaitingWorkouts.isEmpty) {
        if (kDebugMode) print('✅ No workouts awaiting join');
        return;
      }

      if (kDebugMode) print('📋 Found ${awaitingWorkouts.length} workouts awaiting join');

      // Find first workout that hasn't had popup shown
      for (final workout in awaitingWorkouts) {
        final popupShown = workout['popup_already_shown'] ?? false;
        final timeRemaining = workout['time_remaining_seconds'] as int;

        // Skip if popup already shown or window expired
        if (popupShown || timeRemaining <= 0) continue;

        // Show the popup
        if (context.mounted) {
          await _showJoinPopup(context, workout);
        }
        
        // Only show one popup per app open
        break;
      }
    } catch (e) {
      if (kDebugMode) print('❌ Error checking for pending joins: $e');
    }
  }

  /// Check if workout join popups are enabled in user settings
  static Future<bool> _arePopupsEnabled() async {
    try {
      final currentUserId = _supabase.auth.currentUser?.id;
      if (currentUserId == null) return true; // Default to enabled

      final profile = await _supabase
          .from('user_profiles')
          .select('workout_join_popups_enabled')
          .eq('id', currentUserId)
          .maybeSingle();

      return profile?['workout_join_popups_enabled'] ?? true;
    } catch (e) {
      return true; // Default to enabled on error
    }
  }

  /// Show the join workout popup
  static Future<void> _showJoinPopup(
    BuildContext context,
    Map<String, dynamic> workout,
  ) async {
    final workoutId = workout['workout_id'] as String;
    final workoutType = workout['workout_type'] as String? ?? 'Workout';
    final buddyName = workout['buddy_name'] as String? ?? 'Your buddy';
    final plannedDuration = workout['planned_duration_minutes'] as int? ?? 30;
    final timeRemaining = workout['time_remaining_seconds'] as int;

    // Mark popup as shown
    await _workoutService.markJoinPopupShown(workoutId);

    if (!context.mounted) return;

    // Show the popup
    await JoinWorkoutPopup.show(
      context,
      workoutId: workoutId,
      workoutType: workoutType,
      buddyName: buddyName,
      plannedDurationMinutes: plannedDuration,
      timeRemainingSeconds: timeRemaining,
      onJoin: () async {
        // Join the workout
        final result = await _workoutService.creatorJoinWorkout(workoutId);
        
        if (context.mounted) {
          if (result['success'] == true) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Row(
                  children: [
                    const Icon(Icons.check_circle, color: Colors.white),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        'Joined workout with $buddyName! ${result['remaining_minutes']}m remaining',
                      ),
                    ),
                  ],
                ),
                backgroundColor: Colors.green,
                behavior: SnackBarBehavior.floating,
              ),
            );
          } else {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(result['message'] ?? 'Failed to join workout'),
                backgroundColor: Colors.red,
                behavior: SnackBarBehavior.floating,
              ),
            );
          }
        }
      },
      onDecline: () {
        // Just close the popup - user can still join from card
        if (kDebugMode) print('ℹ️ User declined join popup');
      },
    );
  }

  /// Toggle workout join popups setting
  static Future<bool> setPopupsEnabled(bool enabled) async {
    try {
      final currentUserId = _supabase.auth.currentUser?.id;
      if (currentUserId == null) return false;

      await _supabase.from('user_profiles').update({
        'workout_join_popups_enabled': enabled,
      }).eq('id', currentUserId);

      if (kDebugMode) print('✅ Workout join popups ${enabled ? 'enabled' : 'disabled'}');
      return true;
    } catch (e) {
      if (kDebugMode) print('❌ Error updating popup setting: $e');
      return false;
    }
  }

  /// Get current popup setting
  static Future<bool> getPopupsEnabled() async {
    return await _arePopupsEnabled();
  }
}