import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// One notification_inbox row, as the Notifications page reads it.
class InboxRow {
  final String id;
  final String type;
  final String title;
  final String body;
  final bool quiet;
  final String? referenceId;
  final String? senderId;
  final DateTime createdAt;

  const InboxRow({
    required this.id,
    required this.type,
    required this.title,
    required this.body,
    required this.createdAt,
    this.quiet = false,
    this.referenceId,
    this.senderId,
  });

  factory InboxRow.fromMap(Map<String, dynamic> m) => InboxRow(
    id: m['id'] as String,
    type: m['notification_type'] as String,
    title: m['title'] as String,
    body: m['body'] as String,
    quiet: m['quiet'] as bool? ?? false,
    referenceId: m['reference_id'] as String?,
    senderId: m['sender_id'] as String?,
    createdAt: DateTime.parse(m['created_at'] as String),
  );
}

/// The public profile columns a row's avatar needs.
class InboxSender {
  final String? avatarId;
  final String? border;
  const InboxSender({this.avatarId, this.border});
}

class NotificationInboxService {
  static const int rowLimit = 100;
  static const Duration window = Duration(days: 7);

  final SupabaseClient _client;
  final String? _userId;

  NotificationInboxService({SupabaseClient? client, String? userId})
    : _client = client ?? Supabase.instance.client,
      _userId = userId;

  String? get _uid => _userId ?? _client.auth.currentUser?.id;

  /// The signed-in user's last 7 days, newest first. Throws on failure, so
  /// the page can show its failure state. The daily purge can leave rows up
  /// to about 8 days old, so the window is filtered here too.
  Future<List<InboxRow>> loadRecent({DateTime? now}) async {
    final rows = await _client
        .from('notification_inbox')
        .select(
          'id, notification_type, title, body, quiet, reference_id, sender_id, created_at',
        )
        .eq('user_id', _uid!)
        .gte(
          'created_at',
          (now ?? DateTime.now()).toUtc().subtract(window).toIso8601String(),
        )
        .order('created_at', ascending: false)
        .limit(rowLimit);
    return rows.map(InboxRow.fromMap).toList();
  }

  /// One query for all [ids]. A sender whose profile is gone is simply absent.
  Future<Map<String, InboxSender>> loadSenders(List<String> ids) async {
    if (ids.isEmpty) return {};
    final rows = await _client
        .from('user_profiles')
        .select('id, avatar_id, avatar_border')
        .inFilter('id', ids);
    return {
      for (final r in rows)
        r['id'] as String: InboxSender(
          avatarId: r['avatar_id'] as String?,
          border: r['avatar_border'] as String?,
        ),
    };
  }

  /// Per account, on this device only. It holds the created_at of the newest
  /// row shown on the last visit, so it runs on the server's clock.
  Future<DateTime?> readLastSeen() async {
    final uid = _uid;
    if (uid == null) return null;
    final prefs = await SharedPreferences.getInstance();
    return DateTime.tryParse(prefs.getString(_key(uid)) ?? '');
  }

  Future<void> writeLastSeen(DateTime value) async {
    final uid = _uid;
    if (uid == null) return;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_key(uid), value.toUtc().toIso8601String());
  }

  static String _key(String uid) => 'notif_inbox_last_seen_$uid';
}
