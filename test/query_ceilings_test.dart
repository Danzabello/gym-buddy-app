import 'package:flutter_test/flutter_test.dart';
import 'package:gym_buddy_app/services/coin_service.dart';
import 'package:gym_buddy_app/services/friend_service.dart';
import 'package:gym_buddy_app/services/nickname_service.dart';
import 'package:gym_buddy_app/services/workout_history_service.dart';
import 'package:gym_buddy_app/services/workout_service.dart';
import 'package:gym_buddy_app/utils/query_ceilings.dart';

import 'support/fake_supabase.dart';

const _me = '11111111-1111-4111-8111-111111111111';

/// The first request to [table], or fails.
int _callTo(FakeSupabase server, String table) {
  final i = server.calls.indexWhere((c) => c.url.pathSegments.last == table);
  expect(i, isNot(-1), reason: 'no request to $table');
  return i;
}

void main() {
  late FakeSupabase server;
  setUp(() async {
    server = FakeSupabase();
    await server.signIn(_me);
  });

  test('the ceilings keep their margin over the realistic maximum', () {
    expect(kFriendsCeiling, greaterThanOrEqualTo(10 * 50));
    expect(kPendingRequestsCeiling, greaterThanOrEqualTo(10 * 20));
    expect(kDayWorkoutsCeiling, greaterThanOrEqualTo(10 * 10));
    expect(kWeekCoinRowsCeiling, greaterThanOrEqualTo(10 * 70));
  });

  test('accepted friendships are read with the friends ceiling', () async {
    await FriendService(client: server.client).getFriends();
    final i = _callTo(server, 'friendships');
    expect(server.query(i)['status'], 'eq.accepted');
    expect(server.query(i)['limit'], '$kFriendsCeiling');
  });

  test('pending requests are read with their ceiling, newest first', () async {
    await FriendService(client: server.client).getPendingRequests();
    final i = _callTo(server, 'friendships');
    expect(server.query(i)['status'], 'eq.pending');
    expect(server.query(i)['order'], startsWith('created_at.desc'));
    expect(server.query(i)['limit'], '$kPendingRequestsCeiling');
  });

  test('nicknames are read with the friends ceiling', () async {
    await NicknameService(client: server.client).getAllNicknames(forceRefresh: true);
    final i = _callTo(server, 'friend_nicknames');
    expect(server.query(i)['limit'], '$kFriendsCeiling');
  });

  test("today's workouts are read with the day ceiling", () async {
    await WorkoutService(client: server.client).getTodaysWorkouts();
    final i = _callTo(server, 'workouts');
    expect(server.query(i)['workout_date'], startsWith('eq.'));
    expect(server.query(i)['limit'], '$kDayWorkoutsCeiling');
  });

  test('the week of coin rows is read with its ceiling', () async {
    await CoinService(client: server.client).getWeekTotals();
    final i = _callTo(server, 'coin_transactions');
    expect(server.query(i)['created_at'], startsWith('gte.'));
    expect(server.query(i)['limit'], '$kWeekCoinRowsCeiling');
  });

  group('WorkoutHistoryService.getWorkoutHistory', () {
    test('sends its limit to the server, newest first, with no date filter', () async {
      await WorkoutHistoryService(client: server.client).getWorkoutHistory(limit: 50);
      final q = server.query(_callTo(server, 'workout_logs'));
      expect(q['limit'], '50');
      expect(q['order'], 'workout_date.desc.nullslast,workout_time.desc.nullslast');
      expect(q['user_id'], 'eq.$_me');
      expect(q.containsKey('workout_date'), isFalse);
    });

    test('sends an inclusive date range to the server', () async {
      await WorkoutHistoryService(client: server.client).getWorkoutHistory(
        startDate: DateTime(2026, 11, 1, 15, 30),
        endDate: DateTime(2026, 11, 30),
        limit: 100,
      );
      final url = server.calls[_callTo(server, 'workout_logs')].url;
      expect(url.queryParametersAll['workout_date'], ['gte.2026-11-01', 'lte.2026-11-30']);
      expect(url.queryParameters['limit'], '100');
    });

    test('returns the rows the server sent, in its order', () async {
      Map<String, dynamic> log(String id, String date) => {
            'id': id,
            'user_id': _me,
            'workout_date': date,
            'workout_time': '${date}T10:00:00Z',
            'workout_name': 'Run',
            'workout_category': 'Cardio',
            'buddy': {'display_name': 'Sam'},
          };
      server.reply = (_) => [log('b', '2026-11-12'), log('a', '2026-11-10')];
      final logs = await WorkoutHistoryService(client: server.client).getWorkoutHistory(limit: 50);
      expect(logs.map((l) => l.id), ['b', 'a']);
      expect(logs.first.buddyName, 'Sam');
    });
  });
}
