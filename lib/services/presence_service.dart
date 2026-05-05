// lib/services/presence_service.dart

import 'package:supabase_flutter/supabase_flutter.dart';

enum UserPresenceStatus { online, workingOut, offline }

class PresenceService {
  static final PresenceService _instance = PresenceService._internal();
  factory PresenceService() => _instance;
  PresenceService._internal();

  final SupabaseClient _supabase = Supabase.instance.client;
  RealtimeChannel? _channel;

  // Who's currently online — keyed by user_id
  final Map<String, Map<String, dynamic>> _presenceState = {};

  // Callback so the UI can react to changes
  void Function(Map<String, Map<String, dynamic>>)? onPresenceChanged;

  String? get _currentUserId => _supabase.auth.currentUser?.id;

  // ── Join the presence channel ──────────────────────────────
  Future<void> join() async {
    final userId = _currentUserId;
    if (userId == null) return;

    _channel = _supabase.channel(
      'gym_buddy_presence',
      opts: const RealtimeChannelConfig(self: true),
    );

    _channel!
      .onPresenceSync((payload) {
        _syncState();
      })
      .onPresenceJoin((payload) {
        _syncState();
      })
      .onPresenceLeave((payload) {
        _syncState();
      })
      .subscribe(((status, [error]) async {
        if (status == RealtimeSubscribeStatus.subscribed) {
          await _channel!.track({
            'user_id': userId,
            'status': 'online',
            'joined_at': DateTime.now().toIso8601String(),
          });
        }
      }));
  }

  // ── Update status (online / working_out) ──────────────────
  Future<void> setStatus(UserPresenceStatus status) async {
    final userId = _currentUserId;
    if (userId == null || _channel == null) return;

    final statusStr = status == UserPresenceStatus.workingOut
        ? 'working_out'
        : 'online';

    await _channel!.track({
      'user_id': userId,
      'status': statusStr,
      'updated_at': DateTime.now().toIso8601String(),
    });
  }

  // ── Leave the channel ─────────────────────────────────────
  Future<void> leave() async {
    await _channel?.untrack();
    await _supabase.removeChannel(_channel!);
    _channel = null;
    _presenceState.clear();
  }

  // ── Get friends who are working out right now ─────────────
  List<Map<String, dynamic>> getFriendsWorkingOut(List<String> friendIds) {
    return _presenceState.values
        .where((p) =>
            friendIds.contains(p['user_id']) &&
            p['status'] == 'working_out')
        .toList();
  }

  // ── Get all online friends ────────────────────────────────
  List<Map<String, dynamic>> getOnlineFriends(List<String> friendIds) {
    return _presenceState.values
        .where((p) => friendIds.contains(p['user_id']))
        .toList();
  }

  // ── Internal: sync presence state from channel ────────────
  void _syncState() {
    if (_channel == null) return;
    final raw = _channel!.presenceState();
    _presenceState.clear();

    for (final singleState in raw) {
      for (final presence in singleState.presences) {
        final userId = presence.payload['user_id'] as String?;
        if (userId != null) {
          _presenceState[userId] = Map<String, dynamic>.from(presence.payload);
        }
      }
    }

    onPresenceChanged?.call(Map.unmodifiable(_presenceState));
  }
}