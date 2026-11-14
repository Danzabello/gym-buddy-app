import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:gym_buddy_app/services/chat_service.dart';
import 'package:gym_buddy_app/services/handshake_service.dart' show ServerClock;
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

const me = '11111111-1111-4111-8111-111111111111';
const buddy = '22222222-2222-4222-8222-222222222222';
const other = '33333333-3333-4333-8333-333333333333';

/// A Supabase client whose HTTP goes to [reply]. Every request is kept.
class _Server {
  final calls = <http.Request>[];
  Object? Function(http.Request) reply = (_) => {};
  int status = 200;
  bool down = false;

  late final SupabaseClient client = SupabaseClient(
    'https://example.supabase.co',
    'anon',
    httpClient: MockClient((req) async {
      calls.add(req);
      if (down) throw const SocketException('down');
      return http.Response(jsonEncode(reply(req)), status,
          request: req, headers: {'content-type': 'application/json; charset=utf-8'});
    }),
  );

  Map<String, dynamic> body(int i) => jsonDecode(calls[i].body) as Map<String, dynamic>;
}

/// Stands in for Realtime: the test pushes rows through [insert].
class _Feed {
  String? userId;
  void Function(Map<String, dynamic>)? insert;
  int subscribed = 0, unsubscribed = 0;

  ChatUnsubscribe call(String uid, void Function(Map<String, dynamic>) onInsert) {
    subscribed++;
    userId = uid;
    insert = onInsert;
    return () {
      unsubscribed++;
      insert = null;
    };
  }
}

Map<String, dynamic> _msg(String id, DateTime created,
        {String from = buddy, String to = me, String body = 'hi', bool withExpiry = true}) =>
    {
      'id': id,
      'sender_id': from,
      'recipient_id': to,
      'body': body,
      'created_at': created.toUtc().toIso8601String(),
      if (withExpiry) 'expires_at': created.toUtc().add(chatLifetime).toIso8601String(),
    };

Map<String, dynamic> _conversation(DateTime serverNow, List<Map<String, dynamic>> messages,
        {bool isBuddy = true, bool blockedByMe = false}) =>
    {
      'server_now': serverNow.toUtc().toIso8601String(),
      'is_buddy': isBuddy,
      'blocked_by_me': blockedByMe,
      'messages': messages,
    };

