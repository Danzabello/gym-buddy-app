import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:gym_buddy_app/services/invite_service.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

Future<String?> _pending() => InviteService().pendingInviteCode();

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  group('parseInviteReferrer', () {
    test('takes the exact form the invite page sends', () {
      expect(parseInviteReferrer('invite_code=3F9A21BC'), '3F9A21BC');
    });

    test('upper-cases a lower-case code', () {
      expect(parseInviteReferrer('invite_code=3f9a21bc'), '3F9A21BC');
    });

    test('ignores extra parameters', () {
      expect(parseInviteReferrer('invite_code=3F9A21BC&utm_source=x'), isNull);
      expect(parseInviteReferrer('utm_source=x&invite_code=3F9A21BC'), isNull);
    });

    test('ignores the wrong length', () {
      expect(parseInviteReferrer('invite_code=3F9A21B'), isNull);
      expect(parseInviteReferrer('invite_code=3F9A21BCD'), isNull);
      expect(parseInviteReferrer('invite_code='), isNull);
    });

    test('ignores junk', () {
      expect(parseInviteReferrer(null), isNull);
      expect(parseInviteReferrer(''), isNull);
      expect(parseInviteReferrer('utm_source=google-play&utm_medium=organic'), isNull);
      expect(parseInviteReferrer('invite_code=3F9A-1BC'), isNull);
      expect(parseInviteReferrer('invite_code=3F9A21B%'), isNull);
      expect(parseInviteReferrer(' invite_code=3F9A21BC'), isNull);
      expect(parseInviteReferrer('INVITE_CODE=3F9A21BC'), isNull);
    });
  });

  test('normalizeInviteCode', () {
    expect(normalizeInviteCode(' 3f9a21bc '), '3F9A21BC');
    expect(normalizeInviteCode('3F9A'), isNull);
    expect(normalizeInviteCode('3F9A21B!'), isNull);
  });

  group('classifyAccept', () {
    Future<InviteRedeemStatus> status(Future<Object?> Function() f) async =>
        (await classifyAccept(f)).status;

    test('an inviter id is paired', () async {
      final r = await classifyAccept(() async => 'inviter-1');
      expect(r.status, InviteRedeemStatus.paired);
      expect(r.inviterId, 'inviter-1');
    });

    test('null (unknown, used, expired, own) is invalid', () async {
      expect(await status(() async => null), InviteRedeemStatus.invalid);
    });

    test('too_many_attempts is rate limited', () async {
      expect(
          await status(() async =>
              throw const PostgrestException(message: 'too_many_attempts', code: 'P0001')),
          InviteRedeemStatus.rateLimited);
    });

    test('any other server error is invalid', () async {
      for (final m in ['cannot_accept_own_invite', 'unauthenticated']) {
        expect(
            await status(() async =>
                throw PostgrestException(message: m, code: 'P0001')),
            InviteRedeemStatus.invalid);
      }
    });

    test('network errors are offline', () async {
      expect(await status(() async => throw const SocketException('down')),
          InviteRedeemStatus.offline);
      expect(await status(() async => throw TimeoutException('slow')),
          InviteRedeemStatus.offline);
    });
  });

  test('redeem says malformed before calling the server', () async {
    // No Supabase client exists in this test, so any RPC would throw.
    final r = await InviteService().redeem('3F9A');
    expect(r.status, InviteRedeemStatus.malformed);
  });

  group('createTeamWithRetry', () {
    test('succeeds on the first try', () async {
      var calls = 0;
      expect(await createTeamWithRetry(() async => calls++, delay: Duration.zero), isTrue);
      expect(calls, 1);
    });

    test('retries until it works', () async {
      var calls = 0;
      final ok = await createTeamWithRetry(() async {
        if (++calls < 3) throw Exception('blip');
      }, delay: Duration.zero);
      expect(ok, isTrue);
      expect(calls, 3);
    });

    test('gives up after three retries', () async {
      var calls = 0;
      final ok = await createTeamWithRetry(() async {
        calls++;
        throw Exception('down');
      }, delay: Duration.zero);
      expect(ok, isFalse);
      expect(calls, 4);
    });
  });

  group('team retry at launch', () {
    test('runs once for the user who accepted', () async {
      await InviteService().rememberTeamRetry('me', 'inviter-1');
      final made = <String>[];
      Future<void> create(String id) async => made.add(id);
      await InviteService().retryPendingTeam('me', create: create);
      await InviteService().retryPendingTeam('me', create: create);
      expect(made, ['inviter-1']);
    });

    test('a failed retry is not tried again', () async {
      await InviteService().rememberTeamRetry('me', 'inviter-1');
      var calls = 0;
      Future<void> fail(String _) async {
        calls++;
        throw Exception('down');
      }
      await InviteService().retryPendingTeam('me', create: fail);
      await InviteService().retryPendingTeam('me', create: fail);
      expect(calls, 1);
    });

    test('is left alone for another user', () async {
      await InviteService().rememberTeamRetry('me', 'inviter-1');
      final made = <String>[];
      await InviteService()
          .retryPendingTeam('someone-else', create: (id) async => made.add(id));
      expect(made, isEmpty);
      await InviteService().retryPendingTeam('me', create: (id) async => made.add(id));
      expect(made, ['inviter-1']);
    });
  });

  group('redeem', redeemTests);

  group('pending code lifecycle', () {
    test('the referrer is stored once', () async {
      var reads = 0;
      Future<String?> read() async {
        reads++;
        return 'invite_code=3F9A21BC';
      }
      await InviteService().readInstallReferrerOnce(read);
      expect(await _pending(), '3F9A21BC');
      await InviteService().clearPendingInviteCode();
      await InviteService().readInstallReferrerOnce(read);
      expect(reads, 1);
      expect(await _pending(), isNull);
    });

    test('a failed referrer read still counts as done', () async {
      var reads = 0;
      Future<String?> read() async {
        reads++;
        throw Exception('no Play');
      }
      await InviteService().readInstallReferrerOnce(read);
      await InviteService().readInstallReferrerOnce(read);
      expect(reads, 1);
      expect(await _pending(), isNull);
    });

    test('the referrer does not overwrite a code a link stored', () async {
      await InviteService().storePendingInviteCode('AAAA1111');
      await InviteService()
          .readInstallReferrerOnce(() async => 'invite_code=BBBB2222');
      expect(await _pending(), 'AAAA1111');
    });

    test('a link stores only a valid code', () async {
      await InviteService.storeCodeFromLink(
          Uri.parse('https://x.supabase.co/functions/v1/invite-redirect?code=3f9a21bc'));
      expect(await _pending(), '3F9A21BC');
      await InviteService.storeCodeFromLink(
          Uri.parse('https://x.supabase.co/functions/v1/invite-redirect?code=<script>'));
      expect(await _pending(), '3F9A21BC');
    });

    test('is cleared on sign-out', () async {
      await InviteService().storePendingInviteCode('3F9A21BC');
      await InviteService.onAuthEvent(AuthChangeEvent.tokenRefreshed);
      expect(await _pending(), '3F9A21BC');
      await InviteService.onAuthEvent(AuthChangeEvent.signedOut);
      expect(await _pending(), isNull);
    });

    test('is discarded for a finished account only', () async {
      await InviteService().storePendingInviteCode('3F9A21BC');
      await InviteService().discardPendingIfOnboarded(null);
      await InviteService().discardPendingIfOnboarded(false);
      expect(await _pending(), '3F9A21BC');
      await InviteService().discardPendingIfOnboarded(true);
      expect(await _pending(), isNull);
    });
  });
}

