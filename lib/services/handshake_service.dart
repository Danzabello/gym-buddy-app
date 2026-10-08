import 'package:supabase_flutter/supabase_flutter.dart';

/// Client side of the server-driven workout handshake. The server decides the
/// state (get_workout_card); every action is one RPC and the answer is the
/// truth. No workouts column is written from here.

typedef Rpc = Future<dynamic> Function(String fn, Map<String, dynamic> params);

Future<dynamic> _supabaseRpc(String fn, Map<String, dynamic> params) =>
    Supabase.instance.client.rpc(fn, params: params);

/// A server error code (RAISE EXCEPTION 'code') plus its DETAIL, if any.
class HandshakeError implements Exception {
  final String code;
  final String? detail;
  const HandshakeError(this.code, [this.detail]);

  factory HandshakeError.from(Object e) {
    if (e is HandshakeError) return e;
    if (e is PostgrestException) {
      final m = e.message.trim();
      final code = _messages.keys.firstWhere(m.contains, orElse: () => m);
      return HandshakeError(code, e.details?.toString());
    }
    return const HandshakeError('unknown');
  }

  /// Seconds left for nudge_too_soon (the DETAIL), else null.
  int? get secondsLeft => int.tryParse(detail ?? '');

  String message({String? name}) {
    final who = name ?? 'Your buddy';
    switch (code) {
      case 'nudge_too_soon':
        final s = secondsLeft;
        return s == null
            ? 'You nudged a moment ago. Try again soon.'
            : 'You can nudge again in ${clockText(Duration(seconds: s))}.';
      case 'invite_cap_reached':
        return '$who has too many invites waiting. Try again later.';
      default:
        return _messages[code] ?? 'Something went wrong. Try again.';
    }
  }
}

const _messages = <String, String>{
  'not_authenticated': 'Please sign in again.',
  'not_found': 'That workout is no longer there.',
  'not_participant': 'That workout is not yours.',
  'not_invitee': 'Only the invited person can do that.',
  'not_creator': 'Only the person who planned it can do that.',
  'wrong_state': 'This workout just changed. Showing the latest.',
  'window_closed': 'The time for this workout has passed.',
  'too_early': 'It is too early for that.',
  'already_in_workout': 'Finish or leave your current workout first.',
  'nudge_too_soon': '',
  'invite_cap_reached': '',
  'daily_workout_limit_reached': 'You have reached the workout limit for today.',
};

/// mm:ss, or h:mm:ss from an hour up.
String clockText(Duration d) {
  final s = d.isNegative ? 0 : d.inSeconds;
  final h = s ~/ 3600, m = s % 3600 ~/ 60, sec = s % 60;
  final mm = m.toString().padLeft(2, '0'), ss = sec.toString().padLeft(2, '0');
  return h > 0 ? '$h:$mm:$ss' : '$mm:$ss';
}

/// Server time on this phone: offset = server_now - local now, taken when a
/// card arrives. Timers tick locally from [now], never from DateTime.now().
class ServerClock {
  ServerClock([DateTime Function()? local]) : _local = local ?? DateTime.now;
  final DateTime Function() _local;
  Duration offset = Duration.zero;

  void sync(DateTime serverNow) => offset = serverNow.difference(_local());
  DateTime now() => _local().add(offset);
}

/// complete_workout worked but finish_checkin_session did not: retry with
/// `finish(..., alreadyCompleted: true)`.
class CreditPending implements Exception {
  final HandshakeError cause;
  const CreditPending(this.cause);
}

class WorkoutCardData {
  final String state;
  final Map<String, dynamic>? workout;
  final List<Map<String, dynamic>> invites;
  final int openInviteCount;
  final DateTime serverNow;
  const WorkoutCardData({
    required this.state,
    this.workout,
    this.invites = const [],
    this.openInviteCount = 0,
    required this.serverNow,
  });

  /// Keys are read by name; jsonb key order is not stable.
  factory WorkoutCardData.fromJson(Map<String, dynamic> j) => WorkoutCardData(
        state: j['state'] as String? ?? 'none',
        workout: j['workout'] == null
            ? null
            : Map<String, dynamic>.from(j['workout'] as Map),
        invites: [
          for (final i in (j['invites'] as List? ?? const []))
            Map<String, dynamic>.from(i as Map)
        ],
        openInviteCount: (j['open_invite_count'] as num?)?.toInt() ?? 0,
        serverNow: DateTime.parse(j['server_now'] as String),
      );
}

class HandshakeService {
  HandshakeService({Rpc? rpc}) : _rpc = rpc ?? _supabaseRpc;
  final Rpc _rpc;

  Future<Map<String, dynamic>> _call(String fn, Map<String, dynamic> p) async {
    try {
      final r = await _rpc(fn, p);
      return r is Map ? Map<String, dynamic>.from(r) : <String, dynamic>{};
    } catch (e) {
      throw HandshakeError.from(e);
    }
  }

  Future<WorkoutCardData> card([String? id]) async =>
      WorkoutCardData.fromJson(await _call('get_workout_card', {'p_workout_id': id}));

  Future<Map<String, dynamic>> accept(String id, {bool force = false}) =>
      _call('accept_workout_invite', {'p_workout_id': id, 'p_force': force});
  Future<Map<String, dynamic>> decline(String id) =>
      _call('decline_workout_invite', {'p_workout_id': id});
  Future<Map<String, dynamic>> imHere(String id) => _call('im_here', {'p_workout_id': id});
  Future<Map<String, dynamic>> cantMakeIt(String id) =>
      _call('cant_make_it', {'p_workout_id': id});
  Future<Map<String, dynamic>> goSolo(String id) => _call('go_solo', {'p_workout_id': id});
  Future<Map<String, dynamic>> cancel(String id) =>
      _call('cancel_workout', {'p_workout_id': id});
  Future<Map<String, dynamic>> leave(String id) =>
      _call('leave_workout', {'p_workout_id': id});
  Future<Map<String, dynamic>> nudge(String id) =>
      _call('nudge_workout', {'p_workout_id': id});
  Future<Map<String, dynamic>> changeTime(String id, DateTime date, String time) =>
      _call('change_workout_time', {
        'p_workout_id': id,
        'p_date': date.toIso8601String().split('T')[0],
        'p_time': time,
      });

  /// Finish = complete_workout, THEN finish_checkin_session (the partner is
  /// only credited by the second). Pass [alreadyCompleted] to retry just the
  /// second after it failed, so nothing is completed or credited twice. The
  /// only place the client calls the credit path.
  Future<Map<String, dynamic>> finish(String id, int minutes,
      {bool alreadyCompleted = false}) async {
    if (!alreadyCompleted) {
      await _call('complete_workout', {'p_workout_id': id, 'p_actual_minutes': minutes});
    }
    try {
      return await _call('finish_checkin_session', {'p_workout_id': id});
    } on HandshakeError catch (e) {
      throw CreditPending(e);
    }
  }
}
