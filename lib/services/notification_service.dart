import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:gym_buddy_app/utils/debug_logger.dart';
import '../widgets/avatars/animated_bear.dart';
import '../widgets/live_event_toast.dart';
import '../widgets/user_avatar.dart';

// ── Push payload (data-only pushes from send-notification) ──────────────────

/// One push as send-notification's data message carries it. Every field is a
/// string; missing ones are ''.
class PushPayload {
  final String title, body, type, referenceId, kind, color, channel, tag;
  final String avatarId, avatarBorder, ringHex, senderName, streak, style;

  const PushPayload({
    required this.title,
    required this.body,
    this.type = '',
    this.referenceId = '',
    this.kind = '',
    this.color = '',
    this.channel = '',
    this.tag = '',
    this.avatarId = '',
    this.avatarBorder = '',
    this.ringHex = '',
    this.senderName = '',
    this.streak = '',
    this.style = '',
  });

  /// Null when there is nothing to show (no title): a notification-mode push
  /// the system already drew, or a malformed one.
  static PushPayload? fromData(Map<String, dynamic> d) {
    String s(String k) => (d[k] ?? '').toString();
    if (s('title').isEmpty) return null;
    return PushPayload(
      title: s('title'),
      body: s('body'),
      type: s('type'),
      referenceId: s('reference_id'),
      kind: s('kind'),
      color: s('color'),
      channel: s('channel'),
      tag: s('tag'),
      avatarId: s('avatar_id'),
      avatarBorder: s('avatar_border'),
      ringHex: s('ring_hex'),
      senderName: s('sender_name'),
      streak: s('streak'),
      style: s('style'),
    );
  }

  bool get hasSender => senderName.isNotEmpty || avatarId.isNotEmpty;
}

/// Notification accent per kind. The server sends `color` too; this is the
/// fallback when it doesn't. Raw hex on purpose (owner-approved 2026-10-08):
/// these colours go to the Android system tray, outside the app theme, so
/// AppColors can't supply them. All six live in this one map.
const Map<String, Color> kindColors = {
  'orange': Color(0xFFEA580C), // your move
  'lavender': Color(0xFFA99BF5), // people
  'emerald': Color(0xFF50C878), // done
  'amber': Color(0xFFFBBF24), // running out of time
  'red': Color(0xFFF87171), // ended
  'grey': Color(0xFFB9CFC3), // info
};

/// Ring when the sender has no Ring Color equipped.
const Color kDefaultRingColor = Color(0xFF50C878);

Color? parseHexColor(String? hex) {
  final m = RegExp(r'^#([0-9A-Fa-f]{6})$').firstMatch(hex ?? '');
  return m == null ? null : Color(0xFF000000 | int.parse(m.group(1)!, radix: 16));
}

Color colorForPush(PushPayload p) =>
    parseHexColor(p.color) ?? kindColors[p.kind] ?? kindColors['grey']!;

const String kLegacyChannelId = 'gym_buddy_high_importance';

/// The app's channels. Vibration and sound are fixed once a channel exists
/// on a device, so they are set here and never changed in place.
final List<AndroidNotificationChannel> kPushChannels = [
  const AndroidNotificationChannel(kLegacyChannelId, 'Gym Buddy Notifications',
      description: 'Streak alerts, buddy check-ins, and workout reminders',
      importance: Importance.high),
  AndroidNotificationChannel('gym_buddy_handshake', 'Workouts with a buddy',
      description: "Time to start, your buddy is here, nudges",
      importance: Importance.high,
      vibrationPattern: Int64List.fromList([0, 150, 120, 150])), // two short
  AndroidNotificationChannel('gym_buddy_invites', 'Workout invites',
      description: 'Invites and their answers',
      importance: Importance.high,
      vibrationPattern: Int64List.fromList([0, 250])), // one
  AndroidNotificationChannel('gym_buddy_streaks', 'Streaks',
      description: 'Check-ins, milestones and streak warnings',
      importance: Importance.defaultImportance,
      playSound: false,
      vibrationPattern: Int64List.fromList([0, 700])), // one long, no sound
  AndroidNotificationChannel('gym_buddy_friends', 'Friends',
      description: 'Friend requests',
      importance: Importance.high,
      vibrationPattern: Int64List.fromList([0, 250])),
  AndroidNotificationChannel('gym_buddy_coach_max', 'Coach Max',
      description: 'Coach Max check-ins',
      importance: Importance.defaultImportance,
      vibrationPattern: Int64List.fromList([0, 250])),
];

