import 'package:flutter_test/flutter_test.dart';
import 'package:gym_buddy_app/services/team_sync_service.dart';

void main() {
  group('checkinSyncMessage', () {
    test('maps every submit_checkin reason to short plain text', () {
      final reasons = ['credited', 'already_checked_in', 'not_checked_in_today', 'no_teams', null, 'unknown'];
      for (final r in reasons) {
        final m = checkinSyncMessage(r);
        expect(m, isNotEmpty);
        expect(RegExp(r'^[\x20-\x7E]+$').hasMatch(m), isTrue, reason: 'no emoji or non-ASCII in "$m"');
      }
      expect(checkinSyncMessage('already_checked_in'), 'Already checked in today.');
      expect(checkinSyncMessage(null), 'Something went wrong. Please try again.');
    });
  });

  group('syncAllTeamsCheckIns', () {
    Future<Map<String, dynamic>> run(Future<dynamic> Function() rpc) =>
        TeamSyncService(submitCheckin: rpc).syncAllTeamsCheckIns();

    test('calls submit_checkin once and reports a credited sync', () async {
      var calls = 0;
      final res = await run(() async {
        calls++;
        return {'credited': true, 'reason': 'credited', 'xp': 0, 'coins': 0, 'teams': []};
      });
      expect(calls, 1);
      expect(res['success'], isTrue);
      expect(res['synced'], 1);
      expect(res['reason'], 'credited');
      expect(res['message'], 'Check-ins synced');
    });

    test('a sync onto several teams still shows no count', () async {
      final res = await run(() async => {
            'credited': true,
            'reason': 'credited',
            'teams': [
              {'streak_id': 'a', 'updated': true},
              {'streak_id': 'b', 'updated': false},
              {'streak_id': 'c', 'updated': true},
            ],
          });
      expect(res['synced'], 1);
      expect(res['message'], isNot(matches(RegExp(r'\d'))));
    });

    test('nothing to copy is a success with nothing synced', () async {
      for (final reason in ['already_checked_in', 'not_checked_in_today', 'no_teams']) {
        final res = await run(() async => {'credited': false, 'reason': reason});
        expect(res['success'], isTrue, reason: reason);
        expect(res['synced'], 0, reason: reason);
        expect(res['message'], checkinSyncMessage(reason));
      }
    });

    test('an RPC failure is reported, not thrown', () async {
      final res = await run(() async => throw Exception('network down'));
      expect(res['success'], isFalse);
      expect(res['synced'], 0);
      expect(res['message'], 'Something went wrong. Please try again.');
    });
  });
}
