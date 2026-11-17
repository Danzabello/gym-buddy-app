import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:gym_buddy_app/utils/debug_logger.dart';
import 'handshake_service.dart';
import 'package:gym_buddy_app/utils/query_ceilings.dart';
import 'dashboard_refresh.dart';

class WorkoutService {
  /// [userId], [insert] and [client] are test seams; all default to Supabase.
  WorkoutService({this.userId, this.insert, SupabaseClient? client}) : _client = client;
  final String? Function()? userId;
  final Future<void> Function(Map<String, dynamic> row)? insert;
  final SupabaseClient? _client;

  SupabaseClient get _supabase => _client ?? Supabase.instance.client;

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
      final currentUserId = userId != null ? userId!() : _supabase.auth.currentUser?.id;
      if (currentUserId == null) return 'Please sign in again.';
      final dateStr = date.toIso8601String().split('T')[0];
      final row = {
        'user_id': currentUserId,
        'workout_type': workoutType,
        'workout_date': dateStr,
        'workout_time': time,
        'planned_duration_minutes': plannedDurationMinutes ?? 60,
        'status': 'scheduled',
        'buddy_id': buddyId,
        'buddy_status': buddyId != null ? 'pending' : null,
      };
      await (insert ?? (r) => _supabase.from('workouts').insert(r).select().single())(row);
      if (kDebugMode) debugLog('✅ Workout created');
      markStale({AppTab.dashboard, AppTab.schedule});
      return null;
    } catch (e) {
      if (kDebugMode) debugLog('❌ Error creating workout: $e');
      // A plain sentence for the person, never a raw code (the invite cap is the sender's).
      return HandshakeError.from(e).message(name: buddyName);
    }
  }

  Future<bool> deleteWorkout(String workoutId) async {
    try {
      await _supabase.from('workouts').delete().eq('id', workoutId);
      if (kDebugMode) debugLog('✅ Workout deleted');
      markStale({AppTab.dashboard, AppTab.schedule});
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

  /// [strict] rethrows a failed read instead of returning [], so the
  /// dashboard refresh can tell a failure from a real answer.
  Future<List<Map<String, dynamic>>> getTodaysWorkouts({bool strict = false}) async {
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
          .order('workout_time', ascending: true)
          .limit(kDayWorkoutsCeiling);
      if (kDebugMode) debugLog('📋 Found ${response.length} workouts for today');
      return List<Map<String, dynamic>>.from(response);
    } catch (e) {
      if (kDebugMode) debugLog('❌ Error getting today\'s workouts: $e');
      if (strict) rethrow;
      return [];
    }
  }

  /// Ids of the signed-in user's scheduled or in-progress workouts from one
  /// day ago on, soonest first. Invites received and not yet accepted live in
  /// Invitations, so they are left out. Errors are thrown for the caller.
  Future<List<String>> listOpenWorkoutIds({DateTime? now}) async {
    final uid = _supabase.auth.currentUser!.id;
    final since = (now ?? DateTime.now()).toUtc().subtract(const Duration(days: 1)).toIso8601String();
    final rows = await _supabase
        .from('workouts')
        .select('id, buddy_id, buddy_status')
        .or('user_id.eq.$uid,buddy_id.eq.$uid')
        .inFilter('status', ['scheduled', 'in_progress'])
        .gte('planned_at', since)
        .order('planned_at')
        .limit(kOpenWorkoutsCeiling);
    return [
      for (final r in rows)
        if (r['buddy_id'] != uid || r['buddy_status'] == 'accepted') r['id'] as String
    ];
  }

  /// How many completed workouts [uid] took part in, as owner or buddy. One
  /// head request with an exact count: no rows come back, so the number is
  /// right however long the history gets. Throws on failure, like the read
  /// it replaced; the Profile tab's loader catches it.
  Future<int> completedWorkoutCount(String uid) => _supabase
      .from('workouts')
      .count(CountOption.exact)
      .or('user_id.eq.$uid,buddy_id.eq.$uid')
      .eq('status', 'completed');

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
}