void main() {
  final t0 = DateTime.utc(2026, 11, 14, 12);

  (ChatService, _Server, _Feed) make({DateTime Function()? local, Duration? resyncEvery}) {
    final server = _Server();
    final feed = _Feed();
    final service = ChatService(
      client: server.client,
      userId: me,
      subscribe: feed.call,
      clock: ServerClock(local),
      resyncEvery: resyncEvery ?? const Duration(seconds: 60),
    );
    return (service, server, feed);
  }

  group('newMessageId', () {
    test('is a version 4 UUID and differs every time', () {
      final v4 = RegExp(r'^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$');
      final ids = {for (var i = 0; i < 200; i++) ChatService.newMessageId()};
      expect(ids.length, 200);
      expect(ids.every(v4.hasMatch), isTrue);
    });
  });

  group('send', () {
    test('calls send_chat_message with the id, the buddy and the trimmed text', () async {
      final (s, server, _) = make();
      server.reply = (_) => {
            'ok': true,
            'duplicate': false,
            'server_now': t0.toIso8601String(),
            'message': _msg('m1', t0, from: me, to: buddy, body: 'done, your turn'),
          };
      final r = await s.send(buddyId: buddy, body: '  done, your turn \n', id: 'm1');
      expect(server.calls.single.url.path, '/rest/v1/rpc/send_chat_message');
      expect(server.calls.single.method, 'POST');
      expect(server.body(0), {'p_id': 'm1', 'p_recipient_id': buddy, 'p_body': 'done, your turn'});
      expect(r.status, ChatSendStatus.sent);
      expect(r.id, 'm1');
      expect(r.message!.body, 'done, your turn');
      expect(r.message!.createdAt, t0);
      expect(r.message!.expiresAt, t0.add(chatLifetime));
    });

    test('makes an id when none is given and returns it for the retry', () async {
      final (s, server, _) = make();
      server.down = true;
      final first = await s.send(buddyId: buddy, body: 'hello');
      expect(first.status, ChatSendStatus.offline);
      expect(server.body(0)['p_id'], first.id);
      expect(first.id, matches(RegExp(r'^[0-9a-f-]{36}$')));

      server.down = false;
      server.reply = (_) => {
            'ok': true,
            'duplicate': true,
            'server_now': t0.toIso8601String(),
            'message': _msg(first.id, t0, from: me, to: buddy, body: 'hello'),
          };
      final retry = await s.send(buddyId: buddy, body: 'hello', id: first.id);
      expect(server.body(1)['p_id'], first.id, reason: 'the retry reuses the id, so nothing is stored twice');
      expect(retry.status, ChatSendStatus.sent);
      expect(retry.message!.id, first.id);
    });

    test('empty and too long are answered without calling the server', () async {
      final (s, server, _) = make();
      expect((await s.send(buddyId: buddy, body: '')).status, ChatSendStatus.empty);
      expect((await s.send(buddyId: buddy, body: ' \n\t ')).status, ChatSendStatus.empty);
      expect((await s.send(buddyId: buddy, body: 'x' * 501)).status, ChatSendStatus.tooLong);
      expect(server.calls, isEmpty);
    });

    test('the limit is 500 code points, counted like the server counts them', () async {
      final (s, server, _) = make();
      server.reply = (_) => {'ok': false, 'reason': 'not_buddies'};
      await s.send(buddyId: buddy, body: 'x' * 500);
      await s.send(buddyId: buddy, body: '\u{1F4AA}' * 500); // 1000 UTF-16 units, 500 code points
      expect(server.calls.length, 2);
      expect((await s.send(buddyId: buddy, body: '\u{1F4AA}' * 501)).status, ChatSendStatus.tooLong);
      expect(server.calls.length, 2);
    });

    test('every server reason maps to its status', () {
      ChatSendStatus of(Map<String, dynamic> j) => chatSendResultFromJson(j, 'm1').status;
      expect(of({'ok': false, 'reason': 'not_buddies'}), ChatSendStatus.notBuddies);
      expect(of({'ok': false, 'reason': 'blocked'}), ChatSendStatus.blocked);
      expect(of({'ok': false, 'reason': 'rate_limited', 'retry_after_seconds': 42}), ChatSendStatus.rateLimited);
      expect(of({'ok': false, 'reason': 'too_long'}), ChatSendStatus.tooLong);
      expect(of({'ok': false, 'reason': 'empty'}), ChatSendStatus.empty);
      expect(of({'ok': false, 'reason': 'id_taken'}), ChatSendStatus.error);
      expect(of({'ok': false, 'reason': 'something_new'}), ChatSendStatus.error);
      expect(of({'ok': false}), ChatSendStatus.error);
    });

    test('a refusal carries no message, and the rate limit carries its wait', () async {
      final (s, server, _) = make();
      server.reply = (_) => {'ok': false, 'reason': 'rate_limited', 'retry_after_seconds': 37, 'server_now': t0.toIso8601String()};
      final limited = await s.send(buddyId: buddy, body: 'hi', id: 'm1');
      expect(limited.status, ChatSendStatus.rateLimited);
      expect(limited.retryAfter, const Duration(seconds: 37));
      expect(limited.message, isNull);

      server.reply = (_) => {'ok': false, 'reason': 'rate_limited'};
      expect((await s.send(buddyId: buddy, body: 'hi')).retryAfter, const Duration(seconds: 60));

      server.reply = (_) => {'ok': false, 'reason': 'blocked', 'server_now': t0.toIso8601String()};
      final blocked = await s.send(buddyId: buddy, body: 'hi', id: 'm2');
      expect(blocked.status, ChatSendStatus.blocked);
      expect(blocked.message, isNull);
      expect(blocked.retryAfter, isNull);
    });

    test('a server error is error, no answer at all is offline, and neither throws', () async {
      final (s, server, _) = make();
      server.status = 400;
      server.reply = (_) => {'message': 'not_authenticated', 'code': 'P0001'};
      expect((await s.send(buddyId: buddy, body: 'hi')).status, ChatSendStatus.error);

      server.down = true;
      expect((await s.send(buddyId: buddy, body: 'hi')).status, ChatSendStatus.offline);
    });
  });

  group('loadConversation', () {
    test('calls get_chat_messages and returns the messages oldest first with the two flags', () async {
      final (s, server, _) = make(local: () => t0);
      server.reply = (_) => _conversation(t0, [
            _msg('b', t0.subtract(const Duration(minutes: 1)), body: 'second'),
            _msg('a', t0.subtract(const Duration(minutes: 2)), from: me, to: buddy, body: 'first'),
          ]);
      final c = await s.loadConversation(buddy);
      expect(server.calls.single.url.path, '/rest/v1/rpc/get_chat_messages');
      expect(server.body(0), {'p_buddy_id': buddy});
      expect(c.messages.map((m) => m.body), ['first', 'second']);
      expect((c.isBuddy, c.blockedByMe, c.canSend), (true, false, true));
      expect(c.messages.first.senderId, me);
      expect(c.messages.first.recipientId, buddy);
    });

    test('messages sent in the same instant are ordered by id on every phone', () async {
      final (s, server, _) = make(local: () => t0);
      server.reply = (_) => _conversation(t0, [_msg('z', t0), _msg('a', t0)]);
      expect((await s.loadConversation(buddy)).messages.map((m) => m.id), ['a', 'z']);
    });

    test('not buddies and blocked by me are passed on, and neither can send', () async {
      final (s, server, _) = make(local: () => t0);
      server.reply = (_) => _conversation(t0, [], isBuddy: false);
      var c = await s.loadConversation(buddy);
      expect((c.isBuddy, c.canSend, c.messages.isEmpty), (false, false, true));
      server.reply = (_) => _conversation(t0, [], blockedByMe: true);
      c = await s.loadConversation(buddy);
      expect((c.blockedByMe, c.canSend), (true, false));
    });

    test('a failed load throws, so a screen can show its error state', () async {
      final (s, server, _) = make();
      server.status = 403;
      server.reply = (_) => {'message': 'permission denied', 'code': '42501'};
      await expectLater(s.loadConversation(buddy), throwsA(isA<PostgrestException>()));
      server.down = true;
      await expectLater(s.loadConversation(buddy), throwsA(isA<SocketException>()));
    });

    test('expiry follows the server clock: a phone clock 5 hours off changes nothing', () async {
      // The server says it is t0. One message expires a minute after t0, one expired a minute before.
      Map<String, dynamic> reply() => _conversation(t0, [
            _msg('live', t0.subtract(chatLifetime).add(const Duration(minutes: 1))),
            _msg('dead', t0.subtract(chatLifetime).subtract(const Duration(minutes: 1))),
          ]);
      for (final skew in const [Duration(hours: -5), Duration.zero, Duration(hours: 5)]) {
        final (s, server, _) = make(local: () => t0.add(skew));
        server.reply = (_) => reply();
        final c = await s.loadConversation(buddy);
        expect(c.messages.map((m) => m.id), ['live'], reason: 'phone clock off by $skew');
        expect(s.serverNow(), t0, reason: 'serverNow is the server\'s clock, not the phone\'s');
      }
    });
  });

  group('watchConversation', () {
    /// Listens and collects every emission and error.
    (List<ChatConversation>, List<Object>, StreamSubscription<ChatConversation>) listen(ChatService s) {
      final seen = <ChatConversation>[];
      final errors = <Object>[];
      final sub = s.watchConversation(buddy).listen(seen.add, onError: errors.add);
      return (seen, errors, sub);
    }

    test('emits the loaded conversation first and subscribes for this user', () async {
      final (s, server, feed) = make(local: () => t0);
      server.reply = (_) => _conversation(t0, [_msg('a', t0.subtract(const Duration(minutes: 5)))]);
      final (seen, errors, sub) = listen(s);
      await pumpEventQueue();
      expect(errors, isEmpty);
      expect(seen.single.messages.single.id, 'a');
      expect((feed.subscribed, feed.userId), (1, me));
      await sub.cancel();
    });

    test('a Realtime row from this buddy is added; one from someone else is ignored; a repeat is not doubled', () async {
      final (s, server, feed) = make(local: () => t0);
      server.reply = (_) => _conversation(t0, [_msg('a', t0.subtract(const Duration(minutes: 5)))]);
      final (seen, _, sub) = listen(s);
      await pumpEventQueue();

      feed.insert!(_msg('b', t0, body: 'new', withExpiry: false));
      await pumpEventQueue();
      expect(seen.last.messages.map((m) => m.id), ['a', 'b']);
      expect(seen.last.messages.last.expiresAt, t0.add(chatLifetime), reason: 'Realtime rows carry no expires_at');

      final count = seen.length;
      feed.insert!(_msg('x', t0, from: other));
      await pumpEventQueue();
      expect(seen.length, count, reason: 'a row from another sender does not touch this conversation');

      feed.insert!(_msg('b', t0, body: 'new', withExpiry: false));
      await pumpEventQueue();
      expect(seen.last.messages.map((m) => m.id), ['a', 'b']);
      await sub.cancel();
    });

    test('a message leaves the list at its expiry time, without a reload', () async {
      final now = DateTime.now().toUtc();
      final (s, server, _) = make();
      server.reply = (_) => _conversation(now, [
            _msg('soon', now.subtract(chatLifetime).add(const Duration(milliseconds: 150))),
            _msg('later', now.subtract(const Duration(hours: 1))),
          ]);
      final (seen, _, sub) = listen(s);
      await pumpEventQueue();
      expect(seen.last.messages.map((m) => m.id), ['soon', 'later']);
      final calls = server.calls.length;
      await Future<void>.delayed(const Duration(milliseconds: 500));
      expect(seen.last.messages.map((m) => m.id), ['later']);
      expect(server.calls.length, calls, reason: 'the phone drops it by itself');
      await sub.cancel();
    });

    test('the reload brings in what Realtime missed and keeps a row that beat its answer', () async {
      final (s, server, feed) = make(local: () => t0, resyncEvery: const Duration(milliseconds: 60));
      server.reply = (_) => _conversation(t0, [_msg('a', t0.subtract(const Duration(minutes: 5)))]);
      final (seen, _, sub) = listen(s);
      await pumpEventQueue();
      feed.insert!(_msg('rt', t0.subtract(const Duration(minutes: 1))));
      server.reply = (_) => _conversation(t0, [
            _msg('a', t0.subtract(const Duration(minutes: 5))),
            _msg('missed', t0.subtract(const Duration(minutes: 3))),
          ]);
      await Future<void>.delayed(const Duration(milliseconds: 200));
      expect(seen.last.messages.map((m) => m.id), ['a', 'missed', 'rt']);
      expect(server.calls.length, greaterThan(1));
      await sub.cancel();
    });

    test('buddy removed while open: sending closes, what is on screen stays so it can be reported', () async {
      final (s, server, feed) = make(local: () => t0, resyncEvery: const Duration(milliseconds: 60));
      server.reply = (_) => _conversation(t0, [_msg('abuse', t0.subtract(const Duration(minutes: 1)))]);
      final (seen, _, sub) = listen(s);
      await pumpEventQueue();
      server.reply = (_) => _conversation(t0, [], isBuddy: false);
      await Future<void>.delayed(const Duration(milliseconds: 200));
      expect((seen.last.isBuddy, seen.last.canSend), (false, false));
      expect(seen.last.messages.map((m) => m.id), ['abuse']);

      final count = seen.last.messages.length;
      feed.insert!(_msg('late', t0));
      await pumpEventQueue();
      expect(seen.last.messages.length, count, reason: 'nothing new is shown once they are not buddies');
      await sub.cancel();
    });

    test('blocked by me: the view is cleared', () async {
      final (s, server, _) = make(local: () => t0, resyncEvery: const Duration(milliseconds: 60));
      server.reply = (_) => _conversation(t0, [_msg('a', t0.subtract(const Duration(minutes: 1)))]);
      final (seen, _, sub) = listen(s);
      await pumpEventQueue();
      server.reply = (_) => _conversation(t0, [], blockedByMe: true);
      await Future<void>.delayed(const Duration(milliseconds: 200));
      expect((seen.last.blockedByMe, seen.last.canSend, seen.last.messages.isEmpty), (true, false, true));
      await sub.cancel();
    });

    test('a message this user sends shows up in the open conversation', () async {
      final (s, server, _) = make(local: () => t0);
      server.reply = (req) => req.url.path.endsWith('get_chat_messages')
          ? _conversation(t0, [])
          : {
              'ok': true,
              'duplicate': false,
              'server_now': t0.toIso8601String(),
              'message': _msg('mine', t0, from: me, to: buddy, body: 'on my way'),
            };
      final (seen, _, sub) = listen(s);
      await pumpEventQueue();
      expect(seen.last.messages, isEmpty);
      await s.send(buddyId: buddy, body: 'on my way', id: 'mine');
      await pumpEventQueue();
      expect(seen.last.messages.single.body, 'on my way');
      await sub.cancel();
    });

    test('a failed first load is a stream error; a failed reload later is skipped', () async {
      final (s, server, _) = make(local: () => t0, resyncEvery: const Duration(milliseconds: 60));
      server.down = true;
      final (seen, errors, sub) = listen(s);
      await pumpEventQueue();
      expect(seen, isEmpty);
      expect(errors.single, isA<SocketException>());

      server.down = false;
      server.reply = (_) => _conversation(t0, [_msg('a', t0.subtract(const Duration(minutes: 1)))]);
      await Future<void>.delayed(const Duration(milliseconds: 200));
      expect(seen.last.messages.single.id, 'a');

      server.down = true;
      final errorCount = errors.length;
      await Future<void>.delayed(const Duration(milliseconds: 200));
      expect(errors.length, errorCount);
      expect(seen.last.messages.single.id, 'a');
      await sub.cancel();
    });

    test('cancelling stops the reloads and the subscription', () async {
      final (s, server, feed) = make(local: () => t0, resyncEvery: const Duration(milliseconds: 50));
      server.reply = (_) => _conversation(t0, [_msg('a', t0.subtract(const Duration(minutes: 1)))]);
      final (seen, _, sub) = listen(s);
      await pumpEventQueue();
      await sub.cancel();
      final calls = server.calls.length, emitted = seen.length;
      await Future<void>.delayed(const Duration(milliseconds: 200));
      expect(feed.unsubscribed, 1);
      expect(server.calls.length, calls);
      expect(seen.length, emitted);
    });
  });

  group('block', () {
    test('block and unblock call set_chat_block and say true when it worked', () async {
      final (s, server, _) = make();
      server.reply = (_) => true;
      expect(await s.block(buddy), isTrue);
      server.reply = (_) => false;
      expect(await s.unblock(buddy), isTrue);
      expect(server.calls.map((c) => c.url.path).toSet(), {'/rest/v1/rpc/set_chat_block'});
      expect(server.body(0), {'p_user_id': buddy, 'p_blocked': true});
      expect(server.body(1), {'p_user_id': buddy, 'p_blocked': false});
    });

    test('a refusal or no connection is false, never an exception', () async {
      final (s, server, _) = make();
      server.status = 400;
      server.reply = (_) => {'message': 'too_many_blocks', 'code': 'P0001'};
      expect(await s.block(buddy), isFalse);
      server.down = true;
      expect(await s.unblock(buddy), isFalse);
    });

    test('loadBlockedIds reads the caller\'s block list and throws on failure', () async {
      final (s, server, _) = make();
      server.reply = (_) => [
            {'blocked_id': buddy},
            {'blocked_id': other},
          ];
      expect(await s.loadBlockedIds(), {buddy, other});
      expect(server.calls.single.url.path, '/rest/v1/chat_blocks');
      expect(server.calls.single.url.queryParameters['select'], 'blocked_id');
      server.status = 403;
      server.reply = (_) => {'message': 'permission denied', 'code': '42501'};
      await expectLater(s.loadBlockedIds(), throwsA(isA<PostgrestException>()));
    });
  });

  group('report', () {
    test('calls report_chat_message with the id, the reason name and the note, and never the text', () async {
      final (s, server, _) = make();
      server.reply = (_) => {'ok': true, 'duplicate': false};
      final r = await s.report(messageId: 'm1', reason: ChatReportReason.harassment, note: 'again and again');
      expect(r, ChatReportStatus.reported);
      expect(server.calls.single.url.path, '/rest/v1/rpc/report_chat_message');
      expect(server.body(0), {'p_message_id': 'm1', 'p_reason': 'harassment', 'p_note': 'again and again'});
    });

    test('every reason is one the server accepts', () {
      expect(ChatReportReason.values.map((r) => r.name).toSet(),
          {'harassment', 'spam', 'sexual', 'hate', 'threat', 'other'});
    });

    test('every server answer maps to its status', () {
      expect(chatReportStatusFromJson({'ok': true, 'duplicate': false}), ChatReportStatus.reported);
      expect(chatReportStatusFromJson({'ok': true, 'duplicate': true}), ChatReportStatus.alreadyReported);
      expect(chatReportStatusFromJson({'ok': false, 'reason': 'message_not_found'}), ChatReportStatus.messageGone);
      expect(chatReportStatusFromJson({'ok': false, 'reason': 'rate_limited'}), ChatReportStatus.rateLimited);
      expect(chatReportStatusFromJson({'ok': false, 'reason': 'invalid_reason'}), ChatReportStatus.error);
      expect(chatReportStatusFromJson({'ok': false, 'reason': 'note_too_long'}), ChatReportStatus.error);
      expect(chatReportStatusFromJson({}), ChatReportStatus.error);
    });

    test('a server error is error, no answer at all is offline, and neither throws', () async {
      final (s, server, _) = make();
      server.status = 400;
      server.reply = (_) => {'message': 'not_authenticated', 'code': 'P0001'};
      expect(await s.report(messageId: 'm1', reason: ChatReportReason.spam), ChatReportStatus.error);
      server.down = true;
      expect(await s.report(messageId: 'm1', reason: ChatReportReason.spam), ChatReportStatus.offline);
    });
  });
}
