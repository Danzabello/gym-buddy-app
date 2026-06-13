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

  Future<bool> _manualCheckActiveWorkout(String userId) async {
    try {
      final sessions = await _supabase
          .from('active_checkin_sessions')
          .select('id')
          .eq('user_id', userId)
          .limit(1);
      if (sessions.isNotEmpty) return true;
      final workouts = await _supabase
          .from('workouts')
          .select('id')
          .eq('status', 'in_progress')
          .or('and(user_id.eq.$userId,creator_joined.eq.true),started_by_user_id.eq.$userId')
          .limit(1);
      return workouts.isNotEmpty;
    } catch (e) {
      if (kDebugMode) debugLog('❌ Error in manual check: $e');
      return false;
    }
  }

  Future<List<Map<String, dynamic>>> getWorkoutsAwaitingCreatorJoin() async {
    try {
      final currentUserId = _supabase.auth.currentUser?.id;
      if (currentUserId == null) return [];
      final result = await _supabase.rpc(
        'get_workouts_awaiting_creator_join',
        params: {'creator_id': currentUserId},
      );
      if (kDebugMode) debugLog('📋 Found ${result.length} workouts awaiting creator join');
      return List<Map<String, dynamic>>.from(result);
    } catch (e) {
      if (kDebugMode) debugLog('❌ Error getting awaiting workouts: $e');
      return await _manualGetAwaitingWorkouts();
    }
  }

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
      if (kDebugMode) debugLog('❌ Error in manual awaiting query: $e');
      return [];
    }
  }

  Future<bool> acceptWorkoutInvitation(String workoutId) async {
    try {
      final currentUserId = _supabase.auth.currentUser?.id;
      if (currentUserId == null) return false;
      // ✅ READY CHECK: accepting no longer starts the workout.
      // Both users must confirm ready before the timer begins.
      await _supabase.from('workouts').update({
        'buddy_status': 'accepted',
        'updated_at': DateTime.now().toUtc().toIso8601String(),
      }).eq('id', workoutId);
      if (kDebugMode) debugLog('✅ Invitation accepted — waiting for ready check');
      return true;
    } catch (e) {
      if (kDebugMode) debugLog('❌ Error accepting invitation: $e');
      return false;
    }
  }

  Future<Map<String, dynamic>> creatorJoinWorkout(String workoutId) async {
    try {
      final currentUserId = _supabase.auth.currentUser?.id;
      if (currentUserId == null) return {'success': false, 'error': 'Not logged in'};
      final workout = await _supabase
          .from('workouts')
          .select('*, creator:user_id(display_name), buddy:buddy_id(display_name)')
          .eq('id', workoutId)
          .single();
      final status = workout['status'];
      final startedAt = workout['workout_started_at'];
      final plannedDuration = workout['planned_duration_minutes'] ?? 30;
      final creatorJoined = workout['creator_joined'] ?? false;
      if (status != 'in_progress') return {'success': false, 'error': 'Workout not in progress'};
      if (creatorJoined) return {'success': false, 'error': 'Already joined'};
      if (startedAt == null) return {'success': false, 'error': 'Workout not started yet'};
      final startTime = DateTime.parse(startedAt);
      final joinWindowMinutes = plannedDuration ~/ 4;
      final joinWindowEnd = startTime.add(Duration(minutes: joinWindowMinutes));
      final now = DateTime.now();
      if (now.isAfter(joinWindowEnd)) return {'success': false, 'error': 'Join window expired'};
      final elapsedMinutes = now.difference(startTime).inMinutes;
      final remainingMinutes = plannedDuration - elapsedMinutes;
      final workoutType = workout['workout_type'] ?? 'Workout';
      await _supabase.from('workouts').update({
        'creator_joined': true,
        'creator_joined_at': now.toIso8601String(),
        'updated_at': now.toIso8601String(),
      }).eq('id', workoutId);
      await _supabase.from('active_checkin_sessions').upsert({
        'user_id': currentUserId,
        'started_at': now.toUtc().toIso8601String(),
        'planned_duration': remainingMinutes > 0 ? remainingMinutes : 5,
        'workout_type': workoutType,
        'workout_emoji': _getWorkoutEmoji(workoutType),
        'workout_id': workoutId,
      });
      if (kDebugMode) debugLog('✅ Creator joined workout with $remainingMinutes minutes remaining');
      return {
        'success': true,
        'remainingMinutes': remainingMinutes,
        'workoutType': workoutType,
        'emoji': _getWorkoutEmoji(workoutType),
      };
    } catch (e) {
      if (kDebugMode) debugLog('❌ Error joining workout: $e');
      return {'success': false, 'error': 'Could not join workout. Please try again.'};
    }
  }

  Future<void> markJoinPopupShown(String workoutId) async {
    try {
      await _supabase.from('workouts').update({
        'creator_popup_shown': true,
        'updated_at': DateTime.now().toIso8601String(),
      }).eq('id', workoutId);
    } catch (e) {
      if (kDebugMode) debugLog('❌ Error marking popup shown: $e');
    }
  }

  Future<Map<String, dynamic>> getCreatorWorkoutStatus(String workoutId) async {
    try {
      final currentUserId = _supabase.auth.currentUser?.id;
      if (currentUserId == null) return {'status': 'error'};
      final workout = await _supabase
          .from('workouts')
          .select('*, buddy:user_profiles!buddy_id(display_name)')
          .eq('id', workoutId)
          .single();
      if (workout['creator_joined'] == true) return {'status': 'joined', 'workout': workout};
      if (workout['status'] == 'completed') {
        return {
          'status': 'buddy_completed',
          'workout': workout,
          'message': '${workout['buddy']?['display_name'] ?? 'Your buddy'} completed the workout and helped the streak grow! 🎉',
        };
      }
      if (workout['status'] == 'in_progress' && workout['workout_started_at'] != null) {
        final startedAt = DateTime.parse(workout['workout_started_at']);
        final plannedDuration = workout['planned_duration_minutes'] as int;
        final joinWindowMinutes = plannedDuration ~/ 4;
        final joinWindowEnd = startedAt.add(Duration(minutes: joinWindowMinutes));
        final now = DateTime.now();
        if (now.isBefore(joinWindowEnd)) {
          return {
            'status': 'waiting_to_join',
            'workout': workout,
            'join_window_remaining_seconds': joinWindowEnd.difference(now).inSeconds,
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
      if (kDebugMode) debugLog('❌ Error getting creator workout status: $e');
      return {'status': 'error'};
    }
  }

  // ============================================================
  // MUTUAL READY CHECK
  // ============================================================

  /// Creator confirms ready — sets 30-min expiry window
  Future<String?> setCreatorReady({
    required String workoutId,
    required bool ready,
  }) async {
    try {
      if (ready) {
        await _supabase.from('workouts').update({
          'creator_ready': true,
          'ready_expires_at': DateTime.now()
              .add(const Duration(minutes: 30))
              .toUtc()
              .toIso8601String(),
        }).eq('id', workoutId);
        if (kDebugMode) debugLog('✅ Creator marked ready for workout $workoutId');
      } else {
        await _supabase.from('workouts').update({
          'creator_ready': false,
          'ready_expires_at': null,
        }).eq('id', workoutId);
        if (kDebugMode) debugLog('✅ Creator cancelled ready for workout $workoutId');
      }
      return null;
    } catch (e) {
      if (kDebugMode) debugLog('❌ Error in setCreatorReady: $e');
      return 'Could not update workout. Please try again.';
    }
  }

  /// Buddy confirms ready — starts workout for both simultaneously
  /// Sets creator_joined:true so creator skips the join window entirely
  Future<String?> setBuddyReady({required String workoutId}) async {
    try {
      final currentUserId = _supabase.auth.currentUser?.id;
      if (currentUserId == null) return 'Not logged in';

      final now = DateTime.now().toUtc().toIso8601String();

      // Fetch workout for active session details
      final workout = await _supabase
          .from('workouts')
          .select('planned_duration_minutes, workout_type')
          .eq('id', workoutId)
          .single();

      final plannedDuration = workout['planned_duration_minutes'] ?? 30;
      final workoutType = workout['workout_type'] ?? 'Workout';

      // Transition to in_progress — creator_joined:true skips join window on creator's card
      await _supabase.from('workouts').update({
        'buddy_ready': true,
        'status': 'in_progress',
        'workout_started_at': now,
        'started_by_user_id': currentUserId,
        'creator_joined': true,
      }).eq('id', workoutId);

      // Create active session for the buddy
      await _supabase.from('active_checkin_sessions').upsert({
        'user_id': currentUserId,
        'started_at': now,
        'planned_duration': plannedDuration,
        'workout_type': workoutType,
        'workout_emoji': _getWorkoutEmoji(workoutType),
        'workout_id': workoutId,
      });

      if (kDebugMode) debugLog('✅ Both confirmed ready — workout $workoutId started');
      return null;
    } catch (e) {
      if (kDebugMode) debugLog('❌ Error in setBuddyReady: $e');
      return 'Could not update workout. Please try again.';
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
      return 'Could not save workout. Please try again.';
    }
  }

  Future<bool> startWorkout(String workoutId) async {
    try {
      final currentUserId = _supabase.auth.currentUser?.id;
      await _supabase.from('workouts').update({
        'workout_started_at': DateTime.now().toUtc().toIso8601String(),
        'status': 'in_progress',
        'started_by_user_id': currentUserId,
        'updated_at': DateTime.now().toUtc().toIso8601String(),
      }).eq('id', workoutId);
      if (kDebugMode) debugLog('✅ Workout started');
      return true;
    } catch (e) {
      if (kDebugMode) debugLog('❌ Error starting workout: $e');
      return false;
    }
  }

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
      final thisUserCancelled = isCreator
          ? (workout['creator_cancelled'] ?? false)
          : (workout['buddy_cancelled'] ?? false);
      if (thisUserCancelled) {
        if (kDebugMode) debugLog('⚠️ User already cancelled — cannot complete');
        return false;
      }
      int? actualDuration;
      if (workout['workout_started_at'] != null) {
        final startTime = DateTime.parse(workout['workout_started_at']);
        actualDuration = DateTime.now().difference(startTime).inMinutes;
      }
      await _supabase.from('workouts').update({
        'status': 'completed',
        'actual_duration_minutes': actualDuration,
        'workout_completed_at': DateTime.now().toIso8601String(),
        'updated_at': DateTime.now().toIso8601String(),
      }).eq('id', workoutId);
      if (!isCreator && buddyId != null) {
        await _supabase.from('workouts').update({
          'buddy_completed_at': DateTime.now().toUtc().toIso8601String(),
        }).eq('id', workoutId);
      }
      await _supabase.from('active_checkin_sessions').delete().eq('user_id', currentUserId);
      return true;
    } catch (e) {
      if (kDebugMode) debugLog('❌ Error completing workout: $e');
      return false;
    }
  }

  Future<bool> declineWorkoutInvitation(String workoutId) async {
    try {
      await _supabase.from('workouts').update({
        'buddy_status': 'declined',
        'updated_at': DateTime.now().toIso8601String(),
      }).eq('id', workoutId);
      if (kDebugMode) debugLog('✅ Workout invitation declined');
      return true;
    } catch (e) {
      if (kDebugMode) debugLog('❌ Error declining invitation: $e');
      return false;
    }
  }

  Future<bool> cancelWorkout(String workoutId) async {
    try {
      final currentUserId = _supabase.auth.currentUser?.id;
      if (currentUserId == null) return false;
      final workout = await _supabase
          .from('workouts')
          .select('user_id, buddy_id, status, creator_cancelled, buddy_cancelled')
          .eq('id', workoutId)
          .single();
      final creatorId = workout['user_id'] as String?;
      final buddyId = workout['buddy_id'] as String?;
      final isCreator = currentUserId == creatorId;
      final isBuddy = currentUserId == buddyId;
      await _supabase.from('active_checkin_sessions').delete().eq('user_id', currentUserId);
      if (kDebugMode) debugLog('✅ Deleted session for current user');
      final otherCancelled = isCreator
          ? (workout['buddy_cancelled'] ?? false)
          : (workout['creator_cancelled'] ?? false);
      if (otherCancelled) {
        await _supabase.from('workouts').update({
          'status': 'cancelled',
          'creator_cancelled': isCreator ? true : (workout['creator_cancelled'] ?? false),
          'buddy_cancelled': isBuddy ? true : (workout['buddy_cancelled'] ?? false),
          'updated_at': DateTime.now().toIso8601String(),
        }).eq('id', workoutId);
        if (kDebugMode) debugLog('✅ Both users cancelled — workout fully cancelled');
      } else if (buddyId == null) {
        await _supabase.from('workouts').update({
          'status': 'cancelled',
          'creator_cancelled': true,
          'updated_at': DateTime.now().toIso8601String(),
        }).eq('id', workoutId);
        if (kDebugMode) debugLog('✅ Solo workout cancelled');
      } else {
        await _supabase.from('workouts').update({
          'creator_cancelled': isCreator ? true : (workout['creator_cancelled'] ?? false),
          'buddy_cancelled': isBuddy ? true : (workout['buddy_cancelled'] ?? false),
          'updated_at': DateTime.now().toIso8601String(),
        }).eq('id', workoutId);
        if (kDebugMode) debugLog('✅ User cancelled their part — other user can still complete');
      }
      return true;
    } catch (e) {
      if (kDebugMode) debugLog('❌ Error cancelling workout: $e');
      return false;
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

  Future<bool> updateWorkoutStatus(String workoutId, String status) async {
    try {
      await _supabase.from('workouts').update({
        'status': status,
        'updated_at': DateTime.now().toIso8601String(),
      }).eq('id', workoutId);
      if (kDebugMode) debugLog('✅ Workout status updated to: $status');
      return true;
    } catch (e) {
      if (kDebugMode) debugLog('❌ Error updating workout: $e');
      return false;
    }
  }

  // ============================================================
  // CLEANUP
  // ============================================================

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
        if (kDebugMode) debugLog('✅ No timed-out workouts found');
        return;
      }
      if (kDebugMode) debugLog('⏰ Found ${timedOutWorkouts.length} timed-out workouts, auto-completing...');
      for (final workout in timedOutWorkouts) {
        final startedAt = DateTime.parse(workout['workout_started_at']);
        final existingNotes = workout['notes'] as String? ?? '';
        await _supabase.from('workouts').update({
          'status': 'completed',
          'workout_completed_at': startedAt.add(const Duration(hours: 3)).toIso8601String(),
          'actual_duration_minutes': 180,
          'updated_at': DateTime.now().toIso8601String(),
          'notes': existingNotes.isEmpty
              ? '(Auto-completed after 3 hours)'
              : '$existingNotes (Auto-completed after 3 hours)',
        }).eq('id', workout['id']);
        if (kDebugMode) debugLog('✅ Auto-completed workout: ${workout['id']}');
      }
    } catch (e) {
      if (kDebugMode) debugLog('❌ Error auto-completing workouts: $e');
    }
  }

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
        if (workout == null ||
            workout['status'] == 'cancelled' ||
            workout['status'] == 'completed') {
          await _supabase.from('active_checkin_sessions').delete().eq('id', session['id']);
          if (kDebugMode) debugLog('🧹 Cleaned up orphaned session: ${session['id']}');
        }
      }
    } catch (e) {
      if (kDebugMode) debugLog('⚠️ Error cleaning up sessions: $e');
    }
  }

  Future<void> cleanupStaleWorkouts() async {
    try {
      final currentUserId = _supabase.auth.currentUser?.id;
      if (currentUserId == null) return;
      final threeHoursAgo = DateTime.now().subtract(const Duration(hours: 3));
      final staleWorkouts = await _supabase
          .from('workouts')
          .select('id, workout_started_at')
          .eq('status', 'in_progress')
          .or('user_id.eq.$currentUserId,buddy_id.eq.$currentUserId')
          .lt('workout_started_at', threeHoursAgo.toIso8601String());
      if (staleWorkouts.isEmpty) {
        if (kDebugMode) debugLog('✅ No stale workouts to clean up');
        return;
      }
      if (kDebugMode) debugLog('🧹 Found ${staleWorkouts.length} stale workouts, auto-completing...');
      for (final workout in staleWorkouts) {
        await _supabase.from('workouts').update({
          'status': 'completed',
          'actual_duration_minutes': 180,
          'workout_completed_at': DateTime.now().toIso8601String(),
          'notes': '(Auto-completed — workout exceeded 3 hour limit)',
          'updated_at': DateTime.now().toIso8601String(),
        }).eq('id', workout['id']);
        await _supabase
            .from('active_checkin_sessions')
            .delete()
            .eq('workout_id', workout['id']);
        if (kDebugMode) debugLog('✅ Auto-completed stale workout: ${workout['id']}');
      }
    } catch (e) {
      if (kDebugMode) debugLog('❌ Error cleaning up stale workouts: $e');
    }
  }

  // ============================================================
  // QUERIES
  // ============================================================

  Future<List<Map<String, dynamic>>> getUpcomingWorkouts() async {
    try {
      final currentUserId = _supabase.auth.currentUser?.id;
      if (currentUserId == null) return [];
      final today = DateTime.now().toIso8601String().split('T')[0];
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
      final Map<String, Map<String, dynamic>> workoutMap = {};
      for (final w in inProgressWorkouts) { workoutMap[w['id']] = w; }
      for (final w in scheduledWorkouts) { workoutMap[w['id']] ??= w; }
      final result = workoutMap.values.toList();
      result.sort((a, b) {
        if (a['status'] == 'in_progress' && b['status'] != 'in_progress') return -1;
        if (b['status'] == 'in_progress' && a['status'] != 'in_progress') return 1;
        return (a['workout_date'] ?? '').compareTo(b['workout_date'] ?? '');
      });

      result.removeWhere((w) {
        final iAmCreator = w['user_id'] == currentUserId;

        // ── Scheduled: any cancel or decline kills it for BOTH sides ──
        if (w['status'] == 'scheduled') {
          return (w['creator_cancelled'] ?? false) ||
              (w['buddy_cancelled'] ?? false) ||
              w['buddy_status'] == 'declined';
        }

        // ── In progress: fair cancel — only hide from whoever cancelled ──
        return iAmCreator
            ? (w['creator_cancelled'] ?? false)
            : (w['buddy_cancelled'] ?? false);
      });

      if (kDebugMode) debugLog('📋 Found ${result.length} upcoming workouts');
      return result;
    } catch (e) {
      if (kDebugMode) debugLog('❌ Error getting upcoming workouts: $e');
      return [];
    }
  }

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

  // ============================================================
  // HELPERS
  // ============================================================

  String _getWorkoutEmoji(String? workoutType) {
    switch (workoutType?.toLowerCase()) {
      case 'cardio':      return '🏃';
      case 'strength':    return '💪';
      case 'hiit':        return '⚡';
      case 'leg day':
      case 'lower body':  return '🦵';
      case 'upper body':  return '💪';
      case 'full body':   return '🏋️';
      case 'yoga':        return '🧘';
      default:            return '🏋️';
    }
  }
}