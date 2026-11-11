import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gym_buddy_app/onboarding/google_sign_in_section.dart';
import 'package:gym_buddy_app/onboarding/onboarding_account.dart';
import 'package:gym_buddy_app/services/auth_service.dart';
import 'package:gym_buddy_app/theme/app_theme.dart';

const _err = 'Google sign-in did not work. Try again.';

Widget _app(Widget child) => MaterialApp(
      theme: AppTheme.fromAccent(AccentPalette.emeraldInk),
      home: Scaffold(body: SingleChildScrollView(child: child)),
    );

Future<void> _tap(WidgetTester t) async {
  await t.tap(find.text('Continue with Google'));
  await t.pump();
  await t.pump();
}

void main() {
  testWidgets('shows the "or" divider and the button', (t) async {
    await t.pumpWidget(_app(GoogleSignInSection(
        show: true,
        signIn: () async => GoogleSignInResult.cancelled,
        onSignedIn: () async => true)));
    expect(find.text('or'), findsOneWidget);
    expect(find.text('Continue with Google'), findsOneWidget);
  });

  testWidgets('hidden when not shown (non-Android default)', (t) async {
    await t.pumpWidget(_app(GoogleSignInSection(
        signIn: () async => GoogleSignInResult.success,
        onSignedIn: () async => true)));
    expect(find.text('or'), findsNothing);
    expect(find.text('Continue with Google'), findsNothing);
  });

  testWidgets('cancel: no banner, screen not told', (t) async {
    var signedIn = 0;
    await t.pumpWidget(_app(GoogleSignInSection(
        show: true,
        signIn: () async => GoogleSignInResult.cancelled,
        onSignedIn: () async {
          signedIn++;
          return true;
        })));
    await _tap(t);
    expect(find.text(_err), findsNothing);
    expect(signedIn, 0);
    expect(find.text('Continue with Google'), findsOneWidget);
  });

  testWidgets('failure shows exactly the approved message', (t) async {
    await t.pumpWidget(_app(GoogleSignInSection(
        show: true,
        signIn: () async => GoogleSignInResult.failed,
        onSignedIn: () async => true)));
    await _tap(t);
    expect(find.text(_err), findsOneWidget);
  });

  testWidgets('success: screen carries on, no banner', (t) async {
    var signedIn = 0;
    await t.pumpWidget(_app(GoogleSignInSection(
        show: true,
        signIn: () async => GoogleSignInResult.success,
        onSignedIn: () async {
          signedIn++;
          return true;
        })));
    await _tap(t);
    expect(signedIn, 1);
    expect(find.text(_err), findsNothing);
  });

  testWidgets('success but the screen could not carry on: approved message',
      (t) async {
    await t.pumpWidget(_app(GoogleSignInSection(
        show: true,
        signIn: () async => GoogleSignInResult.success,
        onSignedIn: () async => false)));
    await _tap(t);
    expect(find.text(_err), findsOneWidget);
  });

  testWidgets('a second tap while signing in is ignored; banner clears on retry',
      (t) async {
    final gate = Completer<GoogleSignInResult>();
    var calls = 0;
    await t.pumpWidget(_app(GoogleSignInSection(
        show: true,
        signIn: () {
          calls++;
          return calls == 1
              ? Future.value(GoogleSignInResult.failed)
              : gate.future;
        },
        onSignedIn: () async => true)));
    await _tap(t);
    expect(find.text(_err), findsOneWidget);

    await _tap(t);
    expect(find.text(_err), findsNothing, reason: 'cleared when retrying');
    expect(find.text('Continue with Google'), findsNothing,
        reason: 'spinner while busy');
    await t.tap(find.byType(OutlinedButton), warnIfMissed: false);
    await t.pump();
    expect(calls, 2);
    gate.complete(GoogleSignInResult.cancelled);
    await t.pump();
  });

  group('routeGoogleSignUp', () {
    Future<(GoogleSignUpNext, int)> run(OnboardingState s,
        {bool signOutThrows = false}) async {
      var outs = 0;
      final r = await routeGoogleSignUp(
        state: () async => s,
        signOut: () async {
          outs++;
          if (signOutThrows) throw StateError('x');
        },
      );
      return (r, outs);
    }

    test('new or unfinished account continues onboarding', () async {
      expect(await run(OnboardingState.noProfile),
          (GoogleSignUpNext.continueOnboarding, 0));
      expect(await run(OnboardingState.incomplete),
          (GoogleSignUpNext.continueOnboarding, 0));
    });

    test('finished account goes home, stays signed in', () async {
      expect(await run(OnboardingState.complete), (GoogleSignUpNext.goHome, 0));
    });

    test('unreadable status signs out and fails', () async {
      expect(await run(OnboardingState.unknown), (GoogleSignUpNext.failed, 1));
      expect((await run(OnboardingState.unknown, signOutThrows: true)).$1,
          GoogleSignUpNext.failed);
    });
  });
}
