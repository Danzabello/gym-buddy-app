import 'dart:async';
import 'dart:convert';

import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gym_buddy_app/pages/notifications_page.dart';
import 'package:gym_buddy_app/pages/wardrobe/wardrobe_avatar_render.dart';
import 'package:gym_buddy_app/services/coach_max_service.dart';
import 'package:gym_buddy_app/services/notification_inbox_service.dart';
import 'package:gym_buddy_app/services/notification_service.dart';
import 'package:gym_buddy_app/theme/app_theme.dart';
import 'package:gym_buddy_app/widgets/ai_disclosure_tag.dart';
import 'package:gym_buddy_app/widgets/avatars/animated_coach_max.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

const _cmx = CoachMaxService.coachMaxId;

InboxRow row(
  String id, {
  String type = 'friend_request',
  String title = 'Mijo',
  String body = 'is done. Your turn.',
  bool quiet = false,
  String? ref,
  String? sender,
  DateTime? at,
}) => InboxRow(
  id: id,
  type: type,
  title: title,
  body: body,
  quiet: quiet,
  referenceId: ref,
  senderId: sender,
  createdAt: at ?? _today(9),
);

DateTime _today(int hour) {
  final n = DateTime.now();
  return DateTime(n.year, n.month, n.day, hour);
}

class _Fake {
  Future<List<InboxRow>> Function() rows = () async => [];
  int rowLoads = 0;
  List<List<String>> senderQueries = [];
  List<List<String>> ringQueries = [];
  Map<String, InboxSender> senders = {};
  Map<String, String> rings = {};
  bool sendersFail = false;
  DateTime? lastSeen;
  List<DateTime> writes = [];
  int asks = 0;
  int settingsOpens = 0;
  int permissionChecks = 0;
  bool permissionAfterCheck = true;
  bool checkSetsPermission = false;
  AuthorizationStatus? askResult = AuthorizationStatus.authorized;
  Completer<void>? askGate;

  NotificationsDeps get deps => NotificationsDeps(
    loadRows: () {
      rowLoads++;
      return rows();
    },
    loadSenders: (ids) async {
      senderQueries.add(ids);
      if (sendersFail) throw Exception('boom');
      return senders;
    },
    loadRings: (ids) async {
      ringQueries.add(ids);
      return rings;
    },
    readLastSeen: () async => lastSeen,
    writeLastSeen: (v) async => writes.add(v),
    checkPermission: () async {
      permissionChecks++;
      if (checkSetsPermission) {
        NotificationService.osPermission.value = permissionAfterCheck;
      }
      return permissionAfterCheck;
    },
    askPermission: () async {
      asks++;
      await askGate?.future;
      return askResult;
    },
    openSystemSettings: () async => settingsOpens++,
    settingsPage: () => const Scaffold(body: Text('settings stand-in')),
  );
}

Future<void> _open(WidgetTester t, _Fake f, {double textScale = 1, Size size = const Size(400, 4000)}) async {
  t.view.physicalSize = size;
  t.view.devicePixelRatio = 1;
  addTearDown(t.view.reset);
  await t.pumpWidget(
    MaterialApp(
      theme: AppTheme.fromAccent(AccentPalette.emeraldInk),
      builder: (c, w) => MediaQuery(
        data: MediaQuery.of(c).copyWith(
          disableAnimations: true,
          textScaler: TextScaler.linear(textScale),
        ),
        child: w!,
      ),
      home: Builder(
        builder: (ctx) => Scaffold(
          body: TextButton(
            onPressed: () => Navigator.push(
              ctx,
              MaterialPageRoute(builder: (_) => NotificationsPage(deps: f.deps)),
            ),
            child: const Text('open'),
          ),
        ),
      ),
    ),
  );
  await t.tap(find.text('open'));
  await t.pumpAndSettle();
}

Future<void> _back(WidgetTester t) async {
  await t.tap(find.bySemanticsLabel('Back'));
  await t.pumpAndSettle();
}

final _dots = find.byKey(const Key('inbox-new-dot'));

