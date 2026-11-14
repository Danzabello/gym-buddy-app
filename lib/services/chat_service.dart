import 'dart:async';
import 'dart:math';

import 'package:supabase_flutter/supabase_flutter.dart';

import 'handshake_service.dart' show ServerClock;

/// 24-hour buddy chat, service layer only (design: dev/chat/design.md).
/// The server decides everything: who may send, the rate limit, blocks and
/// the 24 hours. Messages are kept in memory only, never on the phone.

/// The server's cap, counted in code points like Postgres char_length.
const int chatMaxLength = 500;
const Duration chatLifetime = Duration(hours: 24);

class ChatMessage {
  final String id;
  final String senderId;
  final String recipientId;
  final String body;

  /// Server clock, both of them. Compare with [ChatService.serverNow].
  final DateTime createdAt;
  final DateTime expiresAt;

  const ChatMessage({
    required this.id,
    required this.senderId,
    required this.recipientId,
    required this.body,
    required this.createdAt,
    required this.expiresAt,
  });

  /// A row from send_chat_message, get_chat_messages or Realtime (which has
  /// no expires_at).
  factory ChatMessage.fromMap(Map<String, dynamic> m) {
    final created = DateTime.parse(m['created_at'] as String);
    final expires = m['expires_at'] as String?;
    return ChatMessage(
      id: m['id'] as String,
      senderId: m['sender_id'] as String,
      recipientId: m['recipient_id'] as String,
      body: m['body'] as String,
      createdAt: created,
      expiresAt: expires == null ? created.add(chatLifetime) : DateTime.parse(expires),
    );
  }

  /// Oldest first, the id breaking ties, so both phones show one order.
  static int byTime(ChatMessage a, ChatMessage b) {
    final t = a.createdAt.compareTo(b.createdAt);
    return t != 0 ? t : a.id.compareTo(b.id);
  }
}

/// One conversation as the server last described it.
class ChatConversation {
  final List<ChatMessage> messages;

  /// False once either person has removed the other: nothing can be sent.
  /// Messages already loaded stay in [messages] until they expire, so one of
  /// them can still be reported.
  final bool isBuddy;

  /// True when the signed-in user has blocked this buddy.
  final bool blockedByMe;

  const ChatConversation(this.messages, {this.isBuddy = true, this.blockedByMe = false});

  bool get canSend => isBuddy && !blockedByMe;
}

enum ChatSendStatus {
  sent,

  /// Not buddies (any more), or the other account cannot chat.
  notBuddies,

  /// One of the two has blocked the other. Nothing was stored.
  blocked,

  /// Too many messages; see [ChatSendResult.retryAfter].
  rateLimited,
  tooLong,
  empty,

  /// No answer from the server. Retry with the same [ChatSendResult.id].
  offline,
  error,
}

class ChatSendResult {
  final ChatSendStatus status;

  /// The id this attempt used. Pass it to [ChatService.send] again on a
  /// retry, so the message is stored once.
  final String id;
  final ChatMessage? message;
  final Duration? retryAfter;
  const ChatSendResult(this.status, this.id, {this.message, this.retryAfter});
}

/// What send_chat_message answered, as a typed result.
ChatSendResult chatSendResultFromJson(Map<String, dynamic> j, String id) {
  if (j['ok'] == true) {
    return ChatSendResult(ChatSendStatus.sent, id,
        message: ChatMessage.fromMap(Map<String, dynamic>.from(j['message'] as Map)));
  }
  switch (j['reason']) {
    case 'not_buddies':
      return ChatSendResult(ChatSendStatus.notBuddies, id);
    case 'blocked':
      return ChatSendResult(ChatSendStatus.blocked, id);
    case 'rate_limited':
      return ChatSendResult(ChatSendStatus.rateLimited, id,
          retryAfter: Duration(seconds: (j['retry_after_seconds'] as num?)?.toInt() ?? 60));
    case 'too_long':
      return ChatSendResult(ChatSendStatus.tooLong, id);
    case 'empty':
      return ChatSendResult(ChatSendStatus.empty, id);
    default:
      return ChatSendResult(ChatSendStatus.error, id);
  }
}

/// The reasons the server accepts, by [name].
enum ChatReportReason { harassment, spam, sexual, hate, threat, other }

enum ChatReportStatus {
  reported,
  alreadyReported,

  /// The server no longer holds the message, or it was not sent to this user.
  messageGone,
  rateLimited,
  offline,
  error,
}

/// What report_chat_message answered, as a typed result.
ChatReportStatus chatReportStatusFromJson(Map<String, dynamic> j) {
  if (j['ok'] == true) {
    return j['duplicate'] == true ? ChatReportStatus.alreadyReported : ChatReportStatus.reported;
  }
  switch (j['reason']) {
    case 'message_not_found':
      return ChatReportStatus.messageGone;
    case 'rate_limited':
      return ChatReportStatus.rateLimited;
    default:
      return ChatReportStatus.error;
  }
}

