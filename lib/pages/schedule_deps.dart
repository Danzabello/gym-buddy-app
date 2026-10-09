import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../services/coin_service.dart';
import '../services/handshake_service.dart';
import '../services/team_streak_service.dart';
import '../widgets/completed_workouts_section.dart';
import 'finish_flow.dart';
import '../widgets/workout_schedule_card.dart';

typedef Unsubscribe = void Function();

/// One private 'workouts' channel shared by every open schedule page (the
/// join policy is for that exact topic, so it can only be joined once).
class WorkoutsFeed {
  static final _listeners = <VoidCallback>{};
  static RealtimeChannel? _channel;

  static Unsubscribe listen(VoidCallback onChange) {
    final client = Supabase.instance.client;
    _listeners.add(onChange);
    _channel ??= client
        .channel('workouts', opts: const RealtimeChannelConfig(private: true))
        .onPostgresChanges(
            event: PostgresChangeEvent.all,
            schema: 'public',
            table: 'workouts',
            callback: (_) {
              for (final l in [..._listeners]) {
                l();
              }
            })
        .subscribe();
    return () {
      _listeners.remove(onChange);
      if (_listeners.isEmpty && _channel != null) {
        client.removeChannel(_channel!);
        _channel = null;
      }
    };
  }
}

/// Everything the schedule pages need from the outside world, so tests can
/// hand them fakes.
class ScheduleDeps {
  final HandshakeService svc;
  final Unsubscribe Function(VoidCallback onChange) listen;
  final Future<Person> Function() loadMe;
  final Future<int> Function() loadStreak;

  /// Ids of my open workouts (scheduled or running), earliest first.
  final Future<List<String>> Function() listIds;

  /// The "Recent completed workouts" section at the bottom of the list.
  final Widget Function(int refreshTrigger) completed;

  /// What happens after a finish succeeds (celebration, streak sheet, ...).
  final FinishHooks? finishHooks;

  const ScheduleDeps({
    required this.svc,
    required this.listen,
    required this.loadMe,
    required this.loadStreak,
    required this.listIds,
    required this.completed,
    this.finishHooks,
  });

  factory ScheduleDeps.live() {
    final client = Supabase.instance.client;
    return ScheduleDeps(
      svc: HandshakeService(),
      listen: WorkoutsFeed.listen,
      completed: (t) => CompletedWorkoutsSection(refreshTrigger: t),
      loadMe: () async {
        final uid = client.auth.currentUser!.id;
        final row = await client
            .from('user_profiles').select('display_name, avatar_id').eq('id', uid).single();
        final hex = (await CoinService().getEquippedColorHexForUsers([uid]))[uid];
        return Person(
            name: row['display_name'] as String?,
            avatarId: row['avatar_id'] as String?,
            ring: ringFromHex(hex));
      },
      loadStreak: () async => (await TeamStreakService().getAllUserStreaks())
          .fold<int>(0, (m, s) => s.currentStreak > m ? s.currentStreak : m),
      listIds: () async {
        final uid = client.auth.currentUser!.id;
        final since = DateTime.now().toUtc().subtract(const Duration(days: 1)).toIso8601String();
        final rows = await client
            .from('workouts')
            .select('id, buddy_id, buddy_status')
            .or('user_id.eq.$uid,buddy_id.eq.$uid')
            .inFilter('status', ['scheduled', 'in_progress'])
            .gte('planned_at', since)
            .order('planned_at');
        // invites I received and have not accepted live in Invitations, not here
        return [
          for (final r in rows)
            if (r['buddy_id'] != uid || r['buddy_status'] == 'accepted') r['id'] as String
        ];
      },
    );
  }
}
