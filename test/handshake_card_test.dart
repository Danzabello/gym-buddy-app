import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gym_buddy_app/services/handshake_service.dart';
import 'package:gym_buddy_app/theme/app_theme.dart';
import 'package:gym_buddy_app/widgets/workout_invites_list.dart';
import 'package:gym_buddy_app/widgets/workout_schedule_card.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

final _now = DateTime.utc(2026, 10, 10, 12, 0, 0);

Map<String, dynamic> workout(String state, {
  bool creator = true, bool other = true, int goal = 45, String? startedAgo, String? lastNudgeAgo,
  String planned = '2026-10-10T14:14:00Z',
}) {
  DateTime? started;
  if (startedAgo != null) started = _now.subtract(Duration(minutes: int.parse(startedAgo)));
  return {
    'state': state,
    'workout_id': 'w1',
    'workout_type': 'Strength',
    'i_am_creator': creator,
    'planned_at': planned,
    'window_opens_at': '2026-10-10T14:09:00Z',
    'planned_duration_minutes': goal,
    'workout_started_at': started?.toIso8601String(),
    'goal_at': started?.add(Duration(minutes: goal)).toIso8601String(),
    'last_nudge_at': lastNudgeAgo == null
        ? null : _now.subtract(Duration(minutes: int.parse(lastNudgeAgo))).toIso8601String(),
    'other_person': other
        ? {'id': 'u2', 'display_name': 'Sam', 'avatar_id': 'bear', 'ring_color': '#FF6F5E'}
        : null,
  };
}

WorkoutCardData card(String state, {Map<String, dynamic>? w}) => WorkoutCardData.fromJson({
      'state': state,
      'workout': w ?? workout(state),
      'invites': [],
      'open_invite_count': 0,
      'server_now': _now.toIso8601String(),
    });

Future<List<CardAction>> pump(WidgetTester t, WorkoutCardData d,
    {int streak = 3, bool busy = false, bool reduce = true, int settleMs = 100}) async {
  final actions = <CardAction>[];
  final clock = ServerClock(() => DateTime.now())..sync(d.serverNow);
  await t.pumpWidget(MaterialApp(
    theme: ThemeData(extensions: [AppColors.fromAccent(AccentPalette.emeraldInk)]),
    home: Builder(builder: (c) => MediaQuery(
      data: MediaQuery.of(c).copyWith(disableAnimations: reduce),
      child: Scaffold(
        body: SingleChildScrollView(
          child: WorkoutScheduleCard(
              data: d, clock: clock, me: const Person(name: 'Me', avatarId: 'lion'),
              streakDays: streak, busy: busy, onAction: actions.add),
        ),
      ),
    )),
  ));
  await t.pump(Duration(milliseconds: settleMs));
  return actions;
}

