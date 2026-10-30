import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gym_buddy_app/onboarding/onboarding_account.dart';
import 'package:gym_buddy_app/onboarding/onboarding_draft.dart';
import 'package:gym_buddy_app/onboarding/onboarding_host.dart';
import 'package:gym_buddy_app/onboarding/onboarding_step_buddy.dart';
import 'package:gym_buddy_app/services/invite_service.dart';
import 'package:gym_buddy_app/theme/app_theme.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

const _maxDefault =
    "That's me. I'm an AI, so I never miss a day. Invite a friend any time.";
const _maxError =
    "That code didn't work. Check it, or ask your buddy for a new link.";

class _Fake {
  String? pending;
  Object? saveError;
  Object? finishError;
  InviteRedeemResult result =
      const InviteRedeemResult(InviteRedeemStatus.paired, 'inviter-1');
  final calls = <String>[];

  BuddyDeps deps() => BuddyDeps(
        pendingCode: () async => pending,
        clearPendingCode: () async {
          calls.add('clear');
          pending = null;
        },
        saveRow: (_) async {
          calls.add('saveRow');
          if (saveError != null) throw saveError!;
        },
        finish: (_) async {
          calls.add('finish');
          if (finishError != null) throw finishError!;
        },
        redeem: (code) async {
          calls.add('redeem $code');
          return result;
        },
        inviterName: (id) async {
          calls.add('name $id');
          return 'Dan';
        },
      );
}

Future<void> _settle(WidgetTester t) async {
  for (var i = 0; i < 4; i++) {
    await t.pump(const Duration(milliseconds: 300));
  }
}

Future<OnboardingHostState> _open(WidgetTester t, _Fake f) async {
  t.view.physicalSize = const Size(1080, 2400);
  t.view.devicePixelRatio = 3;
  addTearDown(t.view.reset);
  await t.pumpWidget(MaterialApp(
    theme: AppTheme.fromAccent(AccentPalette.emeraldInk),
    builder: (c, w) => MediaQuery(
      data: MediaQuery.of(c).copyWith(disableAnimations: true),
      child: w!,
    ),
    home: OnboardingHost(buddyDeps: f.deps()),
  ));
  final host = t.state<OnboardingHostState>(find.byType(OnboardingHost));
  host.go(3);
  await _settle(t);
  return host;
}

Future<void> _tap(WidgetTester t, Finder f) async {
  await t.ensureVisible(f);
  await t.pump();
  await t.tap(f);
  await _settle(t);
}

Finder _main(String label) => find.widgetWithText(ElevatedButton, label);

Future<void> _typeAndJoin(WidgetTester t, String code) async {
  await _tap(t, find.text('Have an invite code?'));
  await t.enterText(find.byType(TextField), code);
  await _tap(t, find.widgetWithText(OutlinedButton, 'Join'));
}

