import 'package:flutter_test/flutter_test.dart';
import 'package:gym_buddy_app/onboarding/onboarding_account.dart';
import 'package:gym_buddy_app/services/auth_service.dart';

class _Port implements OnboardingAuthPort {
  final List<String?> signUps;
  final String? signInError;
  final OnboardingState state;
  bool session = false;
  final calls = <String>[];

  _Port({
    this.signUps = const ['already registered'],
    this.signInError,
    this.state = OnboardingState.noProfile,
  });

  @override
  Future<String?> signUp(String email, String password) async {
    calls.add('signUp');
    final r =
        signUps[(calls.where((c) => c == 'signUp').length - 1).clamp(
          0,
          signUps.length - 1,
        )];
    if (r == null) session = true;
    return r;
  }

  @override
  Future<String?> signIn(String email, String password) async {
    calls.add('signIn');
    if (signInError == null) session = true;
    return signInError;
  }

  @override
  bool get hasSession => session;

  @override
  Future<OnboardingState> profileState() async {
    calls.add('profileState');
    return state;
  }

  @override
  Future<void> signOut() async {
    calls.add('signOut');
    session = false;
  }
}

Future<String?> _run(_Port p) => createOnboardingAuthUser(
  email: 'a@b.co',
  password: 'Onboard12345',
  port: p,
);

void main() {
  group('readOnboardingState', () {
    test('empty list is no profile row', () async {
      expect(
        await readOnboardingState(() async => []),
        OnboardingState.noProfile,
      );
    });

    test('row with onboarding_completed true is complete', () async {
      expect(
        await readOnboardingState(
          () async => [
            {'onboarding_completed': true},
          ],
        ),
        OnboardingState.complete,
      );
    });

    test('row with onboarding_completed false is incomplete', () async {
      expect(
        await readOnboardingState(
          () async => [
            {'onboarding_completed': false},
          ],
        ),
        OnboardingState.incomplete,
      );
    });

    test('a thrown error is unknown, never no profile', () async {
      expect(
        await readOnboardingState(() async => throw Exception('offline')),
        OnboardingState.unknown,
      );
    });
  });

  group('step 1 sign-up when the email already exists', () {
    test(
      'same credentials and no profile row continue to the avatar step',
      () async {
        final p = _Port(state: OnboardingState.noProfile);
        expect(await _run(p), isNull);
        expect(p.calls, ['signUp', 'signIn', 'profileState']);
        expect(p.hasSession, isTrue);
      },
    );

    test('wrong password or offline shows the sign-in hint', () async {
      final p = _Port(signInError: 'nope');
      expect(await _run(p), kSignupFailedMessage);
      expect(p.calls, ['signUp', 'signIn']);
    });

    test(
      'a finished account is signed back out with the same message',
      () async {
        final p = _Port(state: OnboardingState.complete);
        expect(await _run(p), kSignupFailedMessage);
        expect(p.calls, contains('signOut'));
      },
    );

    test('a failed profile read does not resume', () async {
      final p = _Port(state: OnboardingState.unknown);
      expect(await _run(p), kSignupErrorMessage);
      expect(p.calls, contains('signOut'));
    });

    // A Join on step 5 writes the row with onboarding_completed false, so
    // this is someone who joined (maybe already paired) and quit before the
    // main button: they keep their account and resume at step 2.
    test('an unfinished profile row resumes and is kept', () async {
      final p = _Port(state: OnboardingState.incomplete);
      expect(await _run(p), isNull);
      expect(p.calls, ['signUp', 'signIn', 'profileState']);
      expect(p.hasSession, isTrue);
    });
  });

  group('step 1 sign-up for a new email', () {
    test('a session means success', () async {
      expect(await _run(_Port(signUps: [null])), isNull);
    });

    test(
      'no session (email confirmation on) shows the generic message',
      () async {
        expect(await _run(_NoSession()), kSignupFailedMessage);
      },
    );
  });
}

class _NoSession extends _Port {
  _NoSession() : super(signUps: [null]);
  @override
  Future<String?> signUp(String email, String password) async => null;
}