void main() {
  setUp(() {
    NotificationService.osPermission.value = null;
    NotificationService.tabRequest.value = null;
    NotificationService.workoutRequest.value = null;
  });

  group('helpers', () {
    final now = DateTime(2026, 10, 30, 14); // a Friday

    test('day labels are the plain strings', () {
      expect(inboxDayLabel(DateTime(2026, 10, 30, 0, 1), now), 'Today');
      expect(inboxDayLabel(DateTime(2026, 10, 29, 23, 59), now), 'Yesterday');
      expect(inboxDayLabel(DateTime(2026, 10, 28, 12), now), 'Wed 28 Oct');
    });

    test('Yesterday is the calendar day: month ends and clock changes', () {
      expect(inboxDayLabel(DateTime(2026, 10, 31, 23), DateTime(2026, 11, 1, 1)), 'Yesterday');
      // Both 2026 European clock changes, where a day is 23 or 25 hours long.
      expect(inboxDayLabel(DateTime(2026, 3, 28, 12), DateTime(2026, 3, 29, 23, 30)), 'Yesterday');
      expect(inboxDayLabel(DateTime(2026, 10, 24, 0, 30), DateTime(2026, 10, 25, 0, 30)), 'Yesterday');
      expect(inboxDayLabel(DateTime(2026, 10, 23, 23, 30), DateTime(2026, 10, 25, 0, 30)), 'Fri 23 Oct');
    });

    test('grouping by local day keeps order and splits at midnight', () {
      final groups = groupInboxByDay([
        row('a', at: DateTime(2026, 10, 30, 9)),
        row('b', at: DateTime(2026, 10, 30, 0, 5)),
        row('c', at: DateTime(2026, 10, 29, 23, 55)),
        row('d', at: DateTime(2026, 10, 28, 8)),
      ], now);
      expect(groups.map((g) => g.label), ['Today', 'Yesterday', 'Wed 28 Oct']);
      expect(groups.map((g) => g.rows.map((r) => r.id).join()), ['ab', 'c', 'd']);
    });

    test('a UTC created_at lands on its local day', () {
      final at = DateTime(2026, 10, 29, 23, 59);
      expect(groupInboxByDay([row('a', at: at.toUtc())], now).single.label, 'Yesterday');
    });

    test('a row is new only when newer than the last visit', () {
      final seen = DateTime.utc(2026, 10, 30, 12);
      expect(inboxRowIsNew(seen.add(const Duration(microseconds: 1)), seen), isTrue);
      expect(inboxRowIsNew(seen, seen), isFalse);
      expect(inboxRowIsNew(seen.subtract(const Duration(minutes: 1)), seen), isFalse);
      expect(inboxRowIsNew(seen, null), isTrue, reason: 'first visit');
    });

    test('the stored marker only moves forward, and nothing shown writes nothing', () {
      final a = DateTime.utc(2026, 10, 30, 12);
      final b = a.add(const Duration(minutes: 1));
      expect(nextLastSeen(null, a), a);
      expect(nextLastSeen(a, b), b);
      expect(nextLastSeen(b, a), isNull);
      expect(nextLastSeen(a, a), isNull);
      expect(nextLastSeen(a, null), isNull);
      expect(nextLastSeen(null, null), isNull);
    });

    test('sender lookups are distinct and never Coach Max', () {
      final ids = inboxSenderIds([
        row('a', sender: 's1'),
        row('b', sender: 's1'),
        row('c', sender: 's2'),
        row('d'),
        row('e', sender: _cmx),
      ]);
      expect(ids, ['s1', 's2']);
    });

    test('a row reads as one sentence', () {
      String s({String title = 'Mijo', bool isNew = false, bool quiet = false}) => inboxRowSemantics(
        title: title, body: 'is done. Your turn.', time: '6:42 PM', isNew: isNew, quiet: quiet,
      );
      expect(s(), 'Mijo is done. Your turn., 6:42 PM');
      expect(s(isNew: true), 'Mijo is done. Your turn., 6:42 PM, new');
      expect(s(quiet: true), 'Mijo is done. Your turn., 6:42 PM. No sound, quiet hours');
      expect(s(isNew: true, quiet: true), 'Mijo is done. Your turn., 6:42 PM, new. No sound, quiet hours');
      expect(s(title: ''), 'is done. Your turn., 6:42 PM');
    });

    test('type icons, with the bell for anything unknown', () {
      expect(inboxIcon('friend_request'), Icons.people_outline_rounded);
      expect(inboxIcon('buddy_checked_in'), Icons.people_outline_rounded);
      expect(inboxIcon('streak_danger'), Icons.local_fire_department_outlined);
      expect(inboxIcon('checkin_ready'), Icons.fitness_center_rounded);
      expect(inboxIcon('invite_received'), Icons.fitness_center_rounded);
      expect(inboxIcon('coach_max_motivational'), Icons.smart_toy_outlined);
      expect(inboxIcon('something_new'), Icons.notifications_none_rounded);
    });

    test('every type the server sends today has a kind icon and a tap destination', () {
      for (final type in const [
        'invite_received', 'invite_accepted', 'invite_declined', 'invite_expired', 'invite_rescheduled',
        'workout_cancelled', 'time_to_start', 'buddy_tapped_first', 'started', 'nudge', 'cant_make_it',
        'buddy_left', 'buddy_finished', 'still_going', 'before_auto', 'friend_request', 'friend_accepted',
        'buddy_checked_in', 'buddy_nudge', 'streak_milestone', 'streak_broken', 'streak_danger',
        'coach_max_motivational', 'checkin_ready',
      ]) {
        expect(inboxIcon(type), isNot(Icons.notifications_none_rounded), reason: type);
        expect(tabForType(type), isNotNull, reason: type);
      }
    });

    test('the dot shows only when the permission is known off', () {
      expect(bellDotVisible(false), isTrue);
      expect(bellDotVisible(true), isFalse);
      expect(bellDotVisible(null), isFalse);
    });

    const blocked = {
      (399, AuthorizationStatus.authorized): false,
      (399, AuthorizationStatus.denied): true,
      (399, null): false,
      (400, AuthorizationStatus.authorized): false,
      (400, AuthorizationStatus.denied): false,
      (400, null): false,
    };
    blocked.forEach((k, expected) {
      test('dialogWasBlocked ${k.$1} ms, ${k.$2}: $expected', () {
        expect(dialogWasBlocked(Duration(milliseconds: k.$1), k.$2), expected);
      });
    });
  });

  group('list', () {
    testWidgets('title, section, uppercase day headers, exact words, footer', (t) async {
      final now = DateTime.now();
      final f = _Fake()
        ..rows = () async => [
          row('a', title: 'Mijo', body: 'is done. Your turn.', at: _today(9)),
          row('b', title: 'Streak in danger', body: 'Your 12-day streak ends at midnight. Check in now.',
              type: 'streak_danger', at: DateTime(now.year, now.month, now.day - 1, 18)),
          row('c', title: 'Sam', body: 'is your buddy now. Pick a time and train.',
              at: DateTime(now.year, now.month, now.day - 3, 20)),
        ];
      await _open(t, f);
      expect(find.text('Notifications'), findsOneWidget);
      expect(find.text('LAST 7 DAYS'), findsOneWidget);
      expect(find.text('TODAY'), findsOneWidget);
      expect(find.text('YESTERDAY'), findsOneWidget);
      expect(find.text(inboxDayLabel(DateTime(now.year, now.month, now.day - 3), now).toUpperCase()), findsOneWidget);
      expect(find.text('Today'), findsNothing);
      for (final s in ['Mijo', 'is done. Your turn.', 'Streak in danger',
          'Your 12-day streak ends at midnight. Check in now.', 'Sam',
          'is your buddy now. Pick a time and train.', 'Older than 7 days is cleared.']) {
        expect(find.text(s), findsOneWidget, reason: s);
      }
    });

    testWidgets('a screen reader gets the plain day label', (t) async {
      final h = t.ensureSemantics();
      final f = _Fake()..rows = () async => [row('a')];
      await _open(t, f);
      expect(find.bySemanticsLabel('Today'), findsOneWidget);
      h.dispose();
    });

    testWidgets('an empty title shows the body alone', (t) async {
      final f = _Fake()..rows = () async => [row('a', title: '', body: 'is done. Your turn.')];
      await _open(t, f);
      expect(find.text('is done. Your turn.'), findsOneWidget);
      expect(t.takeException(), isNull);
    });

    testWidgets('the quiet chip and its accessibility text, and no talk of later', (t) async {
      final h = t.ensureSemantics();
      final f = _Fake()
        ..lastSeen = DateTime.now().add(const Duration(days: 1))
        ..rows = () async => [
          row('q', title: 'Streak ended', body: '7 days with Sam.', type: 'streak_broken', quiet: true),
          row('n', title: 'Plain', body: 'row', type: 'streak_broken'),
        ];
      await _open(t, f);
      expect(find.text('Quiet hours'), findsOneWidget);
      expect(find.bySemanticsLabel(RegExp(r'^Streak ended 7 days with Sam\., .*\. No sound, quiet hours$')), findsOneWidget);
      expect(find.bySemanticsLabel(RegExp(r'^Plain row, [^.]*$')), findsOneWidget);
      expect(find.textContaining('later'), findsNothing);
      h.dispose();
    });

    testWidgets('spinner while loading', (t) async {
      final gate = Completer<List<InboxRow>>();
      final f = _Fake()..rows = () => gate.future;
      t.view.physicalSize = const Size(400, 800);
      t.view.devicePixelRatio = 1;
      addTearDown(t.view.reset);
      await t.pumpWidget(MaterialApp(
        theme: AppTheme.fromAccent(AccentPalette.emeraldInk),
        home: NotificationsPage(deps: f.deps),
      ));
      await t.pump();
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      gate.complete([]);
      await t.pump();
      await t.pump();
      expect(find.byType(CircularProgressIndicator), findsNothing);
    });

    testWidgets('failure, then Try again loads', (t) async {
      var fail = true;
      final f = _Fake()
        ..rows = () async {
          if (fail) throw Exception('boom');
          return [row('a')];
        };
      await _open(t, f);
      expect(find.text('Could not load your notifications'), findsOneWidget);
      expect(find.text('LAST 7 DAYS'), findsNothing);
      expect(find.text('Older than 7 days is cleared.'), findsNothing);
      fail = false;
      await t.tap(find.text('Try again'));
      await t.pumpAndSettle();
      expect(find.text('Could not load your notifications'), findsNothing);
      expect(find.text('Mijo'), findsOneWidget);
    });

    testWidgets('pull to refresh reloads', (t) async {
      final f = _Fake()..rows = () async => [row('a')];
      await _open(t, f, size: const Size(400, 800));
      expect(f.rowLoads, 1);
      await t.fling(find.byType(ListView), const Offset(0, 400), 1000);
      await t.pumpAndSettle();
      expect(f.rowLoads, 2);
      expect(find.text('Mijo'), findsOneWidget);
    });

    testWidgets('no overflow at 360 dp and text scale 2', (t) async {
      NotificationService.osPermission.value = false;
      final f = _Fake()
        ..rows = () async => [
          row('a', title: 'A very long streak title for a small phone',
              body: 'wants to be your gym buddy. Accept to start a streak together.', quiet: true),
          row('b', sender: _cmx, title: 'Coach Max', body: 'Keep the momentum going!'),
        ];
      await _open(t, f, textScale: 2, size: const Size(360, 640));
      expect(t.takeException(), isNull);
      await t.scrollUntilVisible(find.text('Older than 7 days is cleared.'), 200, scrollable: find.byType(Scrollable).last);
      expect(t.takeException(), isNull);
    });
  });

  group('Coach Max welcome card', () {
    testWidgets('an empty list shows it, built in the app, and nothing is stored', (t) async {
      final f = _Fake();
      await _open(t, f);
      expect(find.text('Coach Max'), findsOneWidget);
      expect(find.byType(AiInlinePill), findsOneWidget);
      expect(find.byType(AnimatedCoachMax), findsOneWidget);
      expect(find.text('Welcome to your inbox. Check-ins, buddy updates and streak alerts show up here for 7 days.'), findsOneWidget);
      expect(find.text('🤖'), findsNothing);
      expect(find.text('LAST 7 DAYS'), findsNothing);
      expect(find.text('Older than 7 days is cleared.'), findsNothing);
      expect(find.text('Nothing yet'), findsNothing);
      await _back(t);
      expect(f.writes, isEmpty);
    });

    testWidgets('it goes once there are rows', (t) async {
      final f = _Fake()..rows = () async => [row('a')];
      await _open(t, f);
      expect(find.byType(AiInlinePill), findsNothing);
    });

    testWidgets('it does not replace a failed load', (t) async {
      final f = _Fake()..rows = () async => throw Exception('boom');
      await _open(t, f);
      expect(find.byType(AiInlinePill), findsNothing);
    });
  });

  group('avatars', () {
    testWidgets('one profile query and one ring query for distinct senders', (t) async {
      final f = _Fake()
        ..senders = {
          's1': const InboxSender(avatarId: 'lion', border: 'bold'),
          's2': const InboxSender(avatarId: 'wolf', border: 'not_a_style'),
        }
        ..rings = {'s1': '#FF6F5E'}
        ..rows = () async => [
          row('a', sender: 's1'),
          row('b', sender: 's1'),
          row('c', sender: 's2'),
        ];
      await _open(t, f);
      expect(f.senderQueries, [['s1', 's2']]);
      expect(f.ringQueries, [['s1', 's2']]);
      final avatars = t.widgetList<WardrobeAvatarRender>(find.byType(WardrobeAvatarRender)).toList();
      expect(avatars.length, 3);
      expect(avatars[0].borderStyle.name, 'bold');
      expect(avatars[0].borderColor, const Color(0xFFFF6F5E));
      expect(avatars[2].avatarId, 'wolf');
      expect(avatars[2].borderStyle.name, 'simple', reason: 'unknown style');
      final primary = Theme.of(t.element(find.byType(NotificationsPage))).colorScheme.primary;
      expect(avatars[2].borderColor, primary, reason: 'no readable ring');
    });

    testWidgets('no sender, or a profile that is gone, shows the type icon', (t) async {
      final f = _Fake()
        ..rows = () async => [
          row('a', type: 'streak_danger'),
          row('b', type: 'invite_received', sender: 'gone'),
        ];
      await _open(t, f);
      expect(find.byType(WardrobeAvatarRender), findsNothing);
      expect(find.byIcon(Icons.local_fire_department_outlined), findsOneWidget);
      expect(find.byIcon(Icons.fitness_center_rounded), findsOneWidget);
    });

    testWidgets('no senders means no lookups', (t) async {
      final f = _Fake()..rows = () async => [row('a')];
      await _open(t, f);
      expect(f.senderQueries, isEmpty);
      expect(f.ringQueries, isEmpty);
    });

    testWidgets('a failed lookup still shows the rows, with icons', (t) async {
      final f = _Fake()
        ..sendersFail = true
        ..rows = () async => [row('a', sender: 's1')];
      await _open(t, f);
      expect(find.text('Mijo'), findsOneWidget);
      expect(find.text('Could not load your notifications'), findsNothing);
      expect(find.byIcon(Icons.people_outline_rounded), findsOneWidget);
    });

    testWidgets('Coach Max rows use the robot with the AI badge, no emoji, no lookup', (t) async {
      final f = _Fake()
        ..rows = () async => [row('a', sender: _cmx, type: 'coach_max_motivational', title: 'Coach Max', body: 'Keep the momentum going!')];
      await _open(t, f);
      expect(find.byType(AnimatedCoachMax), findsOneWidget);
      expect(t.widget<AnimatedCoachMax>(find.byType(AnimatedCoachMax)).animate, isFalse);
      expect(find.byType(AiCornerBadge), findsOneWidget);
      expect(find.byType(WardrobeAvatarRender), findsNothing);
      expect(find.text('🤖'), findsNothing);
      expect(f.senderQueries, isEmpty);
    });
  });

  group('new dots and last visit', () {
    final older = DateTime.utc(2026, 10, 30, 8);

    testWidgets('a first visit marks every row new', (t) async {
      final f = _Fake()..rows = () async => [row('a'), row('b')];
      await _open(t, f);
      expect(_dots, findsNWidgets(2));
    });

    testWidgets('only rows newer than the last visit get a dot', (t) async {
      final f = _Fake()
        ..lastSeen = older
        ..rows = () async => [
          row('a', at: older.add(const Duration(minutes: 1))),
          row('b', at: older),
          row('c', at: older.subtract(const Duration(minutes: 1))),
        ];
      await _open(t, f);
      expect(_dots, findsOneWidget);
    });

    testWidgets('opening writes nothing; leaving stores the newest row shown', (t) async {
      final newest = older.add(const Duration(minutes: 5));
      final f = _Fake()
        ..lastSeen = older
        ..rows = () async => [row('a', at: newest), row('b', at: older)];
      await _open(t, f);
      expect(f.writes, isEmpty);
      expect(_dots, findsOneWidget);
      await _back(t);
      expect(f.writes, [newest]);
    });

    testWidgets('going to the background stores it, and the dots stay for this visit', (t) async {
      final newest = older.add(const Duration(minutes: 5));
      final f = _Fake()
        ..lastSeen = older
        ..rows = () async => [row('a', at: newest)];
      await _open(t, f);
      t.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      await t.pump();
      expect(f.writes, [newest]);
      t.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await t.pumpAndSettle();
      expect(_dots, findsOneWidget);
      await _back(t);
      expect(f.writes, [newest], reason: 'no second write of the same value');
    });

    testWidgets('a refresh keeps the dots and moves the marker to what was shown', (t) async {
      final first = older.add(const Duration(minutes: 5));
      final second = older.add(const Duration(minutes: 9));
      var rows = [row('a', at: first)];
      final f = _Fake()
        ..lastSeen = older
        ..rows = () async => rows;
      await _open(t, f, size: const Size(400, 800));
      rows = [row('b', at: second), row('a', at: first)];
      await t.fling(find.byType(ListView), const Offset(0, 400), 1000);
      await t.pumpAndSettle();
      expect(_dots, findsNWidgets(2));
      await _back(t);
      expect(f.writes, [second]);
    });

    testWidgets('a failed load clears nothing', (t) async {
      final f = _Fake()
        ..lastSeen = older
        ..rows = () async => throw Exception('boom');
      await _open(t, f);
      await _back(t);
      expect(f.writes, isEmpty);
    });

    testWidgets('going to Settings and back is not leaving', (t) async {
      final f = _Fake()..rows = () async => [row('a')];
      await _open(t, f);
      await t.tap(find.bySemanticsLabel('Notification settings'));
      await t.pumpAndSettle();
      expect(find.text('settings stand-in'), findsOneWidget);
      expect(f.writes, isEmpty);
      await t.binding.handlePopRoute();
      await t.pumpAndSettle();
      expect(find.text('Notifications'), findsOneWidget);
      expect(_dots, findsOneWidget);
    });

    testWidgets('a failing last-visit store never breaks the page', (t) async {
      final f = _Fake()..rows = () async => [row('a')];
      final deps = f.deps;
      t.view.physicalSize = const Size(400, 800);
      t.view.devicePixelRatio = 1;
      addTearDown(t.view.reset);
      await t.pumpWidget(MaterialApp(
        theme: AppTheme.fromAccent(AccentPalette.emeraldInk),
        home: Builder(builder: (ctx) => TextButton(
          onPressed: () => Navigator.push(ctx, MaterialPageRoute(builder: (_) => NotificationsPage(
            deps: NotificationsDeps(
              loadRows: deps.loadRows,
              loadSenders: deps.loadSenders,
              loadRings: deps.loadRings,
              readLastSeen: () async => throw Exception('read'),
              writeLastSeen: (_) async => throw Exception('write'),
              checkPermission: () async => throw Exception('check'),
              askPermission: deps.askPermission,
              openSystemSettings: deps.openSystemSettings,
              settingsPage: deps.settingsPage,
            ),
          ))),
          child: const Text('open'),
        )),
      ));
      await t.tap(find.text('open'));
      await t.pumpAndSettle();
      expect(find.text('Mijo'), findsOneWidget);
      await _back(t);
      expect(t.takeException(), isNull);
    });
  });

  group('tapping a row', () {
    testWidgets('a friend push closes the page and asks home for Friends', (t) async {
      final f = _Fake()..rows = () async => [row('a', type: 'friend_request', ref: 'f1')];
      await _open(t, f);
      await t.tap(find.text('Mijo'));
      await t.pumpAndSettle();
      expect(find.byType(NotificationsPage), findsNothing);
      expect(NotificationService.tabRequest.value, 1);
      expect(NotificationService.workoutRequest.value, isNull);
    });

    testWidgets('a workout push also asks for that workout', (t) async {
      final f = _Fake()..rows = () async => [row('a', type: 'time_to_start', ref: 'w1')];
      await _open(t, f);
      await t.tap(find.text('Mijo'));
      await t.pumpAndSettle();
      expect(NotificationService.tabRequest.value, 0);
      expect(NotificationService.workoutRequest.value, 'w1');
    });

    testWidgets('checkin_ready opens the dashboard, not a workout', (t) async {
      final f = _Fake()..rows = () async => [row('a', type: 'checkin_ready', ref: 's1')];
      await _open(t, f);
      await t.tap(find.text('Mijo'));
      await t.pumpAndSettle();
      expect(NotificationService.tabRequest.value, 2);
      expect(NotificationService.workoutRequest.value, isNull);
    });

    testWidgets('a type with no destination stays on the page', (t) async {
      final f = _Fake()..rows = () async => [row('a', type: 'something_new')];
      await _open(t, f);
      await t.tap(find.text('Mijo'));
      await t.pumpAndSettle();
      expect(find.byType(NotificationsPage), findsOneWidget);
      expect(NotificationService.tabRequest.value, isNull);
    });

    testWidgets('a double tap pops once', (t) async {
      final f = _Fake()..rows = () async => [row('a')];
      await _open(t, f);
      await t.tap(find.text('Mijo'));
      await t.tap(find.text('Mijo'), warnIfMissed: false);
      await t.pumpAndSettle();
      expect(find.text('open'), findsOneWidget);
    });

    testWidgets('leaving by a row stores the last visit too', (t) async {
      final at = DateTime.utc(2026, 10, 30, 8);
      final f = _Fake()..rows = () async => [row('a', at: at)];
      await _open(t, f);
      await t.tap(find.text('Mijo'));
      await t.pumpAndSettle();
      expect(f.writes, [at]);
    });
  });

  group('permission card', () {
    const off = 'Notifications are off';
    const turnOn = 'Turn on notifications';

    testWidgets('shown only when known off, above the list, with its words', (t) async {
      final f = _Fake()..rows = () async => [row('a')];
      await _open(t, f);
      expect(f.permissionChecks, 1);
      expect(find.text(off), findsNothing, reason: 'unknown shows nothing');
      NotificationService.osPermission.value = false;
      await t.pump();
      expect(find.text(off), findsOneWidget);
      expect(find.text('Turn them on to get streak alerts and buddy check-ins.'), findsOneWidget);
      expect(find.text(turnOn), findsOneWidget);
      expect(t.getTopLeft(find.text(off)).dy, lessThan(t.getTopLeft(find.text('LAST 7 DAYS')).dy));
    });

    testWidgets('a grant takes the card away without leaving the page', (t) async {
      NotificationService.osPermission.value = false;
      final f = _Fake()..rows = () async => [row('a')];
      await _open(t, f);
      await t.tap(find.text(turnOn));
      await t.pump();
      NotificationService.osPermission.value = true; // what requestPermissionFromUser does
      await t.pumpAndSettle();
      expect(find.text(off), findsNothing);
      expect(find.byType(NotificationsPage), findsOneWidget);
      expect(f.settingsOpens, 0);
    });

    testWidgets('it asks once, even after a double tap', (t) async {
      NotificationService.osPermission.value = false;
      final f = _Fake()..askGate = Completer<void>();
      await _open(t, f);
      await t.tap(find.text(turnOn));
      await t.pump();
      await t.tap(find.text(turnOn));
      await t.pump();
      expect(f.asks, 1);
      f.askGate!.complete();
      await t.pumpAndSettle();
      expect(f.asks, 1);
    });

    testWidgets('a blocked dialog opens the phone settings once', (t) async {
      NotificationService.osPermission.value = false;
      final f = _Fake()..askResult = AuthorizationStatus.denied;
      await _open(t, f);
      await t.tap(find.text(turnOn));
      await t.pumpAndSettle();
      expect(f.asks, 1);
      expect(f.settingsOpens, 1);
      expect(find.text(off), findsOneWidget, reason: 'still off until they come back');
    });

    testWidgets('coming back from the phone settings rechecks and the card goes', (t) async {
      NotificationService.osPermission.value = false;
      final f = _Fake()
        ..checkSetsPermission = true
        ..permissionAfterCheck = false;
      await _open(t, f);
      expect(find.text(off), findsOneWidget);
      f.permissionAfterCheck = true;
      t.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await t.pumpAndSettle();
      expect(find.text(off), findsNothing);
      expect(find.byType(NotificationsPage), findsOneWidget);
    });

    testWidgets('the card stays over a failed load and over the welcome card', (t) async {
      NotificationService.osPermission.value = false;
      final fail = _Fake()..rows = () async => throw Exception('boom');
      await _open(t, fail);
      expect(find.text(off), findsOneWidget);
      expect(find.text('Could not load your notifications'), findsOneWidget);
    });
  });

  group('service', () {
    const uid = '11111111-1111-1111-1111-111111111111';

    (NotificationInboxService, List<Uri>) svc(Object Function(http.Request) reply, {int status = 200}) {
      final calls = <Uri>[];
      final client = SupabaseClient(
        'https://example.supabase.co',
        'anon',
        httpClient: MockClient((req) async {
          calls.add(req.url);
          return http.Response(jsonEncode(reply(req)), status, request: req, headers: {'content-type': 'application/json'});
        }),
      );
      return (NotificationInboxService(client: client, userId: uid), calls);
    }

    test('rows: own user, 7 days back in UTC, newest first, limit 100, no new RPC', () async {
      final (s, calls) = svc((_) => [
        {
          'id': 'r1', 'notification_type': 'nudge', 'title': 'T', 'body': 'B', 'quiet': true,
          'reference_id': 'w1', 'sender_id': 's1', 'created_at': '2026-11-05T12:00:00.123456+00:00',
        },
      ]);
      final rows = await s.loadRecent(now: DateTime.utc(2026, 11, 5, 12));
      final q = calls.single;
      expect(q.path, '/rest/v1/notification_inbox');
      expect(q.queryParameters['user_id'], 'eq.$uid');
      expect(q.queryParameters['created_at'], 'gte.2026-10-29T12:00:00.000Z');
      expect(q.queryParameters['order'], 'created_at.desc.nullslast');
      expect(q.queryParameters['limit'], '100');
      expect(q.queryParameters['select']!.contains('batch_key'), isFalse);
      final r = rows.single;
      expect((r.id, r.type, r.title, r.body, r.quiet, r.referenceId, r.senderId),
          ('r1', 'nudge', 'T', 'B', true, 'w1', 's1'));
      expect(r.createdAt, DateTime.utc(2026, 11, 5, 12, 0, 0, 123, 456));
    });

    test('a failed read throws, so the page can show its failure state', () async {
      final (s, _) = svc((_) => {'message': 'nope', 'code': '42501'}, status: 403);
      await expectLater(s.loadRecent(), throwsA(isA<PostgrestException>()));
    });

    test('senders: one query over the public columns, none for no ids', () async {
      final (s, calls) = svc((_) => [
        {'id': 's1', 'avatar_id': 'lion', 'avatar_border': 'bold'},
      ]);
      expect(await s.loadSenders([]), isEmpty);
      expect(calls, isEmpty);
      final found = await s.loadSenders(['s1', 's2']);
      final q = calls.single;
      expect(q.path, '/rest/v1/user_profiles');
      expect(q.queryParameters['select'], 'id,avatar_id,avatar_border');
      expect(q.queryParameters['id'], 'in.("s1","s2")');
      expect(found.keys, ['s1']);
      expect(found['s1']!.border, 'bold');
    });

    test('last visit is per account and keeps the microseconds', () async {
      SharedPreferences.setMockInitialValues({});
      final (s, _) = svc((_) => []);
      expect(await s.readLastSeen(), isNull);
      final at = DateTime.utc(2026, 11, 5, 12, 0, 0, 123, 456);
      await s.writeLastSeen(at);
      expect(await s.readLastSeen(), at);
      final other = NotificationInboxService(
        client: SupabaseClient('https://example.supabase.co', 'anon'),
        userId: '22222222-2222-2222-2222-222222222222',
      );
      expect(await other.readLastSeen(), isNull);
    });
  });
}
