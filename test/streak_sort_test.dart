import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gym_buddy_app/home_screen.dart';
import 'package:gym_buddy_app/theme/app_theme.dart';
import 'package:gym_buddy_app/utils/crash_report.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

typedef _Write = (StreakSortMode, List<String>?);

void main() {
  /// A controller whose writes are recorded; [onWrite] decides what a write does.
  ({StreakSortController ctl, List<_Write> writes, List<String> reports}) make({
    Future<void> Function(StreakSortMode, List<String>?)? onWrite,
  }) {
    final writes = <_Write>[];
    final reports = <String>[];
    final ctl = StreakSortController(
      write: (mode, order) {
        writes.add((mode, order));
        return onWrite == null ? Future.value() : onWrite(mode, order);
      },
      report: (e, st, label) => reports.add(label),
    );
    return (ctl: ctl, writes: writes, reports: reports);
  }

  group('the enum', () {
    test('has exactly the four sorts, in the order the sheet shows them', () {
      expect(StreakSortMode.values.map((m) => m.displayName),
          ['Highest Streak', 'Most Workouts', 'Best All-Time', 'Custom']);
    });
  });

  group('loading', () {
    test('each of the four saved values restores', () {
      for (final mode in StreakSortMode.values) {
        final t = make();
        t.ctl.loaded(mode.name);
        expect(t.ctl.shown, mode);
        expect(t.ctl.saved, mode);
      }
    });

    test('null and unknown values, old ones included, read as Highest Streak', () {
      for (final raw in [null, '', 'mostRecent', 'favorites', 'mostUrgent', 'alphabetical',
          'recent', 'risk', 'az', 'garbage', 7]) {
        final t = make();
        t.ctl.loaded(raw);
        expect(t.ctl.shown, StreakSortMode.highestCurrent, reason: '$raw');
        expect(t.ctl.saved, StreakSortMode.highestCurrent, reason: '$raw');
      }
    });

    test('a failed read keeps the default, shows no status line and writes nothing', () {
      final t = make();
      // The read failed or was offline: loaded() is never called.
      expect(t.ctl.shown, StreakSortMode.highestCurrent);
      expect(t.ctl.saved, isNull);
      expect(streakSortStatus(shown: t.ctl.shown, saved: t.ctl.saved), isNull);
      expect(t.writes, isEmpty);
    });

    test('nothing is written on load, whatever the saved value is', () {
      final t = make();
      t.ctl.loaded('favorites');
      t.ctl.paint('mostRecent');
      t.ctl.loaded(null);
      t.ctl.loaded('custom');
      expect(t.writes, isEmpty);
    });

    test('the first paint from the saved copy shows a sort without claiming it is saved', () {
      final t = make();
      t.ctl.paint('bestAllTime');
      expect(t.ctl.shown, StreakSortMode.bestAllTime);
      expect(t.ctl.saved, isNull);
    });

    test('a later load does not undo a pick made this session', () async {
      final t = make();
      t.ctl.loaded('highestCurrent');
      await t.ctl.choose(StreakSortMode.mostWorkouts);
      t.ctl.loaded('highestCurrent'); // a refresh read the older server value
      expect(t.ctl.shown, StreakSortMode.mostWorkouts);
    });
  });

  group('saving', () {
    test('a tap on a different sort writes once, and shows before the write finishes', () async {
      final pending = Completer<void>();
      final t = make(onWrite: (_, __) => pending.future);
      t.ctl.loaded('highestCurrent');

      final done = t.ctl.choose(StreakSortMode.bestAllTime);
      expect(t.ctl.shown, StreakSortMode.bestAllTime); // on screen at once
      expect(t.ctl.saved, StreakSortMode.highestCurrent); // not saved yet
      expect(t.writes, [(StreakSortMode.bestAllTime, null)]);

      pending.complete();
      expect(await done, isTrue);
      expect(t.ctl.saved, StreakSortMode.bestAllTime);
      expect(t.writes, hasLength(1));
    });

    test('a tap on the sort already saved writes nothing', () async {
      final t = make();
      t.ctl.loaded('mostWorkouts');
      expect(await t.ctl.choose(StreakSortMode.mostWorkouts), isTrue);
      expect(t.writes, isEmpty);
    });

    test('Custom with its order is always written, with the order', () async {
      final t = make();
      t.ctl.loaded('custom');
      await t.ctl.choose(StreakSortMode.custom, customOrder: ['t1', 't2']);
      expect(t.writes, hasLength(1));
      expect(t.writes.single.$1, StreakSortMode.custom);
      expect(t.writes.single.$2, ['t1', 't2']);
    });

    test('a failed save keeps the tapped sort on screen and leaves the saved value as it was', () async {
      final t = make(onWrite: (_, __) async => throw StateError('server error'));
      t.ctl.loaded('highestCurrent');
      expect(await t.ctl.choose(StreakSortMode.bestAllTime), isFalse);
      expect(t.ctl.shown, StreakSortMode.bestAllTime);
      expect(t.ctl.saved, StreakSortMode.highestCurrent);
    });

    test('rapid taps: the last tap wins and an older save finishing later is ignored', () async {
      final first = Completer<void>();
      final second = Completer<void>();
      final t = make(onWrite: (mode, _) =>
          mode == StreakSortMode.mostWorkouts ? first.future : second.future);
      t.ctl.loaded('highestCurrent');

      final a = t.ctl.choose(StreakSortMode.mostWorkouts);
      final b = t.ctl.choose(StreakSortMode.bestAllTime);
      expect(t.ctl.shown, StreakSortMode.bestAllTime);

      second.complete(); // the newer save finishes first
      await b;
      expect(t.ctl.saved, StreakSortMode.bestAllTime);

      first.complete(); // the older one finishes after it
      await a;
      expect(t.ctl.saved, StreakSortMode.bestAllTime); // not overwritten
      expect(t.ctl.shown, StreakSortMode.bestAllTime);
    });

    test('tapping back to the saved sort while another save is out still writes, so the last tap wins', () async {
      final slow = Completer<void>();
      final t = make(onWrite: (mode, _) =>
          mode == StreakSortMode.mostWorkouts ? slow.future : Future.value());
      t.ctl.loaded('highestCurrent');

      final a = t.ctl.choose(StreakSortMode.mostWorkouts); // out, slow
      await t.ctl.choose(StreakSortMode.highestCurrent); // back to the saved one
      expect(t.writes.map((w) => w.$1),
          [StreakSortMode.mostWorkouts, StreakSortMode.highestCurrent]);
      expect(t.ctl.saved, StreakSortMode.highestCurrent);

      slow.complete();
      await a;
      expect(t.ctl.saved, StreakSortMode.highestCurrent); // the older result is ignored
    });

    test('a real error is reported with a clear label; the network being down is not', () async {
      var t = make(onWrite: (_, __) async => throw StateError('bug'));
      t.ctl.loaded('highestCurrent');
      await t.ctl.choose(StreakSortMode.bestAllTime);
      expect(t.reports, ['streak_sort_save']);

      for (final skipped in <Object>[
        const SocketException('down'),
        TimeoutException('slow'),
        AuthException('expired'),
        const PostgrestException(message: 'jwt expired', code: 'PGRST301'),
      ]) {
        t = make(onWrite: (_, __) async => throw skipped);
        t.ctl.loaded('highestCurrent');
        await t.ctl.choose(StreakSortMode.bestAllTime);
        expect(t.reports, isEmpty, reason: '$skipped');
      }
    });

    test('isReportableError says the same thing the helper acts on', () {
      expect(isReportableError(StateError('bug')), isTrue);
      expect(isReportableError(const PostgrestException(message: 'denied', code: '42501')), isTrue);
      expect(isReportableError(const SocketException('down')), isFalse);
      expect(isReportableError(AuthException('expired')), isFalse);
    });
  });

  group('the status line', () {
    test('saved: Remembered, with the sort name', () {
      expect(streakSortStatus(shown: StreakSortMode.bestAllTime, saved: StreakSortMode.bestAllTime),
          'Remembered. The app will open on Best All-Time next time.');
    });

    test('not saved: says what shows now and what the app opens on', () {
      expect(streakSortStatus(shown: StreakSortMode.custom, saved: StreakSortMode.highestCurrent),
          "Couldn't save. Showing Custom for now. The app will open on Highest Streak next time.");
    });

    test('a later successful save clears the failure line by itself', () async {
      var fail = true;
      final t = make(onWrite: (_, __) async {
        if (fail) throw StateError('server error');
      });
      t.ctl.loaded('highestCurrent');

      await t.ctl.choose(StreakSortMode.mostWorkouts);
      expect(streakSortStatus(shown: t.ctl.shown, saved: t.ctl.saved)!, startsWith("Couldn't save."));

      fail = false;
      await t.ctl.choose(StreakSortMode.mostWorkouts); // tapped again, saved this time
      expect(streakSortStatus(shown: t.ctl.shown, saved: t.ctl.saved),
          'Remembered. The app will open on Most Workouts next time.');
    });
  });

  group('the sheet', () {
    // Every emoji or pictograph: none is allowed in the sheet or the dialog.
    // (Emoticons, pictographs, symbols, dingbats, arrows, the emoji selector and joiner.
    // The middle dot in the hint is none of these.)
    final emoji = RegExp(
        r'[\u{1F000}-\u{1FAFF}\u{2190}-\u{21FF}\u{2300}-\u{23FF}\u{2600}-\u{27BF}\u{2B00}-\u{2BFF}\u{FE0F}\u{200D}]',
        unicode: true);

    Widget app(StreakSortController ctl, {void Function()? onCustom, void Function(StreakSortMode)? onPick}) =>
        MaterialApp(
          theme: ThemeData(extensions: const [AppColors.dark]),
          home: Scaffold(
            body: Align(
              alignment: Alignment.bottomCenter,
              child: StreakSortSheet(
                controller: ctl,
                onPick: onPick ?? (m) => unawaited(ctl.choose(m)),
                onCustom: onCustom ?? () {},
              ),
            ),
          ),
        );

    Iterable<String> texts(WidgetTester t, Finder within) => t
        .widgetList<Text>(find.descendant(of: within, matching: find.byType(Text)))
        .map((w) => w.data ?? '');

    Finder card(StreakSortMode m) => find.byKey(ValueKey('streak_sort_card_${m.name}'));

    testWidgets('shows exactly four options, none of the removed ones', (t) async {
      final k = make();
      k.ctl.loaded('highestCurrent');
      await t.pumpWidget(app(k.ctl));

      expect(find.byWidgetPredicate((w) => w.key.toString().contains('streak_sort_card_')), findsNWidgets(4));
      for (final name in ['Highest Streak', 'Most Workouts', 'Best All-Time', 'Custom']) {
        expect(find.text(name), findsOneWidget);
      }
      for (final gone in ['Most Recent', 'Favorites', 'At Risk First', 'A to Z']) {
        expect(find.text(gone), findsNothing);
      }
      expect(find.text('Sort Your Streaks'), findsOneWidget);
      expect(find.text('Tap to select · Long-press for info'), findsOneWidget);
    });

    testWidgets('has no emoji and no icon anywhere in the sheet', (t) async {
      final k = make();
      k.ctl.loaded('highestCurrent');
      await t.pumpWidget(app(k.ctl));
      final sheet = find.byType(StreakSortSheet);
      for (final s in texts(t, sheet)) {
        expect(emoji.hasMatch(s), isFalse, reason: 'emoji in "$s"');
      }
      expect(find.descendant(of: sheet, matching: find.byType(Icon)), findsNothing);
      expect(find.descendant(of: sheet, matching: find.byType(ImageIcon)), findsNothing);
    });

    testWidgets('a tap applies at once and writes once; the line says Remembered', (t) async {
      final k = make();
      k.ctl.loaded('highestCurrent');
      await t.pumpWidget(app(k.ctl));

      await t.tap(card(StreakSortMode.mostWorkouts));
      await t.pump();
      expect(k.ctl.shown, StreakSortMode.mostWorkouts);
      expect(k.writes, [(StreakSortMode.mostWorkouts, null)]);
      expect(find.text('Remembered. The app will open on Most Workouts next time.'), findsOneWidget);
    });

    testWidgets('a failed save keeps the tap on screen and shows the failure line, then a success clears it', (t) async {
      var fail = true;
      final k = make(onWrite: (_, __) async {
        if (fail) throw StateError('server error');
      });
      k.ctl.loaded('highestCurrent');
      await t.pumpWidget(app(k.ctl));

      await t.tap(card(StreakSortMode.bestAllTime));
      await t.pump();
      await t.pump();
      expect(find.text("Couldn't save. Showing Best All-Time for now. The app will open on Highest Streak next time."),
          findsOneWidget);

      fail = false;
      await t.tap(card(StreakSortMode.bestAllTime));
      await t.pump();
      await t.pump();
      expect(find.text('Remembered. The app will open on Best All-Time next time.'), findsOneWidget);
      expect(find.textContaining("Couldn't save"), findsNothing);
    });

    testWidgets('with the saved value unknown there is no status line', (t) async {
      final k = make();
      await t.pumpWidget(app(k.ctl));
      expect(find.byKey(const ValueKey('streak_sort_status')), findsNothing);
    });

    testWidgets('Custom hands over to its own picker and writes nothing itself', (t) async {
      final k = make();
      k.ctl.loaded('highestCurrent');
      var custom = 0;
      await t.pumpWidget(app(k.ctl, onCustom: () => custom++));
      await t.tap(card(StreakSortMode.custom));
      await t.pump();
      expect(custom, 1);
      expect(k.writes, isEmpty);
      expect(k.ctl.shown, StreakSortMode.highestCurrent);
    });

    testWidgets('a long press opens the info and does not select', (t) async {
      final k = make();
      k.ctl.loaded('highestCurrent');
      await t.pumpWidget(app(k.ctl));

      await t.longPress(card(StreakSortMode.bestAllTime));
      await t.pumpAndSettle();
      expect(find.byType(StreakSortInfoDialog), findsOneWidget);
      expect(k.ctl.shown, StreakSortMode.highestCurrent); // not selected
      expect(k.writes, isEmpty);

      // The real text, an EXAMPLE box, and nothing but text in the dialog.
      final dialog = find.byType(StreakSortInfoDialog);
      expect(find.descendant(of: dialog, matching: find.text(StreakSortMode.bestAllTime.longDescription)),
          findsOneWidget);
      expect(find.descendant(of: dialog, matching: find.text('EXAMPLE')), findsOneWidget);
      expect(find.descendant(of: dialog, matching: find.text('Sarah (best: 45 days) appears before Mike (best: 32 days)')),
          findsOneWidget);
      for (final s in texts(t, dialog)) {
        expect(emoji.hasMatch(s), isFalse, reason: 'emoji in "$s"');
      }
      expect(find.descendant(of: dialog, matching: find.byType(Icon)), findsNothing);

      await t.tap(find.byKey(const ValueKey('streak_sort_got_it')));
      await t.pumpAndSettle();
      expect(find.byType(StreakSortInfoDialog), findsNothing);
    });

    testWidgets('every sort has an info dialog with its own text and no emoji', (t) async {
      final k = make();
      k.ctl.loaded('highestCurrent');
      await t.pumpWidget(app(k.ctl));
      for (final mode in StreakSortMode.values) {
        await t.longPress(card(mode));
        await t.pumpAndSettle();
        final dialog = find.byType(StreakSortInfoDialog);
        expect(find.descendant(of: dialog, matching: find.text(mode.displayName)), findsOneWidget);
        for (final s in texts(t, dialog)) {
          expect(emoji.hasMatch(s), isFalse, reason: '${mode.name}: "$s"');
        }
        await t.tap(find.byKey(const ValueKey('streak_sort_got_it')));
        await t.pumpAndSettle();
      }
    });

    testWidgets('the top border and the button follow the selected sort\'s colour', (t) async {
      final k = make();
      k.ctl.loaded('highestCurrent');
      await t.pumpWidget(MaterialApp(
        theme: ThemeData(extensions: const [AppColors.dark]),
        home: Scaffold(
          body: Column(children: [
            StreakSortButton(controller: k.ctl, onTap: () {}),
            StreakSortSheet(controller: k.ctl, onPick: (m) => unawaited(k.ctl.choose(m)), onCustom: () {}),
          ]),
        ),
      ));
      Color border() => ((t.widget<AnimatedContainer>(find.byKey(const ValueKey('streak_sort_top_border'))).decoration)
              as BoxDecoration)
          .color!;
      Color button() => ((t.widget<AnimatedContainer>(find.byKey(const ValueKey('streak_sort_button'))).decoration)
              as BoxDecoration)
          .border!
          .top
          .color;

      expect(border(), StreakSortMode.highestCurrent.color);
      expect(button(), StreakSortMode.highestCurrent.color);

      await t.tap(card(StreakSortMode.bestAllTime));
      await t.pump(const Duration(milliseconds: 400));
      expect(border(), StreakSortMode.bestAllTime.color);
      expect(button(), StreakSortMode.bestAllTime.color);
    });
  });

  group('a save that fails while the saved value is unknown', () {
    test('the line says only what shows now; nothing tapped says nothing', () {
      expect(streakSortStatus(shown: StreakSortMode.custom, saved: null, failed: true),
          "Couldn't save. Showing Custom for now.");
      expect(streakSortStatus(shown: StreakSortMode.custom, saved: null, failed: true),
          isNot(contains('will open on')));
      expect(streakSortStatus(shown: StreakSortMode.highestCurrent, saved: null), isNull);
      expect(streakSortStatus(shown: StreakSortMode.highestCurrent, saved: null, failed: false), isNull);
    });

    test('the controller tracks it: set by a failure, cleared by a later success', () async {
      var fail = true;
      final t = make(onWrite: (_, __) async {
        if (fail) throw StateError('server error');
      });
      // The first read never answered: saved is unknown.
      expect(t.ctl.saved, isNull);
      expect(t.ctl.failed, isFalse);
      expect(streakSortStatus(shown: t.ctl.shown, saved: t.ctl.saved, failed: t.ctl.failed), isNull);

      await t.ctl.choose(StreakSortMode.bestAllTime);
      expect(t.ctl.failed, isTrue);
      expect(t.ctl.saved, isNull);
      expect(streakSortStatus(shown: t.ctl.shown, saved: t.ctl.saved, failed: t.ctl.failed),
          "Couldn't save. Showing Best All-Time for now.");

      fail = false;
      await t.ctl.choose(StreakSortMode.bestAllTime); // tapped again: retried, and saved
      expect(t.ctl.failed, isFalse);
      expect(t.ctl.saved, StreakSortMode.bestAllTime);
      expect(streakSortStatus(shown: t.ctl.shown, saved: t.ctl.saved, failed: t.ctl.failed),
          'Remembered. The app will open on Best All-Time next time.');
    });

    test('an older save failing after a newer one does not raise the flag', () async {
      final older = Completer<void>();
      final t = make(onWrite: (mode, _) =>
          mode == StreakSortMode.mostWorkouts ? older.future : Future.value());
      final a = t.ctl.choose(StreakSortMode.mostWorkouts);
      await t.ctl.choose(StreakSortMode.bestAllTime); // newer, saved
      older.completeError(StateError('late failure'));
      await a;
      expect(t.ctl.failed, isFalse);
      expect(t.ctl.saved, StreakSortMode.bestAllTime);
    });

    test('with the saved value known, tapping it again after a failure clears the flag', () async {
      var fail = true;
      final t = make(onWrite: (_, __) async {
        if (fail) throw StateError('server error');
      });
      t.ctl.loaded('highestCurrent');
      await t.ctl.choose(StreakSortMode.mostWorkouts);
      expect(t.ctl.failed, isTrue);
      await t.ctl.choose(StreakSortMode.highestCurrent); // back to what is saved
      expect(t.ctl.failed, isFalse);
      expect(streakSortStatus(shown: t.ctl.shown, saved: t.ctl.saved, failed: t.ctl.failed),
          'Remembered. The app will open on Highest Streak next time.');
    });

    Widget sheetApp(StreakSortController ctl) => MaterialApp(
          theme: ThemeData(extensions: const [AppColors.dark]),
          home: Scaffold(
            body: Align(
              alignment: Alignment.bottomCenter,
              child: StreakSortSheet(
                  controller: ctl, onPick: (m) => unawaited(ctl.choose(m)), onCustom: () {}),
            ),
          ),
        );

    testWidgets('the sheet shows the short failure line, then Remembered after a success', (t) async {
      var fail = true;
      final k = make(onWrite: (_, __) async {
        if (fail) throw StateError('server error');
      });
      await t.pumpWidget(sheetApp(k.ctl));
      expect(find.byKey(const ValueKey('streak_sort_status')), findsNothing); // nothing tapped

      await t.tap(find.byKey(const ValueKey('streak_sort_card_bestAllTime')));
      await t.pump();
      await t.pump();
      expect(find.text("Couldn't save. Showing Best All-Time for now."), findsOneWidget);
      expect(find.textContaining('will open on'), findsNothing);

      fail = false;
      await t.tap(find.byKey(const ValueKey('streak_sort_card_bestAllTime')));
      await t.pump();
      await t.pump();
      expect(find.text('Remembered. The app will open on Best All-Time next time.'), findsOneWidget);
      expect(find.textContaining("Couldn't save"), findsNothing);
    });
  });

  group('the Custom text', () {
    test('says what Custom really does, and no longer claims it switches on by itself', () {
      expect(StreakSortMode.custom.longDescription,
          'Pick your own buddies and the order they appear in. Tap Custom to set it up.');
      expect(StreakSortMode.custom.example,
          'You choose Riley first, then Sam, then Alex, and that is the order you see.');
      expect(StreakSortMode.custom.description, 'Your own order');
      for (final text in [
        StreakSortMode.custom.longDescription,
        StreakSortMode.custom.example,
        StreakSortMode.custom.description,
      ]) {
        expect(text.toLowerCase(), isNot(contains('automatically')));
        expect(text, isNot(contains('preset center')));
      }
    });

    testWidgets('the card and the info dialog show it', (t) async {
      final k = make();
      k.ctl.loaded('highestCurrent');
      await t.pumpWidget(MaterialApp(
        theme: ThemeData(extensions: const [AppColors.dark]),
        home: Scaffold(
          body: Align(
            alignment: Alignment.bottomCenter,
            child: StreakSortSheet(controller: k.ctl, onPick: (_) {}, onCustom: () {}),
          ),
        ),
      ));
      expect(find.text('Your own order'), findsOneWidget);
      expect(find.text('Manual selection'), findsNothing);

      await t.longPress(find.byKey(const ValueKey('streak_sort_card_custom')));
      await t.pumpAndSettle();
      final dialog = find.byType(StreakSortInfoDialog);
      expect(find.descendant(of: dialog, matching: find.text(StreakSortMode.custom.longDescription)),
          findsOneWidget);
      expect(find.descendant(of: dialog, matching: find.text(StreakSortMode.custom.example)),
          findsOneWidget);
    });
  });

  group('the toast after the Custom picker Save', () {
    Future<void> show(WidgetTester t, bool saved) async {
      await t.pumpWidget(MaterialApp(
        theme: ThemeData(extensions: const [AppColors.dark]),
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () => ScaffoldMessenger.of(context)
                  .showSnackBar(customOrderSnackBar(saved: saved, colors: AppColors.of(context))),
              child: const Text('go'),
            ),
          ),
        ),
      ));
      await t.tap(find.text('go'));
      await t.pump();
      await t.pump(const Duration(milliseconds: 400));
    }

    testWidgets('saved: green, with the check and the success text', (t) async {
      await show(t, true);
      expect(find.text('Custom order saved!'), findsOneWidget);
      expect(find.descendant(of: find.byType(SnackBar), matching: find.byIcon(Icons.check_circle)), findsOneWidget);
      expect(t.widget<SnackBar>(find.byType(SnackBar)).backgroundColor, Colors.green[600]);
    });

    testWidgets('not saved: amber, no check, and it says so', (t) async {
      await show(t, false);
      expect(find.text("Couldn't save your Custom order."), findsOneWidget);
      expect(find.descendant(of: find.byType(SnackBar), matching: find.byType(Icon)), findsNothing);
      expect(t.widget<SnackBar>(find.byType(SnackBar)).backgroundColor, kStreakSortWarnColor);
    });

    testWidgets('the failure text is readable on the amber', (t) async {
      await show(t, false);
      final style = t.widget<Text>(find.text("Couldn't save your Custom order.")).style!;
      final contrast = (style.color!.computeLuminance() + 0.05) /
          (kStreakSortWarnColor.computeLuminance() + 0.05);
      expect(1 / contrast, greaterThan(4.5)); // dark text on the lighter amber
    });
  });
}
