// lib/services/nudge_service.dart
import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:gym_buddy_app/utils/debug_logger.dart';

class NudgeService {
  final SupabaseClient _supabase = Supabase.instance.client;

  static const int _earliestHour = 10; // no nudges before 10am

  /// Returns true if the current user has already sent a nudge
  /// to [targetUserId] today.
  Future<bool> hasNudgedToday(String targetUserId) async {
    try {
      final currentUserId = _supabase.auth.currentUser?.id;
      if (currentUserId == null) return false;

      final today = _todayString();
      final existing = await _supabase
          .from('buddy_nudges')
          .select('id')
          .eq('sender_id', currentUserId)
          .eq('receiver_id', targetUserId)
          .eq('nudge_date', today)
          .maybeSingle();

      return existing != null;
    } catch (e) {
      if (kDebugMode) debugLog('❌ NudgeService.hasNudgedToday: $e');
      return false;
    }
  }

  /// Sends a nudge to [targetUserId].
  /// Returns a [NudgeResult] describing what happened.
  Future<NudgeResult> sendNudge({
    required String targetUserId,
    required String targetDisplayName,
  }) async {
    try {
      final currentUserId = _supabase.auth.currentUser?.id;
      if (currentUserId == null) return NudgeResult.error;

      // ── 1. Time gate ──────────────────────────────────────
      final hour = DateTime.now().hour;
      if (hour < _earliestHour) return NudgeResult.tooEarly;

      // ── 2. One-per-day gate ───────────────────────────────
      final today = _todayString();
      final existing = await _supabase
          .from('buddy_nudges')
          .select('id')
          .eq('sender_id', currentUserId)
          .eq('receiver_id', targetUserId)
          .eq('nudge_date', today)
          .maybeSingle();

      if (existing != null) return NudgeResult.alreadySent;

      // ── 3. Get sender display name ────────────────────────
      final senderProfile = await _supabase
          .from('user_profiles')
          .select('display_name')
          .eq('id', currentUserId)
          .maybeSingle();

      final senderName =
          senderProfile?['display_name'] as String? ?? 'Your buddy';

      // ── 4. Record nudge ───────────────────────────────────
      await _supabase.from('buddy_nudges').insert({
        'sender_id': currentUserId,
        'receiver_id': targetUserId,
        'nudge_date': today,
      });

      // ── 5. Send push via existing edge function ───────────
      await _supabase.functions.invoke(
        'send-notification',
        body: {
          'user_id': targetUserId,
          'title': '🔥 Don\'t break the streak!',
          'body':
              '$senderName is waiting on your check-in — keep it going!',
          'type': 'buddy_nudge',
          'reference_id': currentUserId,
          'batch_key': 'nudge_${currentUserId}_${targetUserId}_$today',
        },
      );

      if (kDebugMode) {
      }

      return NudgeResult.sent;
    } catch (e) {
      if (kDebugMode) debugLog('❌ NudgeService.sendNudge: $e');
      return NudgeResult.error;
    }
  }

  /// Loads which friend IDs have already been nudged today
  /// by the current user.  Returns a Set for O(1) lookup.
  Future<Set<String>> getNudgedTodaySet(List<String> friendIds) async {
    try {
      final currentUserId = _supabase.auth.currentUser?.id;
      if (currentUserId == null || friendIds.isEmpty) return {};

      final today = _todayString();
      final rows = await _supabase
          .from('buddy_nudges')
          .select('receiver_id')
          .eq('sender_id', currentUserId)
          .eq('nudge_date', today)
          .inFilter('receiver_id', friendIds);

      return {for (final r in rows) r['receiver_id'] as String};
    } catch (e) {
      if (kDebugMode) debugLog('❌ NudgeService.getNudgedTodaySet: $e');
      return {};
    }
  }

  String _todayString() {
    final now = DateTime.now();
    return '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';
  }
}

enum NudgeResult { sent, alreadySent, tooEarly, error }