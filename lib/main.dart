import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'home_screen.dart';
import 'signup_screen.dart';
import 'services/coach_max_service.dart';
import 'package:firebase_core/firebase_core.dart';
import 'services/notification_service.dart';
import 'dart:io';
import 'onboarding/splash_screen.dart';
import 'login_screen.dart';
import 'services/achievement_service.dart';
import 'dart:async';
import 'package:app_links/app_links.dart';
import 'services/invite_service.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await dotenv.load(fileName: '.env');
  if (Platform.isAndroid || Platform.isIOS) {
    await Firebase.initializeApp();
  }
  await Supabase.initialize(
    url: dotenv.env['SUPABASE_URL']!,
    anonKey: dotenv.env['SUPABASE_ANON_KEY']!,
  );
  runApp(const GymBuddyApp());
}

class GymBuddyApp extends StatelessWidget {
  const GymBuddyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Gym Buddy',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.blue),
        useMaterial3: true,
      ),
      home: const AuthWrapper(),
      debugShowCheckedModeBanner: false,
    );
  }
}

class AuthWrapper extends StatefulWidget {
  const AuthWrapper({super.key});

  @override
  State<AuthWrapper> createState() => _AuthWrapperState();
}

class _AuthWrapperState extends State<AuthWrapper> {
  final CoachMaxService _coachMaxService = CoachMaxService();
  final _appLinks = AppLinks();
  StreamSubscription<Uri>? _linkSubscription;

  bool _isInitializing = true;
  bool _hasCompletedOnboarding = false;

  @override
  void initState() {
    super.initState();
    _initializeApp();
    _initDeepLinks();
  }

  @override
  void dispose() {
    _linkSubscription?.cancel();
    super.dispose();
  }

  // ─── Deep link handling ────────────────────────────────────────────────────

  Future<void> _initDeepLinks() async {
    // Handle link that cold-launched the app (app was fully closed)
    try {
      final initialUri = await _appLinks.getInitialLink();
      if (initialUri != null) {
        _handleInviteLink(initialUri);
      }
    } catch (e) {
      if (kDebugMode) print('❌ Deep link initial: $e');
    }

    // Handle links while app is already running in background
    _linkSubscription = _appLinks.uriLinkStream.listen(
      _handleInviteLink,
      onError: (e) {
        if (kDebugMode) print('❌ Deep link stream: $e');
      },
    );
  }

  void _handleInviteLink(Uri uri) {
    final code = uri.queryParameters['code'];
    if (code != null && code.isNotEmpty) {
      if (kDebugMode) print('🔗 Invite code received via deep link: $code');
      unawaited(InviteService().storePendingInviteCode(code));
    }
  }

  // ─── App initialisation ────────────────────────────────────────────────────

  Future<void> _initializeApp() async {
    final user = Supabase.instance.client.auth.currentUser;
    if (user != null) {
      await NotificationService().initialize();
      final onboardingStatus = await _checkOnboardingStatus(user.id);
      if (onboardingStatus) {
        await _coachMaxService.scheduleCoachMaxCheckIn(user.id);
        unawaited(AchievementService().checkLoyaltyAchievements());
      }
      setState(() {
        _hasCompletedOnboarding = onboardingStatus;
        _isInitializing = false;
      });
    } else {
      setState(() => _isInitializing = false);
    }
  }

  Future<bool> _checkOnboardingStatus(String userId) async {
    try {
      final response = await Supabase.instance.client
          .from('user_profiles')
          .select('onboarding_completed')
          .eq('id', userId)
          .single();
      return response['onboarding_completed'] == true;
    } catch (e) {
      return false;
    }
  }

  // ─── Build ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    if (_isInitializing) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }

    final user = Supabase.instance.client.auth.currentUser;
    if (user == null) {
      return const SplashScreen();
    } else if (!_hasCompletedOnboarding) {
      Supabase.instance.client.auth.signOut();
      return const SplashScreen();
    } else {
      return const HomeScreen();
    }
  }
}