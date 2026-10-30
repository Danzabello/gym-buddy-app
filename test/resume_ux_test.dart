import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gym_buddy_app/main.dart';
import 'package:gym_buddy_app/onboarding/onboarding_host.dart';
import 'package:gym_buddy_app/onboarding/onboarding_resume.dart';
import 'package:gym_buddy_app/onboarding/onboarding_step_buddy.dart';
import 'package:gym_buddy_app/onboarding/onboarding_theme.dart';
import 'package:gym_buddy_app/onboarding/splash_screen.dart';
import 'package:gym_buddy_app/services/auth_service.dart';
import 'package:gym_buddy_app/services/invite_service.dart';
import 'package:gym_buddy_app/theme/app_theme.dart';

const _welcome = "Welcome back. Let's finish setting you up.";
const _escape = 'Not you? Use a different account.';
const _pairedLine =
    'Nice. You and Dan are a team now. Your streak starts when you both check in.';

const _fullRow = OnboardingResume(
    name: 'Rowan', age: 27, username: 'rowan_g', avatarId: 'wolf');
const _pairedRow = OnboardingResume(
    name: 'Rowan',
    age: 27,
    username: 'rowan_g',
    avatarId: 'wolf',
    pairedWith: 'Dan');

class _Fake {
  String? uid = 'u1';
  Future<OnboardingState> Function() state =
      () async => OnboardingState.unknown;
  OnboardingResume? resume;
  int stateReads = 0;
  int signOuts = 0;
  Completer<void>? signOutGate;

  AuthWrapperDeps deps() => AuthWrapperDeps(
        userId: () => uid,
        onSignedIn: (_) async {},
        onboardingState: (_) {
          stateReads++;
          return state();
        },
        loadResume: (_) async => resume,
        onCompleted: (_) async {},
        home: (_) => const Scaffold(body: Text('HOME')),
        signOut: () async {
          signOuts++;
          await signOutGate?.future;
          uid = null;
        },
        buddyDeps: BuddyDeps(
          pendingCode: () async => null,
          clearPendingCode: () async {},
          saveRow: (_) async {},
          finish: (_) async {},
          redeem: (_) async =>
              const InviteRedeemResult(InviteRedeemStatus.invalid),
          inviterName: (_) async => 'Dan',
        ),
      );
}

Future<void> _settle(WidgetTester t) async {
  for (var i = 0; i < 6; i++) {
    await t.pump(const Duration(milliseconds: 300));
  }
}

Future<void> _open(WidgetTester t, _Fake f, {Widget? home}) async {
  t.view.physicalSize = const Size(1080, 2400);
  t.view.devicePixelRatio = 3;
  addTearDown(t.view.reset);
  await t.pumpWidget(MaterialApp(
    theme: AppTheme.fromAccent(AccentPalette.emeraldInk),
    builder: (c, w) => MediaQuery(
      data: MediaQuery.of(c).copyWith(disableAnimations: true),
      child: w!,
    ),
    home: home ?? AuthWrapper(deps: f.deps()),
  ));
  await _settle(t);
}

OnboardingHostState _host(WidgetTester t) =>
    t.state<OnboardingHostState>(find.byType(OnboardingHost));

