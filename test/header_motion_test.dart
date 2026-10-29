import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gym_buddy_app/services/level_service.dart';
import 'package:gym_buddy_app/widgets/header_motion.dart';

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

HeaderStep fill(int from, int to, int width) =>
    HeaderStep(HeaderStepKind.fill, fromXp: from, toXp: to, width: width);

void main() {
  setUp(() => HeaderMotion.session = null);

  group('planHeaderSteps', () {
    test('+10 xp inside a level is one fill', () {
      expect(planHeaderSteps(info(1, 60, 200), info(1, 70, 200)), [
        fill(60, 70, 200),
      ]);
    });

    test('+200 xp from level 1 at 60/200 to level 2 at 70/250', () {
      expect(planHeaderSteps(info(1, 60, 200), info(2, 70, 250)), [
        fill(60, 200, 200),
        const HeaderStep(HeaderStepKind.levelUp, width: 250, level: 2),
        const HeaderStep(HeaderStepKind.remainder, toXp: 70, width: 250),
      ]);
    });

    test('crossing two levels is exactly one level-up beat', () {
      final plan = planHeaderSteps(info(1, 60, 200), info(3, 30, 300));
      expect(plan.where((s) => s.kind == HeaderStepKind.levelUp), hasLength(1));
      expect(plan, [
        fill(60, 200, 200),
        const HeaderStep(HeaderStepKind.levelUp, width: 300, level: 3),
        const HeaderStep(HeaderStepKind.remainder, toXp: 30, width: 300),
      ]);
    });

    test('landing exactly on a new level has no remainder', () {
      final plan = planHeaderSteps(info(1, 60, 200), info(2, 0, 250));
      expect(plan.map((s) => s.kind), [
        HeaderStepKind.fill,
        HeaderStepKind.levelUp,
      ]);
    });

    test('a spend with no xp change plans nothing', () {
      expect(planHeaderSteps(info(2, 70, 250), info(2, 70, 250)), isEmpty);
    });

    test('no change at all plans nothing', () {
      expect(planHeaderSteps(info(1, 0, 200), info(1, 0, 200)), isEmpty);
    });

    test('a lower level plans nothing (the caller snaps)', () {
      expect(planHeaderSteps(info(3, 10, 300), info(2, 10, 250)), isEmpty);
    });
  });

  group('headerSyncMode', () {
    HeaderSyncMode mode({
      bool fg = true,
      bool reduce = false,
      bool covered = false,
      bool tab = true,
    }) => headerSyncMode(
      foreground: fg,
      reduceMotion: reduce,
      covered: covered,
      tabReady: tab,
    );

    test('animates only when foreground, uncovered, on the ready tab', () {
      expect(mode(), HeaderSyncMode.animate);
    });

    test('background and reduced motion snap', () {
      expect(mode(fg: false), HeaderSyncMode.snap);
      expect(mode(reduce: true), HeaderSyncMode.snap);
      expect(mode(reduce: true, covered: true), HeaderSyncMode.snap);
    });

    test('a covered page or a sliding tab holds', () {
      expect(mode(covered: true), HeaderSyncMode.hold);
      expect(mode(tab: false), HeaderSyncMode.hold);
    });
  });

  group('HeaderMotion.sync first value', () {
    test('sweeps from empty and records the numbers', () {
      final m = HeaderMotion(const TestVSync());
      m.sync(info(2, 70, 250), 140, HeaderSyncMode.animate);
      expect(m.xp, 0);
      expect(m.coins, 140);
      expect(HeaderMotion.session!.coins, 140);
      m.dispose();
    });

    test('reduced motion shows the final numbers at once', () {
      final m = HeaderMotion(const TestVSync());
      m.sync(info(2, 70, 250), 140, HeaderSyncMode.snap);
      expect(m.xp, 70);
      m.dispose();
    });
  });

  group('header widgets', () {
    late HeaderMotion motion;

    Future<void> pumpHeader(WidgetTester tester, {required bool sweep}) async {
      await tester.pumpWidget(
        MaterialApp(
          home: _Host(sweep: sweep, onMotion: (m) => motion = m),
        ),
      );
    }

    String xpText(WidgetTester tester) => tester
        .widgetList<Text>(find.byType(Text))
        .map((t) => t.data)
        .whereType<String>()
        .join('|');

    // Frame by frame, so tickers started by a timer or a finished step get a
    // frame to start on.
    Future<void> run(WidgetTester tester, int ms) async {
      for (var t = 0; t < ms; t += 16) {
        await tester.pump(const Duration(milliseconds: 16));
      }
    }

    double bar(WidgetTester tester) => tester
        .widget<LinearProgressIndicator>(find.byType(LinearProgressIndicator))
        .value!;

    testWidgets(
      'with animations disabled the first frame shows the final values',
      (tester) async {
        tester.platformDispatcher.accessibilityFeaturesTestValue =
            const FakeAccessibilityFeatures(disableAnimations: true);
        addTearDown(
          tester.platformDispatcher.clearAccessibilityFeaturesTestValue,
        );
        await tester.pumpWidget(const MaterialApp(home: _Host(onMotion: null)));
        expect(find.text('140'), findsOneWidget);
        expect(find.text('LV 2'), findsOneWidget);
        expect(find.text('LV 3'), findsOneWidget);
        expect(find.text(' · 70/250 XP'), findsOneWidget);
        expect(bar(tester), closeTo(70 / 250, 1e-9));
        await tester.pumpWidget(const SizedBox());
      },
    );

    testWidgets(
      'entry sweep starts empty, waits 600 ms, then fills over 1000 ms',
      (tester) async {
        await pumpHeader(tester, sweep: true);
        expect(bar(tester), 0);
        expect(find.text(' · 0/250 XP'), findsOneWidget);
        expect(find.text('140'), findsOneWidget); // coins show straight away
        await run(tester, 500);
        expect(bar(tester), 0);
        await run(tester, 300); // 600 ms pause is over
        expect(bar(tester), greaterThan(0));
        expect(bar(tester), lessThan(70 / 250));
        await run(tester, 1200);
        expect(bar(tester), closeTo(70 / 250, 1e-9));
        expect(find.text(' · 70/250 XP'), findsOneWidget);
        await tester.pumpWidget(const SizedBox());
      },
    );

    testWidgets('a credit counts coins and xp to the target', (tester) async {
      await pumpHeader(tester, sweep: false);
      motion.credit(info(2, 80, 250), 150);
      await tester.pump(const Duration(milliseconds: 100));
      await tester.pump(const Duration(milliseconds: 300));
      final mid = int.parse(xpText(tester).split('|').first);
      expect(mid, inExclusiveRange(140, 150));
      await tester.pump(const Duration(milliseconds: 1000));
      expect(find.text('150'), findsOneWidget);
      expect(find.text(' · 80/250 XP'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('a level-up plays one beat and ends on the new level', (
      tester,
    ) async {
      var settled = 0;
      await tester.pumpWidget(
        MaterialApp(
          home: _Host(
            sweep: false,
            onMotion: (m) => motion = m,
            onSettled: () => settled++,
          ),
        ),
      );
      motion.snap(info(1, 190, 200), 140);
      await tester.pump();
      motion.credit(info(3, 30, 300), 140);
      await run(tester, 700); // fill (600) done, pop under way
      expect(motion.popping, isTrue);
      expect(find.text('LV 1'), findsOneWidget); // swap waits for the peak
      await run(tester, 300);
      expect(find.text('LV 3'), findsWidgets);
      expect(bar(tester), 1); // holding full
      await run(tester, 1600);
      expect(find.text(' · 30/300 XP'), findsOneWidget);
      expect(bar(tester), closeTo(0.1, 1e-9));
      expect(settled, 1);
      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('a credit during the beat waits for it, then plays', (
      tester,
    ) async {
      await pumpHeader(tester, sweep: false);
      motion.snap(info(1, 190, 200), 140);
      await tester.pump();
      motion.credit(info(2, 10, 250), 140);
      await run(tester, 800); // mid-beat, bar held full
      motion.credit(info(2, 60, 250), 140);
      await run(tester, 100);
      expect(bar(tester), 1); // the queued credit has not touched the bar
      await run(tester, 3000);
      expect(find.text(' · 60/250 XP'), findsOneWidget);
      expect(find.text('LV 2'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
    });

    String coinText(WidgetTester tester) => tester
        .widget<Text>(
          find.descendant(
            of: find.byType(HeaderCoinCount),
            matching: find.byType(Text),
          ),
        )
        .data!;

    testWidgets('a header rebuilt after a spend counts down from the record', (
      tester,
    ) async {
      HeaderMotion.session = HeaderRecord(info(2, 70, 250), 140);
      await pumpHeader(tester, sweep: false);
      expect(coinText(tester), '140'); // the record shows before anything loads
      motion.sync(info(2, 70, 250), 40, HeaderSyncMode.animate);
      await run(tester, 300);
      final mid = int.parse(coinText(tester));
      expect(mid, inExclusiveRange(40, 140));
      expect(motion.ringOpacity, 0);
      await run(tester, 900);
      expect(coinText(tester), '40');
      expect(motion.ringOpacity, 0);
      expect(HeaderMotion.session!.coins, 40);
      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('a rebuild with identical values does not animate', (
      tester,
    ) async {
      HeaderMotion.session = HeaderRecord(info(2, 70, 250), 140);
      await pumpHeader(tester, sweep: false);
      motion.sync(info(2, 70, 250), 140, HeaderSyncMode.animate);
      await tester.pump();
      expect(tester.hasRunningAnimations, isFalse);
      expect(coinText(tester), '140');
      expect(motion.ringOpacity, 0);
      await tester.pumpWidget(const SizedBox());
    });

    testWidgets(
      'a catch-up credit counts up with the ring and plays the level-up',
      (tester) async {
        HeaderMotion.session = HeaderRecord(info(1, 190, 200), 40);
        await pumpHeader(tester, sweep: false);
        motion.sync(info(2, 30, 250), 140, HeaderSyncMode.animate);
        await run(tester, 240);
        expect(motion.ringOpacity, greaterThan(0));
        await run(tester, 3500);
        expect(coinText(tester), '140');
        expect(find.text('LV 2'), findsOneWidget);
        expect(find.text(' · 30/250 XP'), findsOneWidget);
        await tester.pumpWidget(const SizedBox());
      },
    );

    testWidgets('resume snaps and updates the record', (tester) async {
      HeaderMotion.session = HeaderRecord(info(2, 70, 250), 140);
      await pumpHeader(tester, sweep: false);
      motion.sync(info(2, 90, 250), 40, HeaderSyncMode.snap);
      await tester.pump();
      expect(coinText(tester), '40');
      expect(find.text(' · 90/250 XP'), findsOneWidget);
      expect(tester.hasRunningAnimations, isFalse);
      expect(HeaderMotion.session!.coins, 40);
      expect(HeaderMotion.session!.level.xpIntoCurrentLevel, 90);
      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('reduced motion snaps', (tester) async {
      tester.platformDispatcher.accessibilityFeaturesTestValue =
          const FakeAccessibilityFeatures(disableAnimations: true);
      addTearDown(
        tester.platformDispatcher.clearAccessibilityFeaturesTestValue,
      );
      HeaderMotion.session = HeaderRecord(info(2, 70, 250), 140);
      late BuildContext ctx;
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (c) {
              ctx = c;
              return _Host(onMotion: (m) => motion = m);
            },
          ),
        ),
      );
      motion.sync(
        info(2, 90, 250),
        40,
        headerSyncMode(
          foreground: true,
          reduceMotion: MediaQuery.disableAnimationsOf(ctx),
          covered: false,
          tabReady: true,
        ),
      );
      await tester.pump();
      expect(coinText(tester), '40');
      expect(tester.hasRunningAnimations, isFalse);
      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('a held write changes nothing', (tester) async {
      HeaderMotion.session = HeaderRecord(info(2, 70, 250), 140);
      await pumpHeader(tester, sweep: false);
      motion.sync(info(2, 70, 250), 40, HeaderSyncMode.hold);
      await run(tester, 1000);
      expect(coinText(tester), '140');
      expect(HeaderMotion.session!.coins, 140);
      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('a spend counts down without a ring', (tester) async {
      await pumpHeader(tester, sweep: false);
      motion.credit(info(2, 70, 250), 100);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));
      expect(motion.ringOpacity, 0);
      await tester.pump(const Duration(milliseconds: 1000));
      expect(find.text('100'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('a credit makes the ring pulse', (tester) async {
      await pumpHeader(tester, sweep: false);
      motion.credit(info(2, 70, 250), 150);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 240));
      expect(motion.ringOpacity, closeTo(1, 0.01));
      await tester.pump(const Duration(milliseconds: 1000));
      expect(motion.ringOpacity, 0);
      await tester.pumpWidget(const SizedBox());
    });
  });
}

class _Host extends StatefulWidget {
  const _Host({this.sweep, this.onMotion, this.onSettled});

  /// null: decide from MediaQuery like the dashboard does.
  final bool? sweep;
  final void Function(HeaderMotion)? onMotion;
  final VoidCallback? onSettled;

  @override
  State<_Host> createState() => _HostState();
}

class _HostState extends State<_Host> with TickerProviderStateMixin {
  late final HeaderMotion motion = HeaderMotion(
    this,
    onSettled: widget.onSettled,
  );

  @override
  void initState() {
    super.initState();
    widget.onMotion?.call(motion);
  }

  @override
  void dispose() {
    motion.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!motion.ready) {
      motion.init(
        info(2, 70, 250),
        140,
        sweep: widget.sweep ?? !MediaQuery.disableAnimationsOf(context),
      );
    }
    return Scaffold(
      body: Column(
        children: [
          HeaderCoinCount(
            motion: motion,
            fallback: 0,
            style: const TextStyle(),
          ),
          HeaderXpRow(
            motion: motion,
            semanticLabel: headerSemanticLabel(140, info(2, 70, 250)),
            track: Colors.grey,
            fill: Colors.orange,
            textColor: Colors.black,
            popColor: Colors.amber,
          ),
        ],
      ),
    );
  }
}
