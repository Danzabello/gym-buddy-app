import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:gym_buddy_app/services/economy_sync.dart';
import 'package:gym_buddy_app/services/level_service.dart';
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

  group('EconomyNumbers equality', () {
    LevelInfo info({int level = 2, String title = 'T', int xp = 10, int a = 5, int b = 20,
            int into = 5, int need = 10, double pct = 0.5}) =>
        LevelInfo(level: level, title: title, currentXp: xp, xpForThisLevel: a,
            xpForNextLevel: b, xpIntoCurrentLevel: into, xpNeededForNext: need, progressPercent: pct);

    test('an unchanged refresh does not notify', () async {
      final sync = EconomySync(fetch: () async => EconomyNumbers(info(), 30));
      await sync.refresh();
      var notified = 0;
      sync.numbers.addListener(() => notified++);
      await sync.refresh();
      expect(notified, 0);
    });

    test('equal values share a hash code', () {
      expect(EconomyNumbers(info(), 3).hashCode, EconomyNumbers(info(), 3).hashCode);
    });

    test('a change in any one field is not equal', () {
      final base = EconomyNumbers(info(), 3);
      final changed = [
        EconomyNumbers(info(), 4),
        EconomyNumbers(null, 3),
        EconomyNumbers(info(level: 3), 3),
        EconomyNumbers(info(title: 'U'), 3),
        EconomyNumbers(info(xp: 11), 3),
        EconomyNumbers(info(a: 6), 3),
        EconomyNumbers(info(b: 21), 3),
        EconomyNumbers(info(into: 6), 3),
        EconomyNumbers(info(need: 11), 3),
        EconomyNumbers(info(pct: 0.6), 3),
      ];
      for (final c in changed) {
        expect(c == base, isFalse);
      }
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