/// accept_invite answers [accept]; create_invite_team fails [teamFailures]
/// times first.
class _Server {
  final Object? Function() accept;
  int teamFailures;
  final calls = <String>[];
  _Server(this.accept, {this.teamFailures = 0});

  Future<Object?> rpc(String fn, Map<String, dynamic> params) async {
    calls.add(fn);
    if (fn == 'accept_invite') return accept();
    if (teamFailures-- > 0) throw Exception('down');
    return 'team-1';
  }

  Future<InviteRedeemResult> redeem(String code) => InviteService()
      .redeem(code, rpc: rpc, userId: 'me', retryDelay: Duration.zero);
}

void redeemTests() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('paired clears the waiting code and makes the team', () async {
    await InviteService().storePendingInviteCode('3F9A21BC');
    final s = _Server(() => 'inviter-1');
    final r = await s.redeem('3F9A21BC');
    expect(r.status, InviteRedeemStatus.paired);
    expect(s.calls, ['accept_invite', 'create_invite_team']);
    expect(await _pending(), isNull);
  });

  test('a team that fails four times is kept for the launch retry', () async {
    final s = _Server(() => 'inviter-1', teamFailures: 4);
    expect((await s.redeem('3F9A21BC')).status, InviteRedeemStatus.paired);
    expect(s.calls.where((c) => c == 'create_invite_team').length, 4);
    final made = <String>[];
    await InviteService().retryPendingTeam('me', create: (id) async => made.add(id));
    expect(made, ['inviter-1']);
  });

  test('a team that works on a retry leaves nothing behind', () async {
    final s = _Server(() => 'inviter-1', teamFailures: 2);
    await s.redeem('3F9A21BC');
    final made = <String>[];
    await InviteService().retryPendingTeam('me', create: (id) async => made.add(id));
    expect(made, isEmpty);
  });

  test('an invalid waiting code is dropped', () async {
    await InviteService().storePendingInviteCode('3F9A21BC');
    final s = _Server(() => null);
    expect((await s.redeem('3F9A21BC')).status, InviteRedeemStatus.invalid);
    expect(s.calls, ['accept_invite']);
    expect(await _pending(), isNull);
  });

  test('offline and rate limited keep the waiting code', () async {
    await InviteService().storePendingInviteCode('3F9A21BC');
    for (final err in <Object>[
      const SocketException('down'),
      const PostgrestException(message: 'too_many_attempts'),
    ]) {
      final s = _Server(() => throw err);
      await s.redeem('3F9A21BC');
      expect(s.calls, ['accept_invite']);
      expect(await _pending(), '3F9A21BC');
    }
  });
}
