import 'package:flutter_test/flutter_test.dart';
import 'package:gym_buddy_app/services/handshake_service.dart';
import 'package:gym_buddy_app/services/invite_service.dart';
import 'package:gym_buddy_app/services/tab_refresh.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Which tabs are marked stale, in page order.
List<AppTab> staleTabs() => [for (final t in AppTab.values) if (tabRefresh[t]!.stale) t];

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    for (final r in tabRefresh.values) {
      r.stale = false;
    }
  });

  group('invite redeem', () {
    Future<void> redeem({required bool teamMade}) => InviteService().redeem(
          '3F9A21BC',
          userId: 'me',
          retryDelay: Duration.zero,
          rpc: (fn, _) async {
            if (fn == 'accept_invite') return 'inviter-1';
            if (teamMade) return null;
            throw StateError('create_invite_team failed');
          },
        );

    test('marks the dashboard, Friends and Profile when the team is made', () async {
      await redeem(teamMade: true);
      expect(staleTabs(), [AppTab.friends, AppTab.dashboard, AppTab.profile]);
    });

    test('marks nothing when every team attempt failed', () async {
      await redeem(teamMade: false);
      expect(staleTabs(), isEmpty);
    });
  });

  group('handshake actions', () {
    HandshakeService svc(Map<String, dynamic> result) =>
        HandshakeService(rpc: (fn, p) async => result);

    test('an accept that only reports an overlap marks nothing', () async {
      await svc({'state': 'overlap', 'with_workout_id': 'w2'}).accept('w1');
      expect(staleTabs(), isEmpty);
    });

    for (final result in ['nothing_to_finish', 'too_early']) {
      test('a finish with result $result marks nothing', () async {
        await svc({'result': result, 'checked_in': 0, 'teams': []}).finish('w1', 50, alreadyCompleted: true);
        expect(staleTabs(), isEmpty);
      });
    }

    test('a successful accept marks the dashboard and Schedule', () async {
      await svc({'state': 'accepted'}).accept('w1');
      expect(staleTabs(), [AppTab.schedule, AppTab.dashboard]);
    });

    test('a credited finish marks the dashboard and Schedule', () async {
      await svc({'result': 'credited', 'checked_in': 1, 'teams': []}).finish('w1', 50, alreadyCompleted: true);
      expect(staleTabs(), [AppTab.schedule, AppTab.dashboard]);
    });

    test('the card read marks nothing', () async {
      await svc({'state': 'none', 'invites': [], 'open_invite_count': 0, 'server_now': '2026-11-17T12:00:00Z'})
          .card();
      expect(staleTabs(), isEmpty);
    });
  });
}
