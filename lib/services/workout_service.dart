import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class WorkoutService {
  final SupabaseClient _supabase = Supabase.instance.client;

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
      final currentUserId = _supabase.auth.currentUser?.id;
      if (currentUserId == null) return [];

      final today = DateTime.now().toIso8601String().split('T')[0];

      // Get workouts where user is creator or buddy
      final response = await _supabase
          .from('workouts')
          .select('''
            *,
            creator:user_profiles!user_id(display_name, fitness_level),
            buddy:user_profiles!buddy_id(display_name, fitness_level)
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
      final currentUserId = _supabase.auth.currentUser?.id;
      if (currentUserId == null) return [];

      final today = DateTime.now().toIso8601String().split('T')[0];

      // Get workouts for today where user is creator or buddy, and status is not cancelled
      final response = await _supabase
          .from('workouts')
          .select('''
            *,
            creator:user_profiles!user_id(display_name, fitness_level),
            buddy:user_profiles!buddy_id(display_name, fitness_level)
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
            creator:user_profiles!user_id(display_name, fitness_level),
            buddy:user_profiles!buddy_id(display_name, fitness_level)
          ''')
          .order('workout_date', ascending: false)
          .order('workout_time', ascending: false);

      return List<Map<String, dynamic>>.from(response);
    } catch (e) {
      if (kDebugMode) print('❌ Error getting all workouts: $e');
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

  // Complete workout with actual duration
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
}
