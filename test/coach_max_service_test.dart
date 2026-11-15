import 'package:flutter_test/flutter_test.dart';
import 'package:gym_buddy_app/services/coach_max_service.dart';
import 'package:gym_buddy_app/utils/app_dates.dart';

import 'support/fake_supabase.dart';

const _user = '11111111-1111-4111-8111-111111111111';

void main() {
  /// Requests that would write a schedule row.
  Iterable<String> scheduleWrites(FakeSupabase server) => server.calls
      .where((c) => c.url.pathSegments.last == 'coach_max_schedule' && c.method != 'GET')
      .map((c) => c.method);

  group('CoachMaxService.runDueCoachMaxCheckIn', () {
    test('with no row for today it reads once and writes nothing', () async {
      final server = FakeSupabase()..reply = (_) => [];
      await CoachMaxService(client: server.client).runDueCoachMaxCheckIn(_user);

      expect(server.calls, hasLength(1));
      expect(server.calls.single.method, 'GET');
      expect(server.target(0), 'coach_max_schedule');
      expect(server.query(0)['user_id'], 'eq.$_user');
      expect(server.query(0)['scheduled_date'], 'eq.${localTodayString()}');
    });

    test('a row that is already checked in needs nothing more', () async {
      final server = FakeSupabase()
        ..reply = (_) => [
              {'id': 'row-1', 'has_checked_in': true},
            ];
      await CoachMaxService(client: server.client).runDueCoachMaxCheckIn(_user);
      expect(server.calls, hasLength(1));
    });

    test('a due row leads to check_in_coach_max, and still no schedule write', () async {
      final server = FakeSupabase();
      server.reply = (req) {
        final single = (req.headers['Accept'] ?? '').contains('pgrst.object');
        switch (req.url.pathSegments.last) {
          case 'coach_max_schedule':
            return single
                ? {'scheduled_date': '2020-01-01', 'scheduled_time': '00:00:00', 'has_checked_in': false}
                : [
                    {'id': 'row-1', 'has_checked_in': false},
                  ];
          case 'team_members':
            return [
              {'team_id': 'team-1'},
            ];
          case 'team_streaks':
            return [
              {'id': 'streak-1'},
            ];
          case 'check_in_coach_max':
            return {'checked_in': false, 'reason': 'not_due_yet'};
          default:
            return [];
        }
      };
      await CoachMaxService(client: server.client).runDueCoachMaxCheckIn(_user);

      final rpc = server.calls.lastWhere((c) => c.url.pathSegments.last == 'check_in_coach_max');
      expect(rpc.method, 'POST');
      expect(rpc.body, contains(_user));
      expect(scheduleWrites(server), isEmpty);
    });

    test('a failed read is swallowed', () async {
      final server = FakeSupabase()..down = true;
      await CoachMaxService(client: server.client).runDueCoachMaxCheckIn(_user);
      expect(scheduleWrites(server), isEmpty);
    });
  });

  group('CoachMaxService.initializeCoachMaxForUser', () {
    test('a new team is one ensure_coach_max_team call and no schedule row', () async {
      final server = FakeSupabase()
        ..reply = (_) => {'team_id': 't', 'streak_id': 's', 'created': true};
      expect(await CoachMaxService(client: server.client).initializeCoachMaxForUser(_user), isTrue);
      expect(server.calls, hasLength(1));
      expect(server.target(0), 'ensure_coach_max_team');
    });

    test('an existing team is the same single call', () async {
      final server = FakeSupabase()
        ..reply = (_) => {'team_id': 't', 'streak_id': 's', 'created': false};
      expect(await CoachMaxService(client: server.client).initializeCoachMaxForUser(_user), isTrue);
      expect(server.calls, hasLength(1));
    });

    test('a failed call is false, not thrown', () async {
      final server = FakeSupabase()..down = true;
      expect(await CoachMaxService(client: server.client).initializeCoachMaxForUser(_user), isFalse);
    });
  });
}
