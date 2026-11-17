import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:gym_buddy_app/home_screen.dart';
import 'package:gym_buddy_app/services/break_day_service.dart';
import 'package:gym_buddy_app/services/coin_service.dart';
import 'package:gym_buddy_app/services/nickname_service.dart';
import 'package:gym_buddy_app/services/saved_copy.dart';
import 'package:gym_buddy_app/services/team_streak_service.dart';
import 'package:gym_buddy_app/services/workout_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/fake_supabase.dart';

const _a = 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa';
const _b = 'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb';

Map<String, dynamic> viaJson(Map<String, dynamic> m) =>
    jsonDecode(jsonEncode(m)) as Map<String, dynamic>;

final streak = TeamStreak(
  id: 's1',
  teamId: 't1',
  teamName: 'Us',
  teamEmoji: '🔥',
  currentStreak: 4,
  longestStreak: 9,
  lastWorkoutDate: null,
  isCoachMaxTeam: false,
  members: [TeamMember(userId: _b, displayName: 'B', isCoachMax: false)],
  todayCheckIns: const [],
);

/// One load's answers: a part in [failed] failed (null), a part in [empty]
/// answered empty, any other part answered with a fresh value.
Map<String, dynamic>? load({
  Map<String, dynamic>? saved,
  Set<String> failed = const {},
  Set<String> empty = const {},
  List<TeamStreak>? streaks,
}) {
  T? v<T>(String k, T fresh, T none) =>
      failed.contains(k) ? null : (empty.contains(k) ? none : fresh);
  final out = dashboardSavedPayload(
    saved: saved,
    streaks: streaks ?? [streak],
    prefs: v('prefs', (sort: 'highestCurrent', customOrder: ['t1'], zone: 'America/New_York'),
        (sort: 'highestCurrent', customOrder: <String>[], zone: null)),
    nicknames: v('nicknames', {_b: 'New'}, <String, String>{}),
    checkIns: v('checkIns', {'2026-11-17'}, <String>{}),
    breakDates: v('breakDates', {'2026-11-17'}, <String>{}),
    buddyOnBreak: v('buddyOnBreak', {_b: false}, <String, bool>{}),
    buddyZones: v('buddyZones', {_b: 'Europe/Paris'}, <String, String>{}),
    ringHex: v('ringHex', {_b: '#222222'}, <String, String>{}),
    hasCheckedIn: v('hasCheckedIn', true, false),
    workouts: v('workouts', [{'id': 'w-new'}], <Map<String, dynamic>>[]),
  );
  return out == null ? null : viaJson(out);
}

/// The entry an earlier load saved: every part different from [load]'s.
final saved = viaJson(dashboardSavedPayload(
  saved: null,
  streaks: [streak],
  prefs: (sort: 'custom', customOrder: ['t9'], zone: 'Europe/London'),
  nicknames: {_b: 'Old'},
  checkIns: {'2026-11-16'},
  breakDates: {'2026-11-15'},
  buddyOnBreak: {_b: true},
  buddyZones: {_b: 'Asia/Tokyo'},
  ringHex: {_b: '#111111'},
  hasCheckedIn: false,
  workouts: [{'id': 'w-old'}],
)!);

/// The saved keys each read feeds, and what an empty answer saves.
const parts = <String, Map<String, Object?>>{
  'prefs': {'sort': 'highestCurrent', 'customOrder': <Object>[], 'zone': null},
  'nicknames': {'nicknames': <String, Object>{}},
  'checkIns': {'checkIns': <Object>[]},
  'breakDates': {'breakDates': <Object>[]},
  'buddyOnBreak': {'buddyOnBreak': <String, Object>{}},
  'buddyZones': {'buddyZones': <String, Object>{}},
  'ringHex': {'ringHex': <String, Object>{}},
  'hasCheckedIn': {'hasCheckedIn': false},
  'workouts': {'workouts': <Object>[]},
};

