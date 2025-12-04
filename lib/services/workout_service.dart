import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class WorkoutService {
  final SupabaseClient _supabase = Supabase.instance.client;

  /// Auto-complete workouts that have been in progress for too long (3 hours)
  Future<void> autoCompleteTimedOutWorkouts() async {
    try {
      final currentUserId = _supabase.auth.currentUser?.id;
      if (currentUserId == null) return;

      final threeHoursAgo = DateTime.now().subtract(const Duration(hours: 3));

      // Find workouts that are in_progress and started more than 3 hours ago
      final timedOutWorkouts = await _supabase
          .from('workouts')
          .select('id, workout_started_at, notes')
          .eq('status', 'in_progress')
          .or('user_id.eq.$currentUserId,buddy_id.eq.$currentUserId')
          .lt('workout_started_at', threeHoursAgo.toIso8601String());

      if (timedOutWorkouts.isEmpty) {
        if (kDebugMode) print('✅ No timed-out workouts found');
        return;
      }

      if (kDebugMode) print('⏰ Found ${timedOutWorkouts.length} timed-out workouts, auto-completing...');

      for (final workout in timedOutWorkouts) {
        final startedAt = DateTime.parse(workout['workout_started_at']);
        const duration = 180; // Cap at 3 hours (180 minutes)
        final existingNotes = workout['notes'] as String? ?? '';

        await _supabase.from('workouts').update({
          'status': 'completed',
          'workout_completed_at': startedAt.add(const Duration(hours: 3)).toIso8601String(),
          'actual_duration_minutes': duration,
          'updated_at': DateTime.now().toIso8601String(),
          'notes': existingNotes.isEmpty 
              ? '(Auto-completed after 3 hours)' 
              : '$existingNotes (Auto-completed after 3 hours)',
        }).eq('id', workout['id']);

        if (kDebugMode) print('✅ Auto-completed workout: ${workout['id']}');
      }
    } catch (e) {
      if (kDebugMode) print('❌ Error auto-completing workouts: $e');
    }
  }

  // Create a new workout
  Future<String?> createWorkout({
    required String workoutType,
    required DateTime date,
    required String time,
    required int plannedDurationMinutes,
    String? buddyId,
    String? notes,
  }) async {
    try {
      final currentUserId = _supabase.auth.currentUser?.id;
      if (currentUserId == null) return 'User not logged in';

      final response = await _supabase.from('workouts').insert({
        'user_id': currentUserId,
        'buddy_id': buddyId,
        'workout_type': workoutType,
        'workout_date': date.toIso8601String().split('T')[0], // YYYY-MM-DD
        'workout_time': time,
        'planned_duration_minutes': plannedDurationMinutes,
        'status': 'scheduled',
        'buddy_status': buddyId != null ? 'pending' : null,
        'notes': notes,
      }).select().single();

      if (kDebugMode) print('✅ Workout created: $response');
      return null; // Success
    } catch (e) {
      if (kDebugMode) print('❌ Error creating workout: $e');
      return e.toString();
    }
  }

  // Get upcoming workouts for current user
  Future<List<Map<String, dynamic>>> getUpcomingWorkouts() async {
    try {
      // Auto-complete any timed-out workouts first
      await autoCompleteTimedOutWorkouts();

      final currentUserId = _supabase.auth.currentUser?.id;
      if (currentUserId == null) return [];

      final today = DateTime.now().toIso8601String().split('T')[0];

      // Get workouts where user is creator or buddy
      final response = await _supabase
          .from('workouts')
          .select('''
            *,
            creator:user_profiles!user_id(display_name, fitness_level, avatar_id),
            buddy:user_profiles!buddy_id(display_name, fitness_level, avatar_id)
          ''')
          .or('user_id.eq.$currentUserId,buddy_id.eq.$currentUserId')
          .neq('status', 'completed')
          .neq('status', 'cancelled')
          .gte('workout_date', today)
          .order('workout_date')
          .order('workout_time');

      if (kDebugMode) print('📋 Found ${response.length} upcoming workouts');
      return List<Map<String, dynamic>>.from(response);
    } catch (e) {
      if (kDebugMode) print('❌ Error getting workouts: $e');
      return [];
    }
  }

  // Get today's workouts specifically
  Future<List<Map<String, dynamic>>> getTodaysWorkouts() async {
    try {
      // Auto-complete any timed-out workouts first
      await autoCompleteTimedOutWorkouts();

      final currentUserId = _supabase.auth.currentUser?.id;
      if (currentUserId == null) return [];

      final today = DateTime.now().toIso8601String().split('T')[0];

      // Get workouts for today where user is creator or buddy, and status is not cancelled
      final response = await _supabase
          .from('workouts')
          .select('''
            *,
            creator:user_profiles!user_id(display_name, fitness_level, avatar_id),
            buddy:user_profiles!buddy_id(display_name, fitness_level, avatar_id)
          ''')
          .or('user_id.eq.$currentUserId,buddy_id.eq.$currentUserId')
          .eq('workout_date', today)
          .neq('status', 'cancelled')
          .neq('status', 'completed')
          .order('workout_time');

      if (kDebugMode) print('📋 Found ${response.length} workouts for today');
      return List<Map<String, dynamic>>.from(response);
    } catch (e) {
      if (kDebugMode) print('❌ Error getting today\'s workouts: $e');
      return [];
    }
  }

  // Get all workouts (including past)
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
      if (kDebugMode) print('❌ Error getting all workouts: $e');
      return [];
    }
  }

  // Get completed workouts history
  Future<List<Map<String, dynamic>>> getCompletedWorkouts({int limit = 20}) async {
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
          .eq('status', 'completed')
          .order('workout_completed_at', ascending: false)
          .limit(limit);

      if (kDebugMode) print('📋 Found ${response.length} completed workouts');
      return List<Map<String, dynamic>>.from(response);
    } catch (e) {
      if (kDebugMode) print('❌ Error getting completed workouts: $e');
      return [];
    }
  }

  // Get in-progress workouts
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

      if (kDebugMode) print('📋 Found ${response.length} in-progress workouts');
      return List<Map<String, dynamic>>.from(response);
    } catch (e) {
      if (kDebugMode) print('❌ Error getting in-progress workouts: $e');
      return [];
    }
  }

  // Update workout status
  Future<bool> updateWorkoutStatus(String workoutId, String status) async {
    try {
      await _supabase
          .from('workouts')
          .update({'status': status, 'updated_at': DateTime.now().toIso8601String()})
          .eq('id', workoutId);

      if (kDebugMode) print('✅ Workout status updated to: $status');
      return true;
    } catch (e) {
      if (kDebugMode) print('❌ Error updating workout: $e');
      return false;
    }
  }

  // Delete workout
  Future<bool> deleteWorkout(String workoutId) async {
    try {
      await _supabase.from('workouts').delete().eq('id', workoutId);

      if (kDebugMode) print('✅ Workout deleted');
      return true;
    } catch (e) {
      if (kDebugMode) print('❌ Error deleting workout: $e');
      return false;
    }
  }

  // Accept workout invitation (for buddy)
  Future<bool> acceptWorkoutInvitation(String workoutId) async {
    try {
      await _supabase
          .from('workouts')
          .update({
            'buddy_status': 'accepted',
            'updated_at': DateTime.now().toIso8601String()
          })
          .eq('id', workoutId);

      if (kDebugMode) print('✅ Workout invitation accepted');
      return true;
    } catch (e) {
      if (kDebugMode) print('❌ Error accepting invitation: $e');
      return false;
    }
  }

  // Decline workout invitation (for buddy)
  Future<bool> declineWorkoutInvitation(String workoutId) async {
    try {
      await _supabase
          .from('workouts')
          .update({
            'buddy_status': 'declined',
            'updated_at': DateTime.now().toIso8601String()
          })
          .eq('id', workoutId);

      if (kDebugMode) print('✅ Workout invitation declined');
      return true;
    } catch (e) {
      if (kDebugMode) print('❌ Error declining invitation: $e');
      return false;
    }
  }

  // Mark workout as completed
  Future<bool> completeWorkout(String workoutId) async {
    return await updateWorkoutStatus(workoutId, 'completed');
  }

  // Cancel workout
  Future<bool> cancelWorkout(String workoutId) async {
    return await updateWorkoutStatus(workoutId, 'cancelled');
  }

  // Start workout - begins the timer
  Future<bool> startWorkout(String workoutId) async {
    try {
      await _supabase
          .from('workouts')
          .update({
            'workout_started_at': DateTime.now().toIso8601String(),
            'status': 'in_progress',
            'updated_at': DateTime.now().toIso8601String(),
          })
          .eq('id', workoutId);

      if (kDebugMode) print('✅ Workout started');
      return true;
    } catch (e) {
      if (kDebugMode) print('❌ Error starting workout: $e');
      return false;
    }
  }

  // Complete workout with actual duration calculated from start time
  Future<bool> completeWorkoutWithDuration(String workoutId) async {
    try {
      // Get workout to calculate duration
      final workout = await _supabase
          .from('workouts')
          .select('workout_started_at')
          .eq('id', workoutId)
          .single();

      int? actualDuration;
      if (workout['workout_started_at'] != null) {
        final startTime = DateTime.parse(workout['workout_started_at']);
        final endTime = DateTime.now();
        actualDuration = endTime.difference(startTime).inMinutes;
        
        // Cap at 3 hours if somehow it's longer
        if (actualDuration > 180) {
          actualDuration = 180;
        }
      }

      await _supabase
          .from('workouts')
          .update({
            'status': 'completed',
            'workout_completed_at': DateTime.now().toIso8601String(),
            'actual_duration_minutes': actualDuration,
            'updated_at': DateTime.now().toIso8601String(),
          })
          .eq('id', workoutId);

      if (kDebugMode) print('✅ Workout completed with duration: $actualDuration minutes');
      return true;
    } catch (e) {
      if (kDebugMode) print('❌ Error completing workout: $e');
      return false;
    }
  }

  // Finish workout - alias for completeWorkoutWithDuration (more intuitive name)
  Future<bool> finishWorkout(String workoutId) async {
    return await completeWorkoutWithDuration(workoutId);
  }

  // Get workout by ID
  Future<Map<String, dynamic>?> getWorkoutById(String workoutId) async {
    try {
      final response = await _supabase
          .from('workouts')
          .select('''
            *,
            creator:user_profiles!user_id(display_name, fitness_level, avatar_id),
            buddy:user_profiles!buddy_id(display_name, fitness_level, avatar_id)
          ''')
          .eq('id', workoutId)
          .single();

      return response;
    } catch (e) {
      if (kDebugMode) print('❌ Error getting workout: $e');
      return null;
    }
  }

  // Get workout statistics for user
  Future<Map<String, dynamic>> getWorkoutStats() async {
    try {
      final currentUserId = _supabase.auth.currentUser?.id;
      if (currentUserId == null) {
        return {
          'total_workouts': 0,
          'this_week': 0,
          'this_month': 0,
          'total_minutes': 0,
          'avg_duration': 0,
        };
      }

      // Get all completed workouts
      final allWorkouts = await _supabase
          .from('workouts')
          .select('id, workout_date, actual_duration_minutes')
          .or('user_id.eq.$currentUserId,buddy_id.eq.$currentUserId')
          .eq('status', 'completed');

      final totalWorkouts = allWorkouts.length;

      // Calculate total and average duration
      int totalMinutes = 0;
      for (final workout in allWorkouts) {
        totalMinutes += (workout['actual_duration_minutes'] as int?) ?? 0;
      }
      final avgDuration = totalWorkouts > 0 ? (totalMinutes / totalWorkouts).round() : 0;

      // This week's workouts
      final weekStart = DateTime.now().subtract(Duration(days: DateTime.now().weekday - 1));
      final weekStartStr = weekStart.toIso8601String().split('T')[0];
      final thisWeek = allWorkouts.where((w) {
        final date = w['workout_date'] as String?;
        return date != null && date.compareTo(weekStartStr) >= 0;
      }).length;

      // This month's workouts
      final monthStart = DateTime(DateTime.now().year, DateTime.now().month, 1);
      final monthStartStr = monthStart.toIso8601String().split('T')[0];
      final thisMonth = allWorkouts.where((w) {
        final date = w['workout_date'] as String?;
        return date != null && date.compareTo(monthStartStr) >= 0;
      }).length;

      if (kDebugMode) {
        print('📊 Workout Stats:');
        print('   Total: $totalWorkouts');
        print('   This week: $thisWeek');
        print('   This month: $thisMonth');
        print('   Total minutes: $totalMinutes');
        print('   Avg duration: $avgDuration min');
      }

      return {
        'total_workouts': totalWorkouts,
        'this_week': thisWeek,
        'this_month': thisMonth,
        'total_minutes': totalMinutes,
        'avg_duration': avgDuration,
      };
    } catch (e) {
      if (kDebugMode) print('❌ Error getting workout stats: $e');
      return {
        'total_workouts': 0,
        'this_week': 0,
        'this_month': 0,
        'total_minutes': 0,
        'avg_duration': 0,
      };
    }
  }

  Future<bool> completeWorkoutWithCheckIn(String workoutId) async {
    final success = await completeWorkoutWithDuration(workoutId);
    
    if (success) {
      // Get the workout to check if it's a buddy workout
      final workout = await getWorkoutById(workoutId);
      
      if (workout != null && 
          workout['buddy_id'] != null && 
          workout['buddy_status'] == 'accepted') {
        // Trigger team streak check-in
      }
    }
    
    return success;
  }
}