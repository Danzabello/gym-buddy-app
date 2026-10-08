import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:gym_buddy_app/utils/debug_logger.dart';

class WorkoutService {
  final SupabaseClient _supabase = Supabase.instance.client;

  // ============================================================
  // BUDDY JOIN SYSTEM
  // ============================================================

  Future<bool> isUserInActiveWorkout(String userId) async {
    try {
      final activeSessions = await _supabase
          .from('active_checkin_sessions')
          .select('id')
          .eq('user_id', userId);
      if (activeSessions.isNotEmpty) {
        return true;
      }
      final inProgressWorkouts = await _supabase
          .from('workouts')
          .select('id')
          .eq('status', 'in_progress')
          .or('user_id.eq.$userId,buddy_id.eq.$userId');
      if (inProgressWorkouts.isNotEmpty) {
        return true;
      }
      return false;
    } catch (e) {
      if (kDebugMode) debugLog('❌ Error checking active workout: $e');
      return false;
    }
  }

  // ============================================================
  // CORE WORKOUT METHODS
  // ============================================================

  Future<String?> createWorkout({
    required String workoutType,
    required DateTime date,
    required String time,
    int? plannedDurationMinutes,
    String? buddyId,
    String? buddyName,
  }) async {
    try {
      final currentUserId = _supabase.auth.currentUser?.id;
      if (currentUserId == null) return 'Not logged in';
      if (buddyId != null) {
        final buddyInWorkout = await isUserInActiveWorkout(buddyId);
        if (buddyInWorkout) {
          return 'BUDDY_IN_WORKOUT';
        }
      }
      final userInWorkout = await isUserInActiveWorkout(currentUserId);
      if (userInWorkout) {
        if (kDebugMode) debugLog('⚠️ Current user is already in an active workout');
        return 'USER_IN_WORKOUT';
      }
      final dateStr = date.toIso8601String().split('T')[0];
      final response = await _supabase.from('workouts').insert({
        'user_id': currentUserId,
        'workout_type': workoutType,
        'workout_date': dateStr,
        'workout_time': time,
        'planned_duration_minutes': plannedDurationMinutes ?? 60,
        'status': 'scheduled',
        'buddy_id': buddyId,
        'buddy_status': buddyId != null ? 'pending' : null,
      }).select().single();
      if (kDebugMode) debugLog('✅ Workout created: ${response['id']}');
      return null;
    } catch (e) {
      if (kDebugMode) debugLog('❌ Error creating workout: $e');
      // The invite cap is the sender's; the buddy is never told.
      if (e is PostgrestException && e.message.contains('invite_cap_reached')) {
        return '${buddyName ?? 'Your buddy'} has too many invites waiting. Try again later.';
      }
      return 'Could not save workout. Please try again.';
    }
  }

  Future<bool> deleteWorkout(String workoutId) async {
    try {
      await _supabase.from('workouts').delete().eq('id', workoutId);
      if (kDebugMode) debugLog('✅ Workout deleted');
      return true;
    } catch (e) {
      if (kDebugMode) debugLog('❌ Error deleting workout: $e');
      return false;
    }
  }

  // ============================================================
  // CLEANUP
  // ============================================================

  Future<void> cleanupOrphanedSessions() async {
    try {
      final currentUserId = _supabase.auth.currentUser?.id;
      if (currentUserId == null) return;
      final sessions = await _supabase
          .from('active_checkin_sessions')
          .select('id, workout_id')
          .eq('user_id', currentUserId);
      for (final session in sessions) {
        final workoutId = session['workout_id'];
        if (workoutId == null) continue;
        final workout = await _supabase
            .from('workouts')
            .select('status')
            .eq('id', workoutId)
            .maybeSingle();
        // A workout completed by the partner keeps this user's session: they
        // are still in it and can Finish (or the server auto-completes it).
        if (workout == null || workout['status'] == 'cancelled') {
          await _supabase.from('active_checkin_sessions').delete().eq('id', session['id']);
          if (kDebugMode) debugLog('🧹 Cleaned up orphaned session: ${session['id']}');
        }
      }
    } catch (e) {
      if (kDebugMode) debugLog('⚠️ Error cleaning up sessions: $e');
    }
  }

  // ============================================================
  // QUERIES
  // ============================================================

  Future<List<Map<String, dynamic>>> getTodaysWorkouts() async {
    try {
      final currentUserId = _supabase.auth.currentUser?.id;
      if (currentUserId == null) return [];
      final today = DateTime.now().toIso8601String().split('T')[0];
      final response = await _supabase
          .from('workouts')
          .select('''
            *,
            creator:user_profiles!user_id(display_name, fitness_level),
            buddy:user_profiles!buddy_id(display_name, fitness_level)
          ''')
          .or('user_id.eq.$currentUserId,buddy_id.eq.$currentUserId')
          .eq('workout_date', today)
          .order('workout_time', ascending: true);
      if (kDebugMode) debugLog('📋 Found ${response.length} workouts for today');
      return List<Map<String, dynamic>>.from(response);
    } catch (e) {
      if (kDebugMode) debugLog('❌ Error getting today\'s workouts: $e');
      return [];
    }
  }