void main() {
  group('each part is saved only when its own read answered', () {
    for (final part in parts.entries) {
      test('${part.key}: a failed read keeps the saved value', () {
        final out = load(saved: saved, failed: {part.key})!;
        for (final k in part.value.keys) {
          expect(out[k], saved[k], reason: k);
        }
        // Every other part is this load's answer.
        final fresh = load()!;
        for (final k in fresh.keys.where((k) => !part.value.containsKey(k))) {
          expect(out[k], fresh[k], reason: k);
        }
        // And it reads back as the saved value.
        final back = dashboardFromSaved(viaJson(out));
        expect(back.streaks.single.teamId, 't1');
      });

      test('${part.key}: empty from a successful read is saved', () {
        final out = load(saved: saved, empty: {part.key})!;
        part.value.forEach((k, none) => expect(out[k], none, reason: k));
      });
    }

    test('a failed part with nothing saved is left out and reads back as null', () {
      final out = load(failed: parts.keys.toSet())!;
      expect(out.keys, ['streaks']);
      final back = dashboardFromSaved(out);
      expect(back.hasCheckedIn, isNull);
      expect(back.workouts, isNull);
      expect(back.nicknames, isNull);
      expect(back.checkIns, isNull);
      expect(back.sort, isNull);
      expect(back.customOrder, isNull);
      expect(back.ringHex, isNull);
    });

    test('a failed streak read (no streaks) writes nothing at all', () {
      expect(load(saved: saved, streaks: const []), isNull);
    });

    test('a full entry round trips', () {
      final back = dashboardFromSaved(load(saved: saved)!);
      expect(back.hasCheckedIn, isTrue);
      expect(back.workouts, [
        {'id': 'w-new'}
      ]);
      expect(back.checkIns, {'2026-11-17'});
      expect(back.buddyOnBreak, {_b: false});
      expect(back.customOrder, ['t1']);
      expect(back.zone, 'America/New_York');
    });
  });

  group('the merge base is the same-day saved entry', () {
    setUp(() => SharedPreferences.setMockInitialValues({}));

    Future<Map<String, dynamic>?> base(DateTime now) => SavedCopy.read<Map<String, dynamic>>(
        _a, 'dashboard',
        maxAge: kSavedMaxAgeDashboard,
        sameDay: true,
        now: now,
        parse: (d) => Map<String, dynamic>.from(d as Map));

    test("yesterday's entry is not carried into today's: a failed part is left out", () async {
      final yesterday = DateTime(2026, 11, 16, 20);
      await SavedCopy.write(_a, 'dashboard', saved, now: yesterday);
      final today = DateTime(2026, 11, 17, 9);
      final out = load(saved: await base(today), failed: {'hasCheckedIn', 'workouts'})!;
      expect(out.containsKey('hasCheckedIn'), isFalse);
      expect(out.containsKey('workouts'), isFalse);
    });

    test("earlier today's entry is the base: a failed part keeps it", () async {
      final morning = DateTime(2026, 11, 17, 7);
      await SavedCopy.write(_a, 'dashboard', saved, now: morning);
      final out = load(saved: await base(DateTime(2026, 11, 17, 9)), failed: {'workouts'})!;
      expect(out['workouts'], [
        {'id': 'w-old'}
      ]);
    });
  });

  group('strict reads throw where the plain ones answer empty', () {
    late FakeSupabase server;
    setUp(() async {
      server = FakeSupabase();
      await server.signIn(_a);
      server.status = 400; // a failed read; a dropped socket would add retries
    });

    test('hasCheckedInToday', () async {
      final svc = TeamStreakService(client: server.client);
      await expectLater(svc.hasCheckedInToday(strict: true), throwsA(anything));
      expect(await svc.hasCheckedInToday(), isFalse);
    });

    test('getTodaysWorkouts', () async {
      final svc = WorkoutService(client: server.client);
      await expectLater(svc.getTodaysWorkouts(strict: true), throwsA(anything));
      expect(await svc.getTodaysWorkouts(), isEmpty);
    });

    test('getAllNicknames', () async {
      final svc = NicknameService(client: server.client);
      await expectLater(svc.getAllNicknames(strict: true), throwsA(anything));
      expect(await svc.getAllNicknames(), isEmpty);
    });

    test('usersOnBreakToday', () async {
      final svc = BreakDayService(client: server.client);
      await expectLater(svc.usersOnBreakToday([_b], strict: true), throwsA(anything));
      expect(await svc.usersOnBreakToday([_b]), isEmpty);
    });

    test('getEquippedColorHexForUsers', () async {
      final svc = CoinService(client: server.client);
      await expectLater(svc.getEquippedColorHexForUsers([_b], strict: true), throwsA(anything));
      expect(await svc.getEquippedColorHexForUsers([_b]), isEmpty);
    });

    test('a successful empty answer is empty, not an error, in strict mode', () async {
      server.status = 200;
      server.reply = (_) => [];
      expect(await TeamStreakService(client: server.client).hasCheckedInToday(strict: true), isFalse);
      expect(await WorkoutService(client: server.client).getTodaysWorkouts(strict: true), isEmpty);
      expect(await NicknameService(client: server.client).getAllNicknames(strict: true), isEmpty);
      expect(await BreakDayService(client: server.client).usersOnBreakToday([_b], strict: true), isEmpty);
      expect(await CoinService(client: server.client).getEquippedColorHexForUsers([_b], strict: true),
          isEmpty);
    });
  });
}
