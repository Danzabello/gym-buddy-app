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
import 'onboarding/onboarding_host.dart';
import 'onboarding/onboarding_resume.dart';
import 'onboarding/onboarding_step_buddy.dart' show BuddyDeps;
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

/// What AuthWrapper needs from the outside world, so tests can hand it fakes.
class AuthWrapperDeps {
  final String? Function() userId;

  /// Work every signed-in launch does before the status read.
  final Future<void> Function(String userId) onSignedIn;
  final Future<OnboardingState> Function(String userId) onboardingState;

  /// The unfinished account's own row; null when it could not be read.
  final Future<OnboardingResume?> Function(String userId) loadResume;

  /// Launch work for a finished account.
  final Future<void> Function(String userId) onCompleted;
  final WidgetBuilder home;

  /// Passed to the onboarding host: its "Not you?" sign-out and buddy step.
  final Future<void> Function() signOut;
  final BuddyDeps? buddyDeps;

  const AuthWrapperDeps({
    required this.userId,
    required this.onSignedIn,
    required this.onboardingState,
    required this.loadResume,
    required this.onCompleted,
    required this.home,
    required this.signOut,
    this.buddyDeps,
  });

  factory AuthWrapperDeps.live() {
    final auth = AuthService();
    return AuthWrapperDeps(
      userId: () => Supabase.instance.client.auth.currentUser?.id,
      onSignedIn: (id) async {
        unawaited(InviteService().retryPendingTeam(id));
        await _startupRead('notification init', NotificationService().initialize(), 10);
      },
      onboardingState: auth.onboardingState,
      loadResume: (id) => loadOnboardingResume(ResumeReads.live(id)),
      onCompleted: (id) async {
        // Refresh the stored device timezone every launch (people travel /
        // swap devices) — feeds per-user "today" resolution server-side.
        unawaited(syncDeviceTimezone());
        await _startupRead('coach max schedule',
            CoachMaxService().scheduleCoachMaxCheckIn(id), 15);
        unawaited(AchievementService().checkLoyaltyAchievements());
      },
      home: (_) => const HomeScreen(),
      signOut: auth.signOut,
    );
  }
}

class AuthWrapper extends StatefulWidget {
  final AuthWrapperDeps? deps;
  const AuthWrapper({super.key, this.deps});

  @override
  State<AuthWrapper> createState() => _AuthWrapperState();
}

class _AuthWrapperState extends State<AuthWrapper> {
  late final AuthWrapperDeps _deps = widget.deps ?? AuthWrapperDeps.live();

  bool _isInitializing = true;

  /// Signed out, or signed in with the status unknown (read failed or timed
  /// out): the splash.
  OnboardingState _state = OnboardingState.unknown;
  OnboardingResume? _resume;

  @override
  void initState() {
    super.initState();
    _initializeApp();
  }

  // ─── App initialisation ────────────────────────────────────────────────────

  Future<void> _initializeApp() async {
    final userId = _deps.userId();
    if (userId == null) {
      setState(() => _isInitializing = false);
      return;
    }
    await _deps.onSignedIn(userId);
    final state = await _startupRead(
            'onboarding status', _deps.onboardingState(userId), 15) ??
        OnboardingState.unknown;
    unawaited(InviteService()
        .discardPendingIfOnboarded(state == OnboardingState.complete ? true : null));
    OnboardingResume? resume;
    if (state == OnboardingState.complete) {
      await _deps.onCompleted(userId);
    } else if (state == OnboardingState.incomplete) {
      // A failed read leaves null, which falls back to the splash below.
      resume = await _startupRead<OnboardingResume?>('onboarding resume', _deps.loadResume(userId), 15);
    } else if (kDebugMode && state == OnboardingState.unknown) {
      // DI-7: a failed read is never treated as orphaned or unfinished.
      debugLog('⚠️ Could not verify onboarding status; leaving account untouched');
    }
    if (!mounted) return;
    setState(() {
      _state = state;
      _resume = resume;
      _isInitializing = false;
    });
  }

  // ─── Build ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    if (_isInitializing) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }

    final splash = SplashScreen(signedIn: () => _deps.userId() != null);
    if (_deps.userId() == null) return splash;
    return switch (_state) {
      OnboardingState.complete => _deps.home(context),
      // Never finished: straight back into the flow. An unfinished row is
      // never deleted (a Join on the buddy step writes one early, possibly
      // already paired).
      OnboardingState.noProfile => OnboardingHost(
          resume: true, signOut: _deps.signOut, buddyDeps: _deps.buddyDeps),
      OnboardingState.incomplete when _resume != null => OnboardingHost(
          resume: true,
          resumeData: _resume,
          signOut: _deps.signOut,
          buddyDeps: _deps.buddyDeps),
      // Status unknown (or the row could not be read): the splash, whose Get
      // started resumes the flow. A network blip never pushes anyone into
      // onboarding.
      _ => splash,
    };
  }
}