typedef ChatUnsubscribe = void Function();

/// Calls [onInsert] with each new chat_messages row addressed to [userId].
typedef ChatSubscribe = ChatUnsubscribe Function(
    String userId, void Function(Map<String, dynamic> row) onInsert);

class ChatService {
  /// Use one instance per signed-in session: the private Realtime topic
  /// chat:(user id) can be joined once, and this instance shares it between
  /// its open conversations.
  ChatService({
    SupabaseClient? client,
    String? userId,
    ChatSubscribe? subscribe,
    ServerClock? clock,
    this.resyncEvery = const Duration(seconds: 60),
  })  : _client = client ?? Supabase.instance.client,
        _userId = userId,
        _clock = clock ?? ServerClock() {
    _subscribe = subscribe ?? _realtime;
  }

  final SupabaseClient _client;
  final String? _userId;
  final ServerClock _clock;
  late final ChatSubscribe _subscribe;

  /// How often an open conversation is reloaded, in case Realtime missed
  /// something or the buddy was removed.
  final Duration resyncEvery;

  String? get _uid => _userId ?? _client.auth.currentUser?.id;

  /// The server's clock as last heard. Expiry is judged against this, never
  /// against the phone's clock.
  DateTime serverNow() => _clock.now();

  /// A random UUID (version 4). Make one per message, before the first
  /// attempt, and reuse it for every retry of that message.
  static String newMessageId([Random? random]) {
    final r = random ?? Random.secure();
    final b = List<int>.generate(16, (_) => r.nextInt(256));
    b[6] = (b[6] & 0x0f) | 0x40;
    b[8] = (b[8] & 0x3f) | 0x80;
    final h = b.map((x) => x.toRadixString(16).padLeft(2, '0')).join();
    return '${h.substring(0, 8)}-${h.substring(8, 12)}-${h.substring(12, 16)}-'
        '${h.substring(16, 20)}-${h.substring(20)}';
  }

  /// Sends [body] to [buddyId]. Never throws: every outcome is a status.
  /// A retry with the same [id] returns the stored message and sends nothing
  /// twice.
  Future<ChatSendResult> send({required String buddyId, required String body, String? id}) async {
    final messageId = id ?? newMessageId();
    final text = body.trim();
    if (text.isEmpty) return ChatSendResult(ChatSendStatus.empty, messageId);
    if (text.runes.length > chatMaxLength) return ChatSendResult(ChatSendStatus.tooLong, messageId);
    try {
      final j = Map<String, dynamic>.from(await _client.rpc('send_chat_message',
          params: {'p_id': messageId, 'p_recipient_id': buddyId, 'p_body': text}) as Map);
      _syncClock(j);
      final result = chatSendResultFromJson(j, messageId);
      final sent = result.message;
      if (sent != null) {
        for (final add in [...?_open[buddyId]]) {
          add(sent);
        }
      }
      return result;
    } on PostgrestException {
      return ChatSendResult(ChatSendStatus.error, messageId);
    } catch (_) {
      return ChatSendResult(ChatSendStatus.offline, messageId);
    }
  }

  /// The unexpired messages with [buddyId], oldest first. Throws on failure,
  /// so a screen can show its error state.
  Future<ChatConversation> loadConversation(String buddyId) async {
    final j = Map<String, dynamic>.from(
        await _client.rpc('get_chat_messages', params: {'p_buddy_id': buddyId}) as Map);
    _syncClock(j);
    final now = serverNow();
    final messages = [
      for (final m in (j['messages'] as List? ?? const []))
        ChatMessage.fromMap(Map<String, dynamic>.from(m as Map))
    ].where((m) => m.expiresAt.isAfter(now)).toList()
      ..sort(ChatMessage.byTime);
    return ChatConversation(messages,
        isBuddy: j['is_buddy'] as bool? ?? true, blockedByMe: j['blocked_by_me'] as bool? ?? false);
  }

