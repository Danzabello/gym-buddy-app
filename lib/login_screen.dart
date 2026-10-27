// ═══════════════════════════════════════════════════════════════════════════
// LOGIN SCREEN — matches splash screen aesthetic
// Drop-in replacement for the LoginScreen class in main.dart
// ═══════════════════════════════════════════════════════════════════════════

import 'dart:async';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'services/auth_service.dart';
import 'services/coach_max_service.dart';
import 'services/notification_service.dart';
import 'home_screen.dart';
import 'signup_screen.dart';
import 'onboarding/onboarding_theme.dart';
import 'onboarding/splash_screen.dart';
import 'theme/app_theme.dart';
import 'utils/input_validators.dart';
import 'utils/timezone_sync.dart';
import 'package:flutter/foundation.dart';


class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen>
    with SingleTickerProviderStateMixin {
  final _emailCtrl = TextEditingController();
  final _passwordCtrl = TextEditingController();
  final _authService = AuthService();
  final _coachMaxService = CoachMaxService();

  late final AnimationController _animCtrl;
  late final Animation<double> _fade;
  late final Animation<Offset> _slide;

  bool _showPassword = false;
  bool _isLoading = false;
  int _failedAttempts = 0;
  bool _isLockedOut = false;
  String? _errorMessage;
  Timer? _lockoutTimer;
  int _lockoutSecondsRemaining = 0;

  // S5 audit fix (follow-up): the lockout used to live purely in this
  // State object, so navigating away and back created a fresh
  // instance and silently wiped it (confirmed live during testing).
  // Persisting the lockout deadline means normal in-app navigation no
  // longer bypasses it. Still UX-only, not real security -- clearing
  // app data or calling the auth API directly still bypasses this
  // entirely. Real protection must come from Supabase Auth's
  // server-side rate limiting.
  static const _kLockoutUntilKey = 'login_lockout_until_ms';

  @override
  void initState() {
    super.initState();
    _animCtrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 800));
    _fade = CurvedAnimation(parent: _animCtrl, curve: Curves.easeOut);
    _slide = Tween<Offset>(
            begin: const Offset(0, 0.08), end: Offset.zero)
        .animate(CurvedAnimation(parent: _animCtrl, curve: Curves.easeOut));
    _animCtrl.forward();
    _restoreLockoutState();
  }

  Future<void> _restoreLockoutState() async {
    final prefs = await SharedPreferences.getInstance();
    final lockoutUntilMs = prefs.getInt(_kLockoutUntilKey);
    if (lockoutUntilMs == null) return;

    final remainingMs = lockoutUntilMs - DateTime.now().millisecondsSinceEpoch;
    if (remainingMs <= 0) {
      await prefs.remove(_kLockoutUntilKey);
      return;
    }

    if (!mounted) return;
    setState(() {
      _isLockedOut = true;
      _lockoutSecondsRemaining = (remainingMs / 1000).ceil();
      _errorMessage = 'Too many attempts. Try again in ${_lockoutSecondsRemaining}s.';
    });
    _runLockoutTimer();
  }

  @override
  void dispose() {
    _animCtrl.dispose();
    _emailCtrl.dispose();
    _passwordCtrl.dispose();
    _lockoutTimer?.cancel();
    super.dispose();
  }

  Future<void> _forgotPassword() async {
    final email = _emailCtrl.text.trim();
    final emailErr = InputValidators.email(email);
    if (emailErr != null) {
      setState(() => _errorMessage = 'Enter a valid email above first, then tap Forgot password.');
      return;
    }
    try {
      await Supabase.instance.client.auth.resetPasswordForEmail(email);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Password reset email sent to $email'),
          backgroundColor: AppColors.of(context).success,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        ),
      );
    } catch (e) {
      setState(() => _errorMessage = 'Could not send reset email. Please try again.');
    }
  }

  Future<void> _login() async {
    if (_isLockedOut) return;

    // 🔒 Validate before touching the auth service
    final emailErr = InputValidators.email(_emailCtrl.text);
    final passErr = InputValidators.password(_passwordCtrl.text);
    if (emailErr != null || passErr != null) {
      setState(() => _errorMessage = emailErr ?? passErr);
      return;
    }

    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    final error = await _authService.signIn(
      email: _emailCtrl.text.trim(),
      password: _passwordCtrl.text,
    );

    if (error == null) {
      _failedAttempts = 0;
      final user = Supabase.instance.client.auth.currentUser;
      if (user != null) {
        await NotificationService().initialize();
        final onboardingComplete = await _authService.checkOnboardingStatus(user.id);
        if (!mounted) return;
        setState(() => _isLoading = false);

        if (onboardingComplete == null) {
          // DI-7 audit fix: the read failed (timeout, network error, etc.)
          // — status is unknown, NOT confirmed orphaned. Fail safe: do not
          // delete the account, just let the user retry.
          setState(() => _errorMessage = 'Could not verify your account. Please try again.');
          return;
        }

        if (!onboardingComplete) {
          // Confirmed via a successful read (not just assumed from a
          // failed one) — clean it up and send back to splash.
          // Token first: the delete-account failure below is swallowed, and in
          // that path the auth user survives with its token row intact.
          await NotificationService().removeToken();
          try {
            await Supabase.instance.client.functions.invoke('delete-account');
          } catch (e) {
            if (kDebugMode) debugPrint('⚠️ cleanup: $e');
          } finally {
            await Supabase.instance.client.auth.signOut();
          }
          if (!mounted) return;
          Navigator.of(context).pushAndRemoveUntil(
            FadeSlideRoute(page: const SplashScreen()),
            (r) => false,
          );
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: const Text('Previous signup was incomplete. Please register again.'),
              backgroundColor: AppColors.of(context).warn,
              behavior: SnackBarBehavior.floating,
            ),
          );
          return;
        }

        unawaited(syncDeviceTimezone());
        await _coachMaxService.scheduleCoachMaxCheckIn(user.id);
        if (!mounted) return;
        Navigator.of(context).pushAndRemoveUntil(
          FadeSlideRoute(page: const HomeScreen()),
          (r) => false,
        );
      }
    } else {
      setState(() {
        _failedAttempts++;
        _isLoading = false;
        if (_failedAttempts >= 5) {
          // S5 audit fix: this is a client-side UX deterrent only, NOT
          // a real security control -- it resets on app restart and
          // can be bypassed entirely by calling the auth service
          // directly. Real brute-force protection must come from
          // Supabase Auth's server-side rate limiting (verify/configure
          // in the Supabase dashboard -- not fixable from this file).
          // A time-based cooldown with no bypass instructions is still
          // strictly better than the old message, which literally told
          // the user (and any attacker) to restart the app to clear it.
          _isLockedOut = true;
          _startLockoutCountdown();
        } else {
          final remaining = 5 - _failedAttempts;
          _errorMessage = _failedAttempts >= 4
              ? 'Incorrect credentials. 1 attempt remaining.'
              : 'Incorrect email or password. $remaining attempts left.';
        }
      });
    }
  }

  void _startLockoutCountdown() {
    _lockoutSecondsRemaining = 60;
    _errorMessage = 'Too many attempts. Try again in ${_lockoutSecondsRemaining}s.';
    _persistLockoutUntil(DateTime.now().add(const Duration(seconds: 60)));
    _runLockoutTimer();
  }

  Future<void> _persistLockoutUntil(DateTime until) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_kLockoutUntilKey, until.millisecondsSinceEpoch);
  }

  Future<void> _clearPersistedLockout() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_kLockoutUntilKey);
  }

  void _runLockoutTimer() {
    _lockoutTimer?.cancel();
    _lockoutTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) {
        timer.cancel();
        return;
      }
      setState(() {
        _lockoutSecondsRemaining--;
        if (_lockoutSecondsRemaining <= 0) {
          _isLockedOut = false;
          _failedAttempts = 0;
          _errorMessage = null;
          timer.cancel();
          _clearPersistedLockout();
        } else {
          _errorMessage = 'Too many attempts. Try again in ${_lockoutSecondsRemaining}s.';
        }
      });
    });
  }

  @override
  Widget build(BuildContext context) {
    final reduceMotion = MediaQuery.disableAnimationsOf(context);
    final content = SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(24, 16, 24, 24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Align(
              alignment: Alignment.centerLeft,
              child: ObBackButton(
                onTap: () => Navigator.of(context).pushAndRemoveUntil(
                  FadeSlideRoute(page: const SplashScreen()),
                  (r) => false,
                ),
              ),
            ),
            const SizedBox(height: 24),
            const ObHeading(
              eyebrow: true,
              title: 'Welcome back',
              body: 'Sign in to keep your streak going.',
            ),
            const SizedBox(height: 28),
            ObTextField(
              label: 'Email',
              hint: 'Enter your email',
              icon: Icons.email_outlined,
              controller: _emailCtrl,
              keyboardType: TextInputType.emailAddress,
              inputFormatters: InputFormatters.email,
            ),
            const SizedBox(height: 16),
            ObTextField(
              label: 'Password',
              hint: 'Enter your password',
              icon: Icons.lock_outline,
              controller: _passwordCtrl,
              obscureText: !_showPassword,
              inputFormatters: InputFormatters.password,
              onSubmitted: (_) => _login(),
              suffixIcon: ObVisibilityButton(
                shown: _showPassword,
                showLabel: 'Show password',
                hideLabel: 'Hide password',
                onPressed: () => setState(() => _showPassword = !_showPassword),
              ),
            ),
            Align(
              alignment: Alignment.centerRight,
              child: TextButton(
                onPressed: _forgotPassword,
                style: TextButton.styleFrom(minimumSize: const Size(48, 48)),
                child: Text('Forgot password?',
                    style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: Theme.of(context).colorScheme.primary)),
              ),
            ),
            if (_errorMessage != null) ...[
              const SizedBox(height: 4),
              ObErrorBanner(_errorMessage!),
            ],
            const SizedBox(height: 20),
            ObPrimaryButton(
              label: 'Sign in',
              isLoading: _isLoading,
              onTap: _isLockedOut ? null : _login,
            ),
            const SizedBox(height: 8),
            ObLinkButton(
              lead: 'New here? ',
              action: 'Create an account',
              onTap: () => Navigator.of(context).pushAndRemoveUntil(
                FadeSlideRoute(page: const SignUpScreen()),
                (r) => false,
              ),
            ),
          ],
        ),
      ),
    );
    return Scaffold(
      resizeToAvoidBottomInset: true,
      body: reduceMotion
          ? content
          : FadeTransition(
              opacity: _fade,
              child: SlideTransition(position: _slide, child: content),
            ),
    );
  }
}
