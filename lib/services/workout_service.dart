import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class WorkoutService {
  final SupabaseClient _supabase = Supabase.instance.client;

  // ============================================================
  // BUDDY JOIN SYSTEM - NEW METHODS
  // ============================================================

  /// Check if a user is currently in an active workout
  /// Used to prevent sending invites to busy users
  Future<bool> isUserInActiveWorkout(String userId) async {
    try {
      // Method 1: Check active_checkin_sessions table
      final activeSessions = await _supabase
          .from('active_checkin_sessions')
          .select('id')
          .eq('user_id', userId);
      
      if (activeSessions.isNotEmpty) {
        if (kDebugMode) print('🏋️ User $userId has active checkin session');
        return true;
      }
      
      // Method 2: Check workouts table for in_progress workouts
      final inProgressWorkouts = await _supabase
          .from('workouts')
          .select('id')
          .eq('status', 'in_progress')
          .or('user_id.eq.$userId,buddy_id.eq.$userId');
      
      if (inProgressWorkouts.isNotEmpty) {
        if (kDebugMode) print('🏋️ User $userId has in_progress workout');
        return true;
      }
      
      if (kDebugMode) print('✅ User $userId is NOT in an active workout');
      return false;
    } catch (e) {
      if (kDebugMode) print('❌ Error checking active workout: $e');
      // Fallback: assume not in workout to avoid blocking
      return false;
    }
  }

  /// Fallback manual check for active workout
  Future<bool> _manualCheckActiveWorkout(String userId) async {
    try {
      // Check active_checkin_sessions
      final sessions = await _supabase
          .from('active_checkin_sessions')
          .select('id')
          .eq('user_id', userId)
          .limit(1);
      
      if (sessions.isNotEmpty) return true;

      // Check in_progress workouts where user has joined
      final workouts = await _supabase
          .from('workouts')
          .select('id')
          .eq('status', 'in_progress')
          .or('and(user_id.eq.$userId,creator_joined.eq.true),started_by_user_id.eq.$userId')
          .limit(1);

      return workouts.isNotEmpty;
    } catch (e) {
      if (kDebugMode) print('❌ Error in manual check: $e');
      return false;
    }
  }

  /// Get workouts waiting for the creator to join
  /// Returns workouts where buddy accepted & started, but creator hasn't joined yet
  Future<List<Map<String, dynamic>>> getWorkoutsAwaitingCreatorJoin() async {
    try {
      final currentUserId = _supabase.auth.currentUser?.id;
      if (currentUserId == null) return [];

      final result = await _supabase.rpc(
        'get_workouts_awaiting_creator_join',
        params: {'creator_id': currentUserId},
      );

      if (kDebugMode) print('📋 Found ${result.length} workouts awaiting creator join');
      return List<Map<String, dynamic>>.from(result);
    } catch (e) {
      if (kDebugMode) print('❌ Error getting awaiting workouts: $e');
      // Fallback: manual query
      return await _manualGetAwaitingWorkouts();
    }
  }

  /// Fallback manual query for awaiting workouts
  Future<List<Map<String, dynamic>>> _manualGetAwaitingWorkouts() async {
    try {
      final currentUserId = _supabase.auth.currentUser?.id;
      if (currentUserId == null) return [];

      final workouts = await _supabase
          .from('workouts')
          .select('''
            *,
            buddy:user_profiles!buddy_id(display_name)
          ''')
          .eq('user_id', currentUserId)
          .eq('status', 'in_progress')
          .not('started_by_user_id', 'is', null)
          .neq('started_by_user_id', currentUserId)
          .or('creator_joined.is.null,creator_joined.eq.false');

      // Calculate join window for each workout
      final now = DateTime.now();
      final result = <Map<String, dynamic>>[];

      for (final workout in workouts) {
        final startedAt = DateTime.parse(workout['workout_started_at']);
        final plannedDuration = workout['planned_duration_minutes'] as int;
        final joinWindowMinutes = plannedDuration ~/ 4;
        final joinWindowEnd = startedAt.add(Duration(minutes: joinWindowMinutes));
        final timeRemaining = joinWindowEnd.difference(now).inSeconds;

        result.add({
          'workout_id': workout['id'],
          'workout_type': workout['workout_type'],
          'buddy_name': workout['buddy']?['display_name'] ?? 'Your buddy',
          'planned_duration_minutes': plannedDuration,
          'started_at': workout['workout_started_at'],
          'join_window_end': joinWindowEnd.toIso8601String(),
          'time_remaining_seconds': timeRemaining,
          'popup_already_shown': workout['creator_popup_shown'] ?? false,
        });
      }

      return result;
    } catch (e) {
      if (kDebugMode) print('❌ Error in manual awaiting query: $e');
      return [];
    }
  }

  /// Accept workout invitation - NOW starts the workout for the ACCEPTOR only
  /// The creator will see a popup to join
  Future<bool> acceptWorkoutInvitation(String workoutId) async {
    try {
      final currentUserId = _supabase.auth.currentUser?.id;
      if (currentUserId == null) return false;
      
      // Get workout details
      final workout = await _supabase
          .from('workouts')
          .select('planned_duration_minutes, workout_type, user_id')
          .eq('id', workoutId)
          .single();
      
      final plannedDuration = workout['planned_duration_minutes'] ?? 30;
      final workoutType = workout['workout_type'] ?? 'Workout';
      
      // Map workout type to emoji
      String emoji = '💪';
      switch (workoutType.toString().toLowerCase()) {
        case 'cardio': emoji = '🏃'; break;
        case 'strength': emoji = '💪'; break;
        case 'hiit': emoji = '⚡'; break;
        case 'leg day':
        case 'lower body': emoji = '🦵'; break;
        case 'upper body': emoji = '💪'; break;
        case 'full body': emoji = '🏋️'; break;
        case 'yoga': emoji = '🧘'; break;
      }
      
      final now = DateTime.now();
      
      // Update workout to in_progress and mark who started it
      await _supabase
          .from('workouts')
          .update({
            'buddy_status': 'accepted',
            'status': 'in_progress',
            'workout_started_at': now.toIso8601String(),
            'started_by_user_id': currentUserId,
            'updated_at': now.toIso8601String(),
          })
          .eq('id', workoutId);
      
      // Create active session for the ACCEPTOR (buddy) only
      // Link it to the workout so we can clean it up on cancel
      await _supabase.from('active_checkin_sessions').upsert({
        'user_id': currentUserId,
        'started_at': now.toIso8601String(),
        'planned_duration': plannedDuration,
        'workout_type': workoutType,
        'workout_emoji': emoji,
        'workout_id': workoutId,  // ✅ Link to workout for cleanup
      });
      
      if (kDebugMode) print('✅ Workout invitation accepted, session created for acceptor');
      return true;
    } catch (e) {
      if (kDebugMode) print('❌ Error accepting invitation: $e');
      return false;
    }
  }

  /// Creator joins the workout (within join window)
  Future<Map<String, dynamic>> creatorJoinWorkout(String workoutId) async {
    try {
      final currentUserId = _supabase.auth.currentUser?.id;
      if (currentUserId == null) {
        return {'success': false, 'error': 'Not logged in'};
      }
      
      // Get workout details
      final workout = await _supabase
          .from('workouts')
          .select('*, creator:user_id(display_name), buddy:buddy_id(display_name)')
          .eq('id', workoutId)
          .single();
      
      final status = workout['status'];
      final startedAt = workout['workout_started_at'];
      final plannedDuration = workout['planned_duration_minutes'] ?? 30;
      final startedByUserId = workout['started_by_user_id'];
      final creatorJoined = workout['creator_joined'] ?? false;
      
      // Validate workout state
      if (status != 'in_progress') {
        return {'success': false, 'error': 'Workout not in progress'};
      }
      
      if (creatorJoined) {
        return {'success': false, 'error': 'Already joined'};
      }
      
      if (startedAt == null) {
        return {'success': false, 'error': 'Workout not started yet'};
      }
      
      // Calculate join window
      final startTime = DateTime.parse(startedAt);
      final joinWindowMinutes = plannedDuration ~/ 4;
      final joinWindowEnd = startTime.add(Duration(minutes: joinWindowMinutes));
      final now = DateTime.now();
      
      if (now.isAfter(joinWindowEnd)) {
        return {'success': false, 'error': 'Join window expired'};
      }
      
      // Calculate remaining time
      final elapsedMinutes = now.difference(startTime).inMinutes;
      final remainingMinutes = plannedDuration - elapsedMinutes;
      
      // Map workout type to emoji
      final workoutType = workout['workout_type'] ?? 'Workout';
      String emoji = '💪';
      switch (workoutType.toString().toLowerCase()) {
        case 'cardio': emoji = '🏃'; break;
        case 'strength': emoji = '💪'; break;
        case 'hiit': emoji = '⚡'; break;
        case 'leg day':
        case 'lower body': emoji = '🦵'; break;
        case 'upper body': emoji = '💪'; break;
        case 'full body': emoji = '🏋️'; break;
        case 'yoga': emoji = '🧘'; break;
      }
      
      // Mark creator as joined
      await _supabase
          .from('workouts')
          .update({
            'creator_joined': true,
            'creator_joined_at': now.toIso8601String(),
            'updated_at': now.toIso8601String(),
          })
          .eq('id', workoutId);
      
      // Create active session for creator with REMAINING time
      // The started_at should reflect when THEY started (now), but planned_duration is what's left
      await _supabase.from('active_checkin_sessions').upsert({
        'user_id': currentUserId,
        'started_at': now.toIso8601String(),
        'planned_duration': remainingMinutes > 0 ? remainingMinutes : 5, // Min 5 minutes
        'workout_type': workoutType,
        'workout_emoji': emoji,
        'workout_id': workoutId,  // ✅ Link to workout
      });
      
      if (kDebugMode) print('✅ Creator joined workout with $remainingMinutes minutes remaining');
      
      return {
        'success': true,
        'remainingMinutes': remainingMinutes,
        'workoutType': workoutType,
        'emoji': emoji,
      };
    } catch (e) {
      if (kDebugMode) print('❌ Error joining workout: $e');
      return {'success': false, 'error': e.toString()};
    }
  }

  /// Mark the join popup as shown for a workout
  Future<void> markJoinPopupShown(String workoutId) async {
    try {
      await _supabase.from('workouts').update({
        'creator_popup_shown': true,
        'updated_at': DateTime.now().toIso8601String(),
      }).eq('id', workoutId);
    } catch (e) {
      if (kDebugMode) print('❌ Error marking popup shown: $e');
    }
  }

  /// Check workout status for the creator's view
  /// Returns different states: waiting_to_join, window_expired, buddy_completed
  Future<Map<String, dynamic>> getCreatorWorkoutStatus(String workoutId) async {
    try {
      final currentUserId = _supabase.auth.currentUser?.id;
      if (currentUserId == null) return {'status': 'error'};

      final workout = await _supabase
          .from('workouts')
          .select('*, buddy:user_profiles!buddy_id(display_name)')
          .eq('id', workoutId)
          .single();

      // If creator has already joined
      if (workout['creator_joined'] == true) {
        return {'status': 'joined', 'workout': workout};
      }

      // If workout is completed
      if (workout['status'] == 'completed') {
        return {
          'status': 'buddy_completed',
          'workout': workout,
          'message': '${workout['buddy']?['display_name'] ?? 'Your buddy'} completed the workout and helped the streak grow! 🎉'
        };
      }

      // If workout is still in progress
      if (workout['status'] == 'in_progress' && workout['workout_started_at'] != null) {
        final startedAt = DateTime.parse(workout['workout_started_at']);
        final plannedDuration = workout['planned_duration_minutes'] as int;
        final joinWindowMinutes = plannedDuration ~/ 4;
        final joinWindowEnd = startedAt.add(Duration(minutes: joinWindowMinutes));
        final now = DateTime.now();

        if (now.isBefore(joinWindowEnd)) {
          final remainingSeconds = joinWindowEnd.difference(now).inSeconds;
          return {
            'status': 'waiting_to_join',
            'workout': workout,
            'join_window_remaining_seconds': remainingSeconds,
            'buddy_name': workout['buddy']?['display_name'] ?? 'Your buddy',
          };
        } else {
          return {
            'status': 'window_expired',
            'workout': workout,
            'message': '${workout['buddy']?['display_name'] ?? 'Your buddy'} started without you',
          };
        }
      }

      return {'status': 'unknown', 'workout': workout};
    } catch (e) {
      if (kDebugMode) print('❌ Error getting creator workout status: $e');
      return {'status': 'error'};
    }
  }

  // Helper to get emoji for workout type
  String _getWorkoutEmoji(String? workoutType) {
    switch (workoutType?.toLowerCase()) {
      case 'cardio':
        return '🏃';
      case 'strength':
        return '💪';
      case 'hiit':
        return '⚡';
      case 'leg day':
      case 'lower body':
        return '🦵';
      case 'upper body':
        return '💪';
      case 'full body':
        return '🏋️';
      case 'yoga':
        return '🧘';
      default:
        return '🏋️';
    }
  }

  // ============================================================
  // EXISTING METHODS (keep these as they are in your current file)
  // ============================================================

  /// Auto-complete workouts that have been in progress for too long (3 hours)
  Future<void> autoCompleteTimedOutWorkouts() async {
    try {
      final currentUserId = _supabase.auth.currentUser?.id;
      if (currentUserId == null) return;

      final threeHoursAgo = DateTime.now().subtract(const Duration(hours: 3));

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
        const duration = 180;
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

  Future<void> cleanupOrphanedSessions() async {
    try {
      final currentUserId = _supabase.auth.currentUser?.id;
      if (currentUserId == null) return;
      
      // Get all active sessions for current user
      final sessions = await _supabase
          .from('active_checkin_sessions')
          .select('id, workout_id')
          .eq('user_id', currentUserId);
      
      for (final session in sessions) {
        final workoutId = session['workout_id'];
        if (workoutId == null) continue;
        
        // Check if linked workout still exists and is in progress
        final workout = await _supabase
            .from('workouts')
            .select('status')
            .eq('id', workoutId)
            .maybeSingle();
        
        if (workout == null || workout['status'] == 'cancelled' || workout['status'] == 'completed') {
          // Workout doesn't exist or is finished - delete orphaned session
          await _supabase
              .from('active_checkin_sessions')
              .delete()
              .eq('id', session['id']);
          
          if (kDebugMode) print('🧹 Cleaned up orphaned session: ${session['id']}');
        }
      }
    } catch (e) {
      if (kDebugMode) print('⚠️ Error cleaning up sessions: $e');
    }
  }

  // Create a new workout - NOW checks if buddy is in active workout
  Future<String?> createWorkout({
    required String workoutType,
    required DateTime date,
    required String time,
    int? plannedDurationMinutes,
    String? buddyId,
  }) async {
    try {
      final currentUserId = _supabase.auth.currentUser?.id;
      if (currentUserId == null) return 'Not logged in';

      // ✅ Check if BUDDY is currently in a workout
      if (buddyId != null) {
        final buddyInWorkout = await isUserInActiveWorkout(buddyId);
        if (buddyInWorkout) {
          if (kDebugMode) print('⚠️ Buddy $buddyId is in an active workout');
          return 'BUDDY_IN_WORKOUT';
        }
      }

      // ✅ Also check if CURRENT USER is in a workout
      final userInWorkout = await isUserInActiveWorkout(currentUserId);
      if (userInWorkout) {
        if (kDebugMode) print('⚠️ Current user is already in an active workout');
        return 'USER_IN_WORKOUT';
      }

      final dateStr = date.toIso8601String().split('T')[0];

      final response = await _supabase
          .from('workouts')
          .insert({
            'user_id': currentUserId,
            'workout_type': workoutType,
            'workout_date': dateStr,
            'workout_time': time,
            'planned_duration_minutes': plannedDurationMinutes ?? 60,
            'status': 'scheduled',
            'buddy_id': buddyId,
            'buddy_status': buddyId != null ? 'pending' : null,
          })
          .select()
          .single();

      if (kDebugMode) print('✅ Workout created: ${response['id']}');
      return null; // Success = no error
    } catch (e) {
      if (kDebugMode) print('❌ Error creating workout: $e');
      return e.toString();
    }
  }

  // Get upcoming workouts
  Future<List<Map<String, dynamic>>> getUpcomingWorkouts() async {
    try {
      final currentUserId = _supabase.auth.currentUser?.id;
      if (currentUserId == null) return [];

      final today = DateTime.now().toIso8601String().split('T')[0];

      // Query 1: Get scheduled workouts for today or future
      final scheduledWorkouts = await _supabase
          .from('workouts')
          .select('''
            *,
            creator:user_profiles!user_id(display_name, fitness_level, avatar_id),
            buddy:user_profiles!buddy_id(display_name, fitness_level, avatar_id)
          ''')
          .or('user_id.eq.$currentUserId,buddy_id.eq.$currentUserId')
          .gte('workout_date', today)
          .eq('status', 'scheduled')
          .order('workout_date', ascending: true)
          .order('workout_time', ascending: true);

      // Query 2: Get ALL in_progress workouts (regardless of date)
      // These should always show until completed/cancelled
      final inProgressWorkouts = await _supabase
          .from('workouts')
          .select('''
            *,
            creator:user_profiles!user_id(display_name, fitness_level, avatar_id),
            buddy:user_profiles!buddy_id(display_name, fitness_level, avatar_id)
          ''')
          .or('user_id.eq.$currentUserId,buddy_id.eq.$currentUserId')
          .eq('status', 'in_progress')
          .order('workout_started_at', ascending: false);

      // Combine and deduplicate
      final Map<String, Map<String, dynamic>> workoutMap = {};
      
      // Add in_progress first (they take priority)
      for (final workout in inProgressWorkouts) {
        workoutMap[workout['id']] = workout;
      }
      
      // Add scheduled (won't overwrite in_progress due to map)
      for (final workout in scheduledWorkouts) {
        workoutMap[workout['id']] ??= workout;
      }

      final result = workoutMap.values.toList();
      
      // Sort: in_progress first, then by date
      result.sort((a, b) {
        // in_progress always comes first
        if (a['status'] == 'in_progress' && b['status'] != 'in_progress') return -1;
        if (b['status'] == 'in_progress' && a['status'] != 'in_progress') return 1;
        
        // Then by date
        final dateA = a['workout_date'] ?? '';
        final dateB = b['workout_date'] ?? '';
        return dateA.compareTo(dateB);
      });

      if (kDebugMode) print('📋 Found ${result.length} upcoming workouts (${inProgressWorkouts.length} in_progress)');
      return result;
    } catch (e) {
      if (kDebugMode) print('❌ Error getting upcoming workouts: $e');
      return [];
    }
  }

  // Get today's workouts
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

      if (kDebugMode) print('📋 Found ${response.length} workouts for today');
      return List<Map<String, dynamic>>.from(response);
    } catch (e) {
      if (kDebugMode) print('❌ Error getting today\'s workouts: $e');
      return [];
    }
  }

  // Get completed workouts
  Future<List<Map<String, dynamic>>> getCompletedWorkouts({int limit = 20}) async {
    try {
      final currentUserId = _supabase.auth.currentUser?.id;
      if (currentUserId == null) return [];

      final response = await _supabase
          .from('workouts')
          .select('''
            *,
            creator:user_profiles!user_id(display_name),
            buddy:user_profiles!buddy_id(display_name)
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

  // Get workout by ID
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
      if (kDebugMode) print('❌ Error getting workout: $e');
      return null;
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

  // Start workout
  Future<bool> startWorkout(String workoutId) async {
    try {
      final currentUserId = _supabase.auth.currentUser?.id;
      
      await _supabase
          .from('workouts')
          .update({
            'workout_started_at': DateTime.now().toIso8601String(),
            'status': 'in_progress',
            'started_by_user_id': currentUserId,
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

  // Complete workout with duration
  Future<bool> completeWorkoutWithDuration(String workoutId) async {
    try {
      final currentUserId = _supabase.auth.currentUser?.id;
      if (currentUserId == null) return false;
      
      final workout = await _supabase
          .from('workouts')
          .select('workout_started_at, user_id, buddy_id, creator_cancelled, buddy_cancelled')
          .eq('id', workoutId)
          .single();

      final creatorId = workout['user_id'] as String?;
      final buddyId = workout['buddy_id'] as String?;
      final isCreator = currentUserId == creatorId;
      
      // Check if THIS user cancelled - they shouldn't be able to complete!
      final thiUserCancelled = isCreator 
          ? (workout['creator_cancelled'] ?? false)
          : (workout['buddy_cancelled'] ?? false);
      
      if (thiUserCancelled) {
        if (kDebugMode) print('⚠️ User already cancelled - cannot complete');
        return false;
      }

      int? actualDuration;
      if (workout['workout_started_at'] != null) {
        final startTime = DateTime.parse(workout['workout_started_at']);
        actualDuration = DateTime.now().difference(startTime).inMinutes;
      }

      // Update workout - mark as completed
      await _supabase.from('workouts').update({
        'status': 'completed',
        'actual_duration_minutes': actualDuration,
        'workout_completed_at': DateTime.now().toIso8601String(),
        'updated_at': DateTime.now().toIso8601String(),
      }).eq('id', workoutId);

      // Clear active session for this user
      await _supabase
          .from('active_checkin_sessions')
          .delete()
          .eq('user_id', currentUserId);

      if (kDebugMode) print('✅ Workout completed by user $currentUserId');
      return true;
    } catch (e) {
      if (kDebugMode) print('❌ Error completing workout: $e');
      return false;
    }
  }

  // Decline workout invitation
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

  // Cancel workout
  Future<bool> cancelWorkout(String workoutId) async {
    try {
      final currentUserId = _supabase.auth.currentUser?.id;
      if (currentUserId == null) return false;
      
      // Get workout details
      final workout = await _supabase
          .from('workouts')
          .select('user_id, buddy_id, status, creator_cancelled, buddy_cancelled')
          .eq('id', workoutId)
          .single();
      
      final creatorId = workout['user_id'] as String?;
      final buddyId = workout['buddy_id'] as String?;
      final isCreator = currentUserId == creatorId;
      final isBuddy = currentUserId == buddyId;
      
      if (kDebugMode) print('🗑️ User $currentUserId cancelling workout $workoutId (isCreator: $isCreator)');
      
      // Delete ONLY this user's active session
      await _supabase
          .from('active_checkin_sessions')
          .delete()
          .eq('user_id', currentUserId);
      
      if (kDebugMode) print('✅ Deleted session for current user');
      
      // Check if the OTHER person has already cancelled
      final otherCancelled = isCreator 
          ? (workout['buddy_cancelled'] ?? false)
          : (workout['creator_cancelled'] ?? false);
      
      if (otherCancelled) {
        // BOTH users have now cancelled - mark workout as fully cancelled
        await _supabase.from('workouts').update({
          'status': 'cancelled',
          'creator_cancelled': isCreator ? true : (workout['creator_cancelled'] ?? false),
          'buddy_cancelled': isBuddy ? true : (workout['buddy_cancelled'] ?? false),
          'updated_at': DateTime.now().toIso8601String(),
        }).eq('id', workoutId);
        
        if (kDebugMode) print('✅ Both users cancelled - workout fully cancelled');
      } else {
        // Only THIS user cancelled - mark their cancellation, but workout continues
        await _supabase.from('workouts').update({
          'creator_cancelled': isCreator ? true : (workout['creator_cancelled'] ?? false),
          'buddy_cancelled': isBuddy ? true : (workout['buddy_cancelled'] ?? false),
          'updated_at': DateTime.now().toIso8601String(),
          // DON'T change status - the other person is still working out!
        }).eq('id', workoutId);
        
        if (kDebugMode) print('✅ User cancelled their part - other user can still complete');
      }
      
      return true;
    } catch (e) {
      if (kDebugMode) print('❌ Error cancelling workout: $e');
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

  // In WorkoutService, add this method:
  Future<void> cleanupStaleWorkouts() async {
    try {
      final currentUserId = _supabase.auth.currentUser?.id;
      if (currentUserId == null) return;

      // Find workouts that have been in_progress for more than 3 hours
      final threeHoursAgo = DateTime.now().subtract(const Duration(hours: 3));

      final staleWorkouts = await _supabase
          .from('workouts')
          .select('id, workout_started_at')
          .eq('status', 'in_progress')
          .or('user_id.eq.$currentUserId,buddy_id.eq.$currentUserId')
          .lt('workout_started_at', threeHoursAgo.toIso8601String());

      if (staleWorkouts.isEmpty) {
        if (kDebugMode) print('✅ No stale workouts to clean up');
        return;
      }

      if (kDebugMode) print('🧹 Found ${staleWorkouts.length} stale workouts, auto-completing...');

      for (final workout in staleWorkouts) {
        // Auto-complete with 180 minute duration
        await _supabase.from('workouts').update({
          'status': 'completed',
          'actual_duration_minutes': 180,
          'workout_completed_at': DateTime.now().toIso8601String(),
          'notes': '(Auto-completed - workout exceeded 3 hour limit)',
          'updated_at': DateTime.now().toIso8601String(),
        }).eq('id', workout['id']);

        // Also clean up any active sessions for this workout
        await _supabase
            .from('active_checkin_sessions')
            .delete()
            .eq('workout_id', workout['id']);

        if (kDebugMode) print('✅ Auto-completed stale workout: ${workout['id']}');
      }
    } catch (e) {
      if (kDebugMode) print('❌ Error cleaning up stale workouts: $e');
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

  // Get workout stats
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
}