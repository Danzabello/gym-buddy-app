import 'dart:io';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:gym_buddy_app/utils/debug_logger.dart';

// Handle background messages (must be top-level function)
@pragma('vm:entry-point')
Future<void> _firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  await Firebase.initializeApp();
  if (kDebugMode) debugLog('🔔 Background message: ${message.notification?.title}');
}

class NotificationService {
  static final NotificationService _instance = NotificationService._internal();
  factory NotificationService() => _instance;
  NotificationService._internal();

  FirebaseMessaging? _fcm;
  final FlutterLocalNotificationsPlugin _localNotifications =
      FlutterLocalNotificationsPlugin();
  final SupabaseClient _supabase = Supabase.instance.client;

  static const AndroidNotificationChannel _channel = AndroidNotificationChannel(
    'gym_buddy_high_importance',
    'Gym Buddy Notifications',
    description: 'Streak alerts, buddy check-ins, and workout reminders',
    importance: Importance.high,
  );

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

      debugLog('✅ NotificationService initialized!');
    } catch (e) {
      debugLog('❌ NotificationService error: $e');
    }
  }

  Future<void> _setupLocalNotifications() async {
    final androidPlugin = _localNotifications
        .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>();
    await androidPlugin?.createNotificationChannel(_channel);

    const androidSettings = AndroidInitializationSettings('@mipmap/ic_launcher');
    const initSettings = InitializationSettings(android: androidSettings);

    await _localNotifications.initialize(
      initSettings,
      onDidReceiveNotificationResponse: (details) {
        debugLog('🔔 Notification tapped: ${details.payload}');
      },
    );

    await _fcm?.setForegroundNotificationPresentationOptions(
      alert: true,
      badge: true,
      sound: true,
    );
  }

  Future<void> _saveTokenToSupabase() async {
    try {
      final userId = _supabase.auth.currentUser?.id;
      if (userId == null) return;

      final token = await _fcm?.getToken();
      if (token == null) return;


      await _supabase.from('device_tokens').upsert({
        'user_id': userId,
        'token': token,
        'platform': 'android',
        'updated_at': DateTime.now().toIso8601String(),
      }, onConflict: 'user_id, token');

      debugLog('✅ FCM token saved to Supabase');
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

  Future<void> _handleForegroundMessage(RemoteMessage message) async {
    debugLog('🔔 Foreground message: ${message.notification?.title}');

    final notification = message.notification;
    if (notification == null) return;

    await _localNotifications.show(
      notification.hashCode,
      notification.title,
      notification.body,
      NotificationDetails(
        android: AndroidNotificationDetails(
          _channel.id,
          _channel.name,
          channelDescription: _channel.description,
          importance: Importance.high,
          priority: Priority.high,
          icon: '@mipmap/ic_launcher',
        ),
      ),
      payload: message.data['type'],
    );
  }

  void _handleNotificationTap(RemoteMessage message) {
    debugLog('🔔 Notification tapped: ${message.data['type']}');
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
      };
}