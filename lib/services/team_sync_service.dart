import 'dart:async' show unawaited;
import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:gym_buddy_app/utils/debug_logger.dart';
import 'economy_sync.dart';

/// Short text for a submit_checkin reason code.
String checkinSyncMessage(String? reason) => switch (reason) {
      'credited' => 'Check-ins synced',
      'already_checked_in' => 'Already checked in today.',
      'not_checked_in_today' => 'No check-in today yet.',
      'no_teams' => 'No teams yet.',
      _ => 'Something went wrong. Please try again.',
    };

/// Service to sync check-ins across all teams
/// This ensures that when a user checks in, ALL their teams get the check-in
/// even if the team was created after the check-in happened
class TeamSyncService {
  TeamSyncService({Future<dynamic> Function()? submitCheckin, void Function()? onCredited})
      : _submitCheckin = submitCheckin ?? (() => Supabase.instance.client.rpc('submit_checkin')),
        _onCredited = onCredited ?? (() => unawaited(EconomySync.instance.refresh()));

  final Future<dynamic> Function() _submitCheckin;
  final void Function() _onCredited;

  /// Sync today's check-ins across all user's teams, server-side
  /// (submit_checkin): every member's real check-in for their own local
  /// today is copied onto shared teams missing it. Never creates a first
  /// check-in and pays nothing. Call on home screen load and after a new
  /// buddy team is created.
  Future<Map<String, dynamic>> syncAllTeamsCheckIns() async {
    try {
      final res = Map<String, dynamic>.from(await _submitCheckin() as Map);
      final reason = res['reason'] as String?;
      if (kDebugMode) debugLog('🔄 SYNC: submit_checkin → $reason');
      // A copied row can pay the invitee bonus (_fulfil_invite_reward).
      if (res['credited'] == true) _onCredited();
      return {
        'success': true,
        'message': checkinSyncMessage(reason),
        // The RPC reports whether the caller got new rows, not how many, so
        // this is 1 or 0 and the message carries no number.
        'synced': res['credited'] == true ? 1 : 0,
        'reason': reason,
      };
    } catch (e) {
      if (kDebugMode) debugLog('❌ SYNC ERROR: $e');
      return {
        'success': false,
        'message': checkinSyncMessage(null),
        'synced': 0,
      };
    }
  }
}