AndroidNotificationChannel channelFor(String? id) =>
    kPushChannels.firstWhere((c) => c.id == id, orElse: () => kPushChannels.first);

/// Group a push is a child of: its channel, except that invites split into
/// still-pending ones ('gym_buddy_invites') and answered ones (..._done).
String groupKeyFor(PushPayload p) {
  final channel = channelFor(p.channel).id;
  final pending = p.type == 'invite_received' || p.type == 'invite_rescheduled';
  return channel == 'gym_buddy_invites' && !pending ? 'gym_buddy_invites_done' : channel;
}

String summaryLabelFor(String group) {
  switch (group) {
    case 'gym_buddy_invites':
      return 'invites';
    case 'gym_buddy_invites_done':
      return 'invite updates';
    case 'gym_buddy_handshake':
      return 'workout updates';
    case 'gym_buddy_streaks':
      return 'streak updates';
    case 'gym_buddy_friends':
      return 'friend updates';
    case 'gym_buddy_coach_max':
      return 'messages';
  }
  return 'updates';
}

/// Home tab a tapped push opens: 0 Workout Schedule, 1 Friends, 2 Dashboard.
int? tabForType(String? type) {
  switch (type) {
    case 'invite_received':
    case 'invite_accepted':
    case 'invite_declined':
    case 'invite_expired':
    case 'invite_rescheduled':
    case 'workout_cancelled':
    case 'time_to_start':
    case 'buddy_tapped_first':
    case 'started':
    case 'nudge':
    case 'cant_make_it':
    case 'buddy_left':
    case 'buddy_finished':
    case 'still_going':
    case 'before_auto':
    case 'workout_overtime':
    case 'workout_invite':
    case 'workout_accepted':
    case 'workout_declined':
      return 0;
    case 'friend_request':
    case 'friend_accepted':
      return 1;
    case 'buddy_checked_in':
    case 'buddy_nudge':
    case 'streak_milestone':
    case 'streak_broken':
    case 'streak_danger':
    case 'coach_max_motivational':
      return 2;
  }
  return null;
}

// ── Avatar bitmap for the large icon ────────────────────────────────────────

/// Same fill as the avatar circles on the dashboard (Emerald Ink clay surface).
const Color _avatarFill = Color(0xFF1D4A35);

/// The sender's avatar as the app draws it (bear painter, else the emoji
/// glyph) in a ring of [ringHex] (default emerald; thicker for 'bold').
/// Cached on disk per avatar + border + ring.
Future<Uint8List> renderAvatarPng(String? avatarId, String? border, String? ringHex,
    {int size = 192, bool useCache = true}) async {
  final ring = parseHexColor(ringHex) ?? kDefaultRingColor;
  final key = '${avatarId ?? 'none'}_${border ?? 'simple'}_${ring.toARGB32().toRadixString(16)}_$size';
  File? cached;
  if (useCache) {
    try {
      cached = File('${Directory.systemTemp.path}/push_avatar_$key.png');
      if (await cached.exists()) return await cached.readAsBytes();
    } catch (_) {
      cached = null;
    }
  }

  final s = size.toDouble();
  final center = Offset(s / 2, s / 2);
  final stroke = s * (border == 'bold' ? 0.10 : 0.06);
  final recorder = ui.PictureRecorder();
  final canvas = Canvas(recorder);
  canvas.drawCircle(center, s / 2, Paint()..color = _avatarFill);
  canvas.save();
  canvas.clipPath(Path()..addOval(Rect.fromCircle(center: center, radius: s / 2 - stroke)));
  final inner = s - 2 * stroke;
  if (avatarId == 'bear') {
    final art = inner * 0.86; // same share as avatarArt
    canvas.translate((s - art) / 2, (s - art) / 2);
    paintStillBear(canvas, Size.square(art));
  } else {
    final tp = TextPainter(
      text: TextSpan(
          text: UserAvatar.avatars[avatarId] ?? UserAvatar.avatars['lion'],
          style: TextStyle(fontSize: inner * 0.6)),
      textDirection: TextDirection.ltr,
    )..layout();
    tp.paint(canvas, center - Offset(tp.width / 2, tp.height / 2));
  }
  canvas.restore();
  canvas.drawCircle(
      center,
      s / 2 - stroke / 2,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = stroke
        ..color = ring);

  final image = await recorder.endRecording().toImage(size, size);
  final png = (await image.toByteData(format: ui.ImageByteFormat.png))!.buffer.asUint8List();
  try {
    await cached?.writeAsBytes(png, flush: true);
  } catch (_) {}
  return png;
}

