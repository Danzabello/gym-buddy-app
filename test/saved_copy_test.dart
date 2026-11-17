import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:gym_buddy_app/services/coin_service.dart';
import 'package:gym_buddy_app/services/friend_service.dart';
import 'package:gym_buddy_app/services/handshake_service.dart';
import 'package:gym_buddy_app/services/level_service.dart';
import 'package:gym_buddy_app/services/team_streak_service.dart';
import 'package:gym_buddy_app/services/saved_copy.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:timezone/data/latest.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

import 'support/fake_supabase.dart';

const _a = 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa';
const _b = 'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb';

void main() {
  final t0 = DateTime(2026, 11, 17, 12);
  Object parse(Object d) => d;

  Future<Object?> read(String? uid, {DateTime? now, Duration? maxAge, bool sameDay = false}) =>
      SavedCopy.read<Object>(uid, 'c',
          maxAge: maxAge ?? const Duration(days: 3), sameDay: sameDay, parse: parse, now: now);

  Future<Set<String>> keys() async => (await SharedPreferences.getInstance()).getKeys();

  setUp(() => SharedPreferences.setMockInitialValues({}));

  group('round trip and owner', () {
    test('saved data comes back for its owner', () async {
      await SavedCopy.write(_a, 'c', {'n': 1}, now: t0);
      expect(await read(_a, now: t0), {'n': 1});
    });

    test('account switch: another user never reads it, and writing as them wipes it', () async {
      await SavedCopy.write(_a, 'c', {'n': 1}, now: t0);
      expect(await read(_b, now: t0), isNull);
      await SavedCopy.write(_b, 'other', {'n': 2}, now: t0);
      expect(await read(_a, now: t0), isNull);
      expect((await keys()).where((k) => k.contains(_a)), isEmpty);
    });

    test('an entry whose inner owner differs is ignored and deleted', () async {
      await SavedCopy.write(_a, 'c', {'n': 1}, now: t0);
      final prefs = await SharedPreferences.getInstance();
      final key = prefs.getKeys().firstWhere((k) => k.endsWith(':c'));
      final m = jsonDecode(prefs.getString(key)!) as Map<String, dynamic>;
      await prefs.setString(key, jsonEncode({...m, 'owner': _b}));
      expect(await read(_a, now: t0), isNull);
      expect(prefs.getString(key), isNull);
    });

    test('signed out (null user) reads nothing', () async {
      await SavedCopy.write(_a, 'c', {'n': 1}, now: t0);
      expect(await read(null, now: t0), isNull);
    });

    test('wipe removes every saved key and leaves the others', () async {
      SharedPreferences.setMockInitialValues({'login_lockout_until': 5, 'accent_theme': 'x'});
      await SavedCopy.write(_a, 'c', {'n': 1}, now: t0);
      await SavedCopy.wipe();
      expect(await keys(), {'login_lockout_until', 'accent_theme'});
    });
  });

  group('wipe only on sign-out or another user', () {
    test('a sign-out wipes', () {
      expect(savedCopyShouldWipe(AuthChangeEvent.signedOut, null, _a), isTrue);
    });

    test('a sign-in as another user wipes', () {
      expect(savedCopyShouldWipe(AuthChangeEvent.signedIn, _b, _a), isTrue);
    });

    test('a sign-in as the same user, or with nothing saved, does not', () {
      expect(savedCopyShouldWipe(AuthChangeEvent.signedIn, _a, _a), isFalse);
      expect(savedCopyShouldWipe(AuthChangeEvent.signedIn, _a, null), isFalse);
    });

    test('a token refresh does not wipe, even for another user id', () {
      expect(savedCopyShouldWipe(AuthChangeEvent.tokenRefreshed, _a, _a), isFalse);
      expect(savedCopyShouldWipe(AuthChangeEvent.tokenRefreshed, _b, _a), isFalse);
    });

    test('the initial session does not wipe, signed in or not', () {
      expect(savedCopyShouldWipe(AuthChangeEvent.initialSession, _a, _a), isFalse);
      expect(savedCopyShouldWipe(AuthChangeEvent.initialSession, null, _a), isFalse);
      expect(savedCopyShouldWipe(AuthChangeEvent.initialSession, _b, _a), isFalse);
    });

    test('a user update does not wipe', () {
      expect(savedCopyShouldWipe(AuthChangeEvent.userUpdated, _a, _a), isFalse);
    });

    test('a failed or offline refresh (strict read throws) keeps the saved copy', () async {
      await SavedCopy.write(_a, 'c', {'n': 1}, now: t0);
      final server = FakeSupabase();
      await server.signIn(_a);
      server.status = 400; // a failed read; a dropped socket would add retries
      await expectLater(FriendService(client: server.client).getFriends(strict: true), throwsA(anything));
      expect(await FriendService(client: server.client).getFriends(), isEmpty);
      expect(await read(_a, now: t0), {'n': 1});
    });
  });

  group('age, version and corruption', () {
    test('max age: just under shows, just over reads nothing and deletes', () async {
      await SavedCopy.write(_a, 'c', {'n': 1}, now: t0);
      const age = Duration(days: 3);
      expect(await read(_a, now: t0.add(age), maxAge: age), {'n': 1});
      expect(await read(_a, now: t0.add(age + const Duration(seconds: 1)), maxAge: age), isNull);
      expect(await read(_a, now: t0), isNull); // gone
    });

    test('a clock that moved back reads nothing', () async {
      await SavedCopy.write(_a, 'c', {'n': 1}, now: t0);
      expect(await read(_a, now: t0.subtract(const Duration(hours: 1))), isNull);
    });

    test('a schema bump is ignored and deleted', () async {
      await SavedCopy.write(_a, 'c', {'n': 1}, now: t0);
      final prefs = await SharedPreferences.getInstance();
      final key = prefs.getKeys().firstWhere((k) => k.endsWith(':c'));
      final m = jsonDecode(prefs.getString(key)!) as Map<String, dynamic>;
      await prefs.setString(key, jsonEncode({...m, 'v': SavedCopy.version + 1}));
      expect(await read(_a, now: t0), isNull);
      expect(prefs.getString(key), isNull);
    });

    test('corrupt, truncated and wrong-shape entries read nothing and never throw', () async {
      for (final bad in ['{not json', '{"v":1,"owner":"$_a"', '[1,2]', '"x"', '{"v":1}']) {
        SharedPreferences.setMockInitialValues({'${SavedCopy.prefix}$_a:c': bad});
        expect(await read(_a, now: t0), isNull, reason: bad);
        expect((await keys()).contains('${SavedCopy.prefix}$_a:c'), isFalse, reason: bad);
      }
    });

    test('a payload the parser rejects is deleted', () async {
      await SavedCopy.write(_a, 'c', {'n': 1}, now: t0);
      final got = await SavedCopy.read<Object>(_a, 'c',
          maxAge: const Duration(days: 1), parse: (_) => throw const FormatException('x'), now: t0);
      expect(got, isNull);
      expect(await read(_a, now: t0), isNull);
    });
  });

  group('size cap', () {
    test('an oversize entry is not written', () async {
      await SavedCopy.write(_a, 'c', {'s': 'x' * SavedCopy.maxEntryChars}, now: t0);
      expect(await read(_a, now: t0), isNull);
    });

    test('a write that would pass the total is skipped and the others stay', () async {
      final big = {'s': 'x' * (200 * 1024)};
      await SavedCopy.write(_a, 'one', big, now: t0);
      await SavedCopy.write(_a, 'two', big, now: t0);
      await SavedCopy.write(_a, 'three', big, now: t0);
      final names = (await keys()).where((k) => k.endsWith(':three'));
      expect(names, isEmpty);
      expect((await keys()).where((k) => k.endsWith(':one') || k.endsWith(':two')), hasLength(2));
    });
  });

  group('date rule', () {
    setUpAll(tzdata.initializeTimeZones);

    test('same local day shows, after local midnight reads nothing', () async {
      final saved = DateTime(2026, 11, 17, 23, 0);
      await SavedCopy.write(_a, 'c', {'n': 1}, now: saved);
      expect(await read(_a, now: DateTime(2026, 11, 17, 23, 59), sameDay: true), {'n': 1});
      expect(await read(_a, now: DateTime(2026, 11, 18, 0, 1), sameDay: true), isNull);
    });

    test('without the rule an earlier day still shows within the age', () async {
      await SavedCopy.write(_a, 'c', {'n': 1}, now: DateTime(2026, 11, 17, 23, 0));
      expect(await read(_a, now: DateTime(2026, 11, 18, 9), sameDay: false), {'n': 1});
    });

    test('the saved zone decides the day, not the device', () async {
      // 2026-11-17 12:00 UTC is already 22:00 on the 17th in Sydney and the
      // same date in UTC; two hours later it is the 18th in Sydney only.
      final sydney = tz.getLocation('Australia/Sydney');
      final saved = DateTime.utc(2026, 11, 17, 12);
      await SavedCopy.write(_a, 'c', {'n': 1}, now: saved, zone: sydney);
      final later = DateTime.utc(2026, 11, 17, 14);
      expect(await read(_a, now: later, sameDay: true), isNull);
      // The same instants with no zone follow the device calendar instead,
      // which for these two is the same day in any zone within a few hours of UTC.
      await SavedCopy.write(_a, 'c', {'n': 1}, now: saved);
      final deviceSameDay = saved.toLocal().day == later.toLocal().day;
      expect(await read(_a, now: later, sameDay: true), deviceSameDay ? {'n': 1} : isNull);
    });
  });

  group('no secrets in what is saved', () {
    test('a saved friends payload holds no email or token', () async {
      await SavedCopy.write(_a, 'friends', {
        'friends': [
          {'id': _b, 'username': 'u', 'display_name': 'B', 'avatar_id': 'x'}
        ],
      }, now: t0);
      final prefs = await SharedPreferences.getInstance();
      final all = prefs.getKeys().map((k) => prefs.getString(k)).join();
      expect(all.contains('@'), isFalse);
      expect(all.contains('access_token'), isFalse);
    });
  });

  group('awaitConfirmed', () {
    test('returns when the refresh ends, before the limit', () async {
      final refresh = Completer<void>();
      final limit = Completer<void>();
      var done = false;
      final f = awaitConfirmed(refresh.future, delay: (_) => limit.future).then((_) => done = true);
      await Future<void>.delayed(Duration.zero);
      expect(done, isFalse);
      refresh.complete();
      await f;
      expect(done, isTrue);
    });

    test('goes on at the limit when the refresh is still running', () async {
      final refresh = Completer<void>();
      final limit = Completer<void>();
      Duration? asked;
      var done = false;
      final f = awaitConfirmed(refresh.future, delay: (d) {
        asked = d;
        return limit.future;
      }).then((_) => done = true);
      await Future<void>.delayed(Duration.zero);
      expect(done, isFalse);
      limit.complete(); // fake time: three seconds pass
      await f;
      expect(done, isTrue);
      expect(asked, const Duration(seconds: 3));
      expect(refresh.isCompleted, isFalse);
    });

    test('goes on when the refresh fails, without throwing', () async {
      final refresh = Completer<void>();
      final f = awaitConfirmed(refresh.future, delay: (_) => Completer<void>().future);
      refresh.completeError(StateError('offline'));
      await f;
    });

    test('the real timer ends the wait at the limit, and is cancelled when the refresh ends first', () async {
      final sw = Stopwatch()..start();
      await awaitConfirmed(Completer<void>().future, limit: const Duration(milliseconds: 60));
      expect(sw.elapsedMilliseconds, greaterThanOrEqualTo(55));
      final done = Completer<void>()..complete();
      await awaitConfirmed(done.future); // returns at once; a leftover 3 s timer would fail the widget tests
    });

    test('nothing to wait for returns at once', () async {
      await awaitConfirmed(null);
    });
  });

  group('ShopItem saved form', () {
    test('round trips every field', () {
      final item = ShopItem(
        id: 'i1',
        name: 'Gold',
        description: 'd',
        category: 'ring_color',
        cost: 50,
        emoji: '⭐',
        assetId: 'a',
        isOwned: true,
        isEquipped: true,
        unlockLevel: 3,
        colorHex: '#FFAA00',
        unlockAchievementId: 'ach',
        unlockAchievementName: 'Name',
      );
      final back = ShopItem.fromSaved(jsonDecode(jsonEncode(item.toSaved())) as Map<String, dynamic>);
      expect(back.toSaved(), item.toSaved());
    });
  });

  group('saved forms of the other models', () {
    Map<String, dynamic> viaJson(Map<String, dynamic> m) =>
        jsonDecode(jsonEncode(m)) as Map<String, dynamic>;

    test('TeamStreak with members and check-ins round trips', () {
      final s = TeamStreak(
        id: 's1',
        teamId: 't1',
        teamName: 'Us',
        teamEmoji: '🔥',
        currentStreak: 4,
        longestStreak: 9,
        totalWorkouts: 20,
        bestStreak: 9,
        lastWorkoutDate: DateTime.utc(2026, 11, 16),
        lastInteractionAt: DateTime.utc(2026, 11, 17, 8, 30),
        isCoachMaxTeam: false,
        members: [
          TeamMember(userId: _a, displayName: 'A', username: 'a', isCoachMax: false, avatarId: 'x'),
          TeamMember(userId: _b, displayName: 'B', isCoachMax: false),
        ],
        todayCheckIns: [
          CheckInStatus(userId: _a, displayName: 'A', checkInTime: DateTime.utc(2026, 11, 17, 7), order: 1),
        ],
        isFavorite: true,
      );
      final back = TeamStreak.fromSaved(viaJson(s.toSaved()));
      expect(back.toSaved(), s.toSaved());
      expect(back.isAtRisk, isFalse);
      expect(back.lastWorkoutDate, s.lastWorkoutDate);
    });

    test('TeamStreak with no dates round trips', () {
      final s = TeamStreak(
        id: 's',
        teamId: 't',
        teamName: 'N',
        teamEmoji: '🔥',
        currentStreak: 0,
        longestStreak: 0,
        lastWorkoutDate: null,
        isCoachMaxTeam: true,
        members: const [],
        todayCheckIns: const [],
      );
      expect(TeamStreak.fromSaved(viaJson(s.toSaved())).toSaved(), s.toSaved());
    });

    test('LevelInfo round trips and compares equal', () {
      final l = LevelInfo(
        level: 7,
        title: 'Rookie',
        currentXp: 700,
        xpForThisLevel: 600,
        xpForNextLevel: 800,
        xpIntoCurrentLevel: 100,
        xpNeededForNext: 100,
        progressPercent: 0.5,
      );
      expect(LevelInfo.fromSaved(viaJson(l.toSaved())), l);
    });

    test('WorkoutCardData round trips through its own reader', () {
      final c = WorkoutCardData(
        state: 'scheduled',
        workout: {'workout_id': 'w', 'planned_at': '2026-11-17T10:00:00Z'},
        invites: [
          {'workout_id': 'i', 'direction': 'received'}
        ],
        openInviteCount: 2,
        serverNow: DateTime.utc(2026, 11, 17, 9),
      );
      final back = WorkoutCardData.fromJson(viaJson(c.toSaved()));
      expect(back.toSaved(), c.toSaved());
      expect(back.serverNow, c.serverNow);
    });
  });
}
