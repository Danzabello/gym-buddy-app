import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:gym_buddy_app/utils/debug_logger.dart';

/// Service for managing workout invites
class WorkoutInviteService {
  final _supabase = Supabase.instance.client;

  /// Send a workout invite
  Future<Map<String, dynamic>?> sendInvite({
    required String recipientId,
    required DateTime scheduledFor,
    String? message,
  }) async {
    try {
      final currentUserId = _supabase.auth.currentUser?.id;
      if (currentUserId == null) {
        debugLog('❌ No authenticated user');
        return null;
      }

      debugLog('📤 Sending workout invite...');
      debugLog('   Scheduled: $scheduledFor');
      debugLog('   Message: $message');

      final invite = await _supabase
          .from('workout_invites')
          .insert({
            'sender_id': currentUserId,
            'recipient_id': recipientId,
            'scheduled_for': scheduledFor.toIso8601String(),
            'message': message,
            'status': 'pending',
          })
          .select()
          .single();

      debugLog('✅ Workout invite sent successfully!');
      return invite;
    } catch (e) {
      debugLog('❌ Error sending workout invite: $e');
      return null;
    }
  }

  /// Get pending invites for the current user (as recipient)
  Future<List<Map<String, dynamic>>> getPendingInvites() async {
    try {
      final currentUserId = _supabase.auth.currentUser?.id;
      if (currentUserId == null) return [];


      final invites = await _supabase
          .from('workout_invites')
          .select('''
            *,
            sender:sender_id(id, display_name, avatar_id)
          ''')
          .eq('recipient_id', currentUserId)
          .eq('status', 'pending')
          .order('scheduled_for', ascending: true);

      debugLog('✅ Found ${invites.length} pending invites');
      return List<Map<String, dynamic>>.from(invites);
    } catch (e) {
      debugLog('❌ Error getting pending invites: $e');
      return [];
    }
  }

  /// Get sent invites for the current user (as sender)
  Future<List<Map<String, dynamic>>> getSentInvites() async {
    try {
      final currentUserId = _supabase.auth.currentUser?.id;
      if (currentUserId == null) return [];


      final invites = await _supabase
          .from('workout_invites')
          .select('''
            *,
            recipient:recipient_id(id, display_name, avatar_id)
          ''')
          .eq('sender_id', currentUserId)
          .order('scheduled_for', ascending: true);

      debugLog('✅ Found ${invites.length} sent invites');
      return List<Map<String, dynamic>>.from(invites);
    } catch (e) {
      debugLog('❌ Error getting sent invites: $e');
      return [];
    }
  }

  /// Accept a workout invite
  Future<bool> acceptInvite(String inviteId) async {
    try {
      debugLog('✅ Accepting workout invite: $inviteId');

      final currentUserId = _supabase.auth.currentUser?.id;
      if (currentUserId == null) {
        debugLog('❌ No authenticated user');
        return false;
      }

      // First, get the invite details
      final invite = await _supabase
          .from('workout_invites')
          .select('sender_id, recipient_id, scheduled_for, message')
          .eq('id', inviteId)
          .single();

      final senderId = invite['sender_id'] as String;
      final scheduledFor = DateTime.parse(invite['scheduled_for']);
      final message = invite['message'] as String?;

      // Create the actual workout entry
      // IMPORTANT: user_id must be the current user (recipient who is accepting)
      // buddy_id is the sender who invited them
      final workoutDate = scheduledFor.toIso8601String().split('T')[0];
      final workoutTime = '${scheduledFor.hour.toString().padLeft(2, '0')}:${scheduledFor.minute.toString().padLeft(2, '0')}';

      await _supabase.from('workouts').insert({
        'user_id': currentUserId, // Current user (recipient) creates the workout
        'buddy_id': senderId, // Sender becomes the buddy
        'workout_type': 'Buddy Workout',
        'workout_date': workoutDate,
        'workout_time': workoutTime,
        'planned_duration_minutes': 60, // Default 1 hour
        'status': 'scheduled',
        'buddy_status': 'accepted', // Already accepted since they initiated
        'notes': message,
      });

      debugLog('✅ Created workout entry for accepted invite');

      // Update the invite status
      await _supabase
          .from('workout_invites')
          .update({
            'status': 'accepted',
            'updated_at': DateTime.now().toIso8601String(),
          })
          .eq('id', inviteId);

      debugLog('✅ Workout invite accepted and workout created!');
      return true;
    } catch (e) {
      debugLog('❌ Error accepting invite: $e');
      return false;
    }
  }

  /// Decline a workout invite
  Future<bool> declineInvite(String inviteId) async {
    try {
      debugLog('❌ Declining workout invite: $inviteId');

      await _supabase
          .from('workout_invites')
          .update({
            'status': 'declined',
            'updated_at': DateTime.now().toIso8601String(),
          })
          .eq('id', inviteId);

      debugLog('✅ Workout invite declined');
      return true;
    } catch (e) {
      debugLog('❌ Error declining invite: $e');
      return false;
    }
  }

  /// Delete an invite (for sender to cancel)
  Future<bool> cancelInvite(String inviteId) async {
    try {
      debugLog('🗑️ Canceling workout invite: $inviteId');

      await _supabase
          .from('workout_invites')
          .delete()
          .eq('id', inviteId);

      debugLog('✅ Workout invite canceled');
      return true;
    } catch (e) {
      debugLog('❌ Error canceling invite: $e');
      return false;
    }
  }

  /// Get upcoming accepted workouts from invites
  Future<List<Map<String, dynamic>>> getUpcomingWorkouts() async {
    try {
      final currentUserId = _supabase.auth.currentUser?.id;
      if (currentUserId == null) return [];


      final now = DateTime.now().toIso8601String();

      // Get workouts where user is either sender or recipient
      final invites = await _supabase
          .from('workout_invites')
          .select('''
            *,
            sender:sender_id(id, display_name, avatar_id),
            recipient:recipient_id(id, display_name, avatar_id)
          ''')
          .eq('status', 'accepted')
          .gte('scheduled_for', now)
          .or('sender_id.eq.$currentUserId,recipient_id.eq.$currentUserId')
          .order('scheduled_for', ascending: true)
          .limit(10);

      debugLog('✅ Found ${invites.length} upcoming workouts');
      return List<Map<String, dynamic>>.from(invites);
    } catch (e) {
      debugLog('❌ Error getting upcoming workouts: $e');
      return [];
    }
  }
}