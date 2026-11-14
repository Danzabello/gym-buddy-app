import 'package:flutter_test/flutter_test.dart';
import 'package:gym_buddy_app/services/break_day_service.dart';

import 'support/fake_supabase.dart';

void main() {
  group('BreakDayService.usersOnBreakToday', () {
    test('asks once for every id and returns the ones on a break', () async {
      final server = FakeSupabase()
        ..reply = (_) => [
              {'user_id': 'a', 'on_break': true},
              {'user_id': 'b', 'on_break': false},
              {'user_id': 'c', 'on_break': true},
            ];
      final result = await BreakDayService(client: server.client)
          .usersOnBreakToday(['a', 'b', 'c', 'a']);

      expect(result, {'a', 'c'});
      expect(server.calls, hasLength(1));
      expect(server.target(0), 'are_on_break_today');
      expect(server.body(0), {
        'p_user_ids': ['a', 'b', 'c'],
      });
    });

    test('an id the server leaves out is not on a break', () async {
      final server = FakeSupabase()
        ..reply = (_) => [
              {'user_id': 'a', 'on_break': true},
            ];
      expect(
          await BreakDayService(client: server.client)
              .usersOnBreakToday(['a', 'b']),
          {'a'});
    });

    test('no ids means no call', () async {
      final server = FakeSupabase();
      expect(await BreakDayService(client: server.client).usersOnBreakToday([]),
          isEmpty);
      expect(server.calls, isEmpty);
    });

    test('a server error or a dropped connection gives nobody', () async {
      final refused = FakeSupabase()
        ..status = 404
        ..reply = (_) => {'message': 'function not found', 'code': 'PGRST202'};
      expect(
          await BreakDayService(client: refused.client).usersOnBreakToday(['a']),
          isEmpty);

      final offline = FakeSupabase()..down = true;
      expect(
          await BreakDayService(client: offline.client).usersOnBreakToday(['a']),
          isEmpty);
    });
  });
}
