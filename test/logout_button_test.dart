import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gym_buddy_app/home_screen.dart' show LogoutButton;

void main() {
  testWidgets('double tapping Log Out signs out once', (t) async {
    final gate = Completer<void>();
    var signOuts = 0;
    await t.pumpWidget(MaterialApp(
      home: Scaffold(
        body: LogoutButton(onLogout: () async {
          signOuts++;
          await gate.future;
        }),
      ),
    ));

    await t.tap(find.text('Log Out'));
    await t.pump(const Duration(milliseconds: 50));
    await t.tap(find.text('Log Out'));
    await t.pump();
    expect(signOuts, 1);

    gate.complete();
    await t.pump();
    await t.tap(find.text('Log Out'));
    await t.pump();
    expect(signOuts, 2, reason: 'the guard is released once the first log out finishes');
  });

  testWidgets('a failed log out does not leave the button stuck', (t) async {
    var calls = 0;
    await t.pumpWidget(MaterialApp(
      home: Scaffold(
        body: LogoutButton(onLogout: () async {
          calls++;
          throw StateError('offline');
        }),
      ),
    ));

    await runZonedGuarded(() async {
      await t.tap(find.text('Log Out'));
      await t.pump();
      await t.tap(find.text('Log Out'));
      await t.pump();
    }, (e, s) {});
    expect(calls, 2);
  });
}
