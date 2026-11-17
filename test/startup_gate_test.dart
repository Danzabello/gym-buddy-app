import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gym_buddy_app/main.dart';
import 'package:gym_buddy_app/onboarding/onboarding_host.dart';
import 'package:gym_buddy_app/onboarding/onboarding_step_buddy.dart';
import 'package:gym_buddy_app/onboarding/splash_screen.dart';
import 'package:gym_buddy_app/services/auth_service.dart';
import 'package:gym_buddy_app/services/invite_service.dart';
import 'package:gym_buddy_app/services/saved_copy.dart';
import 'package:gym_buddy_app/services/startup_gate.dart';
import 'package:gym_buddy_app/theme/app_theme.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'startup_gate_table.dart';

void main() {
  group('decideStartupScreen', () {
    for (final r in startupGateTable) {
      test(r.name, () {
        expect(
          decideStartupScreen(
            sessionUserId: r.session,
            savedOwnerId: r.owner,
            savedOnboarded: r.flag,
            read: r.read,
          ),
          r.expected,
        );
      });
    }
  });

  group('the saved onboarded flag', () {
    setUp(() => SharedPreferences.setMockInitialValues({}));

    test('saved for a user, read back for that user only', () async {
      await SavedCopy.saveOnboarded('u1');
      expect(await SavedCopy.onboarded('u1'), isTrue);
      expect(await SavedCopy.onboarded('u2'), isFalse);
      expect(await SavedCopy.owner(), 'u1');
    });

    test('wiped with the rest of the saved copy', () async {
      await SavedCopy.saveOnboarded('u1');
      await SavedCopy.wipe();
      expect(await SavedCopy.onboarded('u1'), isFalse);
      expect(await SavedCopy.owner(), isNull);
    });

    test('a different user saving it wipes the first user\'s flag', () async {
      await SavedCopy.saveOnboarded('u1');
      await SavedCopy.saveOnboarded('u2');
      expect(await SavedCopy.onboarded('u1'), isFalse);
    });

    test('89 days old still reads, 91 days old reads as not saved', () async {
      final now = DateTime.now();
      await SavedCopy.write('u1', 'onboarded', {'onboarded': true}, now: now.subtract(const Duration(days: 89)));
      expect(await SavedCopy.onboarded('u1'), isTrue);
      await SavedCopy.write('u1', 'onboarded', {'onboarded': true}, now: now.subtract(const Duration(days: 91)));
      expect(await SavedCopy.onboarded('u1'), isFalse);
    });
  });

  group('AuthWrapper with the saved flag', () {
    late _Fake f;
    setUp(() {
      SharedPreferences.setMockInitialValues({});
      f = _Fake();
    });

    testWidgets('flag for this user: Home at once, the read still out', (t) async {
      f
        ..owner = 'u1'
        ..flag = true
        ..read = Completer<OnboardingState>();
      await _open(t, f);
      expect(find.text('HOME'), findsOneWidget);
      expect(find.byType(CircularProgressIndicator), findsNothing);
      expect(find.byType(SplashScreen), findsNothing);
      expect(f.completed, isEmpty);
      await _drain(t);
    });

    testWidgets('a read that never answers stays on Home after the 15 s cap', (t) async {
      f
        ..owner = 'u1'
        ..flag = true
        ..read = Completer<OnboardingState>();
      await _open(t, f);
      await t.pump(const Duration(seconds: 16));
      await _settle(t);
      expect(find.text('HOME'), findsOneWidget);
      expect(find.byType(SplashScreen), findsNothing);
      expect(f.saves, isEmpty); // an unknown is never saved
      expect(f.completed, isEmpty);
    });

    testWidgets('unknown (offline): stays on Home, nothing saved, no Coach Max check', (t) async {
      f
        ..owner = 'u1'
        ..flag = true
        ..state = OnboardingState.unknown;
      await _open(t, f);
      expect(find.text('HOME'), findsOneWidget);
      expect(find.byType(SplashScreen), findsNothing);
      expect(f.saves, isEmpty);
      expect(f.completed, isEmpty);
    });

    testWidgets('complete: stays on Home, saves the flag once, runs the launch work', (t) async {
      f
        ..owner = 'u1'
        ..flag = true
        ..state = OnboardingState.complete;
      await _open(t, f);
      expect(find.text('HOME'), findsOneWidget);
      expect(f.saves, [('u1', true)]);
      expect(f.completed, hasLength(1));
    });

    testWidgets('not onboarded: routes to onboarding and drops the flag', (t) async {
      f
        ..owner = 'u1'
        ..flag = true
        ..state = OnboardingState.noProfile;
      await _open(t, f);
      expect(find.byType(OnboardingHost), findsOneWidget);
      expect(find.text('HOME'), findsNothing);
      expect(f.saves, [('u1', false)]);
    });

    testWidgets('a sign-out while Home stands before the read goes to the splash', (t) async {
      f
        ..owner = 'u1'
        ..flag = true
        ..read = Completer<OnboardingState>();
      await _open(t, f);
      expect(find.text('HOME'), findsOneWidget);
      f.uid = null;
      f.signedOut.add(null);
      await _settle(t);
      expect(find.byType(SplashScreen), findsOneWidget);
      expect(find.text('HOME'), findsNothing);
      await _drain(t);
    });

    testWidgets('a saved copy of another user: today\'s spinner until the read answers', (t) async {
      f
        ..owner = 'someone-else'
        ..flag = true
        ..read = Completer<OnboardingState>();
      await _open(t, f);
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      expect(find.text('HOME'), findsNothing);
      await _drain(t);
    });

    testWidgets('no saved flag, unknown read: the splash, nothing saved', (t) async {
      f.state = OnboardingState.unknown;
      await _open(t, f);
      expect(find.byType(SplashScreen), findsOneWidget);
      expect(find.text('HOME'), findsNothing);
      expect(f.saves, isEmpty);
    });

    testWidgets('no saved flag, complete: Home only after the launch work, flag saved', (t) async {
      final gate = Completer<void>();
      f
        ..state = OnboardingState.complete
        ..onCompletedGate = gate;
      await _open(t, f);
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      expect(find.text('HOME'), findsNothing);
      gate.complete();
      await _settle(t);
      expect(find.text('HOME'), findsOneWidget);
      expect(f.saves, [('u1', true)]);
    });

    testWidgets('no session: the splash, no read', (t) async {
      f
        ..uid = null
        ..owner = 'u1'
        ..flag = true;
      await _open(t, f);
      expect(find.byType(SplashScreen), findsOneWidget);
      expect(f.reads, 0);
    });
  });
}

