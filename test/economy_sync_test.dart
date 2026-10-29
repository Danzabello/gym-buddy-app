import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:gym_buddy_app/services/economy_sync.dart';
import 'package:gym_buddy_app/services/team_sync_service.dart';

void main() {
  group('EconomySync.refresh', () {
    test('publishes what the server reports', () async {
      final sync = EconomySync(fetch: () async => const EconomyNumbers(null, 30));
      expect(sync.numbers.value, isNull);
      var notified = 0;
      sync.numbers.addListener(() => notified++);
      await sync.refresh();
      expect(sync.numbers.value!.coins, 30);
      expect(notified, 1);
    });

    test('a failed read keeps the numbers on screen', () async {
      var coins = 30;
      var fail = false;
      final sync = EconomySync(fetch: () async => fail ? null : EconomyNumbers(null, coins));
      await sync.refresh();
      fail = true;
      await sync.refresh();
      expect(sync.numbers.value!.coins, 30);
    });

    test('a read that throws is swallowed and a later refresh still works', () async {
      var throwNext = true;
      final sync = EconomySync(fetch: () async {
        if (throwNext) throw Exception('network down');
        return const EconomyNumbers(null, 7);
      });
      await sync.refresh();
      expect(sync.numbers.value, isNull);
      throwNext = false;
      await sync.refresh();
      expect(sync.numbers.value!.coins, 7);
    });

    test('calls during a read collapse into one more read, which ends on the latest value', () async {
      var coins = 10;
      var reads = 0;
      final gate = Completer<void>();
      final sync = EconomySync(fetch: () async {
        reads++;
        final seen = coins;
        if (reads == 1) await gate.future;
        return EconomyNumbers(null, seen);
      });
      final first = sync.refresh();
      coins = 30; // a credit lands while the first read is in flight
      unawaited(sync.refresh());
      unawaited(sync.refresh());
      gate.complete();
      await first;
      expect(reads, 2);
      expect(sync.numbers.value!.coins, 30);
    });
  });

  group('TeamSyncService refresh hook', () {
    Future<void> run(Map<String, dynamic> rpc, void Function() onCredited) =>
        TeamSyncService(submitCheckin: () async => rpc, onCredited: onCredited).syncAllTeamsCheckIns();

    test('a sync that copied rows refreshes the numbers', () async {
      var n = 0;
      await run({'credited': true, 'reason': 'credited'}, () => n++);
      expect(n, 1);
    });

    test('a sync that copied nothing does not', () async {
      var n = 0;
      await run({'credited': false, 'reason': 'already_checked_in'}, () => n++);
      expect(n, 0);
    });
  });
}
