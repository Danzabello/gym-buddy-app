import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:gym_buddy_app/pages/achievements_page.dart';
import 'package:gym_buddy_app/services/achievement_service.dart';
import 'package:gym_buddy_app/services/level_service.dart';
import 'package:gym_buddy_app/services/saved_copy.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/fake_supabase.dart';

const _uid = 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa';

LevelInfo _level(int n) => LevelInfo(
      level: n,
      title: 'T$n',
      currentXp: 10,
      xpForThisLevel: 0,
      xpForNextLevel: 100,
      xpIntoCurrentLevel: 10,
      xpNeededForNext: 90,
      progressPercent: 0.1,
    );

Achievement _ach(String id, {int? progress, DateTime? unlockedAt}) => Achievement(
      id: id,
      name: 'n-$id',
      description: 'd',
      category: 'streak',
      icon: 'i',
      rarity: 'common',
      xpReward: 10,
      coinReward: 5,
      targetValue: 7,
      sortOrder: 1,
      progress: progress,
      unlockedAt: unlockedAt,
    );

/// Survives a real save and read: JSON text and back.
Map<String, dynamic> _viaJson(Map<String, dynamic> m) =>
    jsonDecode(jsonEncode(m)) as Map<String, dynamic>;

void main() {
  final shownAll = [_ach('a')];
  final shownLevel = _level(7);
  final AchievementParts shown = (all: shownAll, level: shownLevel);

  group('achievementsAfterLoad', () {
    test('a load where every read failed keeps everything shown', () {
      expect(achievementsAfterLoad(shown, noAchievementParts), shown);
    });

    test('only the list answered: it updates and the level keeps its shown value', () {
      final fresh = [_ach('b')];
      final next = achievementsAfterLoad(shown, (all: fresh, level: null));
      expect(identical(next.all, fresh), isTrue);
      expect(next.level, shownLevel);
    });

    test('only the level answered: it updates and the list keeps its shown value', () {
      final next = achievementsAfterLoad(shown, (all: null, level: _level(8)));
      expect(next.level!.level, 8);
      expect(identical(next.all, shownAll), isTrue);
    });

    test('a real answer replaces the shown value', () {
      final fresh = [_ach('b'), _ach('c')];
      final next = achievementsAfterLoad(shown, (all: fresh, level: _level(9)));
      expect(identical(next.all, fresh), isTrue);
      expect(next.level!.level, 9);
    });
  });

  group('achievementsReady', () {
    test('nothing shown and every read failed is the loading state, with no default painted', () {
      final next = achievementsAfterLoad(noAchievementParts, noAchievementParts);
      expect(achievementsReady(next), isFalse);
      expect(next, noAchievementParts); // no empty list, no level 1
    });

    test('both parts are needed', () {
      expect(achievementsReady(shown), isTrue);
      expect(achievementsReady((all: shownAll, level: null)), isFalse);
      expect(achievementsReady((all: null, level: shownLevel)), isFalse);
    });

    test('a saved copy fills the part a load left unknown', () {
      final next = achievementsAfterLoad(shown, (all: [_ach('new')], level: null));
      expect(achievementsReady(next), isTrue);
    });
  });

  group('achievementsSavedPayload', () {
    test('a complete answer is saved', () {
      expect(achievementsSavedPayload(shown), isNotNull);
    });

    test('a partial answer is not saved, so a failed read is never saved as empty', () {
      expect(achievementsSavedPayload((all: shownAll, level: null)), isNull);
      expect(achievementsSavedPayload((all: null, level: shownLevel)), isNull);
      expect(achievementsSavedPayload(noAchievementParts), isNull);
    });
  });

  group('saved copy', () {
    final t0 = DateTime(2026, 11, 17, 12);
    setUp(() => SharedPreferences.setMockInitialValues({}));

    test('Achievement round trips, unlocked and in progress', () {
      final unlocked = _ach('a', progress: 7, unlockedAt: DateTime.utc(2026, 11, 1, 8, 30));
      final inProgress = _ach('b', progress: 3);
      final untouched = _ach('c');
      for (final a in [unlocked, inProgress, untouched]) {
        final back = Achievement.fromSaved(_viaJson(a.toSaved()));
        expect(back.toSaved(), a.toSaved());
        expect(back.isUnlocked, a.isUnlocked);
        expect(back.unlockedAt, a.unlockedAt);
      }
    });

    test('the class round trips through SavedCopy', () async {
      final answered = (all: [_ach('a', progress: 3), _ach('b')], level: _level(7));
      await SavedCopy.write(_uid, 'achievements', achievementsSavedPayload(answered)!, now: t0);
      final back = await SavedCopy.read<AchievementParts>(_uid, 'achievements',
          maxAge: kSavedMaxAgeAchievements, parse: achievementsFromSaved, now: t0);
      expect(back!.all!.map((a) => a.toSaved()), answered.all.map((a) => a.toSaved()));
      expect(back.level, answered.level);
    });

    test('a failed refresh writes nothing, so the saved list and level stay', () async {
      final good = (all: [_ach('a')], level: _level(7));
      await SavedCopy.write(_uid, 'achievements', achievementsSavedPayload(good)!, now: t0);
      // The refresh where both reads failed: no payload, so nothing is written.
      expect(achievementsSavedPayload(noAchievementParts), isNull);
      final back = await SavedCopy.read<AchievementParts>(_uid, 'achievements',
          maxAge: kSavedMaxAgeAchievements, parse: achievementsFromSaved, now: t0);
      expect(back!.all!.single.id, 'a');
      expect(back.level!.level, 7);
    });

    test('an empty saved list is corrupt: it reads nothing and is deleted', () async {
      await SavedCopy.write(_uid, 'achievements', {'all': [], 'level': _level(1).toSaved()}, now: t0);
      final back = await SavedCopy.read<AchievementParts>(_uid, 'achievements',
          maxAge: kSavedMaxAgeAchievements, parse: achievementsFromSaved, now: t0);
      expect(back, isNull);
      expect((await SharedPreferences.getInstance()).getKeys().where((k) => k.endsWith(':achievements')), isEmpty);
    });

    test('another user never reads it', () async {
      await SavedCopy.write(_uid, 'achievements', achievementsSavedPayload(shown)!, now: t0);
      final back = await SavedCopy.read<AchievementParts>(
          'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb', 'achievements',
          maxAge: kSavedMaxAgeAchievements, parse: achievementsFromSaved, now: t0);
      expect(back, isNull);
    });
  });

  group('AchievementService.getAll strict', () {
    Map<String, dynamic> def(Object id) => {
          'id': id,
          'name': 'n',
          'description': 'd',
          'category': 'streak',
          'icon': 'i',
          'rarity': 'common',
          'xp_reward': 10,
          'coin_reward': 5,
          'target_value': 7,
          'sort_order': 1,
        };

    Future<AchievementService> service(FakeSupabase server) async {
      await server.signIn(_uid);
      return AchievementService(client: server.client);
    }

    // The catalogue and the user's own rows come from two tables.
    Object? Function(dynamic) answer(List<Map<String, dynamic>> defs) =>
        (req) => req.url.pathSegments.last == 'achievements' ? defs : [];

    test('a bad row empties the list by default and rethrows when strict', () async {
      final server = FakeSupabase()..reply = answer([def('a'), def(7)]);
      final svc = await service(server);
      expect(await svc.getAll(), isEmpty); // as before: one bad row loses the list
      await expectLater(svc.getAll(strict: true), throwsA(anything));
    });

    test('a failed read is [] by default and rethrown when strict', () async {
      final refused = FakeSupabase()
        ..status = 500
        ..reply = (_) => {'message': 'boom', 'code': 'XX000'};
      final svc = await service(refused);
      expect(await svc.getAll(), isEmpty);
      await expectLater(svc.getAll(strict: true), throwsA(anything));
    });

    test('a complete answer is the same either way', () async {
      final server = FakeSupabase()..reply = answer([def('a'), def('b')]);
      final svc = await service(server);
      final byDefault = await svc.getAll();
      final strict = await svc.getAll(strict: true);
      expect(byDefault.map((a) => a.id), ['a', 'b']);
      expect(strict.map((a) => a.id), ['a', 'b']);
    });
  });
}
