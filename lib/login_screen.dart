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
import 'utils/input_validators.dart';
import 'package:flutter/services.dart';
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
      _errorMessage = '🔒 Too many attempts. Try again in ${_lockoutSecondsRemaining}s.';
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
          backgroundColor: const Color(0xFF10B981),
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
        final onboardingComplete = await _checkOnboardingStatus(user.id);
        if (!mounted) return;
        setState(() => _isLoading = false);

        if (!onboardingComplete) {
          // Orphaned account — clean it up and send back to splash
          try {
            await Supabase.instance.client.rpc('delete_own_account');
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
            const SnackBar(
              content: Text('Previous signup was incomplete. Please register again.'),
              backgroundColor: Colors.orange,
              behavior: SnackBarBehavior.floating,
            ),
          );
          return;
        }

        await _coachMaxService.scheduleCoachMaxCheckIn(user.id);
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
    _errorMessage = '🔒 Too many attempts. Try again in ${_lockoutSecondsRemaining}s.';
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
          _errorMessage = '🔒 Too many attempts. Try again in ${_lockoutSecondsRemaining}s.';
        }
      });
    });
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
    return Scaffold(
      backgroundColor: Colors.white,
      resizeToAvoidBottomInset: true,
      body: Container(
        decoration: const BoxDecoration(gradient: kGradientDiag),
        child: FadeTransition(
          opacity: _fade,
          child: SlideTransition(
            position: _slide,
            child: Column(
              children: [
                // ── Top — logo + title ────
                SizedBox(
                  height: MediaQuery.of(context).size.height * 0.38,
                  child: Stack(
                    children: [
                      Positioned(
                        top: MediaQuery.of(context).padding.top + 8,
                        left: 20,
                        child: GestureDetector(
                          onTap: () => Navigator.of(context).pushAndRemoveUntil(
                            FadeSlideRoute(page: const SplashScreen()),
                            (r) => false,
                          ),
                          child: Container(
                            width: 36,
                            height: 36,
                            decoration: BoxDecoration(
                              color: Colors.white.withOpacity(0.2),
                              shape: BoxShape.circle,
                            ),
                            child: const Icon(Icons.arrow_back, color: Colors.white, size: 18),
                          ),
                        ),
                      ),
                      Center(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Container(
                              width: 72,
                              height: 72,
                              decoration: BoxDecoration(
                                color: Colors.white.withOpacity(0.2),
                                borderRadius: BorderRadius.circular(20),
                              ),
                              child: const Center(
                                child: _DumbbellIcon(size: 38, color: Colors.white),
                              ),
                            ),
                            const SizedBox(height: 16),
                            const Text(
                              'Welcome back',
                              style: TextStyle(
                                fontSize: 28,
                                fontWeight: FontWeight.w700,
                                color: Colors.white,
                                letterSpacing: -0.3,
                              ),
                            ),
                            const SizedBox(height: 6),
                            Text(
                              'Sign in to continue your streak',
                              style: TextStyle(
                                fontSize: 14,
                                color: Colors.white.withOpacity(0.75),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),

                // ── Bottom — white card ────
                Expanded(
                  child: Container(
                    decoration: const BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.only(
                        topLeft: Radius.circular(28),
                        topRight: Radius.circular(28),
                      ),
                    ),
                    padding: EdgeInsets.fromLTRB(
                      24, 28, 24,
                      MediaQuery.of(context).padding.bottom + 24,
                    ),
                    child: SingleChildScrollView(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          _Label('Email'),
                          const SizedBox(height: 8),
                          // Email field
                          _Field(
                            controller: _emailCtrl,
                            hint: 'Enter your email',
                            icon: Icons.email_outlined,
                            keyboardType: TextInputType.emailAddress,
                            inputFormatters: InputFormatters.email,   // 🔒 no spaces, max 254
                          ),
                          const SizedBox(height: 16),
                          _Label('Password'),
                          const SizedBox(height: 8),
                          // Password field
                          _Field(
                            controller: _passwordCtrl,
                            hint: 'Enter your password',
                            icon: Icons.lock_outline,
                            obscureText: !_showPassword,
                            inputFormatters: InputFormatters.password, // 🔒 max 128
                            suffixIcon: IconButton(
                              icon: Icon(
                                _showPassword ? Icons.visibility_off : Icons.visibility,
                                size: 20,
                                color: Colors.grey[500],
                              ),
                              onPressed: () => setState(() => _showPassword = !_showPassword),
                            ),
                            onSubmitted: (_) => _login(),
                          ),
                          const SizedBox(height: 8),
                          Align(
                            alignment: Alignment.centerRight,
                            child: GestureDetector(
                              onTap: _forgotPassword,
                              child: const Text(
                                'Forgot password?',
                                style: TextStyle(
                                  fontSize: 13,
                                  color: kObBlue,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                            ),
                          ),
                          if (_errorMessage != null) ...[
                            const SizedBox(height: 12),
                            Container(
                              padding: const EdgeInsets.all(12),
                              decoration: BoxDecoration(
                                color: Colors.red[50],
                                borderRadius: BorderRadius.circular(10),
                                border: Border.all(color: Colors.red[200]!),
                              ),
                              child: Row(
                                children: [
                                  Icon(Icons.error_outline, color: Colors.red[700], size: 16),
                                  const SizedBox(width: 8),
                                  Expanded(
                                    child: Text(
                                      _errorMessage!,
                                      style: TextStyle(fontSize: 13, color: Colors.red[700]),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                          const SizedBox(height: 24),
                          SizedBox(
                            width: double.infinity,
                            child: Container(
                              decoration: BoxDecoration(
                                gradient: kGradient,
                                borderRadius: BorderRadius.circular(14),
                                boxShadow: [
                                  BoxShadow(
                                    color: kObBlue.withOpacity(0.3),
                                    blurRadius: 12,
                                    offset: const Offset(0, 4),
                                  ),
                                ],
                              ),
                              child: ElevatedButton(
                                onPressed: _isLoading || _isLockedOut ? null : _login,
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: Colors.transparent,
                                  shadowColor: Colors.transparent,
                                  padding: const EdgeInsets.symmetric(vertical: 16),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(14),
                                  ),
                                ),
                                child: _isLoading
                                    ? const SizedBox(
                                        height: 20,
                                        width: 20,
                                        child: CircularProgressIndicator(
                                          color: Colors.white,
                                          strokeWidth: 2,
                                        ),
                                      )
                                    : const Text(
                                        'Sign in',
                                        style: TextStyle(
                                          fontSize: 16,
                                          fontWeight: FontWeight.w700,
                                          color: Colors.white,
                                        ),
                                      ),
                              ),
                            ),
                          ),
                          const SizedBox(height: 16),
                          Center(
                            child: GestureDetector(
                              onTap: () => Navigator.of(context).pushAndRemoveUntil(
                                FadeSlideRoute(page: const SignUpScreen()),
                                (r) => false,
                              ),
                              child: RichText(
                                text: TextSpan(
                                  style: TextStyle(fontSize: 14, color: Colors.grey[600]),
                                  children: const [
                                    TextSpan(text: "Don't have an account? "),
                                    TextSpan(
                                      text: 'Sign up',
                                      style: TextStyle(
                                        color: kObBlue,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ── Shared field widgets ───────────────────────────────────────────────────
class _Label extends StatelessWidget {
  final String text;
  const _Label(this.text);

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: const TextStyle(
        fontSize: 14,
        fontWeight: FontWeight.w600,
        color: Color(0xFF374151),
      ),
    );
  }
}

class _Field extends StatelessWidget {
  final TextEditingController controller;
  final String hint;
  final IconData icon;
  final bool obscureText;
  final TextInputType? keyboardType;
  final Widget? suffixIcon;
  final void Function(String)? onSubmitted;
  final List<TextInputFormatter>? inputFormatters;

  const _Field({
    required this.controller,
    required this.hint,
    required this.icon,
    this.obscureText = false,
    this.keyboardType,
    this.suffixIcon,
    this.onSubmitted,
    this.inputFormatters,
  });

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      obscureText: obscureText,
      keyboardType: keyboardType,
      onSubmitted: onSubmitted,
      inputFormatters: inputFormatters,
      style: const TextStyle(color: Color(0xFF111827)),  // ← ADD THIS
      buildCounter: (_, {required currentLength, required isFocused, maxLength}) => null,
      decoration: InputDecoration(
        hintText: hint,
        hintStyle: TextStyle(color: Colors.grey[400]),
        prefixIcon: Icon(icon, color: const Color(0xFF6B7280), size: 20),
        suffixIcon: suffixIcon,
        filled: true,
        fillColor: const Color(0xFFF8FAFC),
        border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: const BorderSide(color: Color(0xFFE2E8F0))),
        enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: const BorderSide(color: Color(0xFFE2E8F0))),
        focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: const BorderSide(color: kObBlue, width: 2)),
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      ),
    );
  }
}

// ── Dumbbell icon (copied from splash) ────────────────────────────────────
class _DumbbellIcon extends StatelessWidget {
  final double size;
  final Color color;
  const _DumbbellIcon({required this.size, required this.color});

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      size: Size(size, size),
      painter: _DumbbellPainter(color),
    );
  }
}

class _DumbbellPainter extends CustomPainter {
  final Color color;
  _DumbbellPainter(this.color);

  @override
  void paint(Canvas canvas, Size size) {
    final p = Paint()
      ..color = color
      ..style = PaintingStyle.fill;
    final w = size.width;
    final h = size.height;
    final barH = h * 0.18;
    final barY = (h - barH) / 2;
    canvas.drawRRect(
        RRect.fromLTRBR(w * 0.12, barY, w * 0.88, barY + barH,
            Radius.circular(barH / 2)),
        p);
    for (final x in [w * 0.04, w * 0.72]) {
      canvas.drawRRect(
          RRect.fromLTRBR(
              x, h * 0.22, x + w * 0.18, h * 0.78, Radius.circular(4)),
          p);
    }
  }

  @override
  bool shouldRepaint(_) => false;
}