void main() {
  testWidgets('every state shows its exact copy', (t) async {
    const cases = <String, List<String>>{
      'solo': ['Keep going', 'Same timer, same ring. Nothing else to tap until the goal.',
               'of 45 min', 'Finish unlocks at 45:00'],
      'time_to_start': ['Sam is in', "Tap I'm here. The timer starts when you both have.", "I'm here"],
      'i_am_here': ["You're here", 'Waiting for Sam. The timer starts the moment Sam taps.',
                    'Waiting for Sam', 'Nudge Sam'],
      'buddy_is_here': ['Sam is here', "Tap I'm here and the timer starts for both of you.",
                        "I'm here, start the timer"],
      'running': ['Together with Sam', 'Same timer on both phones.', 'Finish unlocks at 45:00'],
      'goal_reached': ['45:00 goal reached', 'Goal reached',
                       'You can finish now. Keep going if you want to.', 'Finish workout'],
      'buddy_cant_make_it': ["Sam can't make it",
          'No penalty for either of you. You can still train on your own today.',
          'Go solo', 'Cancel workout'],
    };
    for (final e in cases.entries) {
      final solo = e.key == 'solo';
      await pump(t, card(e.key, w: workout(e.key, other: !solo, startedAgo: '10')));
      for (final text in e.value) {
        expect(find.text(text), findsOneWidget, reason: '${e.key}: $text');
      }
      expect(find.text('Workout Schedule'), findsOneWidget);
      expect(find.text(solo ? 'Strength, 15:14' : 'Strength with Sam, 15:14'), findsOneWidget,
          reason: '${e.key} title line');
    }
  });

  testWidgets('waiting for start time: countdown, no button', (t) async {
    final d = card('waiting_start_time', w: workout('waiting_start_time',
        planned: _now.add(const Duration(hours: 2, minutes: 14)).toIso8601String()));
    await pump(t, d);
    expect(find.text('Starts in 2h 14m'), findsOneWidget);
    expect(find.byType(FilledButton), findsNothing);
    expect(find.byType(OutlinedButton), findsNothing);
  });

  testWidgets('streak line, plus the solo variant', (t) async {
    await pump(t, card('running', w: workout('running', startedAgo: '5')));
    expect(find.text('Day 3 streak: this workout keeps it alive'), findsOneWidget);
    await pump(t, card('buddy_cant_make_it'));
    expect(find.text('Day 3 streak: a solo workout today keeps it alive'), findsOneWidget);
  });

  testWidgets('Can\'t make it is for the invited person only', (t) async {
    await pump(t, card('time_to_start', w: workout('time_to_start', creator: false)));
    expect(find.text("Can't make it"), findsOneWidget);
    await pump(t, card('time_to_start'));
    expect(find.text("Can't make it"), findsNothing);
  });

  testWidgets('nudge is disabled with a countdown while it is cooling down', (t) async {
    await pump(t, card('i_am_here', w: workout('i_am_here', lastNudgeAgo: '4')));
    expect(find.textContaining('Nudge Sam, 0'), findsOneWidget); // about 06:00 left
    final b = t.widget<OutlinedButton>(find.widgetWithText(OutlinedButton, 'Nudge Sam, 05:59'));
    expect(b.onPressed, isNull);
  });

  testWidgets('busy disables the buttons', (t) async {
    await pump(t, card('time_to_start'), busy: true);
    expect(t.widget<FilledButton>(find.byType(FilledButton)).onPressed, isNull);
  });

  testWidgets('tapping I\'m here asks for imHere', (t) async {
    final actions = await pump(t, card('time_to_start'));
    await t.tap(find.text("I'm here"));
    expect(actions, [CardAction.imHere]);
  });

  Future<void> openMenu(WidgetTester t) async {
    await t.tap(find.byTooltip('Workout options'));
    await t.pump();
    await t.pump(const Duration(milliseconds: 400));
  }

  testWidgets('menu: inviter before start', (t) async {
    final actions = await pump(t, card('time_to_start'));
    await openMenu(t);
    expect(find.text('Strength with Sam'), findsOneWidget);
    expect(find.text('Change time'), findsOneWidget);
    expect(find.text('Sam gets a notification and can accept or decline.'), findsOneWidget);
    expect(find.text('Cancel workout'), findsOneWidget);
    expect(find.text('Cancels it for you and Sam. Sam gets a notification.'), findsOneWidget);
    expect(find.text('Keep workout'), findsOneWidget);
    expect(find.text('More'), findsNothing);
    // destructive: Are you sure first, nothing sent until confirmed
    await t.tap(find.text('Cancel workout'));
    await t.pump();
    await t.pump(const Duration(milliseconds: 400));
    expect(find.text('Are you sure?'), findsOneWidget);
    expect(actions, isEmpty);
    await t.tap(find.descendant(of: find.byType(AlertDialog), matching: find.text('Cancel workout')));
    await t.pump();
    await t.pump(const Duration(milliseconds: 400));
    expect(actions, [CardAction.cancel]);
  });

  testWidgets('menu: Are you sure can be declined', (t) async {
    final actions = await pump(t, card('time_to_start'));
    await openMenu(t);
    await t.tap(find.text('Cancel workout'));
    await t.pump();
    await t.pump(const Duration(milliseconds: 400));
    await t.tap(find.descendant(of: find.byType(AlertDialog), matching: find.text('Keep workout')));
    await t.pump();
    await t.pump(const Duration(milliseconds: 400));
    expect(actions, isEmpty);
  });

  testWidgets('menu: change time asks the page directly', (t) async {
    final actions = await pump(t, card('time_to_start'));
    await openMenu(t);
    await t.tap(find.text('Change time'));
    await t.pump();
    await t.pump(const Duration(milliseconds: 400));
    expect(actions, [CardAction.changeTime]);
    expect(find.text('Are you sure?'), findsNothing);
  });

  testWidgets('menu: invited person before start', (t) async {
    await pump(t, card('time_to_start', w: workout('time_to_start', creator: false)));
    await openMenu(t);
    expect(find.text("Can't make it"), findsNWidgets(2)); // button + menu
    expect(find.text('Frees Sam up. Sam can still work out solo. No penalty.'), findsOneWidget);
    expect(find.text('Change time'), findsNothing);
    expect(find.text('Cancel workout'), findsNothing);
  });

  testWidgets('menu: running together and solo', (t) async {
    await pump(t, card('running', w: workout('running', startedAgo: '5')));
    await openMenu(t);
    expect(find.text('Leave workout'), findsOneWidget);
    expect(find.text("Your timer stops and this workout doesn't count for you. Sam keeps going."),
        findsOneWidget);
    await t.tap(find.text('Keep workout'));
    await t.pump();
    await t.pump(const Duration(milliseconds: 400));
    await pump(t, card('solo', w: workout('solo', other: false, startedAgo: '5')));
    await openMenu(t);
    expect(find.text('Abandon workout'), findsOneWidget);
  });

  group('invites list', () {
    Map<String, dynamic> inv(int n) => {
          'workout_id': 'i$n', 'direction': 'received', 'state': 'waiting_start_time',
          'planned_at': '2026-10-10T18:00:00Z', 'planned_duration_minutes': 45,
          'other_person': {'display_name': 'Friend$n', 'avatar_id': 'wolf', 'ring_color': null},
        };

    Future<void> show(WidgetTester t, int count, {Map<String, Map<String, dynamic>> over = const {},
        void Function(String, {bool force})? onAccept}) async {
      await t.pumpWidget(MaterialApp(
        theme: ThemeData(extensions: [AppColors.fromAccent(AccentPalette.emeraldInk)]),
        home: Scaffold(body: SingleChildScrollView(child: WorkoutInvitesList(
          invites: [for (var i = 0; i < count; i++) inv(i)],
          overlaps: over,
          onAccept: onAccept ?? (_, {force = false}) {},
          onDecline: (_) {},
        ))),
      ));
    }

    testWidgets('received count only: no N of 5, no limit footer', (t) async {
      await show(t, 5);
      expect(find.text('Invitations'), findsOneWidget);
      expect(find.text('5'), findsOneWidget);
      expect(find.textContaining(' of 5'), findsNothing);
      expect(find.textContaining('Five invites'), findsNothing);
      expect(find.text('Accept'), findsNWidgets(5));
      expect(find.text('Decline'), findsNWidgets(5));
    });

    testWidgets('overlap: amber note, Accept anyway forces', (t) async {
      String? got;
      var forced = false;
      await show(t, 1, over: {
        'i0': {'state': 'overlap', 'with_name': 'Alex', 'with_planned_at': '2026-10-10T18:00:00Z'}
      }, onAccept: (id, {force = false}) { got = id; forced = force; });
      expect(find.textContaining('Overlaps with Alex at '), findsOneWidget);
      expect(find.textContaining('You can keep both, but only one can run at a time.'), findsOneWidget);
      expect(find.text('Accept'), findsNothing);
      await t.tap(find.text('Accept anyway'));
      expect((got, forced), ('i0', true));
    });
  });

  group('M4 finish button', () {
    testWidgets('one button, grey label under the orange wipe', (t) async {
      await pump(t, card('goal_reached', w: workout('goal_reached', startedAgo: '46')), reduce: false, settleMs: 0);
      expect(find.byType(FinishButton), findsOneWidget);
      expect(find.text('Finish workout'), findsOneWidget);
      expect(find.byKey(const Key('finish_wipe')), findsOneWidget);
      // start: the wipe has no width yet
      expect(t.getSize(find.byKey(const Key('finish_wipe'))).width, lessThan(5));
      await t.pump();
    await t.pump(const Duration(milliseconds: 400));
      final mid = t.getSize(find.byKey(const Key('finish_wipe'))).width;
      await t.pump(const Duration(milliseconds: 2000));
      final full = t.getSize(find.byKey(const Key('finish_wipe'))).width;
      expect(mid, greaterThan(0));
      expect(full, t.getSize(find.byType(FinishButton)).width);
      // wipe stays inside the button: no overlap with neighbours
      expect(t.getRect(find.byKey(const Key('finish_wipe'))).right,
          lessThanOrEqualTo(t.getRect(find.byType(FinishButton)).right + 0.5));
    });

    testWidgets('reduce motion: fully wiped at once', (t) async {
      final actions = await pump(t, card('goal_reached', w: workout('goal_reached', startedAgo: '46')));
      expect(t.getSize(find.byKey(const Key('finish_wipe'))).width,
          t.getSize(find.byType(FinishButton)).width);
      await t.tap(find.text('Finish workout'));
      expect(actions, [CardAction.finish]);
    });

    testWidgets('button is at least 48 high', (t) async {
      await pump(t, card('goal_reached', w: workout('goal_reached', startedAgo: '46')));
      expect(t.getSize(find.byType(FinishButton)).height, greaterThanOrEqualTo(48));
    });
  });

  group('pending finish', () {
    setUp(() => SharedPreferences.setMockInitialValues({}));

    test('saved once complete_workout worked, cleared when the credit worked', () async {
      final seen = <PendingFinish?>[];
      final svc = HandshakeService(rpc: (fn, p) async {
        if (fn == 'finish_checkin_session') seen.add(await PendingFinish.load());
        return <String, dynamic>{};
      });
      await svc.finish('w1', 46);
      expect(seen.single?.id, 'w1');
      expect(seen.single?.minutes, 46);
      expect(await PendingFinish.load(), isNull);
    });

    test('credit failure keeps the record; a later launch retries only the credit', () async {
      final calls = <String>[];
      var fail = true;
      final svc = HandshakeService(rpc: (fn, p) async {
        calls.add(fn);
        if (fn == 'finish_checkin_session' && fail) throw const PostgrestException(message: 'boom');
        return <String, dynamic>{};
      });
      await expectLater(svc.finish('w1', 46), throwsA(isA<CreditPending>()));
      final p = await PendingFinish.load();
      expect((p?.id, p?.minutes), ('w1', 46));
      // next launch (new service, same storage)
      fail = false;
      await HandshakeService(rpc: (fn, _) async { calls.add(fn); return <String, dynamic>{}; })
          .finish(p!.id, p.minutes, alreadyCompleted: true);
      expect(calls, ['complete_workout', 'finish_checkin_session', 'finish_checkin_session']);
      expect(await PendingFinish.load(), isNull);
    });

    test('a failed complete_workout leaves no record', () async {
      final svc = HandshakeService(rpc: (fn, p) async => throw const PostgrestException(message: 'too_early'));
      await expectLater(svc.finish('w1', 5), throwsA(isA<HandshakeError>()));
      expect(await PendingFinish.load(), isNull);
    });

    test('a workout that is gone is dropped, not retried forever', () async {
      final svc = HandshakeService(rpc: (fn, p) async {
        if (fn == 'finish_checkin_session') throw const PostgrestException(message: 'not_found');
        return <String, dynamic>{};
      });
      await expectLater(svc.finish('w1', 46), throwsA(isA<CreditPending>()));
      expect(await PendingFinish.load(), isNull);
    });
  });

  test('dashboard: only a session with no workout_id stays on the check-in sheet', () {
    expect(runsOnScheduleCard({'workout_id': null, 'started_at': 'x'}), isFalse); // dashboard solo
    expect(runsOnScheduleCard({'started_at': 'x'}), isFalse);
    expect(runsOnScheduleCard(null), isFalse);
    expect(runsOnScheduleCard({'workout_id': 'w1'}), isTrue);
  });

  test('avatars: waiting at the top, tapper rides, both meet', () {
    expect(avatarAngles('time_to_start').me.abs(), lessThan(0.5));
    expect(avatarAngles('i_am_here').me, lessThan(-1));
    expect(avatarAngles('buddy_is_here').them, greaterThan(1));
    expect((avatarAngles('running').them - avatarAngles('running').me).abs(), lessThan(0.5));
  });

  test('ring colour: hex parsed, junk falls back to null (theme emerald)', () {
    expect(ringFromHex('#FF6F5E'), const Color(0xFFFF6F5E));
    expect(ringFromHex(null), isNull);
    expect(ringFromHex('nope'), isNull);
  });

  group('server clock', () {
    test('offset = server_now - local now, then tracks the local clock', () {
      var local = DateTime.utc(2026, 10, 10, 12, 0, 0);
      final c = ServerClock(() => local)..sync(DateTime.utc(2026, 10, 10, 12, 5, 0));
      expect(c.offset, const Duration(minutes: 5));
      expect(c.now(), DateTime.utc(2026, 10, 10, 12, 5, 0));
      local = local.add(const Duration(seconds: 30));
      expect(c.now(), DateTime.utc(2026, 10, 10, 12, 5, 30));
    });

    test('a phone clock that is behind still shows the server elapsed time', () {
      final started = DateTime.utc(2026, 10, 10, 12, 0, 0);
      final c = ServerClock(() => DateTime.utc(2026, 10, 10, 11, 0, 0)) // phone 1h behind
        ..sync(DateTime.utc(2026, 10, 10, 12, 10, 0));
      expect(c.now().difference(started), const Duration(minutes: 10));
    });

    test('clockText', () {
      expect(clockText(const Duration(minutes: 45)), '45:00');
      expect(clockText(const Duration(seconds: 61)), '01:01');
      expect(clockText(const Duration(hours: 1, minutes: 2, seconds: 3)), '1:02:03');
      expect(clockText(const Duration(seconds: -4)), '00:00');
    });
  });

  group('error mapping', () {
    String msg(String code, {String? detail, String? name}) =>
        HandshakeError.from(PostgrestException(message: code, details: detail)).message(name: name);

    test('every documented code has a human message', () {
      for (final c in ['not_authenticated', 'not_found', 'not_participant', 'not_invitee',
          'not_creator', 'wrong_state', 'window_closed', 'too_early', 'already_in_workout',
          'daily_workout_limit_reached']) {
        expect(msg(c), isNot(contains('_')), reason: c);
        expect(msg(c), isNot('Something went wrong. Try again.'), reason: c);
      }
    });
    test('specific copy', () {
      expect(msg('already_in_workout'), 'Finish or leave your current workout first.');
      expect(msg('invite_cap_reached', name: 'Sam'), 'Sam has too many invites waiting. Try again later.');
      expect(msg('nudge_too_soon', detail: '125'), 'You can nudge again in 02:05.');
      expect(msg('nudge_too_soon'), contains('Try again soon'));
      expect(msg('something_new'), 'Something went wrong. Try again.');
    });
    test('non-postgres errors are unknown', () {
      expect(HandshakeError.from(Exception('socket')).code, 'unknown');
    });
  });

  group('service', () {
    setUp(() => SharedPreferences.setMockInitialValues({}));

    test('finish: complete_workout, then finish_checkin_session, in that order', () async {
      final calls = <String>[];
      final svc = HandshakeService(rpc: (fn, p) async { calls.add(fn); return <String, dynamic>{}; });
      await svc.finish('w1', 46);
      expect(calls, ['complete_workout', 'finish_checkin_session']);
    });

    test('second call fails: CreditPending, retry only repeats the second', () async {
      final calls = <String>[];
      var fail = true;
      final svc = HandshakeService(rpc: (fn, p) async {
        calls.add(fn);
        if (fn == 'finish_checkin_session' && fail) {
          throw const PostgrestException(message: 'boom');
        }
        return <String, dynamic>{};
      });
      await expectLater(svc.finish('w1', 46), throwsA(isA<CreditPending>()));
      fail = false;
      await svc.finish('w1', 46, alreadyCompleted: true);
      expect(calls, ['complete_workout', 'finish_checkin_session', 'finish_checkin_session']);
    });

    test('first call fails: the credit path is never called', () async {
      final calls = <String>[];
      final svc = HandshakeService(rpc: (fn, p) async {
        calls.add(fn);
        throw const PostgrestException(message: 'too_early');
      });
      await expectLater(svc.finish('w1', 5), throwsA(isA<HandshakeError>()));
      expect(calls, ['complete_workout']);
    });

    test('card parse reads keys by name', () async {
      final svc = HandshakeService(rpc: (fn, p) async => {
            'server_now': '2026-10-10T12:00:00Z', 'open_invite_count': 2, 'invites': [],
            'workout': null, 'state': 'none'});
      final d = await svc.card();
      expect((d.state, d.openInviteCount, d.workout), ('none', 2, null));
    });

    test('accept passes p_force', () async {
      Map<String, dynamic>? sent;
      final svc = HandshakeService(rpc: (fn, p) async { sent = p; return <String, dynamic>{}; });
      await svc.accept('w1', force: true);
      expect(sent, {'p_workout_id': 'w1', 'p_force': true});
    });
  });
}