// ── Background handler ──────────────────────────────────────────────────────

@pragma('vm:entry-point')
Future<void> _firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  await Firebase.initializeApp();
  final push = PushPayload.fromData(message.data);
  if (push == null) return; // notification message: the system already showed it
  await NotificationService.showPush(push);
}

class NotificationService {
  static final NotificationService _instance = NotificationService._internal();
  factory NotificationService() => _instance;
  NotificationService._internal();

  FirebaseMessaging? _fcm;
  static final FlutterLocalNotificationsPlugin _localNotifications =
      FlutterLocalNotificationsPlugin();
  static bool _localReady = false;
  final SupabaseClient _supabase = Supabase.instance.client;

  /// A tapped push asks HomeScreen for this tab; HomeScreen clears it.
  static final ValueNotifier<int?> tabRequest = ValueNotifier<int?>(null);

  static const String _summaryPrefix = 'summary_';

  Future<void> initialize() async {
    debugLog('🚀 NotificationService.initialize() STARTING');

    if (!Platform.isAndroid && !Platform.isIOS) {
      debugLog('⏭️ Skipping notifications on non-mobile platform');
      return;
    }

    _fcm = FirebaseMessaging.instance;

    try {
      FirebaseMessaging.onBackgroundMessage(_firebaseMessagingBackgroundHandler);

      final settings = await _fcm?.requestPermission(
        alert: true,
        badge: true,
        sound: true,
        provisional: false,
      );

      if (kDebugMode) {
        debugLog('🔔 Notification permission: ${settings?.authorizationStatus}');
      }

      if (settings?.authorizationStatus == AuthorizationStatus.denied) {
        debugLog('❌ Notifications denied by user');
        // Still try to save existing token even if denied
        await _saveTokenToSupabase();
        return;
      }

      await _setupLocalNotifications();
      await _saveTokenToSupabase();

      _fcm?.onTokenRefresh.listen((newToken) {
        _saveTokenToSupabase();
      });

      FirebaseMessaging.onMessage.listen(_handleForegroundMessage);
      FirebaseMessaging.onMessageOpenedApp.listen(_handleNotificationTap);

      // Cold start from a tap: a system-drawn push, or one this app drew.
      final initial = await _fcm?.getInitialMessage();
      if (initial != null) _handleNotificationTap(initial);
      final launch = await _localNotifications.getNotificationAppLaunchDetails();
      if (launch?.didNotificationLaunchApp == true) {
        _routePayload(launch!.notificationResponse?.payload);
      }

      debugLog('✅ NotificationService initialized!');
    } catch (e) {
      debugLog('❌ NotificationService error: $e');
    }
  }

  /// Plugin init + channels, idempotent. Runs in the main isolate and again
  /// in the background isolate (each has its own plugin state).
  static Future<void> _ensureLocal() async {
    if (_localReady) return;
    final android = _localNotifications
        .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>();
    for (final c in kPushChannels) {
      await android?.createNotificationChannel(c);
    }
    await _localNotifications.initialize(
      const InitializationSettings(
          android: AndroidInitializationSettings('ic_stat_gym_buddy')),
      onDidReceiveNotificationResponse: (r) => _routePayload(r.payload),
    );
    _localReady = true;
  }

  Future<void> _setupLocalNotifications() async {
    await _ensureLocal();
    await _fcm?.setForegroundNotificationPresentationOptions(
      alert: true,
      badge: true,
      sound: true,
    );
  }

