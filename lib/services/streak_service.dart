import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class StreakService {
  final SupabaseClient _supabase = Supabase.instance.client;

  // Get streak info (main method used by home_screen)
  Future<Map<String, dynamic>> getStreakInfo() async {
    return await getStreakData();
  }

  // Get current user's streak data
  Future<Map<String, dynamic>> getStreakData() async {
    try {
      final currentUserId = _supabase.auth.currentUser?.id;
      if (currentUserId == null) {
        return {'current_streak': 0, 'longest_streak': 0, 'last_workout_date': null};
      }

      // Get user's profile which contains streak info
      final profile = await _supabase
          .from('user_profiles')
          .select('current_streak, longest_streak, last_workout_date')
          .eq('id', currentUserId)
          .maybeSingle();

      if (profile == null) {
        return {'current_streak': 0, 'longest_streak': 0, 'last_workout_date': null};
      }

      return {
        'current_streak': profile['current_streak'] ?? 0,
        'longest_streak': profile['longest_streak'] ?? 0,
        'last_workout_date': profile['last_workout_date'],
      };
    } catch (e) {
      if (kDebugMode) print('❌ Error getting streak data: $e');
      return {'current_streak': 0, 'longest_streak': 0, 'last_workout_date': null};
    }
  }

  // Check if user has checked in today
  Future<bool> hasCheckedInToday() async {
    return await hasWorkedOutToday();
  }

  // Check if user has worked out today
  Future<bool> hasWorkedOutToday() async {
    try {
      final currentUserId = _supabase.auth.currentUser?.id;
      if (currentUserId == null) return false;

      final today = DateTime.now().toIso8601String().split('T')[0];

      final workouts = await _supabase
          .from('workouts')
          .select()
          .eq('user_id', currentUserId)
          .eq('status', 'completed')
          .eq('workout_date', today);

      return workouts.isNotEmpty;
    } catch (e) {
      if (kDebugMode) print('❌ Error checking today\'s workout: $e');
      return false;
    }
  }

  // Check in (manual workout logging)
  Future<Map<String, dynamic>> checkIn() async {
    try {
      final currentUserId = _supabase.auth.currentUser?.id;
      if (currentUserId == null) {
        return {'success': false, 'message': 'Not logged in'};
      }

      // Check if already checked in today
      final alreadyCheckedIn = await hasWorkedOutToday();
      if (alreadyCheckedIn) {
        return {'success': false, 'message': 'Already checked in today!'};
      }

      // Create a workout entry for today
      final today = DateTime.now();
      final todayStr = today.toIso8601String().split('T')[0];
      final timeStr = '${today.hour.toString().padLeft(2, '0')}:${today.minute.toString().padLeft(2, '0')}:00';

      // Insert workout and ignore the response (don't return it)
      await _supabase.from('workouts').insert({
        'user_id': currentUserId,
        'workout_type': 'Check-in',
        'workout_date': todayStr,
        'workout_time': timeStr,
        'status': 'completed',
        'workout_completed_at': DateTime.now().toIso8601String(),
      });

      // Update streak
      final streakUpdated = await updateStreakOnWorkoutComplete();

      // Get updated streak info
      final streakData = await getStreakData();

      if (kDebugMode) {
        print('✅ Check-in successful! Streak: ${streakData['current_streak']}');
      }

      return {
        'success': true,
        'message': 'Check-in successful!',
        'current_streak': streakData['current_streak'],
        'longest_streak': streakData['longest_streak'],
      };
    } catch (e) {
      if (kDebugMode) print('❌ Error checking in: $e');
      return {'success': false, 'message': 'Error: $e'};
    }
  }

  // Get check-in history
  Future<List<Map<String, dynamic>>> getCheckInHistory({int limit = 30}) async {
    try {
      final currentUserId = _supabase.auth.currentUser?.id;
      if (currentUserId == null) return [];

      final workouts = await _supabase
          .from('workouts')
          .select()
          .eq('user_id', currentUserId)
          .eq('status', 'completed')
          .order('workout_date', ascending: false)
          .order('workout_time', ascending: false)
          .limit(limit);

      return List<Map<String, dynamic>>.from(workouts);
    } catch (e) {
      if (kDebugMode) print('❌ Error getting check-in history: $e');
      return [];
    }
  }

  // Update streak when a workout is completed
  Future<bool> updateStreakOnWorkoutComplete() async {
    try {
      final currentUserId = _supabase.auth.currentUser?.id;
      if (currentUserId == null) return false;

      // Get current streak data
      final streakData = await getStreakData();
      final currentStreak = streakData['current_streak'] as int;
      final longestStreak = streakData['longest_streak'] as int;
      final lastWorkoutDate = streakData['last_workout_date'] as String?;

      final today = DateTime.now().toIso8601String().split('T')[0];
      
      int newStreak = currentStreak;
      int newLongest = longestStreak;

      if (lastWorkoutDate == null) {
        // First workout ever
        newStreak = 1;
        newLongest = 1;
      } else {
        final lastDate = DateTime.parse(lastWorkoutDate);
        final todayDate = DateTime.parse(today);
        final daysDifference = todayDate.difference(lastDate).inDays;

        if (daysDifference == 0) {
          // Already worked out today, no change
          return true;
        } else if (daysDifference == 1) {
          // Consecutive day - increment streak
          newStreak = currentStreak + 1;
          if (newStreak > longestStreak) {
            newLongest = newStreak;
          }
        } else {
          // Streak broken - reset to 1
          newStreak = 1;
        }
      }

      // Update the profile
      await _supabase
          .from('user_profiles')
          .update({
            'current_streak': newStreak,
            'longest_streak': newLongest,
            'last_workout_date': today,
            'updated_at': DateTime.now().toIso8601String(),
          })
          .eq('id', currentUserId);

      if (kDebugMode) {
        print('✅ Streak updated! Current: $newStreak, Longest: $newLongest');
      }

      return true;
    } catch (e) {
      if (kDebugMode) print('❌ Error updating streak: $e');
      return false;
    }
  }

  // Get streak statistics
  Future<Map<String, dynamic>> getStreakStats() async {
    try {
      final currentUserId = _supabase.auth.currentUser?.id;
      if (currentUserId == null) {
        return {
          'current_streak': 0,
          'longest_streak': 0,
          'total_workouts': 0,
          'this_week': 0,
          'this_month': 0,
        };
      }

      // Get streak data
      final streakData = await getStreakData();

      // Count total completed workouts - fetch all and count manually
      final totalWorkoutsData = await _supabase
          .from('workouts')
          .select('id')
          .eq('user_id', currentUserId)
          .eq('status', 'completed');
      
      final totalWorkouts = (totalWorkoutsData as List).length;

      // Count this week's workouts
      final weekStart = DateTime.now().subtract(Duration(days: DateTime.now().weekday - 1));
      final weekStartStr = weekStart.toIso8601String().split('T')[0];
      
      final thisWeekData = await _supabase
          .from('workouts')
          .select('id')
          .eq('user_id', currentUserId)
          .eq('status', 'completed')
          .gte('workout_date', weekStartStr);
      
      final thisWeek = (thisWeekData as List).length;

      // Count this month's workouts
      final monthStart = DateTime(DateTime.now().year, DateTime.now().month, 1);
      final monthStartStr = monthStart.toIso8601String().split('T')[0];
      
      final thisMonthData = await _supabase
          .from('workouts')
          .select('id')
          .eq('user_id', currentUserId)
          .eq('status', 'completed')
          .gte('workout_date', monthStartStr);

      final thisMonth = (thisMonthData as List).length;

      if (kDebugMode) {
        print('📊 Stats - Total: $totalWorkouts, Week: $thisWeek, Month: $thisMonth');
        print('📊 Streak - Current: ${streakData['current_streak']}, Longest: ${streakData['longest_streak']}');
      }

      return {
        'current_streak': streakData['current_streak'] as int,
        'longest_streak': streakData['longest_streak'] as int,
        'total_workouts': totalWorkouts,
        'this_week': thisWeek,
        'this_month': thisMonth,
      };
    } catch (e) {
      if (kDebugMode) print('❌ Error getting streak stats: $e');
      return {
        'current_streak': 0,
        'longest_streak': 0,
        'total_workouts': 0,
        'this_week': 0,
        'this_month': 0,
      };
    }
  }
}