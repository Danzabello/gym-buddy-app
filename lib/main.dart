import 'package:flutter/material.dart';
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
import 'dart:async' show unawaited;

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
  bool _isInitializing = true;
  bool _hasCompletedOnboarding = false;

  @override
  void initState() {
    super.initState();
    _initializeApp();
  }

  Future<void> _initializeApp() async {
    final user = Supabase.instance.client.auth.currentUser;
    if (user != null) {
      await NotificationService().initialize();
      final onboardingStatus = await _checkOnboardingStatus(user.id);
      if (onboardingStatus) {
        await _coachMaxService.scheduleCoachMaxCheckIn(user.id);
        // 🏆 Loyalty achievements — check passively on every login
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