void main() {
  group('buddy step', () {
    testWidgets('no pending code: two cards and the code link', (t) async {
      final f = _Fake();
      await _open(t, f);
      expect(find.text('Invite a friend'), findsOneWidget);
      expect(find.text('Coach Max'), findsOneWidget);
      expect(find.text(_maxDefault), findsOneWidget);
      expect(_main('Start with Coach Max'), findsOneWidget);
      final link = find.widgetWithText(TextButton, 'Have an invite code?');
      expect(t.getSize(link).height, greaterThanOrEqualTo(44));
      expect(find.byType(TextField), findsNothing);
    });

    testWidgets('the code field opens inline', (t) async {
      final f = _Fake();
      await _open(t, f);
      await _tap(t, find.text('Have an invite code?'));
      expect(find.text('Invite code'), findsOneWidget);
      expect(find.text('8 characters'), findsOneWidget);
      expect(find.widgetWithText(OutlinedButton, 'Join'), findsOneWidget);
      expect(find.text("It's on the page your friend's link opens."), findsOneWidget);
      expect(find.text('Got a code from a friend? Type it in.'), findsOneWidget);

      await t.enterText(find.byType(TextField), 'ab-cd12345xyz');
      await t.pump();
      expect(t.widget<TextField>(find.byType(TextField)).controller!.text,
          'ABCD1234');
    });

    testWidgets('a typed code saves the row first, then redeems', (t) async {
      final f = _Fake();
      await _open(t, f);
      await _typeAndJoin(t, '3f9a21bc');
      expect(f.calls, ['saveRow', 'redeem 3F9A21BC', 'name inviter-1']);
      expect(find.text("You're paired with Dan"), findsOneWidget);
    });

    for (final (status, message) in [
      (InviteRedeemStatus.invalid, kInviteInvalid),
      (InviteRedeemStatus.offline, kInviteOffline),
      (InviteRedeemStatus.rateLimited, kInviteRateLimited),
    ]) {
      testWidgets('error: ${status.name}', (t) async {
        final f = _Fake()..result = InviteRedeemResult(status);
        await _open(t, f);
        await _typeAndJoin(t, '3F9A21BC');
        expect(find.text(message), findsOneWidget);
        expect(find.text(_maxError), findsOneWidget);
        expect(find.text("It's on the page your friend's link opens."), findsNothing);
        final color = t.widget<Text>(find.text(message)).style!.color;
        final ctx = t.element(find.text(message));
        expect(color, AppColors.of(ctx).danger);
      });
    }

    testWidgets('error: malformed, with no save and no redeem', (t) async {
      final f = _Fake();
      await _open(t, f);
      await _typeAndJoin(t, '3F9A');
      expect(find.text(kInviteMalformed), findsOneWidget);
      expect(find.text(_maxError), findsOneWidget);
      expect(f.calls, isEmpty);
    });

    testWidgets('pending code: Join your buddy is picked by default', (t) async {
      final f = _Fake()..pending = 'AAAA1111';
      await _open(t, f);
      expect(find.text('Join your buddy'), findsNWidgets(2)); // card + button
      expect(find.text('You were invited. We will pair you up and start your streak.'),
          findsOneWidget);
      expect(find.text('Coach Max'), findsOneWidget);
      expect(find.text('Someone invited you. Tap Join to team up with them.'),
          findsOneWidget);
      expect(find.text('Have an invite code?'), findsNothing);
      expect(_main('Join your buddy'), findsOneWidget);
    });

    testWidgets('pending code: Join saves first, redeems second, pairs', (t) async {
      final f = _Fake()..pending = 'AAAA1111';
      await _open(t, f);
      await _tap(t, _main('Join your buddy'));
      expect(f.calls, ['saveRow', 'redeem AAAA1111', 'name inviter-1']);
      expect(find.text("You're paired with Dan"), findsOneWidget);
    });

    testWidgets('a failed early save redeems nothing and keeps the code',
        (t) async {
      final f = _Fake()
        ..pending = 'AAAA1111'
        ..saveError = Exception('offline');
      await _open(t, f);
      await _tap(t, _main('Join your buddy'));
      expect(f.calls, ['saveRow']);
      expect(f.pending, 'AAAA1111');
      expect(find.text(kProfileSaveFailed), findsOneWidget);
      expect(_main('Join your buddy'), findsOneWidget);
    });

    testWidgets(
        'a username clash on the main button shows the save-failed message and stays',
        (t) async {
      final f = _Fake()
        ..finishError = const PostgrestException(
            message:
                'duplicate key value violates unique constraint "user_profiles_username_key"',
            code: '23505');
      await _open(t, f);
      await _tap(t, _main('Start with Coach Max'));
      expect(f.calls, contains('finish'));
      expect(find.text(kProfileSaveFailed), findsOneWidget);
      expect(_main('Start with Coach Max'), findsOneWidget);
    });

    testWidgets('pending code that is invalid moves into the field', (t) async {
      final f = _Fake()
        ..pending = 'AAAA1111'
        ..result = const InviteRedeemResult(InviteRedeemStatus.invalid);
      await _open(t, f);
      await _tap(t, _main('Join your buddy'));
      expect(find.text(kInviteInvalid), findsOneWidget);
      expect(find.text('Invite a friend'), findsOneWidget);
      expect(t.widget<TextField>(find.byType(TextField)).controller!.text,
          'AAAA1111');
      expect(_main('Start with Coach Max'), findsOneWidget);
    });

    testWidgets('pending code offline stays waiting with the error', (t) async {
      final f = _Fake()
        ..pending = 'AAAA1111'
        ..result = const InviteRedeemResult(InviteRedeemStatus.offline);
      await _open(t, f);
      await _tap(t, _main('Join your buddy'));
      expect(find.text(kInviteOffline), findsOneWidget);
      expect(_main('Join your buddy'), findsOneWidget);
    });

    testWidgets('pending code, Coach Max picked: code cleared, flow as today',
        (t) async {
      final f = _Fake()..pending = 'AAAA1111';
      final host = await _open(t, f);
      await _tap(t, find.text('Coach Max'));
      expect(find.text(_maxDefault), findsOneWidget);
      await _tap(t, _main('Start with Coach Max'));
      expect(f.calls, ['clear', 'finish']);
      expect(host.index, 4);
    });

    testWidgets('paired: card, lines and Continue', (t) async {
      final f = _Fake()..pending = 'AAAA1111';
      final host = await _open(t, f);
      await _tap(t, _main('Join your buddy'));
      expect(find.text("You're paired with Dan"), findsOneWidget);
      expect(find.text('Your team is ready. Your streak starts when you both check in.'),
          findsOneWidget);
      expect(
          find.text(
              'Nice. You and Dan are a team now. Your streak starts when you both check in.'),
          findsOneWidget);
      expect(find.text('You can add Coach Max or more friends any time later.'),
          findsOneWidget);
      expect(find.text('Coach Max'), findsNothing);
      expect(find.text('Have an invite code?'), findsNothing);

      await _tap(t, _main('Continue'));
      // onboarding_completed is set by the main button alone (finish), and
      // the code is not redeemed or cleared a second time.
      expect(f.calls, ['saveRow', 'redeem AAAA1111', 'name inviter-1', 'finish']);
      expect(host.index, 4);
    });

    testWidgets('paired survives Back and forward', (t) async {
      final f = _Fake()..pending = 'AAAA1111';
      final host = await _open(t, f);
      await _tap(t, _main('Join your buddy'));
      host.back();
      await _settle(t);
      host.next();
      await _settle(t);
      expect(find.text("You're paired with Dan"), findsOneWidget);
      expect(_main('Continue'), findsOneWidget);
    });
  });

  group('profile row', () {
    OnboardingDraft draft() => OnboardingDraft()
      ..name.text = 'Ana'
      ..age.text = '30'
      ..username.text = 'Ana_1';

    test('only the main button marks onboarding complete', () {
      expect(onboardingProfileRow(draft(), 'me', completed: false)['onboarding_completed'],
          isFalse);
      expect(onboardingProfileRow(draft(), 'me', completed: true)['onboarding_completed'],
          isTrue);
    });

    // A PostgREST stand-in that records every request. PATCH with select=id
    // answers the ids of the matching rows ([existing] says whether the row
    // is there); a POST answers 201, or [insertError] when set.
    ({SupabaseClient client, List<http.Request> log, List<int> patchRows}) rig({
      required List<bool> exists,
      Map<String, String>? insertError,
      int status = 409,
    }) {
      final log = <http.Request>[];
      final patchRows = <int>[];
      var patches = 0;
      final client = SupabaseClient('https://x.supabase.co', 'anon',
          httpClient: MockClient((req) async {
        log.add(req);
        if (req.method == 'PATCH') {
          final hit = exists[patches++ % exists.length];
          patchRows.add(hit ? 1 : 0);
          return http.Response(jsonEncode(hit ? [{'id': 'me'}] : []), 200,
              headers: {'content-type': 'application/json'}, request: req);
        }
        if (insertError != null) {
          return http.Response(jsonEncode(insertError), status,
              headers: {'content-type': 'application/json'}, request: req);
        }
        return http.Response('', 201, request: req);
      }));
      addTearDown(client.dispose);
      return (client: client, log: log, patchRows: patchRows);
    }

    List<String> methods(List<http.Request> log) =>
        [for (final r in log) r.method];

    void expectNoUpsert(List<http.Request> log) {
      for (final r in log) {
        expect(r.url.queryParameters.containsKey('on_conflict'), isFalse);
        expect(r.headers['Prefer'] ?? '', isNot(contains('resolution=')));
      }
    }

    Map<String, dynamic> row(bool completed) =>
        onboardingProfileRow(draft(), 'me', completed: completed);

    const pkey = {
      'code': '23505',
      'message':
          'duplicate key value violates unique constraint "user_profiles_pkey"',
    };
    const usernameKey = {
      'code': '23505',
      'message':
          'duplicate key value violates unique constraint "user_profiles_username_key"',
    };

    test('first time: update finds no row, then a plain insert', () async {
      final r = rig(exists: [false]);
      await writeProfileRow(r.client, 'me', row(false));
      expect(methods(r.log), ['PATCH', 'POST']);
      expect(r.log[0].url.queryParameters['select'], 'id');
      expect(r.log[0].url.queryParameters['id'], 'eq.me');
      expect(r.log[0].headers['Prefer'], contains('return=representation'));
      expect(jsonDecode(r.log[0].body), isNot(contains('id')));
      expect(r.log[1].url.queryParameters.containsKey('select'), isFalse);
      expect(r.log[1].headers['Prefer'] ?? '', isNot(contains('return=representation')));
      expect(jsonDecode(r.log[1].body)['id'], 'me');
      expect(jsonDecode(r.log[1].body)['onboarding_completed'], isFalse);
      expectNoUpsert(r.log);
    });

    test('resume: the row exists, update only, no insert', () async {
      final r = rig(exists: [true]);
      await writeProfileRow(r.client, 'me', row(true));
      expect(methods(r.log), ['PATCH']);
      expect(jsonDecode(r.log[0].body)['onboarding_completed'], isTrue);
      expectNoUpsert(r.log);
    });

    test('primary-key race: insert clashes, one more update succeeds', () async {
      final r = rig(exists: [false, true], insertError: pkey);
      await writeProfileRow(r.client, 'me', row(true));
      expect(methods(r.log), ['PATCH', 'POST', 'PATCH']);
      expectNoUpsert(r.log);
    });

    test('primary-key race where the retry finds no row still fails', () async {
      final r = rig(exists: [false, false], insertError: pkey);
      await expectLater(writeProfileRow(r.client, 'me', row(true)),
          throwsA(isA<PostgrestException>()));
      expect(methods(r.log), ['PATCH', 'POST', 'PATCH']);
    });

    test('username taken: rethrown as is, no retry', () async {
      final r = rig(exists: [false], insertError: usernameKey);
      await expectLater(
          writeProfileRow(r.client, 'me', row(true)),
          throwsA(isA<PostgrestException>()
              .having((e) => e.code, 'code', '23505')
              .having((e) => e.message, 'message', contains('user_profiles_username_key'))));
      expect(methods(r.log), ['PATCH', 'POST']);
    });

    test('any other failure throws', () async {
      for (final e in <(int, Map<String, String>)>[
        (500, {'code': 'XX000', 'message': 'boom'}),
        (403, {'code': '42501', 'message': 'permission denied for table user_profiles'}),
      ]) {
        final r = rig(exists: [false], insertError: e.$2, status: e.$1);
        await expectLater(writeProfileRow(r.client, 'me', row(true)),
            throwsA(isA<PostgrestException>()));
        expect(methods(r.log), ['PATCH', 'POST']);
      }
    });

    test('a failed update throws and inserts nothing', () async {
      final client = SupabaseClient('https://x.supabase.co', 'anon',
          httpClient: MockClient((req) async => http.Response(
              jsonEncode({'code': '42501', 'message': 'permission denied'}), 403,
              headers: {'content-type': 'application/json'}, request: req)));
      addTearDown(client.dispose);
      await expectLater(writeProfileRow(client, 'me', row(true)),
          throwsA(isA<PostgrestException>()));
    });
  });
}
