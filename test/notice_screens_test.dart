import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:gym_buddy_app/theme/accent_theme_provider.dart';
import 'package:gym_buddy_app/theme/app_theme.dart';
import 'package:gym_buddy_app/pages/notice_screens.dart';

Map<String, dynamic> ev(String id, String kind, int lost, {String? buddy, bool coach = false, String? best}) => {
      'id': id, 'kind': kind, 'lost_streak': lost, 'buddy_name': buddy,
      'is_coach_max_team': coach, 'team_name': 'Team', 'missed_name': 'Sam',
      if (best != null) 'best_streak': int.parse(best),
    };

void main() {
  test('null kind or empty items -> no notice', () {
    expect(Notice.parse({'kind': null, 'items': [], 'others': 0}), isNull);
    expect(Notice.parse(null), isNull);
  });

  test('own: best missing is null, present is parsed; ids and others kept', () {
    final n = Notice.parse({'kind': 'own', 'others': 2, 'items': [ev('a', 'own', 12, buddy: 'Sam')]})!;
    expect(n.kind, 'own');
    expect(n.others, 2);
    expect(n.ids, ['a']);
    expect(n.items.first.best, isNull);
    final b = Notice.parse({'kind': 'own', 'items': [ev('a', 'own', 12, buddy: 'Sam', best: '20')]})!;
    expect(b.items.first.best, 20);
  });

  test('coach max team name, long name kept whole', () {
    final n = Notice.parse({'kind': 'many', 'items': [
      ev('a', 'own', 3, coach: true),
      ev('b', 'friend', 1, buddy: 'A' * 80),
    ]})!;
    expect(n.items[0].buddy, 'Coach Max');
    expect(n.items[1].buddy.length, 80);
    expect(n.items[1].kind, 'friend');
  });

  test('auto_completed items parse as auto', () {
    final n = Notice.parse({'kind': 'auto_completed', 'others': 0, 'items': [
      {'id': 'x', 'workout_date': '2026-10-06', 'minutes': 15}
    ]})!;
    expect(n.items.first.kind, 'auto');
    expect(n.items.first.minutes, 15);
  });

  test('day pluralisation and counted-for', () {
    expect(daysLabel(1), '1 day');
    expect(daysLabel(2), '2 days');
    final now = DateTime(2026, 10, 7);
    expect(countedFor('2026-10-07', now), 'Today');
    expect(countedFor('2026-10-06', now), 'Tuesday');
    expect(countedFor(null, now), 'Today');
  });

  group('dialogs', () {
    setUp(() => SharedPreferences.setMockInitialValues({}));

    Future<void> open(WidgetTester t, Widget Function(BuildContext) dialog,
        {bool still = true, double scale = 1}) async {
      t.view.physicalSize = const Size(360, 800);
      t.view.devicePixelRatio = 1;
      addTearDown(t.view.reset);
      await t.pumpWidget(ChangeNotifierProvider(
        create: (_) => AccentThemeProvider(),
        child: Consumer<AccentThemeProvider>(
          builder: (_, a, __) => MaterialApp(
            theme: AppTheme.fromAccent(a.palette),
            builder: (ctx, child) => MediaQuery(
              data: MediaQuery.of(ctx).copyWith(disableAnimations: still, textScaler: TextScaler.linear(scale)),
              child: child!,
            ),
            home: Builder(
              builder: (ctx) => TextButton(
                onPressed: () => showDialog<void>(context: ctx, builder: dialog),
                child: const Text('open'),
              ),
            ),
          ),
        ),
      ));
      await t.tap(find.text('open'));
      await t.pumpAndSettle();
    }

    double heroOpacity(WidgetTester t, String text) =>
        t.widget<Opacity>(find.ancestor(of: find.text(text), matching: find.byType(Opacity)).first).opacity;

    final one = {'kind': 'own', 'items': [ev('a', 'own', 12, buddy: 'Sam')]};
    final all = <String, Map<String, dynamic>>{
      'own': one,
      'friend': {'kind': 'friend', 'items': [ev('a', 'friend', 8, buddy: 'B' * 60)]},
      'many': {'kind': 'many', 'items': [for (var i = 0; i < 12; i++) ev('m$i', i.isEven ? 'own' : 'friend', i + 1, buddy: 'Buddy $i ${'x' * 40}')]},
      'auto': {'kind': 'auto_completed', 'items': [{'id': 'x', 'workout_date': '2026-10-06', 'minutes': 15}]},
    };

    testWidgets('reduce motion shows each hero end state', (t) async {
      for (final (kind, text, expected) in [
        (NoticeHeroKind.tick, '15', 0.0),
        (NoticeHeroKind.cross, '12', 0.3),
        (NoticeHeroKind.strike, '12', 0.45),
      ]) {
        await open(t, (_) => Dialog(child: NoticeHero(kind: kind, value: int.parse(text), color: Colors.red)));
        expect(heroOpacity(t, text), closeTo(expected, 0.001), reason: '$kind');
        await t.tapAt(const Offset(2, 2));
        await t.pumpAndSettle();
      }
    });

    testWidgets('3 and 4 digit numbers do not overflow', (t) async {
      for (final v in [123, 4567]) {
        await open(t, (_) => Dialog(child: NoticeHero(kind: NoticeHeroKind.cross, value: v, color: Colors.red)));
        expect(t.takeException(), isNull);
        await t.tapAt(const Offset(2, 2));
        await t.pumpAndSettle();
      }
    });

    testWidgets('button marks seen with the shown ids and closes', (t) async {
      List<String>? seen;
      await open(t, (_) => NoticeDialog(Notice.parse(one)!, onSeen: (ids) async => seen = ids));
      await t.tap(find.text('Got it'));
      await t.pumpAndSettle();
      expect(seen, ['a']);
      expect(find.byType(NoticeDialog), findsNothing);
    });

    testWidgets('barrier tap marks seen and closes; a failing call still closes', (t) async {
      var calls = 0;
      await open(t, (_) => NoticeDialog(Notice.parse(one)!, onSeen: (_) async { calls++; throw Exception('offline'); }));
      await t.tapAt(const Offset(2, 2));
      await t.pumpAndSettle();
      expect(calls, 1);
      expect(find.byType(NoticeDialog), findsNothing);
    });

    testWidgets('many list is capped and scrolls inside the box', (t) async {
      await open(t, (_) => NoticeDialog(Notice.parse(all['many'])!, onSeen: (_) async {}));
      expect(t.getSize(find.byType(ListView)).height, lessThanOrEqualTo(220));
      final pos = t.state<ScrollableState>(find.descendant(of: find.byType(ListView), matching: find.byType(Scrollable))).position;
      expect(pos.maxScrollExtent, greaterThan(0));
      expect(find.text('Got it'), findsOneWidget);
    });

    testWidgets('text scale 2.0 at 360 dp does not overflow any notice', (t) async {
      for (final e in all.entries) {
        await open(t, (_) => NoticeDialog(Notice.parse(e.value)!, onSeen: (_) async {}), scale: 2.0);
        expect(t.takeException(), isNull, reason: e.key);
        expect(find.text('Got it'), findsOneWidget, reason: e.key);
        await t.tapAt(const Offset(2, 2));
        await t.pumpAndSettle();
      }
    });
  });
}