  /// Draws one data-only push. Always shows something: if the avatar fails
  /// or is slow, the same notification goes out without it.
  static Future<void> showPush(PushPayload p) async {
    await _ensureLocal();
    final channel = channelFor(p.channel);

    Uint8List? avatar;
    if (p.hasSender) {
      try {
        avatar = await renderAvatarPng(p.avatarId, p.avatarBorder, p.ringHex)
            .timeout(const Duration(seconds: 3));
      } catch (e) {
        debugLog('⚠️ push avatar failed, showing without it: $e');
      }
    }

    // Spike: MessagingStyle puts the sender (avatar) at the left of the card.
    final StyleInformation style = p.style == 'messaging' && avatar != null
        ? MessagingStyleInformation(
            Person(name: p.senderName, icon: ByteArrayAndroidIcon(avatar)),
            conversationTitle: p.title,
            messages: [
              Message(p.body, DateTime.now(),
                  Person(name: p.title, icon: ByteArrayAndroidIcon(avatar))),
            ],
          )
        : BigTextStyleInformation(p.body);

    final pendingInvite = _isPendingInvite(p.type);
    final group = groupKeyFor(p);
    final details = AndroidNotificationDetails(
      channel.id,
      channel.name,
      channelDescription: channel.description,
      importance: channel.importance,
      priority: channel.importance == Importance.high ? Priority.high : Priority.defaultPriority,
      icon: 'ic_stat_gym_buddy',
      color: colorForPush(p),
      largeIcon: avatar == null || p.style == 'messaging' ? null : ByteArrayAndroidBitmap(avatar),
      styleInformation: style,
      tag: p.tag.isEmpty ? null : p.tag,
      // Always a child of a group, even alone, so it gets the compact grouped
      // look (avatar on the left). See _syncSummary for the summary side.
      groupKey: group,
    );
    final payload = jsonEncode({'type': p.type, 'reference_id': p.referenceId});
    // With a tag, (tag, id) is the identity: a new push with the same tag
    // replaces the old one instead of stacking.
    final id = p.tag.isEmpty ? DateTime.now().millisecondsSinceEpoch ~/ 1000 : 1;
    await _localNotifications.show(id, p.title, p.body, NotificationDetails(android: details),
        payload: payload);

    // A cancelled workout takes its pending invite out of the tray.
    final cancelledInviteTag = p.type == 'workout_cancelled' && p.referenceId.isNotEmpty
        ? 'invite_${p.referenceId}'
        : null;
    if (cancelledInviteTag != null) {
      await _localNotifications.cancel(1, tag: cancelledInviteTag);
    }

    // Groups whose children may have changed: this push's own, and for an
    // invite answer / cancel the pending-invites group it just left.
    const pendingGroup = 'gym_buddy_invites';
    final leaving = cancelledInviteTag ?? (p.tag.isEmpty ? null : p.tag);
    await _syncSummary(group, leavingTag: group == pendingGroup ? null : leaving);
    if (!pendingInvite && (channel.id == pendingGroup || cancelledInviteTag != null)) {
      await _syncSummary(pendingGroup, leavingTag: leaving);
    }
  }

  static bool _isPendingInvite(String type) =>
      type == 'invite_received' || type == 'invite_rescheduled';

  /// One summary per group, posted while the group has children and
  /// cancelled when the last one leaves (no ghost summary). Android shows a
  /// lone child on its own and the summary only once there are two. Pending
  /// invites are a group of their own, so "N invites" counts exactly the
  /// invites still waiting.
  static Future<void> _syncSummary(String group, {String? leavingTag}) async {
    try {
      final android = _localNotifications
          .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>();
      final active = await android?.getActiveNotifications() ?? const [];
      // Android gives no payload for active notifications, but it does carry
      // the group key. leavingTag: being replaced or cancelled right now, the
      // system may not have dropped it yet.
      final children = active
          .where((n) =>
              n.groupKey == group &&
              !(n.tag ?? '').startsWith(_summaryPrefix) &&
              n.tag != leavingTag)
          .toList();
      final summaryTag = '$_summaryPrefix$group';
      if (children.isEmpty) {
        await _localNotifications.cancel(2, tag: summaryTag);
        return;
      }
      final channel = channelFor(group.replaceAll('_done', ''));
      final label = summaryLabelFor(group);
      await _localNotifications.show(
        2,
        '${children.length} $label',
        children.map((n) => n.title ?? '').join(', '),
        NotificationDetails(
          android: AndroidNotificationDetails(
            channel.id,
            channel.name,
            icon: 'ic_stat_gym_buddy',
            color: kindColors['grey'],
            tag: summaryTag,
            groupKey: group,
            setAsGroupSummary: true,
            groupAlertBehavior: GroupAlertBehavior.children, // the summary itself never alerts
            onlyAlertOnce: true,
            playSound: false,
            enableVibration: false,
            styleInformation: InboxStyleInformation(
              [for (final n in children) '${n.title ?? ''} ${n.body ?? ''}'],
              summaryText: '${children.length} $label',
            ),
          ),
        ),
        payload: jsonEncode({'type': group == 'gym_buddy_invites' ? 'invite_received' : ''}),
      );
    } catch (e) {
      debugLog('⚠️ summary failed: $e');
    }
  }