class _Fake {
  String? uid = 'u1';
  String? owner;
  bool flag = false;
  OnboardingState state = OnboardingState.unknown;
  Completer<OnboardingState>? read;
  Completer<void>? onCompletedGate;
  final saves = <(String, bool)>[];
  final completed = <String?>[];
  final signedOut = StreamController<void>.broadcast();
  int reads = 0;

  AuthWrapperDeps deps() => AuthWrapperDeps(
        userId: () => uid,
        onSignedIn: (_) async {},
        onboardingStatus: (_) async {
          reads++;
          return (await (read?.future ?? Future.value(state)), 'Europe/Dublin');
        },
        loadResume: (_) async => null,
        onCompleted: (_, tz) async {
          completed.add(tz);
          await onCompletedGate?.future;
        },
        home: (_) => const Scaffold(body: Text('HOME')),
        signOut: () async {},
        buddyDeps: BuddyDeps(
          pendingCode: () async => null,
          clearPendingCode: () async {},
          saveRow: (_) async {},
          finish: (_) async {},
          redeem: (_) async => const InviteRedeemResult(InviteRedeemStatus.invalid),
          inviterName: (_) async => 'Dan',
        ),
        loadSaved: (_) async => (owner, flag),
        saveOnboarded: (id, on) async => saves.add((id, on)),
        signedOutEvents: () => signedOut.stream,
      );
}

Future<void> _settle(WidgetTester t) async {
  for (var i = 0; i < 6; i++) {
    await t.pump(const Duration(milliseconds: 300));
  }
}

/// Lets the 15 s start-up cap on a read that never answers run out.
Future<void> _drain(WidgetTester t) async {
  await t.pump(const Duration(seconds: 16));
  await _settle(t);
}

Future<void> _open(WidgetTester t, _Fake f) async {
  t.view.physicalSize = const Size(1080, 2400);
  t.view.devicePixelRatio = 3;
  addTearDown(t.view.reset);
  await t.pumpWidget(MaterialApp(
    theme: AppTheme.fromAccent(AccentPalette.emeraldInk),
    builder: (c, w) => MediaQuery(
      data: MediaQuery.of(c).copyWith(disableAnimations: true),
      child: w!,
    ),
    home: AuthWrapper(deps: f.deps()),
  ));
  await _settle(t);
}
