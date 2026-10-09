import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gym_buddy_app/pages/finish_flow.dart';
import 'package:gym_buddy_app/pages/schedule_deps.dart';
import 'package:gym_buddy_app/pages/schedule_page.dart';
import 'package:gym_buddy_app/pages/workout_page.dart';
import 'package:gym_buddy_app/services/handshake_service.dart';
import 'package:gym_buddy_app/services/notification_service.dart';
import 'package:gym_buddy_app/theme/app_theme.dart';
import 'package:gym_buddy_app/widgets/schedule_rows.dart';
import 'package:gym_buddy_app/widgets/workout_schedule_card.dart';
import 'package:shared_preferences/shared_preferences.dart';

final _now = DateTime.now().toUtc();
String _iso(DateTime t) => t.toIso8601String();

/// A workout as get_workout_card returns it, from my side.
Map<String, dynamic> wk(String id, String state, {
  String type = 'Strength', String? other = 'Alex', bool creator = true,
  Duration startsIn = const Duration(hours: 2), int? startedAgoMin, int goal = 45,
}) {
  final planned = _now.add(startsIn);
  final started = startedAgoMin == null ? null : _now.subtract(Duration(minutes: startedAgoMin));
  return {
    'state': state, 'workout_id': id, 'workout_type': type, 'i_am_creator': creator,
    'planned_at': _iso(planned), 'window_opens_at': _iso(planned.subtract(const Duration(minutes: 5))),
    'planned_duration_minutes': goal,
    'workout_started_at': started == null ? null : _iso(started),
    'goal_at': started == null ? null : _iso(started.add(Duration(minutes: goal))),
    'last_nudge_at': null,
    'other_person': other == null
        ? null
        : {'id': 'u2', 'display_name': other, 'avatar_id': 'lion', 'ring_color': '#FF6F5E'},
  };
}

Map<String, dynamic> inv(int n) => {
      'workout_id': 'inv$n', 'direction': 'received', 'state': 'waiting_start_time',
      'planned_at': _iso(_now.add(Duration(hours: n + 1))), 'planned_duration_minutes': 45,
      'other_person': {'display_name': 'Friend$n', 'avatar_id': 'wolf', 'ring_color': null},
    };

class Fake {
  final List<Map<String, dynamic>> workouts;
  final List<Map<String, dynamic>> invites;
  final int out;
  final Map<String, dynamic>? Function(String fn, Map<String, dynamic> p)? onRpc;
  final calls = <String>[];
  Fake(this.workouts, {this.invites = const [], this.out = 0, this.onRpc});

  Map<String, dynamic> cardOf(Map<String, dynamic> w) => {
        'state': w['state'], 'workout': w, 'invites': [], 'open_invite_count': out,
        'server_now': _iso(DateTime.now().toUtc()),
      };

  ScheduleDeps deps({FinishHooks? hooks}) => ScheduleDeps(
        finishHooks: hooks,
        svc: HandshakeService(rpc: (fn, p) async {
          calls.add(fn);
          final custom = onRpc?.call(fn, p);
          if (custom != null) return custom;
          if (fn == 'get_workout_card') {
            final id = p['p_workout_id'] as String?;
            if (id == null) {
              return {
                'state': 'none', 'workout': null, 'invites': invites, 'open_invite_count': out,
                'server_now': _iso(DateTime.now().toUtc()),
              };
            }
            return cardOf(workouts.firstWhere((w) => w['workout_id'] == id));
          }
          return <String, dynamic>{};
        }),
        listen: (_) => () {},
        loadMe: () async => const Person(name: 'Me', avatarId: 'bear'),
        loadStreak: () async => 3,
        listIds: () async => [for (final w in workouts) w['workout_id'] as String],
        completed: (_) => const Text('Recent completed workouts'),
      );
}

Widget app(Widget home) => MaterialApp(
      theme: ThemeData(extensions: [AppColors.fromAccent(AccentPalette.emeraldInk)]),
      home: home,
    );

/// Finish a route push or pop (a ticker is always running, so no pumpAndSettle).
Future<void> go(WidgetTester t) async {
  await t.pump();
  await t.pump(const Duration(seconds: 1));
  await t.pump();
}