  static void _routePayload(String? payload) {
    if (payload == null || payload.isEmpty) return;
    try {
      final type = (jsonDecode(payload) as Map<String, dynamic>)['type'] as String?;
      final tab = tabForType(type);
      if (tab != null) tabRequest.value = tab;
    } catch (_) {}
  }

  Future<void> _saveTokenToSupabase() async {
    try {
      final userId = _supabase.auth.currentUser?.id;
      if (userId == null) return;

      final token = await _fcm?.getToken();
      if (token == null) return;

      // Server-authoritative: register_device_token releases this token from
      // any other account before claiming it for the caller. The client cannot
      // do that itself — RLS scopes every write to auth.uid() = user_id, so a
      // previous owner's row is unreachable from here. device_tokens is now
      // UNIQUE (token), so one handset maps to exactly one account.
      await _supabase.rpc('register_device_token', params: {
        'p_token': token,
        'p_platform': 'android',
      });

      debugLog('✅ FCM token registered to Supabase');
    } catch (e) {
      debugLog('❌ Error saving token: $e');
    }
  }

  Future<void> removeToken() async {
    try {
      final userId = _supabase.auth.currentUser?.id;
      if (userId == null) return;

      final token = await _fcm?.getToken();
      if (token == null) return;

      await _supabase
          .from('device_tokens')
          .delete()
          .eq('user_id', userId)
          .eq('token', token);

      await _fcm?.deleteToken();
      debugLog('✅ FCM token removed');
    } catch (e) {
      debugLog('❌ Error removing token: $e');
    }
  }

  /// The app is already on screen, so a system-tray popup is redundant — show
  /// an in-app toast in the navigator overlay instead, on whatever screen the
  /// user is on. No category filtering here: send-notification has already
  /// checked the user's settings before the push was ever sent.
  Future<void> _handleForegroundMessage(RemoteMessage message) async {
    final notification = message.notification;
    // Data-only pushes carry their text in data.
    final title = notification?.title ?? message.data['title'] as String?;
    final body = notification?.body ?? message.data['body'] as String?;
    debugLog('🔔 Foreground message: $title');
    if (title == null || title.isEmpty) return;

    final type = message.data['type'] as String?;

    // A buddy check-in fires this push AND the dashboard's realtime banner off
    // the same row insert. When that banner is visibly handling it, stand down
    // rather than stacking a second one.
    if (type == 'buddy_checked_in' && LiveEventToast.dashboardOwnsCheckIns) {
      debugLog('⏭️ Skipping toast — dashboard banner owns buddy_checked_in');
      return;
    }

    LiveEventToast.show(
      title: title,
      subtitle: body,
      icon: LiveEventToast.iconForType(type),
    );
  }

  void _handleNotificationTap(RemoteMessage message) {
    debugLog('🔔 Notification tapped: ${message.data['type']}');
    final tab = tabForType(message.data['type'] as String?);
    if (tab != null) tabRequest.value = tab;
  }

  Future<Map<String, dynamic>> getSettings() async {
    try {
      final userId = _supabase.auth.currentUser?.id;
      if (userId == null) return _defaultSettings();

      final result = await _supabase
          .from('notification_settings')
          .select()
          .eq('user_id', userId)
          .maybeSingle();

      return result ?? _defaultSettings();
    } catch (e) {
      return _defaultSettings();
    }
  }

  Future<void> updateSettings(Map<String, dynamic> settings) async {
    try {
      final userId = _supabase.auth.currentUser?.id;
      if (userId == null) return;

      await _supabase.from('notification_settings').upsert({
        'user_id': userId,
        ...settings,
        'updated_at': DateTime.now().toIso8601String(),
      });

      debugLog('✅ Notification settings updated');
    } catch (e) {
      debugLog('❌ Error updating settings: $e');
    }
  }

  Future<bool> checkOsPermission() async {
    if (!Platform.isAndroid && !Platform.isIOS) return true;
    final fcm = FirebaseMessaging.instance;
    final settings = await fcm.getNotificationSettings();
    return settings.authorizationStatus == AuthorizationStatus.authorized ||
        settings.authorizationStatus == AuthorizationStatus.provisional;
  }

  Map<String, dynamic> _defaultSettings() => {
        'notif_social': true,
        'notif_workouts': true,
        'notif_streaks': true,
        'notif_coach_max': true,
        'quiet_hours_enabled': true,
        'quiet_hours_start': 23,
        'quiet_hours_end': 7,
        'live_checkin_banner': true,
      };
}
