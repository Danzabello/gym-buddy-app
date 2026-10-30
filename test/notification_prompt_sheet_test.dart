import 'dart:async';

import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gym_buddy_app/theme/app_theme.dart';
import 'package:gym_buddy_app/widgets/notification_prompt_sheet.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _title = 'Keep your streak alive';
const _body =
    'Turn on notifications so Gym Buddy can reach you at the right moments. You pick which kinds in Settings.';
const _turnOn = 'Turn on notifications';
const _notNow = 'Not now';
const _foot = 'You can change this any time in Settings.';

class _Fake {
  int asks = 0;
  int settingsOpens = 0;
  AuthorizationStatus? result = AuthorizationStatus.authorized;
  Completer<void>? gate;

  Future<AuthorizationStatus?> ask() async {
    asks++;
    await gate?.future;
    return result;
  }

  Future<void> openSettings() async => settingsOpens++;
}

Future<void> _open(WidgetTester t, _Fake f, {double textScale = 1}) async {
  SharedPreferences.setMockInitialValues({});
  t.view.physicalSize = const Size(360 * 3, 640 * 3);
  t.view.devicePixelRatio = 3;
  addTearDown(t.view.reset);
  await t.pumpWidget(MaterialApp(
    theme: AppTheme.fromAccent(AccentPalette.emeraldInk),
    builder: (c, w) => MediaQuery(
      data: MediaQuery.of(c).copyWith(
          disableAnimations: true, textScaler: TextScaler.linear(textScale)),
      child: w!,
    ),
    home: Builder(
      builder: (context) => Scaffold(
        body: Center(
          child: TextButton(
            onPressed: () => showNotificationPromptSheet(context,
                ask: f.ask, openSettings: f.openSettings),
            child: const Text('open'),
          ),
        ),
      ),
    ),
  ));
  await t.tap(find.text('open'));
  await t.pumpAndSettle();
}

Future<void> _expectNothingWritten() async {
  expect((await SharedPreferences.getInstance()).getKeys(), isEmpty);
}

void main() {
  group('dialogWasBlocked', () {
    const cases = {
      (399, AuthorizationStatus.authorized): false,
      (399, AuthorizationStatus.denied): true,
      (399, null): false,
      (400, AuthorizationStatus.authorized): false,
      (400, AuthorizationStatus.denied): false,
      (400, null): false,
    };
    cases.forEach((k, expected) {
      test('${k.$1} ms, ${k.$2}: $expected', () {
        expect(dialogWasBlocked(Duration(milliseconds: k.$1), k.$2), expected);
      });
    });
  });

  test('the dot shows only when the permission is known off', () {
    expect(bellDotVisible(false), isTrue);
    expect(bellDotVisible(true), isFalse);
    expect(bellDotVisible(null), isFalse);
  });

  group('bell routing', () {
    test('granted: snackbar', () async {
      expect(await routeBellTap(() async => true), BellTap.snackbar);
    });
    test('not granted: sheet', () async {
      expect(await routeBellTap(() async => false), BellTap.sheet);
    });
    test('a thrown check: snackbar', () async {
      expect(await routeBellTap(() async => throw Exception('boom')),
          BellTap.snackbar);
    });
  });

  group('sheet', () {
    testWidgets('shows the five strings', (t) async {
      await _open(t, _Fake());
      for (final s in [_title, _body, _turnOn, _notNow, _foot]) {
        expect(find.text(s), findsOneWidget, reason: s);
      }
    });

    testWidgets('Turn on asks once, even after a double tap', (t) async {
      final f = _Fake()..gate = Completer<void>();
      await _open(t, f);
      await t.tap(find.text(_turnOn));
      await t.pump();
      await t.tap(find.byType(ElevatedButton), warnIfMissed: false);
      await t.pump();
      expect(f.asks, 1);
      f.gate!.complete();
      await t.pumpAndSettle();
      expect(f.asks, 1);
      expect(find.text(_title), findsNothing);
      expect(f.settingsOpens, 0);
    });

    testWidgets('a blocked result opens the system settings once', (t) async {
      final f = _Fake()..result = AuthorizationStatus.denied;
      await _open(t, f);
      await t.tap(find.text(_turnOn));
      await t.pumpAndSettle();
      expect(f.settingsOpens, 1);
      expect(find.text(_title), findsNothing);
    });

    testWidgets('an allowed result never opens the settings', (t) async {
      final f = _Fake();
      await _open(t, f);
      await t.tap(find.text(_turnOn));
      await t.pumpAndSettle();
      expect(f.asks, 1);
      expect(f.settingsOpens, 0);
      await _expectNothingWritten();
    });

    testWidgets('Not now closes without asking or writing', (t) async {
      final f = _Fake();
      await _open(t, f);
      await t.tap(find.text(_notNow));
      await t.pumpAndSettle();
      expect(find.text(_title), findsNothing);
      expect(f.asks, 0);
      expect(f.settingsOpens, 0);
      await _expectNothingWritten();
    });

    testWidgets('swiping down closes without asking or writing', (t) async {
      final f = _Fake();
      await _open(t, f);
      await t.fling(find.text(_title), const Offset(0, 500), 1500);
      await t.pumpAndSettle();
      expect(find.text(_title), findsNothing);
      expect(f.asks, 0);
      await _expectNothingWritten();
    });

    testWidgets('Back closes without asking or writing', (t) async {
      final f = _Fake();
      await _open(t, f);
      await t.binding.handlePopRoute();
      await t.pumpAndSettle();
      expect(find.text(_title), findsNothing);
      expect(f.asks, 0);
      await _expectNothingWritten();
    });

    testWidgets('a tap on the scrim closes without asking', (t) async {
      final f = _Fake();
      await _open(t, f);
      await t.tapAt(const Offset(20, 20));
      await t.pumpAndSettle();
      expect(find.text(_title), findsNothing);
      expect(f.asks, 0);
      await _expectNothingWritten();
    });

    testWidgets('no overflow at 360 dp and text scale 2.0; it scrolls',
        (t) async {
      await _open(t, _Fake(), textScale: 2.0);
      expect(t.takeException(), isNull);
      await t.scrollUntilVisible(find.text(_foot), 100,
          scrollable: find.byType(Scrollable).last);
      expect(find.text(_foot), findsOneWidget);
      expect(t.takeException(), isNull);
    });
  });
}