  /// The conversation with [buddyId], kept current while it is listened to:
  /// loaded once, new messages through Realtime, a reload every
  /// [resyncEvery], and each message dropped at its expiry. A failed first
  /// load is a stream error; later failed reloads are skipped. Listen again
  /// when the app comes back to the foreground.
  Stream<ChatConversation> watchConversation(String buddyId) {
    late final StreamController<ChatConversation> out;
    final byId = <String, ChatMessage>{};
    var isBuddy = true, blockedByMe = false, loaded = false;
    Timer? expiry, resync;
    ChatUnsubscribe? unsubscribe;

    void emit() {
      if (out.isClosed) return;
      final now = serverNow();
      byId.removeWhere((_, m) => !m.expiresAt.isAfter(now));
      final messages = byId.values.toList()..sort(ChatMessage.byTime);
      out.add(ChatConversation(messages, isBuddy: isBuddy, blockedByMe: blockedByMe));
      expiry?.cancel();
      if (messages.isNotEmpty) {
        final next = messages.map((m) => m.expiresAt).reduce((a, b) => a.isBefore(b) ? a : b);
        expiry = Timer(next.difference(now) + const Duration(milliseconds: 1), emit);
      }
    }

    void add(ChatMessage m) {
      if (!isBuddy || blockedByMe) return;
      byId[m.id] = m;
      if (loaded) emit();
    }

    Future<void> reload() async {
      try {
        final c = await loadConversation(buddyId);
        if (out.isClosed) return;
        isBuddy = c.isBuddy;
        blockedByMe = c.blockedByMe;
        // A blocker's view is cleared. Otherwise what is on screen stays
        // until it expires, also after the buddy is gone (it can still be
        // reported), and a Realtime row that beat this answer is not lost.
        if (blockedByMe) byId.clear();
        for (final m in c.messages) {
          byId[m.id] = m;
        }
        loaded = true;
        emit();
      } catch (e, st) {
        if (!loaded && !out.isClosed) out.addError(e, st);
      }
    }

    out = StreamController<ChatConversation>(
      onListen: () {
        (_open[buddyId] ??= {}).add(add);
        final uid = _uid;
        if (uid != null) {
          unsubscribe = _subscribe(uid, (row) {
            if (row['sender_id'] == buddyId) add(ChatMessage.fromMap(row));
          });
        }
        resync = Timer.periodic(resyncEvery, (_) => reload());
        reload();
      },
      onCancel: () {
        expiry?.cancel();
        resync?.cancel();
        unsubscribe?.call();
        _open[buddyId]?.remove(add);
        return out.close();
      },
    );
    return out.stream;
  }

  /// Stops chat with [userId] in both directions. False when it failed.
  Future<bool> block(String userId) => _setBlock(userId, true);

  Future<bool> unblock(String userId) => _setBlock(userId, false);

  Future<bool> _setBlock(String userId, bool blocked) async {
    try {
      await _client.rpc('set_chat_block', params: {'p_user_id': userId, 'p_blocked': blocked});
      return true;
    } catch (_) {
      return false;
    }
  }

  /// The ids the signed-in user has blocked. Throws on failure.
  Future<Set<String>> loadBlockedIds() async {
    final rows = await _client.from('chat_blocks').select('blocked_id');
    return {for (final r in rows) r['blocked_id'] as String};
  }

  /// Reports a message this user received. The server keeps its own copy of
  /// the message; nothing of the text is sent from here.
  Future<ChatReportStatus> report({
    required String messageId,
    required ChatReportReason reason,
    String? note,
  }) async {
    try {
      final j = Map<String, dynamic>.from(await _client.rpc('report_chat_message',
          params: {'p_message_id': messageId, 'p_reason': reason.name, 'p_note': note}) as Map);
      return chatReportStatusFromJson(j);
    } on PostgrestException {
      return ChatReportStatus.error;
    } catch (_) {
      return ChatReportStatus.offline;
    }
  }

  void _syncClock(Map<String, dynamic> j) {
    final now = DateTime.tryParse(j['server_now'] as String? ?? '');
    if (now != null) _clock.sync(now);
  }

  // Open conversations by buddy, so a message this user sends shows up in
  // them without waiting for the reload.
  final _open = <String, Set<void Function(ChatMessage)>>{};

  // One shared private channel: the join policy is for this exact topic.
  final _listeners = <void Function(Map<String, dynamic>)>{};
  RealtimeChannel? _channel;

  ChatUnsubscribe _realtime(String userId, void Function(Map<String, dynamic>) onInsert) {
    _listeners.add(onInsert);
    _channel ??= _client
        .channel('chat:$userId', opts: const RealtimeChannelConfig(private: true))
        .onPostgresChanges(
            event: PostgresChangeEvent.insert,
            schema: 'public',
            table: 'chat_messages',
            filter: PostgresChangeFilter(
                type: PostgresChangeFilterType.eq, column: 'recipient_id', value: userId),
            callback: (payload) {
              for (final l in [..._listeners]) {
                l(payload.newRecord);
              }
            })
        .subscribe();
    return () {
      _listeners.remove(onInsert);
      if (_listeners.isEmpty && _channel != null) {
        _client.removeChannel(_channel!);
        _channel = null;
      }
    };
  }
}
