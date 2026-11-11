import 'package:flutter_test/flutter_test.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:gym_buddy_app/services/auth_service.dart';

Future<GoogleSignInResult> _run({
  Future<String?> Function()? pick,
  Future<bool> Function(String)? exchange,
  List<String>? calls,
}) =>
    googleSignInFlow(
      pickIdToken: () {
        calls?.add('pick');
        return (pick ?? () async => 'id-token')();
      },
      exchange: (t) {
        calls?.add('exchange');
        return (exchange ?? (_) async => true)(t);
      },
      signOutGoogle: () async => calls?.add('googleOut'),
    );

void main() {
  test('success: token exchanged, Google session kept', () async {
    final calls = <String>[];
    expect(await _run(calls: calls), GoogleSignInResult.success);
    expect(calls, ['pick', 'exchange']);
  });

  test('cancelled picker: no exchange, no sign-out, no failure', () async {
    final calls = <String>[];
    final r = await _run(
      calls: calls,
      pick: () async => throw const GoogleSignInException(
          code: GoogleSignInExceptionCode.canceled),
    );
    expect(r, GoogleSignInResult.cancelled);
    expect(calls, ['pick']);
  });

  test('other plugin error fails and drops the Google session', () async {
    final calls = <String>[];
    final r = await _run(
      calls: calls,
      pick: () async => throw const GoogleSignInException(
          code: GoogleSignInExceptionCode.clientConfigurationError),
    );
    expect(r, GoogleSignInResult.failed);
    expect(calls, ['pick', 'googleOut']);
  });

  test('missing or empty ID token fails without calling Supabase', () async {
    for (final token in <String?>[null, '']) {
      final calls = <String>[];
      expect(await _run(calls: calls, pick: () async => token),
          GoogleSignInResult.failed);
      expect(calls, ['pick', 'googleOut']);
    }
  });

  test('Supabase error or no network fails', () async {
    for (final err in <Object>[Exception('boom'), StateError('offline')]) {
      final calls = <String>[];
      final r = await _run(calls: calls, exchange: (_) async => throw err);
      expect(r, GoogleSignInResult.failed);
      expect(calls, ['pick', 'exchange', 'googleOut']);
    }
  });

  test('Supabase answering without a user fails', () async {
    final calls = <String>[];
    expect(await _run(calls: calls, exchange: (_) async => false),
        GoogleSignInResult.failed);
    expect(calls.last, 'googleOut');
  });

  test('a failing Google sign-out cannot turn a failure into a throw', () async {
    final r = await googleSignInFlow(
      pickIdToken: () async => null,
      exchange: (_) async => true,
      signOutGoogle: () async => throw StateError('x'),
    );
    expect(r, GoogleSignInResult.failed);
  });

  test('sign-out clears Google after Supabase', () async {
    final calls = <String>[];
    await runSignOut(
      supabaseSignOut: () async => calls.add('supabase'),
      googleSignOut: () async => calls.add('google'),
    );
    expect(calls, ['supabase', 'google']);
  });

  test('sign-out clears Google even when Supabase throws', () async {
    final calls = <String>[];
    await expectLater(
      runSignOut(
        supabaseSignOut: () async => throw StateError('network'),
        googleSignOut: () async => calls.add('google'),
      ),
      throwsStateError,
    );
    expect(calls, ['google']);
  });

  test('the approved error string and the Web client ID', () {
    expect(kGoogleSignInErrorMessage, 'Google sign-in did not work. Try again.');
    expect(kGoogleWebClientId,
        '159614517589-07enhu2avringbf3fj21ggbiiub7easo.apps.googleusercontent.com');
  });
}
