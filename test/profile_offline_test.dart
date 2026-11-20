import 'package:flutter_test/flutter_test.dart';
import 'package:gym_buddy_app/home_screen.dart';
import 'package:gym_buddy_app/services/level_service.dart';
import 'package:gym_buddy_app/services/team_streak_service.dart';

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

void main() {
  // Every part known, each with its own marker so a test can tell them apart.
  final profile = <String, dynamic>{'display_name': 'shown'};
  final streaks = <TeamStreak>[];
  final level = _level(7);
  final favs = <Map<String, dynamic>>[];
  final ProfileParts shown = (
    profile: profile,
    streaks: streaks,
    level: level,
    workouts: 5,
    buddies: 3,
    favs: favs,
  );
  const ProfileParts failed = noProfileParts;

  group('profileAfterLoad', () {
    test('a load where every read failed keeps everything shown', () {
      expect(profileAfterLoad(shown, failed), shown);
    });

    // One failing part at a time: it keeps its shown value, the rest update.
    final fresh = <String, ProfileParts>{
      'profile': (profile: {'display_name': 'new'}, streaks: null, level: null, workouts: null, buddies: null, favs: null),
      'streaks': (profile: null, streaks: [], level: null, workouts: null, buddies: null, favs: null),
      'level': (profile: null, streaks: null, level: _level(8), workouts: null, buddies: null, favs: null),
      'workouts': (profile: null, streaks: null, level: null, workouts: 9, buddies: null, favs: null),
      'buddies': (profile: null, streaks: null, level: null, workouts: null, buddies: 4, favs: null),
      'favs': (profile: null, streaks: null, level: null, workouts: null, buddies: null, favs: []),
    };
    for (final part in fresh.keys) {
      test('only $part answered: it updates and the other five keep their shown value', () {
        final next = profileAfterLoad(shown, fresh[part]!);
        expect(identical(next.profile, shown.profile), part != 'profile');
        expect(identical(next.streaks, shown.streaks), part != 'streaks');
        expect(next.level == shown.level, part != 'level');
        expect(next.workouts == shown.workouts, part != 'workouts');
        expect(next.buddies == shown.buddies, part != 'buddies');
        expect(identical(next.favs, shown.favs), part != 'favs');
      });
    }

    test('a real zero is an answer and replaces the shown value', () {
      final next = profileAfterLoad(shown,
          (profile: null, streaks: null, level: null, workouts: 0, buddies: 0, favs: null));
      expect(next.workouts, 0);
      expect(next.buddies, 0);
    });
  });

  group('profileReady and profileComplete', () {
    test('nothing shown and every read failed is the loading state, with no default painted', () {
      final next = profileAfterLoad(noProfileParts, failed);
      expect(profileReady(next), isFalse);
      expect(next, noProfileParts); // no level 1, no "User", no 0 stats
    });

    test('each part the page prints from is needed, favourites are not', () {
      expect(profileReady(shown), isTrue);
      expect(profileReady((profile: null, streaks: streaks, level: level, workouts: 5, buddies: 3, favs: favs)), isFalse);
      expect(profileReady((profile: profile, streaks: null, level: level, workouts: 5, buddies: 3, favs: favs)), isFalse);
      expect(profileReady((profile: profile, streaks: streaks, level: null, workouts: 5, buddies: 3, favs: favs)), isFalse);
      expect(profileReady((profile: profile, streaks: streaks, level: level, workouts: null, buddies: 3, favs: favs)), isFalse);
      expect(profileReady((profile: profile, streaks: streaks, level: level, workouts: 5, buddies: null, favs: favs)), isFalse);
      expect(profileReady((profile: profile, streaks: streaks, level: level, workouts: 5, buddies: 3, favs: null)), isTrue);
    });

    test('a partial answer is not complete, so it is never saved', () {
      expect(profileComplete(shown), isTrue);
      expect(profileComplete((profile: profile, streaks: streaks, level: level, workouts: 5, buddies: 3, favs: null)), isFalse);
      expect(profileComplete((profile: profile, streaks: null, level: level, workouts: 5, buddies: 3, favs: favs)), isFalse);
    });

    test('a saved copy fills the parts a load left unknown, and the load wins where it answered', () {
      final loaded = (profile: {'display_name': 'new'}, streaks: null, level: null, workouts: null, buddies: null, favs: null);
      final next = profileAfterLoad(shown, loaded);
      expect(next.profile!['display_name'], 'new');
      expect(next.level, level);
      expect(profileReady(next), isTrue);
    });
  });

  group('getAllUserStreaks strict', () {
    Map<String, dynamic> team(String id) => {'team_id': id, 'streak_id': 's-$id'};
    // A team whose id is not a string: its parse throws.
    final broken = {'team_id': 7, 'streak_id': 's-bad'};

    Future<TeamStreakService> service(FakeSupabase server) async {
      await server.signIn(_uid);
      return TeamStreakService(client: server.client);
    }

    test('a team that fails to parse is dropped by default and rethrown when strict', () async {
      final server = FakeSupabase()..reply = (_) => [team('a'), broken];
      final svc = await service(server);

      final byDefault = await svc.getAllUserStreaks();
      expect(byDefault.map((s) => s.teamId), ['a']); // incomplete, as before
      await expectLater(svc.getAllUserStreaks(strict: true), throwsA(anything));
    });

    test('a check-in that fails to parse is dropped by default and rethrown when strict', () async {
      final bad = {
        ...team('a'),
        'today_check_ins': [
          {'user_id': 'u', 'checked_in_at': 'not a date'},
        ],
      };
      final server = FakeSupabase()..reply = (_) => [bad];
      final svc = await service(server);

      final byDefault = await svc.getAllUserStreaks();
      expect(byDefault.single.todayCheckIns, isEmpty);
      await expectLater(svc.getAllUserStreaks(strict: true), throwsA(anything));
    });

    test('a failed read is [] by default and rethrown when strict', () async {
      final refused = FakeSupabase()
        ..status = 500
        ..reply = (_) => {'message': 'boom', 'code': 'XX000'};
      final svc = await service(refused);
      expect(await svc.getAllUserStreaks(), isEmpty);
      await expectLater(svc.getAllUserStreaks(strict: true), throwsA(anything));
    });

    test('a complete answer is the same either way', () async {
      final server = FakeSupabase()..reply = (_) => [team('a'), team('b')];
      final svc = await service(server);
      final a = await svc.getAllUserStreaks();
      final b = await svc.getAllUserStreaks(strict: true);
      expect(a.map((s) => s.teamId).toSet(), {'a', 'b'});
      expect(b.map((s) => s.teamId).toSet(), {'a', 'b'});
    });
  });
}
