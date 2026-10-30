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
        finish: (_) async => calls.add('finish'),
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

    test('Join, quit, resume, main button: no duplicate-key error', () async {
      // A PostgREST stand-in: a plain insert of an existing id is a 23505 on
      // the primary key, as on live; a merge upsert updates the row.
      final rows = <String, Map<String, dynamic>>{};
      final client = SupabaseClient('https://x.supabase.co', 'anon',
          httpClient: MockClient((req) async {
        final body = jsonDecode(req.body) as Map<String, dynamic>;
        final merge = req.url.queryParameters['on_conflict'] == 'id' &&
            (req.headers['Prefer'] ?? '').contains('resolution=merge-duplicates');
        if (rows.containsKey(body['id']) && !merge) {
          return http.Response(
              jsonEncode({
                'code': '23505',
                'message':
                    'duplicate key value violates unique constraint "user_profiles_pkey"',
              }),
              409,
              request: req);
        }
        rows[body['id'] as String] = {...?rows[body['id']], ...body};
        return http.Response('', 201, request: req);
      }));
      addTearDown(client.dispose);

      // Join on step 5, then the app is killed.
      await upsertProfileRow(client, onboardingProfileRow(draft(), 'me', completed: false));
      expect(rows['me']!['onboarding_completed'], isFalse);

      // The stand-in really rejects a second plain insert.
      await expectLater(
          client.from('user_profiles').insert(rows['me']!),
          throwsA(isA<PostgrestException>()));

      // Resumed at step 2 with a new draft, then the main button on step 5.
      await upsertProfileRow(client, onboardingProfileRow(draft(), 'me', completed: true));
      expect(rows['me']!['onboarding_completed'], isTrue);
    });
  });
}