  Future<List<Map<String, dynamic>>> getCompletedWorkouts({int limit = 20}) async {
    try {
      final currentUserId = _supabase.auth.currentUser?.id;
      if (currentUserId == null) return [];
      final response = await _supabase
          .from('workouts')
          .select('''
            *,
            creator:user_profiles!user_id(display_name, avatar_id),
            buddy:user_profiles!buddy_id(display_name, avatar_id)
          ''')
          .or('user_id.eq.$currentUserId,buddy_id.eq.$currentUserId')
          .eq('status', 'completed')
          .order('workout_completed_at', ascending: false)
          .limit(limit);
      if (kDebugMode) debugLog('📋 Found ${response.length} completed workouts');
      return List<Map<String, dynamic>>.from(response);
    } catch (e) {
      if (kDebugMode) debugLog('❌ Error getting completed workouts: $e');
      return [];
    }
  }

  Future<Map<String, dynamic>?> getWorkoutById(String workoutId) async {
    try {
      final response = await _supabase
          .from('workouts')
          .select('''
            *,
            creator:user_profiles!user_id(display_name, fitness_level),
            buddy:user_profiles!buddy_id(display_name, fitness_level)
          ''')
          .eq('id', workoutId)
          .single();
      return response;
    } catch (e) {
      if (kDebugMode) debugLog('❌ Error getting workout: $e');
      return null;
    }
  }

  Future<List<Map<String, dynamic>>> getInProgressWorkouts() async {
    try {
      final currentUserId = _supabase.auth.currentUser?.id;
      if (currentUserId == null) return [];
      final response = await _supabase
          .from('workouts')
          .select('''
            *,
            creator:user_profiles!user_id(display_name, fitness_level, avatar_id),
            buddy:user_profiles!buddy_id(display_name, fitness_level, avatar_id)
          ''')
          .or('user_id.eq.$currentUserId,buddy_id.eq.$currentUserId')
          .eq('status', 'in_progress')
          .order('workout_started_at', ascending: false);
      if (kDebugMode) debugLog('📋 Found ${response.length} in-progress workouts');
      return List<Map<String, dynamic>>.from(response);
    } catch (e) {
      if (kDebugMode) debugLog('❌ Error getting in-progress workouts: $e');
      return [];
    }
  }

  Future<List<Map<String, dynamic>>> getAllWorkouts() async {
    try {
      final currentUserId = _supabase.auth.currentUser?.id;
      if (currentUserId == null) return [];
      final response = await _supabase
          .from('workouts')
          .select('''
            *,
            creator:user_profiles!user_id(display_name, fitness_level, avatar_id),
            buddy:user_profiles!buddy_id(display_name, fitness_level, avatar_id)
          ''')
          .or('user_id.eq.$currentUserId,buddy_id.eq.$currentUserId')
          .order('workout_date', ascending: false)
          .order('workout_time', ascending: false);
      return List<Map<String, dynamic>>.from(response);
    } catch (e) {
      if (kDebugMode) debugLog('❌ Error getting all workouts: $e');
      return [];
    }
  }

  Future<Map<String, dynamic>> getWorkoutStats() async {
    try {
      final currentUserId = _supabase.auth.currentUser?.id;
      if (currentUserId == null) {
        return {'total_workouts': 0, 'this_week': 0, 'this_month': 0, 'total_minutes': 0, 'avg_duration': 0};
      }
      final allWorkouts = await _supabase
          .from('workouts')
          .select('workout_date, actual_duration_minutes')
          .or('user_id.eq.$currentUserId,buddy_id.eq.$currentUserId')
          .eq('status', 'completed');
      final totalWorkouts = allWorkouts.length;
      int totalMinutes = 0;
      for (final w in allWorkouts) {
        totalMinutes += (w['actual_duration_minutes'] as int?) ?? 0;
      }
      final avgDuration = totalWorkouts > 0 ? (totalMinutes / totalWorkouts).round() : 0;
      final weekStart = DateTime.now().subtract(Duration(days: DateTime.now().weekday - 1));
      final weekStartStr = weekStart.toIso8601String().split('T')[0];
      final thisWeek = allWorkouts.where((w) {
        final date = w['workout_date'] as String?;
        return date != null && date.compareTo(weekStartStr) >= 0;
      }).length;
      final monthStart = DateTime(DateTime.now().year, DateTime.now().month, 1);
      final monthStartStr = monthStart.toIso8601String().split('T')[0];
      final thisMonth = allWorkouts.where((w) {
        final date = w['workout_date'] as String?;
        return date != null && date.compareTo(monthStartStr) >= 0;
      }).length;
      return {
        'total_workouts': totalWorkouts,
        'this_week': thisWeek,
        'this_month': thisMonth,
        'total_minutes': totalMinutes,
        'avg_duration': avgDuration,
      };
    } catch (e) {
      if (kDebugMode) debugLog('❌ Error getting workout stats: $e');
      return {'total_workouts': 0, 'this_week': 0, 'this_month': 0, 'total_minutes': 0, 'avg_duration': 0};
    }
  }
}
