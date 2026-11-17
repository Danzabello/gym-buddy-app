import 'package:flutter/scheduler.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gym_buddy_app/home/header_seed.dart';
import 'package:gym_buddy_app/services/level_service.dart';
import 'package:gym_buddy_app/services/saved_copy.dart';
import 'package:gym_buddy_app/widgets/header_motion.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _a = 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa';
const _b = 'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb';

LevelInfo info(int level, int into, int width) => LevelInfo(
      level: level,
      title: 'T',
      currentXp: into,
      xpForThisLevel: 0,
      xpForNextLevel: width,
      xpIntoCurrentLevel: into,
      xpNeededForNext: width - into,
      progressPercent: into / width,
    );

void main() {
  final t0 = DateTime(2026, 11, 17, 12);

  Future<Set<String>> keys() async => (await SharedPreferences.getInstance()).getKeys();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    HeaderMotion.session = null;
    claimHeaderSeed(null); // nothing left over from another test
  });

  group('saving only what the server answered', () {
    test('a failed balance read leaves the saved value, shown and saved', () async {
      await saveHeaderAnswers(_a, level: info(2, 70, 250), coins: 120, now: t0);
      // The next load: level answered, balance failed.
      await saveHeaderAnswers(_a, level: info(2, 80, 250), coins: null, now: t0);
      await seedHeader(_a, now: t0);
      expect(HeaderMotion.session!.coins, 120);
      expect(HeaderMotion.session!.level.xpIntoCurrentLevel, 70); // not half-written
      final shown = headerAfterLoad(
          level: info(2, 80, 250), coins: null, shownLevel: info(2, 70, 250), shownCoins: 120);
      expect(shown!.coins, 120);
    });

    test('a real balance of 0 is saved and shown as 0', () async {
      await saveHeaderAnswers(_a, level: info(1, 0, 200), coins: 0, now: t0);
      await seedHeader(_a, now: t0);
      expect(HeaderMotion.session!.coins, 0);
      expect(headerAfterLoad(level: info(1, 0, 200), coins: 0, shownCoins: 50)!.coins, 0);
    });

    test('nothing from the header is saved from a failed read', () async {
      await saveHeaderAnswers(_a, level: null, coins: 5, avatar: null, now: t0);
      await saveHeaderAnswers(_a, level: info(1, 0, 200), coins: null, now: t0);
      expect(await keys(), isEmpty);
    });

    test('with nothing known, a failed read shows nothing rather than 0', () {
      expect(headerAfterLoad(level: info(1, 0, 200), coins: null), isNull);
      expect(headerAfterLoad(level: null, coins: 10), isNull);
    });

    test('the avatar is saved and restored, a real "none" included', () async {
      await saveHeaderAnswers(_a, avatar: (id: 'wolf'), now: t0);
      await seedHeader(_a, now: t0);
      expect(claimHeaderSeed(_a)!.avatar, 'wolf');
      // A failed avatar read keeps it.
      await saveHeaderAnswers(_a, avatar: null, now: t0);
      await seedHeader(_a, now: t0);
      expect(claimHeaderSeed(_a)!.avatar, 'wolf');
      await saveHeaderAnswers(_a, avatar: (id: null), now: t0);
      await seedHeader(_a, now: t0);
      expect(claimHeaderSeed(_a)!.avatar, isNull);
    });
  });

  group('seed owner and age', () {
    test("a different user's saved header is never used", () async {
      await saveHeaderAnswers(_a, level: info(2, 70, 250), coins: 120, avatar: (id: 'wolf'), now: t0);
      await seedHeader(_b, now: t0);
      expect(HeaderMotion.session, isNull);
      expect(claimHeaderSeed(_b)!.avatar, isNull);
    });

    test('a seed read for one user is dropped when another claims it', () async {
      await saveHeaderAnswers(_a, level: info(2, 70, 250), coins: 120, avatar: (id: 'wolf'), now: t0);
      await seedHeader(_a, now: t0);
      expect(HeaderMotion.session, isNotNull);
      expect(claimHeaderSeed(_b), isNull);
      expect(HeaderMotion.session, isNull);
    });

    test('the seed is taken once', () async {
      await saveHeaderAnswers(_a, level: info(2, 70, 250), coins: 120, now: t0);
      await seedHeader(_a, now: t0);
      expect(claimHeaderSeed(_a)!.numbers, isTrue);
      expect(claimHeaderSeed(_a), isNull);
    });

    test('7 days: just under seeds, just over does not', () async {
      await saveHeaderAnswers(_a, level: info(2, 70, 250), coins: 120, now: t0);
      await seedHeader(_a, now: t0.add(kSavedMaxAgeHeader));
      expect(HeaderMotion.session, isNotNull);
      HeaderMotion.session = null;
      await seedHeader(_a, now: t0.add(kSavedMaxAgeHeader + const Duration(minutes: 1)));
      expect(HeaderMotion.session, isNull);
    });

    test('a session already set is left as it is', () async {
      await saveHeaderAnswers(_a, level: info(2, 70, 250), coins: 120, now: t0);
      HeaderMotion.session = HeaderRecord(info(3, 10, 300), 500);
      await seedHeader(_a, now: t0);
      expect(HeaderMotion.session!.coins, 500);
      expect(claimHeaderSeed(_a)!.numbers, isFalse);
    });

    test('a sign-out wipe leaves nothing to seed', () async {
      await saveHeaderAnswers(_a, level: info(2, 70, 250), coins: 120, avatar: (id: 'wolf'), now: t0);
      await SavedCopy.wipe();
      await seedHeader(_a, now: t0);
      expect(HeaderMotion.session, isNull);
      expect(claimHeaderSeed(_a)!.avatar, isNull);
    });
  });

  group('the first answer after a seed', () {
    final saved = info(2, 70, 250);

    HeaderSyncMode first(LevelInfo level, int coins) => seededSyncMode(HeaderSyncMode.animate,
        shown: saved, shownCoins: 140, level: level, coins: coins);

    test('lower coins, a lower level or less xp snaps; higher animates', () {
      expect(first(saved, 40), HeaderSyncMode.snap);
      expect(first(info(1, 190, 200), 140), HeaderSyncMode.snap);
      expect(first(info(2, 60, 250), 140), HeaderSyncMode.snap);
      expect(first(info(2, 80, 250), 150), HeaderSyncMode.animate);
      expect(first(saved, 140), HeaderSyncMode.animate); // sync's matches() stops it
    });

    test('the rule ends only once a server answer is applied or found equal', () {
      // Offline: the load kept the saved numbers; nothing answered.
      expect(seedSettled(answered: false, mode: HeaderSyncMode.animate, matches: true), isFalse);
      // Equal answer while the header is held (another tab, a dialog).
      expect(seedSettled(answered: true, mode: HeaderSyncMode.hold, matches: true), isTrue);
      // Different answer while held: judged again on the retry.
      expect(seedSettled(answered: true, mode: HeaderSyncMode.hold, matches: false), isFalse);
      // Applied (count-up or snap).
      expect(seedSettled(answered: true, mode: HeaderSyncMode.animate, matches: false), isTrue);
      expect(seedSettled(answered: true, mode: HeaderSyncMode.snap, matches: false), isTrue);
    });

    test('hold and snap are kept', () {
      expect(seededSyncMode(HeaderSyncMode.hold, shown: saved, shownCoins: 140, level: saved, coins: 40),
          HeaderSyncMode.hold);
      expect(seededSyncMode(HeaderSyncMode.snap, shown: saved, shownCoins: 140, level: saved, coins: 400),
          HeaderSyncMode.snap);
    });

    testWidgets('saved equals real: the saved numbers paint at once, no sweep, no replay', (tester) async {
      await saveHeaderAnswers(_a, level: saved, coins: 140, now: t0);
      await seedHeader(_a, now: t0);
      final m = HeaderMotion(const TestVSync());
      addTearDown(m.dispose);
      expect(m.ready, isTrue);
      expect(m.coins, 140);
      expect(m.xp, 70); // full bar at once: the entry sweep is skipped
      m.sync(saved, 140, first(saved, 140));
      await tester.pump();
      expect(SchedulerBinding.instance.transientCallbackCount, 0);
      expect(m.coins, 140);
      await tester.pump(const Duration(seconds: 2));
      expect(m.xp, 70);
    });

    testWidgets('real higher: counts up from the saved number', (tester) async {
      await saveHeaderAnswers(_a, level: saved, coins: 140, now: t0);
      await seedHeader(_a, now: t0);
      final m = HeaderMotion(const TestVSync());
      addTearDown(m.dispose);
      m.sync(info(2, 80, 250), 150, first(info(2, 80, 250), 150));
      await tester.pump(const Duration(milliseconds: 100));
      await tester.pump(const Duration(milliseconds: 200));
      expect(m.coins, inExclusiveRange(140, 150));
      await tester.pump(const Duration(seconds: 1));
      expect(m.coins, 150);
      expect(m.xp, 80);
    });

    testWidgets('real lower: snaps, never counts down from the saved number', (tester) async {
      await saveHeaderAnswers(_a, level: saved, coins: 140, now: t0);
      await seedHeader(_a, now: t0);
      final m = HeaderMotion(const TestVSync());
      addTearDown(m.dispose);
      m.sync(saved, 40, first(saved, 40));
      expect(m.coins, 40);
      await tester.pump();
      expect(SchedulerBinding.instance.transientCallbackCount, 0);
      expect(HeaderMotion.session!.coins, 40);
    });
  });
}