void main() {
  group('AuthWrapper routing', () {
    testWidgets('signed in + unfinished goes straight to the host, no splash',
        (t) async {
      final f = _Fake()
        ..state = (() async => OnboardingState.incomplete)
        ..resume = _fullRow;
      await _open(t, f);
      expect(find.byType(OnboardingHost), findsOneWidget);
      expect(_host(t).widget.resume, isTrue);
      expect(find.byType(SplashScreen), findsNothing);
    });

    testWidgets('signed in + no row goes straight to the host, no splash',
        (t) async {
      final f = _Fake()..state = (() async => OnboardingState.noProfile);
      await _open(t, f);
      expect(find.byType(OnboardingHost), findsOneWidget);
      expect(_host(t).widget.resume, isTrue);
      expect(find.byType(SplashScreen), findsNothing);
    });

    testWidgets('signed in + read failure shows the splash', (t) async {
      final f = _Fake()..state = (() async => OnboardingState.unknown);
      await _open(t, f);
      expect(find.byType(SplashScreen), findsOneWidget);
      expect(find.byType(OnboardingHost), findsNothing);
    });

    testWidgets('signed in + timed-out read shows the splash', (t) async {
      final f = _Fake()..state = (() => Completer<OnboardingState>().future);
      await _open(t, f);
      // Still on the spinner until the 15s startup timeout fires.
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      await t.pump(const Duration(seconds: 16));
      await _settle(t);
      expect(find.byType(SplashScreen), findsOneWidget);
      expect(find.byType(OnboardingHost), findsNothing);
    });

    testWidgets('unfinished but the row cannot be read shows the splash',
        (t) async {
      final f = _Fake()
        ..state = (() async => OnboardingState.incomplete)
        ..resume = null;
      await _open(t, f);
      expect(find.byType(SplashScreen), findsOneWidget);
      expect(find.byType(OnboardingHost), findsNothing);
    });

    testWidgets('signed in + completed goes to the app', (t) async {
      final f = _Fake()..state = (() async => OnboardingState.complete);
      await _open(t, f);
      expect(find.text('HOME'), findsOneWidget);
      expect(find.byType(SplashScreen), findsNothing);
      expect(find.byType(OnboardingHost), findsNothing);
    });

    testWidgets('signed out shows the splash and reads nothing', (t) async {
      final f = _Fake()..uid = null;
      await _open(t, f);
      expect(find.byType(SplashScreen), findsOneWidget);
      expect(f.stateReads, 0);
    });
  });

  group('resume host', () {
    testWidgets('a row prefills the draft and starts at the buddy step; Back walks the filled steps',
        (t) async {
      final f = _Fake()
        ..state = (() async => OnboardingState.incomplete)
        ..resume = _fullRow;
      await _open(t, f);
      final host = _host(t);
      expect(host.index, 3);
      expect(host.draft.name.text, 'Rowan');
      expect(host.draft.age.text, '27');
      expect(host.draft.username.text, 'rowan_g');
      expect(host.draft.avatarId, 'wolf');
      expect(find.text("Who's your buddy?"), findsOneWidget);

      await t.tap(find.byType(ObBackButton));
      await _settle(t);
      expect(host.index, 2);
      expect(find.widgetWithText(TextField, 'Rowan'), findsOneWidget);
      expect(find.text('27'), findsOneWidget);

      host.back();
      await _settle(t);
      expect(host.index, 1);
      expect(find.text('Pick your buddy'), findsOneWidget);
    });

    testWidgets('no row starts at the avatar step with an empty draft',
        (t) async {
      final f = _Fake()..state = (() async => OnboardingState.noProfile);
      await _open(t, f);
      final host = _host(t);
      expect(host.index, 1);
      expect(host.draft.name.text, isEmpty);
      expect(host.draft.age.text, isEmpty);
      expect(host.draft.username.text, isEmpty);
      expect(host.draft.avatarId, 'bear');
      expect(host.draft.pairedWith, isNull);
    });

    testWidgets('a partial row restarts at the avatar step, prefilled',
        (t) async {
      final f = _Fake()
        ..state = (() async => OnboardingState.incomplete)
        ..resume = const OnboardingResume(
            name: 'Rowan', age: null, username: '', avatarId: 'lion');
      await _open(t, f);
      final host = _host(t);
      expect(host.index, 1);
      expect(host.draft.name.text, 'Rowan');
      expect(host.draft.avatarId, 'lion');
    });

    testWidgets('an accepted invite shows the paired card; the paired line wins',
        (t) async {
      final f = _Fake()
        ..state = (() async => OnboardingState.incomplete)
        ..resume = _pairedRow;
      await _open(t, f);
      expect(find.text("You're paired with Dan"), findsOneWidget);
      expect(find.text(_pairedLine), findsOneWidget);
      expect(find.text(_welcome), findsNothing);
      expect(find.widgetWithText(ElevatedButton, 'Continue'), findsOneWidget);
    });

    testWidgets('welcome-back line shows at the buddy step when not paired',
        (t) async {
      final f = _Fake()
        ..state = (() async => OnboardingState.incomplete)
        ..resume = _fullRow;
      await _open(t, f);
      expect(find.text(_welcome), findsOneWidget);
      expect(find.text("You're paired with Dan"), findsNothing);
    });

    testWidgets('welcome-back line shows at the avatar step when there is no row',
        (t) async {
      final f = _Fake()..state = (() async => OnboardingState.noProfile);
      await _open(t, f);
      expect(find.text(_welcome), findsOneWidget);
    });

    testWidgets('the line and the link belong to the first step only',
        (t) async {
      final f = _Fake()
        ..state = (() async => OnboardingState.incomplete)
        ..resume = _fullRow;
      await _open(t, f);
      _host(t).back();
      await _settle(t);
      expect(_host(t).index, 2);
      expect(find.text(_welcome), findsNothing);
      expect(find.text(_escape), findsNothing);
    });
  });

  group('escape link', () {
    testWidgets('is quiet, 44px tall, in the subtle colour', (t) async {
      final f = _Fake()
        ..state = (() async => OnboardingState.incomplete)
        ..resume = _fullRow;
      await _open(t, f);
      final link = find.widgetWithText(TextButton, _escape);
      expect(link, findsOneWidget);
      expect(t.getSize(link).height, greaterThanOrEqualTo(44));
      final colors = AppColors.of(t.element(link));
      final style = t.widget<TextButton>(link).style!;
      expect(style.foregroundColor!.resolve({}), colors.subtleText);
      expect(colors.subtleText, const Color(0xFFB9CFC3));
    });

    testWidgets('is absent outside a resume', (t) async {
      final f = _Fake();
      await _open(t, f,
          home: OnboardingHost(buddyDeps: f.deps().buddyDeps));
      expect(find.text(_escape), findsNothing);
      expect(find.text(_welcome), findsNothing);
    });

    testWidgets('signs out and ends on the splash without a bounce',
        (t) async {
      final f = _Fake()
        ..state = (() async => OnboardingState.incomplete)
        ..resume = _fullRow;
      await _open(t, f);
      expect(f.stateReads, 1);
      await t.tap(find.text(_escape));
      await _settle(t);
      expect(f.signOuts, 1);
      expect(find.byType(SplashScreen), findsOneWidget);
      expect(find.byType(OnboardingHost), findsNothing);
      expect(find.byType(AuthWrapper), findsNothing);
      // Nothing re-read the status: no path back into onboarding.
      expect(f.stateReads, 1);
    });

    testWidgets('a double tap signs out once', (t) async {
      final f = _Fake()
        ..state = (() async => OnboardingState.noProfile)
        ..signOutGate = Completer<void>();
      await _open(t, f);
      await t.tap(find.text(_escape));
      await t.tap(find.text(_escape), warnIfMissed: false);
      await t.pump();
      expect(f.signOuts, 1);
      f.signOutGate!.complete();
      await _settle(t);
      expect(f.signOuts, 1);
      expect(find.byType(SplashScreen), findsOneWidget);
    });
  });

  group('no double push', () {
    testWidgets('the splash replaces AuthWrapper when it starts sign-up',
        (t) async {
      final f = _Fake()..uid = null;
      await _open(t, f);
      expect(find.byType(AuthWrapper), findsOneWidget);
      await t.tap(find.text('Get started'));
      await _settle(t);
      // AuthWrapper is gone, so the account that sign-up creates next cannot
      // rebuild it into a second host on top of the flow.
      expect(find.byType(AuthWrapper), findsNothing);
      expect(find.byType(SplashScreen), findsNothing);
      f.uid = 'new-user';
      await _settle(t);
      expect(find.byType(OnboardingHost), findsNothing);
      expect(f.stateReads, 0);
    });

    testWidgets('login pushes one host and removes AuthWrapper', (t) async {
      final f = _Fake()..uid = null;
      await _open(t, f);
      // Exactly what login_screen.dart does for a noProfile / incomplete
      // account.
      final nav = Navigator.of(t.element(find.byType(SplashScreen)));
      unawaited(nav.pushAndRemoveUntil(
        FadeSlideRoute(
            page: OnboardingHost(
                resume: true,
                signOut: f.deps().signOut,
                buddyDeps: f.deps().buddyDeps)),
        (r) => false,
      ));
      await _settle(t);
      expect(find.byType(OnboardingHost), findsOneWidget);
      expect(find.byType(AuthWrapper), findsNothing);
      expect(find.byType(SplashScreen), findsNothing);
      expect(f.stateReads, 0);
    });
  });

  group('loadOnboardingResume', () {
    ResumeReads reads({
      List<Map<String, dynamic>>? profile,
      List<Map<String, dynamic>> invites = const [],
      Object? profileError,
      Object? inviteError,
    }) =>
        ResumeReads(
          profile: () async {
            if (profileError != null) throw profileError;
            return profile ?? [];
          },
          acceptedInvites: () async {
            if (inviteError != null) throw inviteError;
            return invites;
          },
          inviterName: (id) async => 'name-of-$id',
        );

    const row = {
      'display_name': ' Rowan ',
      'age': 27,
      'username': 'rowan_g',
      'avatar_id': 'wolf',
    };

    test('maps the row; the inviter name comes from the server', () async {
      final r = await loadOnboardingResume(reads(profile: [
        row
      ], invites: [
        {'inviter_id': 'inv-1'}
      ]));
      expect(r!.name, 'Rowan');
      expect(r.age, 27);
      expect(r.username, 'rowan_g');
      expect(r.avatarId, 'wolf');
      expect(r.pairedWith, 'name-of-inv-1');
      expect(r.complete, isTrue);
    });

    test('no accepted invite leaves pairedWith null', () async {
      final r = await loadOnboardingResume(reads(profile: [row]));
      expect(r!.pairedWith, isNull);
    });

    test('a failed profile or invite read is null, never a guess', () async {
      expect(await loadOnboardingResume(reads(profileError: 'boom')), isNull);
      expect(
          await loadOnboardingResume(
              reads(profile: [row], inviteError: 'boom')),
          isNull);
    });
  });
}
