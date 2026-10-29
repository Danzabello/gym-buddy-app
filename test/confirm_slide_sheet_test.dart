import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/gestures.dart' show kTouchSlop;
import 'package:flutter_test/flutter_test.dart';
import 'package:gym_buddy_app/services/handshake_service.dart';
import 'package:gym_buddy_app/theme/app_theme.dart';
import 'package:gym_buddy_app/widgets/confirm_slide_sheet.dart';
import 'package:gym_buddy_app/widgets/workout_schedule_card.dart';

const _me = Person(name: 'Me', avatarId: 'wolf');
const _sam = Person(name: 'Sam', avatarId: 'lion');

Future<void> pump(WidgetTester t, CardAction a,
    {Person? buddy = _sam, Future<void> Function()? run, bool reduce = false, double scale = 1,
    bool talkback = false, String workout = 'Strength with Sam'}) async {
  await t.pumpWidget(MaterialApp(
    theme: ThemeData(extensions: [AppColors.fromAccent(AccentPalette.emeraldInk)]),
    builder: (ctx, child) => MediaQuery(
      data: MediaQuery.of(ctx).copyWith(
          disableAnimations: reduce, textScaler: TextScaler.linear(scale), accessibleNavigation: talkback),
      child: child!,
    ),
    home: Builder(
      builder: (ctx) => Scaffold(
        body: TextButton(
          onPressed: () => showConfirmSlideSheet(ctx,
              action: a, workout: workout, me: _me, buddy: buddy, run: run ?? () async {}),
          child: const Text('open'),
        ),
      ),
    ),
  ));
  await t.tap(find.text('open'));
  await t.pump();
  await t.pump(const Duration(milliseconds: 500));
}

Finder get thumb => find.byType(RingAvatar).last;
/// A finger that has passed touch slop, then moves [dx] more.
Future<TestGesture> hold(WidgetTester t, double dx) async {
  final g = await t.startGesture(t.getCenter(thumb));
  await g.moveBy(const Offset(kTouchSlop + 1, 0));
  await g.moveBy(Offset(dx, 0));
  await t.pump();
  return g;
}

Future<void> step(WidgetTester t, [int ms = 300]) async {
  await t.pump();
  await t.pump(Duration(milliseconds: ms));
}

