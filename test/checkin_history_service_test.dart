import 'package:flutter_test/flutter_test.dart';
import 'package:gym_buddy_app/services/checkin_history_service.dart';
import 'package:gym_buddy_app/services/friend_service.dart';
import 'package:gym_buddy_app/utils/query_ceilings.dart';

import 'support/fake_supabase.dart';

const _me = '11111111-1111-4111-8111-111111111111';
const _friend = '22222222-2222-4222-8222-222222222222';

void main() {
  late FakeSupabase server;
  setUp(() async {
    server = FakeSupabase();
    await server.signIn(_me);
  });

  group('CheckInHistoryService', () {
    test('myCheckInDatesSince sends the week ceiling and de-duplicates', () async {
      server.reply = (_) => [
            {'check_in_date': '2026-11-14'},
            {'check_in_date': '2026-11-14'},
            {'check_in_date': null},
            {'check_in_date': '2026-11-13'},
          ];
      final dates = await CheckInHistoryService(client: server.client).myCheckInDatesSince('2026-11-08');
      expect(dates, {'2026-11-14', '2026-11-13'});
      expect(server.target(0), 'daily_team_checkins');
      final q = server.query(0);
      expect(q['select'], 'check_in_date');
      expect(q['user_id'], 'eq.$_me');
      expect(q['check_in_date'], 'gte.2026-11-08');
      expect(q['order'], startsWith('check_in_date.desc'));
      expect(q['limit'], '$kWeekCheckInsCeiling');
    });

    test('myCheckInDatesSince sends nothing when signed out', () async {
      final out = FakeSupabase();
      expect(await CheckInHistoryService(client: out.client).myCheckInDatesSince('2026-11-08'), isEmpty);
      expect(out.calls, isEmpty);
    });

    test('checkInDatesSince reads the friend with the month ceiling', () async {
      server.reply = (_) => [
            {'check_in_date': '2026-11-01'},
            {'check_in_date': '2026-11-01'},
          ];
      final dates = await CheckInHistoryService(client: server.client).checkInDatesSince(_friend, '2026-10-16');
      expect(dates, {'2026-11-01'});
      expect(server.target(0), 'daily_team_checkins');
      final q = server.query(0);
      expect(q['user_id'], 'eq.$_friend');
      expect(q['check_in_date'], 'gte.2026-10-16');
      expect(q['order'], startsWith('check_in_date.desc'));
      expect(q['limit'], '$kMonthCheckInsCeiling');
    });

    test('friendsCheckedInOn selects user_id, filters and limits', () async {
      server.reply = (_) => [
            {'user_id': _friend},
            {'user_id': _friend},
          ];
      final ids = await CheckInHistoryService(client: server.client).friendsCheckedInOn('2026-11-15', [_friend, 'x']);
      expect(ids, {_friend});
      expect(server.target(0), 'daily_team_checkins');
      final q = server.query(0);
      expect(q['select'], 'user_id');
      expect(q['check_in_date'], 'eq.2026-11-15');
      expect(q['user_id'], startsWith('in.('));
      expect(q['limit'], '$kFriendsCeiling');
    });

    test('friendsCheckedInOn sends nothing for an empty list', () async {
      expect(await CheckInHistoryService(client: server.client).friendsCheckedInOn('2026-11-15', []), isEmpty);
      expect(server.calls, isEmpty);
    });

    test('a failure is thrown for the caller to handle', () async {
      server.down = true;
      await expectLater(
          CheckInHistoryService(client: server.client).checkInDatesSince(_friend, '2026-10-16'), throwsA(anything));
    });
  });

  group('FriendService.sharedTeamIds', () {
    test('reads both users with the ceiling and intersects', () async {
      server.reply = (req) {
        final who = req.url.queryParameters['user_id'];
        return who == 'eq.$_me'
            ? [{'team_id': 'a'}, {'team_id': 'b'}, {'team_id': 'b'}]
            : [{'team_id': 'b'}, {'team_id': 'c'}];
      };
      expect(await FriendService(client: server.client).sharedTeamIds(_friend), {'b'});
      expect(server.calls, hasLength(2));
      for (var i = 0; i < 2; i++) {
        expect(server.target(i), 'team_members');
        expect(server.query(i)['limit'], '$kTeamMembershipsCeiling');
      }
      expect(server.calls.map((c) => c.url.queryParameters['user_id']).toSet(), {'eq.$_me', 'eq.$_friend'});
    });

    test('is empty and sends nothing when signed out', () async {
      final out = FakeSupabase();
      expect(await FriendService(client: out.client).sharedTeamIds(_friend), isEmpty);
      expect(out.calls, isEmpty);
    });
  });
}