Future<void> settle(WidgetTester t) async {
  await t.pump();
  await t.pump(const Duration(milliseconds: 50));
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  group('list page', () {
    testWidgets('empty: the existing empty layout', (t) async {
      final f = Fake([]);
      await t.pumpWidget(app(SchedulePage(deps: f.deps())));
      await settle(t);
      expect(find.text('Workout Schedule'), findsOneWidget);
      expect(find.text('No scheduled workouts'), findsOneWidget);
      expect(find.text('Recent completed workouts'), findsOneWidget);
      expect(find.text('Invitations'), findsNothing);
      expect(find.text('Now'), findsNothing);
    });

    testWidgets('one upcoming workout, with a green countdown', (t) async {
      final f = Fake([wk('a', 'waiting_start_time', startsIn: const Duration(hours: 2, minutes: 14))]);
      await t.pumpWidget(app(SchedulePage(deps: f.deps())));
      await settle(t);
      expect(find.text('Upcoming'), findsOneWidget);
      expect(find.text('Strength with Alex'), findsOneWidget);
      expect(find.textContaining('starts in 2h 14m', findRichText: true), findsOneWidget);
      expect(find.text('Now'), findsNothing);
      expect(find.text('No scheduled workouts'), findsNothing);
    });

    testWidgets('three upcoming, earliest first, no Now row', (t) async {
      final f = Fake([
        wk('c', 'waiting_start_time', type: 'Yoga', other: 'Cleo', startsIn: const Duration(hours: 9)),
        wk('a', 'waiting_start_time', type: 'Cardio', other: 'Ann', startsIn: const Duration(hours: 3)),
        wk('b', 'waiting_start_time', type: 'HIIT', other: null, startsIn: const Duration(hours: 5)),
      ]);
      await t.pumpWidget(app(SchedulePage(deps: f.deps())));
      await settle(t);
      final ys = [for (final s in ['Cardio with Ann', 'HIIT', 'Yoga with Cleo']) t.getTopLeft(find.text(s)).dy];
      expect(ys[0] < ys[1] && ys[1] < ys[2], isTrue);
      expect(find.byType(UpcomingRow), findsNWidgets(3));
      expect(find.byType(NowRow), findsNothing);
    });

    testWidgets('a running workout is the Now row and ticks from the server clock', (t) async {
      final f = Fake([
        wk('r', 'running', startedAgoMin: 12, startsIn: const Duration(minutes: -12)),
        wk('u', 'waiting_start_time', type: 'Yoga', other: 'Cleo'),
      ]);
      await t.pumpWidget(app(SchedulePage(deps: f.deps())));
      await settle(t);
      expect(find.byType(NowRow), findsOneWidget);
      expect(find.text('Now'), findsOneWidget);
      expect(find.text('Strength with Alex'), findsOneWidget);
      expect(find.textContaining('Running 12:0'), findsOneWidget);
      expect(find.text('Yoga with Cleo'), findsOneWidget); // upcoming, not Now
      await t.pump(const Duration(seconds: 2));
      expect(find.textContaining('Running 12:0'), findsOneWidget);
    });

    test('Now status lines', () {
      final n = DateTime.utc(2026, 10, 10, 12);
      String st(String s, {int? ago}) => nowStatus(
          wk('x', s, startedAgoMin: ago).map((k, v) => MapEntry(k, v)), n);
      expect(st('time_to_start'), 'Time to start');
      expect(st('i_am_here'), 'Waiting for Alex');
      expect(st('buddy_is_here'), 'Alex is here');
      expect(st('goal_reached', ago: 50), 'Goal reached');
      expect(st('buddy_cant_make_it'), "Alex can't make it");
      final w = wk('x', 'running');
      w['workout_started_at'] = n.subtract(const Duration(minutes: 12, seconds: 4)).toIso8601String();
      expect(nowStatus(w, n), 'Running 12:04');
    });

    testWidgets('tapping the Now row opens its page; back returns to the list', (t) async {
      final f = Fake([wk('r', 'running', startedAgoMin: 5, startsIn: const Duration(minutes: -5))]);
      await t.pumpWidget(app(SchedulePage(deps: f.deps())));
      await settle(t);
      await t.tap(find.byType(NowRow));
      await go(t);
      expect(find.byType(WorkoutPage), findsOneWidget);
      await t.tap(find.byType(BackButton));
      await go(t);
      expect(find.byType(WorkoutPage), findsNothing);
      await t.pump(const Duration(seconds: 31)); // poll + refetch: nothing re-opens it
      expect(find.byType(WorkoutPage), findsNothing);
      expect(find.byType(SchedulePage), findsOneWidget);
    });

    testWidgets('invitations: received count only, no N of 5, no footer', (t) async {
      final f = Fake([], invites: [for (var i = 0; i < 5; i++) inv(i)], out: 2);
      await t.pumpWidget(app(SchedulePage(deps: f.deps())));
      await settle(t);
      expect(find.text('Invitations'), findsOneWidget);
      expect(find.text('5'), findsOneWidget);
      expect(find.textContaining(' of 5'), findsNothing);
      expect(find.textContaining('Five invites'), findsNothing);
      expect(find.text('Accept'), findsNWidgets(5));
      expect(find.text('No scheduled workouts'), findsNothing);
    });

    testWidgets('sent line only from 3', (t) async {
      await t.pumpWidget(app(SchedulePage(deps: Fake([], invites: [inv(0)], out: 3).deps())));
      await settle(t);
      expect(find.text('You have 3 of 5 invites out'), findsOneWidget);
      await t.pumpWidget(const SizedBox());
      await t.pumpWidget(app(SchedulePage(deps: Fake([], invites: [inv(0)], out: 2).deps())));
      await settle(t);
      expect(find.textContaining('invites out'), findsNothing);
    });

    testWidgets('overlap: amber note, Accept anyway sends force', (t) async {
      Map<String, dynamic>? sent;
      final f = Fake([], invites: [inv(0)], onRpc: (fn, p) {
        if (fn == 'accept_workout_invite') {
          sent = p;
          return p['p_force'] == true
              ? {'state': 'accepted'}
              : {'state': 'overlap', 'with_name': 'Alex', 'with_planned_at': _iso(_now.add(const Duration(hours: 1)))};
        }
        return null;
      });
      await t.pumpWidget(app(SchedulePage(deps: f.deps())));
      await settle(t);
      await t.tap(find.text('Accept'));
      await settle(t);
      expect(find.textContaining('Overlaps with Alex at '), findsOneWidget);
      expect(find.textContaining('You can keep both, but only one can run at a time.'), findsOneWidget);
      await t.tap(find.text('Accept anyway'));
      await settle(t);
      expect(sent?['p_force'], true);
    });

    testWidgets('row menu per role, with Are you sure', (t) async {
      final f = Fake([
        wk('mine', 'waiting_start_time', startsIn: const Duration(hours: 2)),
        wk('theirs', 'waiting_start_time', type: 'Yoga', other: 'Cleo', creator: false, startsIn: const Duration(hours: 4)),
      ]);
      await t.pumpWidget(app(SchedulePage(deps: f.deps())));
      await settle(t);
      Future<void> menu(int i) async {
        await t.tap(find.byTooltip('Workout options').at(i));
        await go(t);
      }
      await menu(0);
      expect(find.text('Change time'), findsOneWidget);
      expect(find.text('Cancel workout'), findsOneWidget);
      expect(find.text('Keep workout'), findsOneWidget);
      expect(find.text('More'), findsNothing);
      await t.tap(find.text('Cancel workout'));
      await go(t);
      expect(find.text('Are you sure?'), findsOneWidget);
      expect(f.calls.contains('cancel_workout'), isFalse);
      await t.tap(find.descendant(of: find.byType(AlertDialog), matching: find.text('Cancel workout')));
      await settle(t);
      expect(f.calls.contains('cancel_workout'), isTrue);

      await menu(1);
      expect(find.text("Can't make it"), findsOneWidget);
      expect(find.text('Change time'), findsNothing);
      await t.tap(find.text('Keep workout'));
      await go(t);
    });
  });

  group('workout page', () {
    Future<void> open(WidgetTester t, Map<String, dynamic> w) async {
      await t.pumpWidget(const SizedBox()); // a fresh State every time
      final key = GlobalKey<NavigatorState>();
      await t.pumpWidget(MaterialApp(
        navigatorKey: key,
        theme: ThemeData(extensions: [AppColors.fromAccent(AccentPalette.emeraldInk)]),
        home: const Scaffold(),
      ));
      key.currentState!.push(MaterialPageRoute(
          builder: (_) => WorkoutPage(workoutId: w['workout_id'] as String, deps: Fake([w]).deps())));
      await go(t);
    }

    testWidgets('header: back arrow, title, options, planned time', (t) async {
      await open(t, wk('w', 'time_to_start', startsIn: Duration.zero));
      expect(find.byType(BackButton), findsOneWidget);
      expect(find.text('Strength with Alex'), findsOneWidget);
      expect(find.byTooltip('Workout options'), findsOneWidget);
      expect(find.textContaining('Today'), findsOneWidget);
      // the card has no header of its own on this page
      expect(find.text('Workout Schedule'), findsNothing);
    });

    testWidgets('solo title is just the type', (t) async {
      await open(t, wk('w', 'solo', other: null, startedAgoMin: 3, startsIn: const Duration(minutes: -3)));
      expect(find.text('Strength'), findsOneWidget);
      expect(find.text('Keep going'), findsOneWidget);
    });

    testWidgets('states show the H3 copy', (t) async {
      const cases = {
        'time_to_start': ['Alex is in', "I'm here"],
        'i_am_here': ["You're here", 'Waiting for Alex'],
        'buddy_is_here': ['Alex is here', "I'm here, start the timer"],
        'running': ['Together with Alex', 'Same timer on both phones.'],
        'goal_reached': ['45:00 goal reached', 'Finish workout'],
        'buddy_cant_make_it': ["Alex can't make it", 'Go solo', 'Cancel workout'],
      };
      for (final e in cases.entries) {
        await open(t, wk('w', e.key, startedAgoMin: e.key == 'goal_reached' ? 50 : 5,
            startsIn: Duration.zero));
        for (final s in e.value) {
          expect(find.text(s), findsOneWidget, reason: '${e.key}: $s');
        }
      }
    });

    testWidgets('menu per role: inviter, invited, running, solo', (t) async {
      Future<void> check(Map<String, dynamic> w, List<String> has, List<String> not) async {
        await open(t, w);
        await t.tap(find.byTooltip('Workout options'));
        await go(t);
        for (final s in has) { expect(find.text(s), findsWidgets, reason: s); }
        for (final s in not) { expect(find.text(s), findsNothing, reason: s); }
        expect(find.text('Keep workout'), findsOneWidget);
        expect(find.text('More'), findsNothing);
        await t.tap(find.text('Keep workout'));
        await go(t);
      }
      await check(wk('w', 'time_to_start', startsIn: Duration.zero), ['Change time', 'Cancel workout'], ['Leave workout']);
      await check(wk('w', 'time_to_start', creator: false, startsIn: Duration.zero), ["Can't make it"], ['Change time']);
      await check(wk('w', 'running', startedAgoMin: 4), ['Leave workout'], ['Cancel workout']);
      await check(wk('w', 'solo', other: null, startedAgoMin: 4), ['Abandon workout'], ['Leave workout']);
    });

    testWidgets('back works and nothing re-pushes the page', (t) async {
      final w = wk('w', 'running', startedAgoMin: 5, startsIn: const Duration(minutes: -5));
      final f = Fake([w]);
      await t.pumpWidget(app(Builder(
        builder: (c) => Scaffold(
          body: Center(
            child: TextButton(
              onPressed: () => Navigator.of(c).push(
                  MaterialPageRoute(builder: (_) => WorkoutPage(workoutId: 'w', deps: f.deps()))),
              child: const Text('open'),
            ),
          ),
        ),
      )));
      await t.tap(find.text('open'));
      await go(t);
      expect(find.byType(WorkoutPage), findsOneWidget);
      await t.tap(find.byType(BackButton));
      await go(t);
      expect(find.byType(WorkoutPage), findsNothing);
      expect(find.text('open'), findsOneWidget);
      await t.pump(const Duration(seconds: 65)); // poll timers and refetches
      expect(find.byType(WorkoutPage), findsNothing);
      expect(find.text('open'), findsOneWidget);
    });

    testWidgets('Finish: the page goes back only after the celebration and the streak sheet are dismissed', (t) async {
      final w = wk('w', 'goal_reached', startedAgoMin: 50, startsIn: const Duration(minutes: -50));
      final f = Fake([w]);
      final celebration = Completer<void>(), sheet = Completer<void>();
      final steps = <String>[];
      final hooks = FinishHooks(
        apply: (_) async => {'teams_updated': 1, 'partner_bonus_earned': true},
        achievements: (_, __) {},
        celebrate: (_, __, ___, ____) { steps.add('celebration'); return celebration.future; },
        streakSheet: (_) { steps.add('streak sheet'); return sheet.future; },
      );
      await t.pumpWidget(const SizedBox());
      final key = GlobalKey<NavigatorState>();
      await t.pumpWidget(MaterialApp(
        navigatorKey: key,
        theme: ThemeData(extensions: [AppColors.fromAccent(AccentPalette.emeraldInk)]),
        home: const Scaffold(body: Text('home')),
      ));
      key.currentState!.push(MaterialPageRoute(
          builder: (_) => WorkoutPage(workoutId: 'w', deps: f.deps(hooks: hooks))));
      await go(t);
      await t.tap(find.text('Finish workout'));
      await t.pump();
      await t.pump(const Duration(milliseconds: 100));
      // order on the server: complete, then credit
      expect(f.calls.where((c) => c == 'complete_workout' || c == 'finish_checkin_session').toList(),
          ['complete_workout', 'finish_checkin_session']);
      expect(steps, ['celebration']);
      await go(t);
      expect(find.byType(WorkoutPage), findsOneWidget, reason: 'celebration still up');
      celebration.complete();
      await t.pump(const Duration(milliseconds: 100));
      expect(steps, ['celebration', 'streak sheet']);
      await go(t);
      expect(find.byType(WorkoutPage), findsOneWidget, reason: 'streak sheet still up');
      sheet.complete();
      await t.pump(const Duration(milliseconds: 100));
      await go(t);
      expect(find.byType(WorkoutPage), findsNothing);
      expect(find.text('home'), findsOneWidget);
    });

    testWidgets('a closed workout shows a plain message, still leaveable', (t) async {
      await open(t, wk('w', 'closed'));
      expect(find.text('This workout is over.'), findsOneWidget);
      expect(find.byType(BackButton), findsOneWidget);
    });
  });

  group('avatar positions', () {
    test('buddy: before anyone taps they sit at 11 and 1', () {
      for (final s in ['waiting_start_time', 'time_to_start']) {
        final a = avatarSpots(s, solo: false);
        expect((a.me, a.them), (330.0, 30.0), reason: s);
        expect((a.meIn, a.themIn), (false, false));
      }
    });
    test('I tap: me down the left to 7, buddy still at 1', () {
      final a = avatarSpots('i_am_here', solo: false);
      expect((a.me, a.them, a.meIn, a.themIn), (210.0, 30.0, true, false));
    });
    test('buddy taps first: buddy at 5, me still at 11', () {
      final a = avatarSpots('buddy_is_here', solo: false);
      expect((a.me, a.them, a.meIn, a.themIn), (330.0, 150.0, false, true));
    });
    test('both in: side by side at 6, both in', () {
      for (final s in ['running', 'goal_reached']) {
        final a = avatarSpots(s, solo: false);
        expect(a.me, greaterThan(180));
        expect(a.them, lessThan(180));
        expect((a.me - 180) + (180 - a.them!), lessThan(40)); // close enough to touch
        expect((a.meIn, a.themIn), (true, true));
      }
    });
    test('solo: 12 until the tap, then 6 for the whole workout', () {
      for (final s in ['waiting_start_time', 'time_to_start']) {
        final a = avatarSpots(s, solo: true);
        expect(a.me % 360, 0.0, reason: s);
        expect((a.them, a.meIn), (null, false));
      }
      for (final s in ['solo', 'running', 'goal_reached']) {
        final a = avatarSpots(s, solo: true);
        expect((a.me, a.them, a.meIn), (180.0, null, true), reason: s);
      }
    });
    test('the ride goes the right way round', () {
      // me: 11 o'clock (330) to 7 o'clock (210) passes 9 o'clock (270): anticlockwise, left side
      expect(avatarSpots('i_am_here', solo: false).me, lessThan(avatarSpots('time_to_start', solo: false).me));
      // buddy: 1 o'clock (30) to 5 o'clock (150) passes 3 o'clock (90): clockwise, right side
      expect(avatarSpots('buddy_is_here', solo: false).them, greaterThan(avatarSpots('time_to_start', solo: false).them!));
    });
    test('never depends on the timer: same state, same place', () {
      expect(avatarSpots('running', solo: false).me, avatarSpots('running', solo: false).me);
    });
  });

  group('avatar motion on the page', () {
    Offset centreOf(WidgetTester t, int i) => t.getCenter(find.byType(RingAvatar).at(i));

    testWidgets('opening a running solo page: avatar already at 6, no ride', (t) async {
      await t.pumpWidget(app(WorkoutPage(
          workoutId: 'w',
          deps: Fake([wk('w', 'solo', other: null, startedAgoMin: 2, startsIn: const Duration(minutes: -2))]).deps())));
      await settle(t);
      final ring = t.getCenter(find.byWidgetPredicate((w) => w is CustomPaint && w.size == const Size.square(220)));
      final av = centreOf(t, 0);
      expect(av.dy, closeTo(ring.dy + 98, 2)); // straight below the ring centre: 6 o'clock
      expect((av.dx - ring.dx).abs(), lessThan(3));
    });

    testWidgets('a real state change rides the ring; reduce motion jumps', (t) async {
      var state = 'time_to_start';
      final deps = Fake([], onRpc: (fn, p) {
        if (fn == 'get_workout_card') {
          final w = wk('w', state, other: null, startedAgoMin: state == 'solo' ? 0 : null,
              startsIn: Duration.zero);
          return {'state': state, 'workout': w, 'invites': [], 'open_invite_count': 0,
                  'server_now': _iso(DateTime.now().toUtc())};
        }
        return null;
      }).deps();
      await t.pumpWidget(app(WorkoutPage(workoutId: 'w', deps: deps)));
      await settle(t);
      final top = centreOf(t, 0);
      // flip the server state and let the 30 s poll pick it up
      state = 'solo';
      await t.pump(const Duration(seconds: 31));
      await t.pump(const Duration(milliseconds: 200)); // mid ride
      final mid = centreOf(t, 0);
      await t.pump(const Duration(seconds: 1));
      final end = centreOf(t, 0);
      expect(mid.dy, greaterThan(top.dy));
      expect(end.dy, greaterThan(mid.dy));
    });
  });

  testWidgets('reduce motion: a state change jumps straight to the new spot', (t) async {
    var state = 'time_to_start';
    final deps = Fake([], onRpc: (fn, p) {
      if (fn != 'get_workout_card') return null;
      final w = wk('w', state, other: null, startedAgoMin: state == 'solo' ? 0 : null, startsIn: Duration.zero);
      return {'state': state, 'workout': w, 'invites': [], 'open_invite_count': 0,
              'server_now': _iso(DateTime.now().toUtc())};
    }).deps();
    await t.pumpWidget(MaterialApp(
      theme: ThemeData(extensions: [AppColors.fromAccent(AccentPalette.emeraldInk)]),
      builder: (c, child) => MediaQuery(data: MediaQuery.of(c).copyWith(disableAnimations: true), child: child!),
      home: WorkoutPage(workoutId: 'w', deps: deps),
    ));
    await settle(t);
    final ring = t.getCenter(find.byWidgetPredicate((w) => w is CustomPaint && w.size == const Size.square(220)));
    state = 'solo';
    await t.pump(const Duration(seconds: 31));
    await t.pump(const Duration(milliseconds: 16)); // one frame later: already there
    expect(t.getCenter(find.byType(RingAvatar).first).dy, closeTo(ring.dy + 98, 2));
  });

  group('New workout button', () {
    testWidgets('empty list: inside the empty state', (t) async {
      await t.pumpWidget(app(SchedulePage(deps: Fake([]).deps())));
      await settle(t);
      expect(find.text('New workout'), findsOneWidget);
      expect(t.widget<FilledButton>(find.widgetWithText(FilledButton, 'New workout')).onPressed, isNotNull);
    });

    testWidgets('list with workouts: at the top, once', (t) async {
      await t.pumpWidget(app(SchedulePage(deps: Fake([wk('a', 'waiting_start_time')]).deps())));
      await settle(t);
      expect(find.text('New workout'), findsOneWidget);
      expect(t.getTopLeft(find.text('New workout')).dy, lessThan(t.getTopLeft(find.text('Upcoming')).dy));
    });

    testWidgets('invites only: still reachable', (t) async {
      await t.pumpWidget(app(SchedulePage(deps: Fake([], invites: [inv(0)]).deps())));
      await settle(t);
      expect(find.text('New workout'), findsOneWidget);
    });
  });

  group('nothing opens a workout page by itself', () {
    testWidgets('resume, poll and realtime-style refetches never push the page', (t) async {
      final f = Fake([wk('r', 'running', startedAgoMin: 5, startsIn: const Duration(minutes: -5))]);
      await t.pumpWidget(app(SchedulePage(deps: f.deps())));
      await settle(t);
      for (final s in [AppLifecycleState.inactive, AppLifecycleState.paused, AppLifecycleState.resumed]) {
        t.binding.handleAppLifecycleStateChanged(s);
        await t.pump(const Duration(seconds: 1));
      }
      await t.pump(const Duration(seconds: 65)); // two polls
      expect(find.byType(WorkoutPage), findsNothing);
      expect(f.calls.where((c) => c == 'get_workout_card').length, greaterThan(3)); // it did refetch
    });

    test('a handled launch tap is never replayed (initialize() runs again after login)', () {
      NotificationService.tabRequest.value = null;
      NotificationService.workoutRequest.value = null;
      NotificationService.resetLaunchForTest();
      NotificationService.routeLaunch({'type': 'buddy_tapped_first', 'reference_id': 'w1'});
      expect(NotificationService.takeWorkoutRequest(), 'w1');
      NotificationService.routeLaunch({'type': 'buddy_tapped_first', 'reference_id': 'w1'}); // second initialize()
      expect(NotificationService.takeWorkoutRequest(), isNull);
    });

    test('a requested workout is taken exactly once', () {
      NotificationService.workoutRequest.value = null;
      NotificationService.routeTap({'type': 'nudge', 'reference_id': 'w2'});
      expect(NotificationService.takeWorkoutRequest(), 'w2');
      expect(NotificationService.takeWorkoutRequest(), isNull);
      expect(NotificationService.workoutRequest.value, isNull);
    });
  });

  group('push taps', () {
    setUp(() {
      NotificationService.tabRequest.value = null;
      NotificationService.workoutRequest.value = null;
    });

    test('workout pushes carry the workout id', () {
      for (final t in ['time_to_start', 'buddy_tapped_first', 'started', 'nudge', 'cant_make_it',
          'buddy_left', 'buddy_finished', 'still_going', 'before_auto', 'invite_accepted']) {
        expect(workoutIdForPush(t, 'w1'), 'w1', reason: t);
      }
      expect(workoutIdForPush('nudge', ''), isNull);
      expect(workoutIdForPush('nudge', null), isNull);
    });

    test('invite pushes open the list, not a page', () {
      for (final t in ['invite_received', 'invite_rescheduled', 'invite_declined', 'invite_expired', 'workout_cancelled']) {
        NotificationService.routeTap({'type': t, 'reference_id': 'w1'});
        expect(NotificationService.tabRequest.value, 0, reason: t);
        expect(NotificationService.workoutRequest.value, isNull, reason: t);
        NotificationService.tabRequest.value = null;
      }
    });

    test('a workout push opens that workout (open, background and killed share this path)', () {
      NotificationService.routeTap({'type': 'buddy_tapped_first', 'reference_id': 'w9'});
      expect(NotificationService.tabRequest.value, 0);
      expect(NotificationService.workoutRequest.value, 'w9');
    });

    test('friend and streak pushes are unchanged', () {
      NotificationService.routeTap({'type': 'friend_request', 'reference_id': 'x'});
      expect((NotificationService.tabRequest.value, NotificationService.workoutRequest.value), (1, null));
      NotificationService.routeTap({'type': 'streak_danger'});
      expect((NotificationService.tabRequest.value, NotificationService.workoutRequest.value), (2, null));
    });
  });
}
