import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'home_screen.dart';
import 'services/auth_service.dart';
import 'services/coach_max_service.dart';
import 'package:firebase_core/firebase_core.dart';
import 'services/notification_service.dart';
import 'dart:io';
import 'onboarding/splash_screen.dart';
import 'services/achievement_service.dart';
import 'dart:async';
import 'package:firebase_crashlytics/firebase_crashlytics.dart';
import 'services/invite_service.dart';
import 'package:provider/provider.dart';
import 'theme/app_theme.dart';
import 'theme/accent_theme_provider.dart';
import 'package:gym_buddy_app/utils/debug_logger.dart';
import 'package:gym_buddy_app/utils/timezone_sync.dart';
import 'widgets/live_event_toast.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await dotenv.load(fileName: '.env');
  if (Platform.isAndroid || Platform.isIOS) {
    await Firebase.initializeApp();
    await FirebaseCrashlytics.instance.setCrashlyticsCollectionEnabled(!kDebugMode);
    FlutterError.onError = FirebaseCrashlytics.instance.recordFlutterFatalError;
    PlatformDispatcher.instance.onError = (error, stack) {
      FirebaseCrashlytics.instance.recordError(error, stack, fatal: true);
      return true;
    };
  }
  await Supabase.initialize(
    url: dotenv.env['SUPABASE_URL']!,
    anonKey: dotenv.env['SUPABASE_ANON_KEY']!,
  );
  InviteService.startListening();
  if (Platform.isAndroid) {
    unawaited(InviteService().readInstallReferrerOnce(InviteService.playReferrer));
  }
  runApp(const GymBuddyApp());
}

/// A startup read must not hold the splash forever. On timeout this reports a
/// non-fatal (the name only, no user data) and returns null, which every
/// caller already treats as "read failed".
Future<T?> _startupRead<T>(String name, Future<T> read, int seconds) async {
  try {
    return await read.timeout(Duration(seconds: seconds));
  } on TimeoutException catch (e, st) {
    if (Platform.isAndroid || Platform.isIOS) {
      unawaited(FirebaseCrashlytics.instance
          .recordError(e, st, reason: 'startup read timed out: $name'));
    }
    return null;
  }
}

class GymBuddyApp extends StatelessWidget {
  const GymBuddyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider(
      create: (_) => AccentThemeProvider(),
      child: Consumer<AccentThemeProvider>(
        builder: (context, accentProvider, _) {
          return MaterialApp(
            title: 'Gym Buddy',
            // Lets NotificationService reach an Overlay with no BuildContext,
            // so a foreground push can toast over whatever screen is showing.
            navigatorKey: appNavigatorKey,
            theme: AppTheme.fromAccent(accentProvider.palette),
            home: const AuthWrapper(),
            debugShowCheckedModeBanner: false,
          );
        },
      ),
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
  final AuthService _authService = AuthService();

  bool _isInitializing = true;
  bool _hasCompletedOnboarding = false;

  @override
  void initState() {
    super.initState();
    _initializeApp();
  }

  // ─── App initialisation ────────────────────────────────────────────────────

  Future<void> _initializeApp() async {
    final user = Supabase.instance.client.auth.currentUser;
    if (user != null) {
      unawaited(InviteService().retryPendingTeam(user.id));
      await _startupRead('notification init', NotificationService().initialize(), 10);
      final onboardingStatus = await _startupRead(
          'onboarding status', _authService.checkOnboardingStatus(user.id), 15);
      unawaited(InviteService().discardPendingIfOnboarded(onboardingStatus));
      if (onboardingStatus == true) {
        // Refresh the stored device timezone every launch (people travel /
        // swap devices) — feeds per-user "today" resolution server-side.
        unawaited(syncDeviceTimezone());
        await _startupRead('coach max schedule',
            _coachMaxService.scheduleCoachMaxCheckIn(user.id), 15);
        unawaited(AchievementService().checkLoyaltyAchievements());
      } else {
        // Not finished (false), or the read failed (null; DI-7: never treat a
        // failed read as orphaned). Either way Splash shows, and its Get
        // started resumes the flow at step 2. An unfinished row is never
        // deleted: a Join on the buddy step writes one early, possibly
        // already paired.
        if (kDebugMode && onboardingStatus == null) {
          debugLog('⚠️ Could not verify onboarding status; leaving account untouched');
        }
      }
      setState(() {
        _hasCompletedOnboarding = onboardingStatus == true;
        _isInitializing = false;
      });
    } else {
      setState(() => _isInitializing = false);
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
      return const SplashScreen();
    } else {
      return const HomeScreen();
    }
  }
}