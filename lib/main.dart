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
import 'services/saved_copy.dart';
import 'services/startup_gate.dart';
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
  SavedCopy.start();
  if (Platform.isAndroid) {
    unawaited(InviteService().readInstallReferrerOnce(InviteService.playReferrer));
  }
  runApp(const GymBuddyApp());
}

/// A startup read must not hold the splash forever. On timeout this reports a
/// non-fatal (the name only, no user data) and returns null, which every
/// caller already treats as "read failed". Any other error does the same, so
/// an unawaited caller never leaks an unhandled exception.
Future<T?> _startupRead<T>(String name, Future<T> read, int seconds) async {
  try {
    return await read.timeout(Duration(seconds: seconds));
  } catch (e, st) {
    if (Platform.isAndroid || Platform.isIOS) {
      unawaited(FirebaseCrashlytics.instance.recordError(e, st,
          reason: e is TimeoutException
              ? 'startup read timed out: $name'
              : 'startup read failed: $name'));
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

  /// Work every signed-in launch does beside the status read. Not awaited:
  /// nothing the first screen shows depends on it.
  final Future<void> Function(String userId) onSignedIn;

  /// The state, plus the stored timezone from the same row (null if unknown).
  final Future<(OnboardingState, String?)> Function(String userId) onboardingStatus;

  /// The unfinished account's own row; null when it could not be read.
  final Future<OnboardingResume?> Function(String userId) loadResume;

  /// Launch work for a finished account.
  final Future<void> Function(String userId, String? storedTimezone) onCompleted;
  final WidgetBuilder home;

  /// Passed to the onboarding host: its "Not you?" sign-out and buddy step.
  final Future<void> Function() signOut;
  final BuddyDeps? buddyDeps;

  /// The saved owner id and whether [userId] was saved as onboarded. Null:
  /// nothing is saved, which is the behaviour before the saved copy.
  final Future<(String?, bool)> Function(String userId)? loadSaved;

  /// Saves (true) after a definite complete, or drops (false) after a
  /// definite not-onboarded. Never called for an unknown read.
  final Future<void> Function(String userId, bool onboarded)? saveOnboarded;

  /// Fires on a sign-out. Listened to only while Home stands in front of an
  /// unanswered read.
  final Stream<void> Function()? signedOutEvents;

  const AuthWrapperDeps({
    required this.userId,
    required this.onSignedIn,
    required this.onboardingStatus,
    required this.loadResume,
    required this.onCompleted,
    required this.home,
    required this.signOut,
    this.buddyDeps,
    this.loadSaved,
    this.saveOnboarded,
    this.signedOutEvents,
  });

  factory AuthWrapperDeps.live() {
    final auth = AuthService();
    return AuthWrapperDeps(
      userId: () => Supabase.instance.client.auth.currentUser?.id,
      onSignedIn: (id) async {
        unawaited(InviteService().retryPendingTeam(id));
        await NotificationService().initialize();
      },
      onboardingStatus: (_) => startupProfileStatus(),
      loadResume: (id) => loadOnboardingResume(ResumeReads.live(id)),
      onCompleted: (id, storedTimezone) async {
        // Refresh the stored device timezone (people travel / swap devices),
        // written only when it differs: feeds per-user "today" server-side.
        unawaited(syncDeviceTimezone(stored: storedTimezone));
        await _startupRead('coach max schedule',
            CoachMaxService().runDueCoachMaxCheckIn(id), 15);
        unawaited(AchievementService().checkLoyaltyAchievements());
      },
      home: (_) => const HomeScreen(),
      signOut: auth.signOut,
      loadSaved: (id) async => (await SavedCopy.owner(), await SavedCopy.onboarded(id)),
      saveOnboarded: (id, onboarded) =>
          onboarded ? SavedCopy.saveOnboarded(id) : SavedCopy.drop(id, 'onboarded'),
      signedOutEvents: () => Supabase.instance.client.auth.onAuthStateChange
          .where((s) => s.event == AuthChangeEvent.signedOut)
          .map((_) {}),
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

  /// The saved copy has been read (local storage, milliseconds), so the
  /// first decision can be made.
  bool _localLoaded = false;
  String? _savedOwner;
  bool _savedOnboarded = false;
  StartupReadResult _read = StartupReadResult.pending;
  StreamSubscription<void>? _signedOutSub;

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

  @override
  void dispose() {
    _signedOutSub?.cancel();
    super.dispose();
  }

  Future<void> _initializeApp() async {
    final userId = _deps.userId();
    if (userId == null) {
      setState(() => _localLoaded = true);
      return;
    }
    // Started together: the notification setup (permission check, token write)
    // no longer holds the status read.
    unawaited(_startupRead('notification init', _deps.onSignedIn(userId), 10));
    final saved = await _deps.loadSaved?.call(userId) ?? (null, false);
    if (!mounted) return;
    setState(() {
      _savedOwner = saved.$1;
      _savedOnboarded = saved.$2;
      _localLoaded = true;
    });
    // Home stands in front of the unanswered read (saved flag): a sign-out
    // meanwhile must still end on the normal auth flow.
    if (_screen() == StartupScreen.home) {
      _signedOutSub = _deps.signedOutEvents?.call().listen((_) {
        if (mounted) setState(() {});
      }, onError: (_) {});
    }
    final (state, storedTimezone) = await _startupRead(
            'onboarding status', _deps.onboardingStatus(userId), 15) ??
        (OnboardingState.unknown, null);
    unawaited(InviteService()
        .discardPendingIfOnboarded(state == OnboardingState.complete ? true : null));
    OnboardingResume? resume;
    if (state == OnboardingState.complete) {
      // Only a definite complete is saved, never an unknown.
      unawaited(_deps.saveOnboarded?.call(userId, true) ?? Future<void>.value());
      // Behind Home when the saved flag put it up first; before it otherwise.
      await _deps.onCompleted(userId, storedTimezone);
    } else if (state == OnboardingState.incomplete || state == OnboardingState.noProfile) {
      unawaited(_deps.saveOnboarded?.call(userId, false) ?? Future<void>.value());
      if (state == OnboardingState.incomplete) {
        // A failed read leaves null, which falls back to the splash below.
        resume = await _startupRead<OnboardingResume?>('onboarding resume', _deps.loadResume(userId), 15);
      }
    } else if (kDebugMode && state == OnboardingState.unknown) {
      // DI-7: a failed read is never treated as orphaned or unfinished.
      debugLog('⚠️ Could not verify onboarding status; leaving account untouched');
    }
    if (!mounted) return;
    unawaited(_signedOutSub?.cancel());
    _signedOutSub = null;
    setState(() {
      _state = state;
      _resume = resume;
      _read = switch (state) {
        OnboardingState.complete => StartupReadResult.complete,
        OnboardingState.noProfile ||
        OnboardingState.incomplete =>
          StartupReadResult.notOnboarded,
        OnboardingState.unknown => StartupReadResult.unknown,
      };
    });
  }

  StartupScreen _screen() => decideStartupScreen(
        sessionUserId: _deps.userId(),
        savedOwnerId: _savedOwner,
        savedOnboarded: _savedOnboarded,
        read: _read,
      );

  // ─── Build ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    const spinner = Scaffold(
      body: Center(child: CircularProgressIndicator()),
    );
    if (!_localLoaded) return spinner;

    final splash = SplashScreen(signedIn: () => _deps.userId() != null);
    return switch (_screen()) {
      StartupScreen.spinner => spinner,
      StartupScreen.splash => splash,
      StartupScreen.home => _deps.home(context),
      // Never finished: straight back into the flow. An unfinished row is
      // never deleted (a Join on the buddy step writes one early, possibly
      // already paired).
      StartupScreen.onboarding => switch (_state) {
          OnboardingState.noProfile => OnboardingHost(
              resume: true, signOut: _deps.signOut, buddyDeps: _deps.buddyDeps),
          OnboardingState.incomplete when _resume != null => OnboardingHost(
              resume: true,
              resumeData: _resume,
              signOut: _deps.signOut,
              buddyDeps: _deps.buddyDeps),
          // Status unknown (or the row could not be read): the splash, whose
          // Get started resumes the flow. A network blip never pushes anyone
          // into onboarding.
          _ => splash,
        },
    };
  }
}