void main() {
  testWidgets('exact copy for the four actions', (t) async {
    const cases = <CardAction, List<String>>{
      CardAction.leave: ['LEAVE WORKOUT', 'Leave Strength with Sam?',
        'Your timer stops and this workout does not count for you. Sam keeps going.', 'Slide to leave'],
      CardAction.abandon: ['CANCEL WORKOUT', 'Cancel this workout?',
        'Your timer stops and this workout does not count.', 'Slide to leave'],
      CardAction.cancel: ['CANCEL WORKOUT', 'Cancel Strength with Sam?',
        'Cancels it for you and Sam. Sam gets a notification.', 'Slide to cancel'],
      CardAction.cantMakeIt: ['WORKOUT INVITE', "Can't make it?",
        'Frees Sam up. Sam can still work out solo. No penalty.', 'Slide to confirm'],
    };
    for (final e in cases.entries) {
      await t.pumpWidget(const SizedBox());
      await pump(t, e.key, buddy: e.key == CardAction.abandon ? null : _sam);
      for (final s in e.value) {
        expect(find.text(s), findsOneWidget, reason: '${e.key}: $s');
      }
      expect(find.text('Keep workout'), findsOneWidget);
      expect(find.text('Now'), findsOneWidget);
      expect(find.text('After'), findsOneWidget);
    }
  });

  testWidgets('Keep workout closes and never runs the action', (t) async {
    var calls = 0;
    await pump(t, CardAction.leave, run: () async => calls++);
    await t.tap(find.text('Keep workout'));
    await step(t);
    expect(calls, 0);
    expect(find.byType(ConfirmSlideSheet), findsNothing);
  });

  testWidgets('a short drag springs back and does not confirm', (t) async {
    var calls = 0;
    await pump(t, CardAction.leave, run: () async => calls++);
    final x0 = t.getTopLeft(thumb).dx;
    final g = await hold(t, 120);
    expect(t.getTopLeft(thumb).dx, greaterThan(x0 + 100));
    await g.up();
    await step(t, 250);
    expect(t.getTopLeft(thumb).dx, x0);
    expect(calls, 0);
    expect(find.byType(ConfirmSlideSheet), findsOneWidget);
  });

  testWidgets('a full drag confirms exactly once and closes', (t) async {
    var calls = 0;
    await pump(t, CardAction.cancel, run: () async => calls++);
    await t.drag(thumb, const Offset(700, 0));
    await step(t);
    expect(calls, 1);
    expect(find.byType(ConfirmSlideSheet), findsNothing);
  });

  testWidgets('release past 85 percent confirms', (t) async {
    var calls = 0;
    await pump(t, CardAction.leave, run: () async => calls++);
    final track = t.getSize(find.bySemanticsLabel(RegExp('Slide to leave'))).width - 64;
    final g = await hold(t, track * 0.9);
    expect(calls, 0); // not released yet
    await g.up();
    await step(t);
    expect(calls, 1);
  });

  testWidgets('semantic tap confirms through the same path', (t) async {
    final h = t.ensureSemantics();
    var calls = 0;
    await pump(t, CardAction.cantMakeIt, run: () async => calls++);
    expect(find.bySemanticsLabel('Slide to confirm. Double tap to confirm'), findsOneWidget);
    t.semantics.tap(find.semantics.byLabel('Slide to confirm. Double tap to confirm'));
    await step(t);
    expect(calls, 1);
    h.dispose();
  });

  testWidgets('while it runs everything is disabled: no second submit', (t) async {
    final done = Completer<void>();
    var calls = 0;
    await pump(t, CardAction.leave, run: () { calls++; return done.future; });
    await t.drag(thumb, const Offset(700, 0));
    await step(t);
    expect(calls, 1);
    expect(find.text('Done'), findsOneWidget);
    expect(t.widget<FilledButton>(find.byType(FilledButton)).onPressed, isNull);
    await t.drag(thumb, const Offset(-300, 0));
    await step(t);
    await t.drag(thumb, const Offset(700, 0));
    await step(t);
    expect(calls, 1);
    done.complete();
    await step(t);
    expect(find.byType(ConfirmSlideSheet), findsNothing);
  });

  testWidgets('an error shows the mapped message and resets the slider', (t) async {
    var calls = 0;
    await pump(t, CardAction.cancel, run: () async {
      calls++;
      throw const HandshakeError('wrong_state');
    });
    final x0 = t.getTopLeft(thumb).dx;
    await t.drag(thumb, const Offset(700, 0));
    await step(t, 400);
    expect(find.text('This workout just changed. Showing the latest.'), findsOneWidget);
    expect(t.getTopLeft(thumb).dx, x0);
    expect(find.text('Slide to cancel'), findsOneWidget);
    expect(t.widget<FilledButton>(find.byType(FilledButton)).onPressed, isNotNull);
    await t.drag(thumb, const Offset(700, 0)); // can try again
    await step(t, 400);
    expect(calls, 2);
  });

  testWidgets('reduce motion starts no loop; otherwise one runs', (t) async {
    await pump(t, CardAction.leave, reduce: true);
    await t.pump(const Duration(seconds: 7));
    expect(t.binding.transientCallbackCount, 0);
    await t.pumpWidget(const SizedBox());
    await pump(t, CardAction.leave);
    expect(t.binding.transientCallbackCount, greaterThan(0));
  });

  testWidgets('text at 1.6x does not overflow and the track stays 64 dp', (t) async {
    t.view.physicalSize = const Size(720, 1280); // 360 x 640 dp
    t.view.devicePixelRatio = 2;
    addTearDown(t.view.reset);
    for (final a in CardAction.values.where((a) =>
        {CardAction.leave, CardAction.abandon, CardAction.cancel, CardAction.cantMakeIt}.contains(a))) {
      await t.pumpWidget(const SizedBox());
      await pump(t, a, scale: 1.6);
      expect(t.takeException(), isNull, reason: '$a');
      expect(t.getSize(find.bySemanticsLabel(RegExp('Double tap to confirm'))).height, 64);
    }
  });

  testWidgets('the TalkBack hint shows only with accessibility services on', (t) async {
    await pump(t, CardAction.leave);
    expect(find.text('Using TalkBack? Double tap the slider to confirm.'), findsNothing);
    await t.pumpWidget(const SizedBox());
    await pump(t, CardAction.leave, talkback: true);
    expect(find.text('Using TalkBack? Double tap the slider to confirm.'), findsOneWidget);
  });
}
