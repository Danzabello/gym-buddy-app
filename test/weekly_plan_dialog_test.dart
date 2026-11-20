import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gym_buddy_app/home_screen.dart';
import 'package:gym_buddy_app/theme/app_theme.dart';
import 'package:gym_buddy_app/widgets/live_event_toast.dart';

const _number = ValueKey('weekly_plan_number');
const _breakDays = ValueKey('weekly_plan_break_days');
const _tier = ValueKey('weekly_plan_tier');
const _plus = ValueKey('weekly_plan_plus');
const _minus = ValueKey('weekly_plan_minus');
const _submit = ValueKey('weekly_plan_submit');
const _error = "Couldn't save your plan. Check your connection and try again.";
final _boundary = GlobalKey();

void main() {
  /// The page the dialog opens from, standing in for the dashboard: it shows
  /// the dialog, then the toast for a saved plan, as the dashboard does.
  Widget harness({
    required Future<void> Function(int) save,
    int initial = 5,
    bool reduce = false,
    void Function(int?)? onResult,
  }) =>
      RepaintBoundary(
        key: _boundary,
        child: MaterialApp(
        theme: ThemeData(extensions: const [AppColors.dark]),
        builder: reduce
            ? (c, child) => MediaQuery(
                  data: MediaQuery.of(c).copyWith(disableAnimations: true),
                  child: child!,
                )
            : null,
        home: Builder(
          builder: (context) => Scaffold(
            backgroundColor: Colors.white, // a known colour behind the scrim
            body: Center(
              child: ElevatedButton(
                onPressed: () async {
                  final r = await showWeeklyPlanDialog(context,
                      save: save, initialWorkoutDays: initial);
                  onResult?.call(r);
                  if (r != null && context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(weeklyPlanSnackBar(r));
                  }
                },
                child: const Text('open'),
              ),
            ),
          ),
        ),
        ),
      );

  Future<void> open(WidgetTester t, Widget app) async {
    t.view.physicalSize = const Size(800, 1600); // tall enough that nothing scrolls
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.reset);
    await t.pumpWidget(app);
    await t.tap(find.text('open'));
    await t.pump();
    await t.pump(const Duration(milliseconds: 400));
  }

  Future<void> wait(WidgetTester t, [int ms = 700]) => t.pump(Duration(milliseconds: ms));

  String number(WidgetTester t) => t.widget<Text>(find.byKey(_number)).data!;
  String breakLabel(WidgetTester t) => t.widget<Text>(find.byKey(_breakDays)).data!;
  String tier(WidgetTester t) => t.widget<Text>(find.byKey(_tier)).data!;
  double opacityOf(WidgetTester t, Key k) => t
      .widget<AnimatedOpacity>(find.descendant(of: find.byKey(k), matching: find.byType(AnimatedOpacity)))
      .opacity;

  group('the dialog', () {
    testWidgets('opens on 5 workout days and 2 break days, with one button', (t) async {
      await open(t, harness(save: (_) async {}));
      expect(number(t), '5');
      expect(breakLabel(t), '2 break days');
      expect(tier(t), 'SOLID');
      expect(find.text('Set my plan'), findsOneWidget);
      expect(find.text('Cancel'), findsNothing);
      expect(find.text('Skip'), findsNothing);
      final inDialog = find.byType(WeeklyPlanDialog);
      for (final type in [ElevatedButton, TextButton, OutlinedButton, IconButton]) {
        expect(find.descendant(of: inDialog, matching: find.byType(type)), findsNothing);
      }
    });

    testWidgets('Back and a tap on the barrier do not close it', (t) async {
      await open(t, harness(save: (_) async {}));
      await t.binding.handlePopRoute();
      await t.pump();
      await t.pump(const Duration(milliseconds: 400));
      expect(find.byType(WeeklyPlanDialog), findsOneWidget);

      await t.tapAt(const Offset(5, 5));
      await t.pump();
      await t.pump(const Duration(milliseconds: 400));
      expect(find.byType(WeeklyPlanDialog), findsOneWidget);
    });

    testWidgets('plus, minus and the segments change the number, the break days and the tier', (t) async {
      await open(t, harness(save: (_) async {}));

      await t.tap(find.byKey(_plus));
      await wait(t);
      expect([number(t), breakLabel(t), tier(t)], ['6', '1 break day', 'HEAVY']);

      await t.tap(find.byKey(_plus));
      await wait(t);
      expect([number(t), breakLabel(t), tier(t)], ['7', 'No break days', 'BEAST MODE']);
      expect(opacityOf(t, _plus), 0.35); // the limit
      await t.tap(find.byKey(_plus));
      await wait(t);
      expect(number(t), '7');

      await t.tap(find.byKey(const ValueKey('weekly_plan_segment_4')));
      await wait(t);
      expect([number(t), breakLabel(t), tier(t)], ['4', '3 break days', 'STEADY']);
      expect(opacityOf(t, _minus), 0.35); // the other limit
      await t.tap(find.byKey(_minus));
      await wait(t);
      expect(number(t), '4');
      expect(opacityOf(t, _plus), 1.0);

      await t.tap(find.byKey(const ValueKey('weekly_plan_segment_6')));
      await wait(t);
      expect(number(t), '6');
    });
  });

  group('layout', () {
    testWidgets('fits a small phone at every tier without overflowing', (t) async {
      t.view.physicalSize = const Size(320, 568);
      t.view.devicePixelRatio = 1;
      addTearDown(t.view.reset);
      await t.pumpWidget(harness(save: (_) async {}));
      await t.tap(find.text('open'));
      await t.pump();
      await t.pump(const Duration(milliseconds: 400));
      for (final n in [4, 5, 6, 7]) {
        await t.tap(find.byKey(ValueKey('weekly_plan_segment_$n')));
        await t.pump(const Duration(milliseconds: 700));
      }
      expect(t.takeException(), isNull); // an overflow would be reported here
      expect(find.text('Set my plan'), findsOneWidget);
    });
  });

  group('scrim and system bars', () {
    // A phone with a tall status bar and a gesture area.
    Future<void> openOnPhone(WidgetTester t) async {
      t.view.physicalSize = const Size(320, 568);
      t.view.devicePixelRatio = 1;
      t.view.padding = const FakeViewPadding(top: 40, bottom: 30);
      t.view.viewPadding = const FakeViewPadding(top: 40, bottom: 30);
      addTearDown(t.view.reset);
      await t.pumpWidget(harness(save: (_) async {}));
      await t.tap(find.text('open'));
      await t.pump();
      await t.pump(const Duration(milliseconds: 700));
    }

    /// The painted colour (r, g, b) at a pixel of the whole screen.
    Future<List<int>> pixel(WidgetTester t, int x, int y) async {
      final box = t.renderObject<RenderRepaintBoundary>(find.byKey(_boundary));
      final image = await t.runAsync(() => box.toImage());
      final data = (await t.runAsync(() => image!.toByteData()))!;
      final i = (y * image!.width + x) * 4;
      return [data.getUint8(i), data.getUint8(i + 1), data.getUint8(i + 2)];
    }

    testWidgets('the backdrop is dimmed to about 60% black, status bar and nav bar strips included', (t) async {
      await openOnPhone(t);
      // White behind, 60% black over it: 255 * 0.4 = 102. The corners are far
      // from the glow, so what shows is the dark layer alone. The top ones are
      // in the status bar strip, the bottom ones in the gesture strip.
      for (final p in [(2, 2), (317, 565), (317, 2), (2, 565)]) {
        final rgb = await pixel(t, p.$1, p.$2);
        for (final c in rgb) {
          expect(c, inInclusiveRange(96, 108), reason: 'pixel $p is $rgb, not dimmed');
        }
      }
    });

    testWidgets('the card stays inside the status bar and gesture areas', (t) async {
      await openOnPhone(t);
      final card = t.getRect(find.byKey(const ValueKey('weekly_plan_card')));
      expect(card.top, greaterThanOrEqualTo(40));
      expect(card.bottom, lessThanOrEqualTo(568 - 30));
      expect(card.left, greaterThanOrEqualTo(0));
      expect(card.right, lessThanOrEqualTo(320));
    });
  });

  group('saving', () {
    testWidgets('a good save calls the service with 7 minus the days, locks, then closes with the toast', (t) async {
      final calls = <int>[];
      final pending = Completer<void>();
      int? result = -1;
      await open(t, harness(
        save: (b) {
          calls.add(b);
          return pending.future;
        },
        onResult: (r) => result = r,
      ));

      await t.tap(find.byKey(_submit));
      await t.pump();
      expect(calls, [2]);
      expect(find.text('Saving...'), findsOneWidget);
      await t.tap(find.byKey(_plus)); // the stepper is locked while saving
      await t.pump();
      expect(number(t), '5');

      pending.complete();
      await t.pump();
      expect(find.byIcon(Icons.check_rounded), findsOneWidget);
      expect(find.byType(WeeklyPlanDialog), findsOneWidget); // the check shows first

      await t.pump(const Duration(milliseconds: 1000));
      await t.pump(const Duration(milliseconds: 400));
      expect(find.byType(WeeklyPlanDialog), findsNothing);
      expect(result, 2);
      expect(find.text('Set 2 break days for this week.'), findsOneWidget);
      expect(calls, [2]);
    });

    testWidgets('one break day reads in the singular, none in the plural', (t) async {
      final calls = <int>[];
      await open(t, harness(save: (b) async => calls.add(b), initial: 6));
      await t.tap(find.byKey(_submit));
      await t.pump(const Duration(milliseconds: 1000));
      await t.pump(const Duration(milliseconds: 400));
      expect(calls, [1]);
      expect(find.text('Set 1 break day for this week.'), findsOneWidget);

      expect(weeklyPlanSnackBar(0).content, isA<Text>());
      expect((weeklyPlanSnackBar(0).content as Text).data, 'Set 0 break days for this week.');
      expect((weeklyPlanSnackBar(3).content as Text).data, 'Set 3 break days for this week.');
    });

    testWidgets('a failed save keeps the dialog open with the message and Try again; a new number clears it', (t) async {
      var calls = 0;
      await open(t, harness(save: (_) async {
        calls++;
        throw Exception('network down');
      }));

      await t.tap(find.byKey(_submit));
      await t.pump();
      await t.pump(const Duration(milliseconds: 400));
      expect(find.byType(WeeklyPlanDialog), findsOneWidget);
      expect(find.text(_error), findsOneWidget);
      expect(find.text('Try again'), findsOneWidget);
      expect(find.text('Set my plan'), findsNothing);
      expect(calls, 1);

      await t.tap(find.byKey(_plus));
      await t.pump();
      await t.pump(const Duration(milliseconds: 700));
      expect(find.text(_error), findsNothing);
      expect(find.text('Set my plan'), findsOneWidget);
      expect(number(t), '6');
    });

    testWidgets('after a failure Try again saves and closes', (t) async {
      final calls = <int>[];
      int? result = -1;
      await open(t, harness(
        save: (b) async {
          calls.add(b);
          if (calls.length == 1) throw Exception('network down');
        },
        onResult: (r) => result = r,
      ));

      await t.tap(find.byKey(_submit));
      await t.pump();
      await t.pump(const Duration(milliseconds: 400));
      expect(find.text('Try again'), findsOneWidget);

      await t.tap(find.text('Try again'));
      await t.pump();
      await t.pump(const Duration(milliseconds: 1000));
      await t.pump(const Duration(milliseconds: 400));
      expect(calls, [2, 2]);
      expect(find.byType(WeeklyPlanDialog), findsNothing);
      expect(result, 2);
    });

    testWidgets('a double tap on Set my plan saves once', (t) async {
      var calls = 0;
      final pending = Completer<void>();
      await open(t, harness(save: (_) {
        calls++;
        return pending.future;
      }));

      await t.tap(find.byKey(_submit));
      await t.tap(find.byKey(_submit)); // no rebuild between the two
      await t.pump();
      await t.tap(find.byKey(_submit)); // and again while it shows Saving...
      await t.pump();
      expect(calls, 1);

      pending.complete();
      await t.pump();
      await t.pump(const Duration(milliseconds: 1000));
      await t.pump(const Duration(milliseconds: 400));
      expect(calls, 1);
    });
  });

  group('weeklyPlanNeeded (the check behind the dialog)', () {
    test('a read that says no plan shows the dialog, one that says there is a plan does not', () async {
      expect(await weeklyPlanNeeded(() async => true), isTrue);
      expect(await weeklyPlanNeeded(() async => false), isFalse);
    });

    test('a failed read is unknown: no dialog, reported once, and the next open asks again', () async {
      final reports = <String>[];
      void report(Object e, StackTrace? st, String label) => reports.add(label);
      var opens = 0;
      Future<bool> read() async {
        opens++;
        if (opens == 1) throw StateError('server error');
        return true;
      }

      expect(await weeklyPlanNeeded(read, report: report), isNull); // first open: unknown
      expect(reports, ['weekly_plan_check']);
      expect(await weeklyPlanNeeded(read, report: report), isTrue); // next open: asked again
      expect(reports, hasLength(1));
      expect(opens, 2);
    });

    test('offline is unknown too, and is not reported', () async {
      final reports = <String>[];
      final r = await weeklyPlanNeeded(() async => throw const SocketException('down'),
          report: (e, st, label) => reports.add(label));
      expect(r, isNull);
      expect(reports, isEmpty);
    });
  });

  group('the check waits for a free screen', () {
    test('a plan that exists is skipped, one that is missing opens only on a free screen, else later', () {
      expect(weeklyPlanStep(needsPlan: false, screenFree: true), WeeklyPlanStep.skip);
      expect(weeklyPlanStep(needsPlan: false, screenFree: false), WeeklyPlanStep.skip);
      expect(weeklyPlanStep(needsPlan: true, screenFree: true), WeeklyPlanStep.show);
      expect(weeklyPlanStep(needsPlan: true, screenFree: false), WeeklyPlanStep.later);
    });

    Widget app(void Function(BuildContext) grab) => MaterialApp(
          home: Builder(builder: (context) {
            grab(context);
            return Scaffold(
              body: Center(
                child: Column(mainAxisSize: MainAxisSize.min, children: [
                  ElevatedButton(
                    onPressed: () => Navigator.of(context).push(MaterialPageRoute<void>(
                        builder: (_) => const Scaffold(body: Text('a pushed page')))),
                    child: const Text('push'),
                  ),
                  ElevatedButton(
                    onPressed: () => showModalBottomSheet<void>(
                        context: context, builder: (_) => const SizedBox(height: 100)),
                    child: const Text('sheet'),
                  ),
                  ElevatedButton(
                    onPressed: () => showDialog<void>(
                        context: context, builder: (_) => const AlertDialog(title: Text('d'))),
                    child: const Text('dialog'),
                  ),
                ]),
              ),
            );
          }),
        );

    testWidgets('Home is free only while it is the current route on the Dashboard tab; the check then says later', (t) async {
      final wasActive = LiveEventToast.dashboardTabActive;
      addTearDown(() => LiveEventToast.dashboardTabActive = wasActive);
      LiveEventToast.dashboardTabActive = true;
      late BuildContext home;
      await t.pumpWidget(app((c) => home = c));
      expect(weeklyPlanScreenIsFree(home), isTrue);
      expect(weeklyPlanStep(needsPlan: true, screenFree: weeklyPlanScreenIsFree(home)),
          WeeklyPlanStep.show);

      // A pushed page above Home: not free, so no dialog and the flag stays unset.
      await t.tap(find.text('push'));
      await t.pumpAndSettle();
      expect(weeklyPlanScreenIsFree(home), isFalse);
      expect(weeklyPlanStep(needsPlan: true, screenFree: weeklyPlanScreenIsFree(home)),
          WeeklyPlanStep.later);
      Navigator.of(home).pop();
      await t.pumpAndSettle();
      expect(weeklyPlanScreenIsFree(home), isTrue);

      // A bottom sheet above Home.
      await t.tap(find.text('sheet'));
      await t.pumpAndSettle();
      expect(weeklyPlanScreenIsFree(home), isFalse);
      Navigator.of(home).pop();
      await t.pumpAndSettle();

      // Another dialog above Home (the pending-notice dialog is one).
      await t.tap(find.text('dialog'));
      await t.pumpAndSettle();
      expect(weeklyPlanScreenIsFree(home), isFalse);
      Navigator.of(home).pop();
      await t.pumpAndSettle();
      expect(weeklyPlanScreenIsFree(home), isTrue);

      // Another tab shown.
      LiveEventToast.dashboardTabActive = false;
      expect(weeklyPlanScreenIsFree(home), isFalse);
    });
  });

  group('reduced motion', () {
    testWidgets('a change shows the new value and colours at once, with no animation left running', (t) async {
      await open(t, harness(save: (_) async {}, reduce: true));
      await wait(t); // the route's own transition has ended
      expect(t.binding.transientCallbackCount, 0);

      await t.tap(find.byKey(_plus));
      await t.pump(); // one frame, no time passes
      expect(number(t), '6');
      expect(tier(t), 'HEAVY');
      expect(t.binding.transientCallbackCount, 0); // no pop, no ring, no throb

      await t.tap(find.byKey(_plus));
      await t.pump();
      expect(number(t), '7');
      expect(t.binding.transientCallbackCount, 0); // no jitter
    });

    testWidgets('with motion on, tier 6 throbs until the dialog closes', (t) async {
      await open(t, harness(save: (_) async {}, initial: 6));
      await wait(t);
      expect(t.binding.transientCallbackCount, greaterThan(0));
      await t.tap(find.byKey(_submit));
      await t.pump(const Duration(milliseconds: 1000));
      await t.pump(const Duration(milliseconds: 400));
      expect(find.byType(WeeklyPlanDialog), findsNothing);
      expect(t.binding.transientCallbackCount, 0);
    });
  });
}
