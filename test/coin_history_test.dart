import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gym_buddy_app/pages/coin_history_page.dart';
import 'package:gym_buddy_app/services/coin_service.dart';
import 'package:gym_buddy_app/theme/app_theme.dart';

CoinTransaction tx(
  String type,
  int amount, {
  String desc = '',
  DateTime? at,
  String id = 'x',
}) => CoinTransaction(
  id: id,
  amount: amount,
  transactionType: type,
  description: desc,
  createdAt: at ?? DateTime(2026, 10, 30, 9, 5),
);

void main() {
  group('coinEntryLabel', () {
    test('every type', () {
      var l = coinEntryLabel(tx('daily_checkin', 5, desc: 'Daily check-in 🔥'));
      expect((l.title, l.subtitle), ('Daily check-in', null));
      l = coinEntryLabel(tx('partner_bonus', 5));
      expect(
        (l.title, l.subtitle),
        ('Buddy bonus', 'Your buddy checked in too'),
      );
      l = coinEntryLabel(tx('invite_bonus', 5));
      expect(
        (l.title, l.subtitle),
        ('Invite bonus', 'Joined via buddy invite'),
      );
      l = coinEntryLabel(tx('invite_reward', 5));
      expect(
        (l.title, l.subtitle),
        ('Invite reward', 'A friend you invited got going'),
      );
    });

    test('earn: Achievement prefix is removed, otherwise Bonus coins', () {
      var l = coinEntryLabel(tx('earn', 50, desc: 'Achievement: First Steps'));
      expect((l.title, l.subtitle), ('Achievement', 'First Steps'));
      l = coinEntryLabel(tx('earn', 10, desc: 'Welcome gift'));
      expect((l.title, l.subtitle), ('Bonus coins', 'Welcome gift'));
      l = coinEntryLabel(tx('earn', 10));
      expect((l.title, l.subtitle), ('Bonus coins', null));
    });

    test('shop_purchase: Purchased prefix is removed', () {
      var l = coinEntryLabel(
        tx('shop_purchase', -30, desc: 'Purchased: Gold Ring'),
      );
      expect((l.title, l.subtitle), ('Shop purchase', 'Gold Ring'));
      l = coinEntryLabel(tx('shop_purchase', -30, desc: 'Gold Ring'));
      expect(l.subtitle, 'Gold Ring');
    });

    test('unknown type: Coins with the description', () {
      final l = coinEntryLabel(tx('refund', 3, desc: 'Oops'));
      expect((l.title, l.subtitle), ('Coins', 'Oops'));
    });

    test('emoji and variation selectors are stripped, empty line dropped', () {
      var l = coinEntryLabel(
        tx('earn', 50, desc: '🏆 Achievement: Iron Will ✨\uFE0F '),
      );
      expect((l.title, l.subtitle), ('Achievement', 'Iron Will'));
      l = coinEntryLabel(tx('refund', 3, desc: '🎉\uFE0F'));
      expect(l.subtitle, null);
    });
  });

  group('days', () {
    final now = DateTime(2026, 10, 30, 14); // a Friday

    test('labels', () {
      expect(coinDayLabel(DateTime(2026, 10, 30, 0, 1), now), 'TODAY');
      expect(coinDayLabel(DateTime(2026, 10, 29, 23, 59), now), 'YESTERDAY');
      expect(coinDayLabel(DateTime(2026, 10, 28, 12), now), 'WED 28 OCT');
    });

    test('grouping by local day keeps order and splits at midnight', () {
      final rows = [
        tx('daily_checkin', 5, at: DateTime(2026, 10, 30, 9), id: 'a'),
        tx('partner_bonus', 5, at: DateTime(2026, 10, 30, 0, 5), id: 'b'),
        tx('shop_purchase', -20, at: DateTime(2026, 10, 29, 23, 55), id: 'c'),
        tx('earn', 50, at: DateTime(2026, 10, 28, 8), id: 'd'),
      ];
      final g = groupCoinsByDay(rows, now);
      expect(g.map((e) => e.label), ['TODAY', 'YESTERDAY', 'WED 28 OCT']);
      expect(g.map((e) => e.rows.map((r) => r.id).join()), ['ab', 'c', 'd']);
    });

    test('amount text: real minus sign, no sign on zero', () {
      expect(coinAmountText(12), '+12');
      expect(coinAmountText(-7), '\u22127');
      expect(coinAmountText(0), '0');
    });

    test('week starts six days back in local time, across a month end', () {
      expect(coinWeekStart(DateTime(2026, 10, 30, 23)), DateTime(2026, 10, 24));
      expect(coinWeekStart(DateTime(2026, 10, 3, 1)), DateTime(2026, 9, 27));
    });
  });

  group('page', () {
    late List<(int, CoinFilter)> calls;
    late bool? popped;

    List<CoinTransaction> rows(int n, {int from = 0, int amount = 5}) => [
      for (var i = 0; i < n; i++)
        tx(
          'daily_checkin',
          amount,
          at: DateTime.now().subtract(Duration(seconds: from + i)),
          id: '${from + i}',
        ),
    ];

    Future<void> open(
      WidgetTester t, {
      required Future<List<CoinTransaction>> Function(int, CoinFilter) page,
      Future<CoinWeekTotals> Function()? totals,
      Future<int> Function()? balance,
      int initial = 50,
    }) async {
      calls = [];
      popped = null;
      t.view.physicalSize = const Size(400, 4000);
      t.view.devicePixelRatio = 1;
      addTearDown(t.view.reset);
      final deps = CoinHistoryDeps(
        loadPage: (o, f) {
          calls.add((o, f));
          return page(o, f);
        },
        loadWeekTotals: totals ?? () async => (earned: 30, spent: 5),
        loadBalance: balance ?? () async => initial,
      );
      await t.pumpWidget(
        MaterialApp(
          theme: AppTheme.fromAccent(AccentPalette.emeraldInk),
          home: Builder(
            builder: (ctx) => TextButton(
              onPressed: () async => popped = await Navigator.push<bool>(
                ctx,
                MaterialPageRoute(
                  builder: (_) =>
                      CoinHistoryPage(initialBalance: initial, deps: deps),
                ),
              ),
              child: const Text('open'),
            ),
          ),
        ),
      );
      await t.tap(find.text('open'));
      await t.pumpAndSettle();
    }

    testWidgets('first page, balance, tiles, signs', (t) async {
      await open(
        t,
        page: (_, __) async => [
          tx('daily_checkin', 5, id: '1'),
          tx('shop_purchase', -5, desc: 'Purchased: Gold Ring', id: '2'),
        ],
      );
      expect(find.text('Coin history'), findsOneWidget);
      expect(find.text('50'), findsOneWidget);
      expect(find.text('+30'), findsOneWidget);
      expect(find.text('\u22125'), findsNWidgets(2)); // tile and row
      expect(find.text('Daily check-in'), findsOneWidget);
      expect(find.text('Gold Ring'), findsOneWidget);
      expect(find.text('TODAY'), findsOneWidget);
      expect(find.text('Show more'), findsNothing);
      expect(calls, [(0, CoinFilter.all)]);
    });

    testWidgets('balance refreshes from the loader', (t) async {
      await open(t, page: (_, __) async => [], balance: () async => 70);
      expect(find.text('70'), findsOneWidget);
      expect(find.text('50'), findsNothing);
    });

    testWidgets('zero totals show 0 with no sign', (t) async {
      await open(
        t,
        page: (_, __) async => [],
        totals: () async => (earned: 0, spent: 0),
      );
      expect(find.text('0'), findsNWidgets(2));
    });

    testWidgets('Earned and Spent chips reload from offset 0 with the filter', (
      t,
    ) async {
      await open(t, page: (_, __) async => rows(3));
      await t.tap(find.text('Earned'));
      await t.pumpAndSettle();
      expect(calls.last, (0, CoinFilter.earned));
      await t.tap(find.text('Spent'));
      await t.pumpAndSettle();
      expect(calls.last, (0, CoinFilter.spent));
      await t.tap(find.text('All'));
      await t.pumpAndSettle();
      expect(calls.last, (0, CoinFilter.all));
    });

    testWidgets('Show more appends, a short page hides the button', (t) async {
      await open(
        t,
        page: (o, _) async => o == 0 ? rows(20) : rows(5, from: 20),
      );
      expect(find.text('Daily check-in'), findsNWidgets(20));
      await t.tap(find.text('Show more'));
      await t.pumpAndSettle();
      expect(calls.last, (20, CoinFilter.all));
      expect(find.text('Daily check-in'), findsNWidgets(25));
      expect(find.text('Show more'), findsNothing);
    });

    testWidgets('empty state keeps balance and tiles', (t) async {
      await open(t, page: (_, __) async => []);
      expect(find.text('No coins yet'), findsOneWidget);
      expect(
        find.text(
          'Check in with your buddy to earn your first coins. '
          'They show up here.',
        ),
        findsOneWidget,
      );
      expect(find.text('50'), findsOneWidget);
      expect(find.text('+30'), findsOneWidget);
    });

    testWidgets('error state, Try again reloads', (t) async {
      var fail = true;
      await open(
        t,
        page: (_, __) async {
          if (fail) throw Exception('boom');
          return rows(2);
        },
      );
      expect(find.text('Could not load your coins'), findsOneWidget);
      expect(find.text('No coins yet'), findsNothing);
      fail = false;
      await t.tap(find.text('Try again'));
      await t.pumpAndSettle();
      expect(find.text('Could not load your coins'), findsNothing);
      expect(find.text('Daily check-in'), findsNWidgets(2));
    });

    testWidgets('loading shows a spinner', (t) async {
      final gate = Completer<List<CoinTransaction>>();
      calls = [];
      await t.pumpWidget(
        MaterialApp(
          theme: AppTheme.fromAccent(AccentPalette.emeraldInk),
          home: CoinHistoryPage(
            initialBalance: 50,
            deps: CoinHistoryDeps(
              loadPage: (_, __) => gate.future,
              loadWeekTotals: () async => (earned: 0, spent: 0),
              loadBalance: () async => 50,
            ),
          ),
        ),
      );
      await t.pump();
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      expect(find.text('50'), findsOneWidget);
      gate.complete([]);
      await t.pumpAndSettle();
      expect(find.byType(CircularProgressIndicator), findsNothing);
    });

    testWidgets('Go to Shop pops true', (t) async {
      await open(t, page: (_, __) async => rows(1));
      await t.tap(find.text('Go to Shop'));
      await t.pumpAndSettle();
      expect(find.text('Coin history'), findsNothing);
      expect(popped, true);
    });

    testWidgets('back button pops without a result', (t) async {
      await open(t, page: (_, __) async => rows(1));
      await t.tap(find.byIcon(Icons.chevron_left_rounded));
      await t.pumpAndSettle();
      expect(find.text('Coin history'), findsNothing);
      expect(popped, null);
    });
  });
}
