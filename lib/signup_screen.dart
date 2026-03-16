import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'onboarding/onboarding_theme.dart';
import 'onboarding/onboarding_basic_info_new.dart';
import 'onboarding/splash_screen.dart';
import 'main.dart';

class SignUpScreen extends StatefulWidget {
  final List<Map<String, dynamic>> pendingInvites;
  const SignUpScreen({super.key, this.pendingInvites = const []});

  @override
  State<SignUpScreen> createState() => _SignUpScreenState();
}

class _SignUpScreenState extends State<SignUpScreen> {
  final _emailCtrl = TextEditingController();
  final _passwordCtrl = TextEditingController();
  final _confirmCtrl = TextEditingController();

  bool _showPassword = false;
  bool _showConfirm = false;
  bool _isLoading = false;
  bool _acceptTerms = false;

  String? _emailError;
  String? _passwordError;
  String? _confirmError;
  String? _generalError;

  @override
  void dispose() {
    _emailCtrl.dispose();
    _passwordCtrl.dispose();
    _confirmCtrl.dispose();
    super.dispose();
  }

  bool _validate() {
    String? emailErr, passErr, confirmErr;
    final email = _emailCtrl.text.trim();
    final pass = _passwordCtrl.text;

    if (email.isEmpty || !email.contains('@') || !email.contains('.')) {
      emailErr = 'Enter a valid email';
    }
    if (pass.isEmpty || pass.length < 6) {
      passErr = 'At least 6 characters';
    }
    if (_confirmCtrl.text != pass) {
      confirmErr = 'Passwords do not match';
    }

    setState(() {
      _emailError = emailErr;
      _passwordError = passErr;
      _confirmError = confirmErr;
      _generalError = null;
    });

    return emailErr == null && passErr == null && confirmErr == null;
  }

  Future<void> _next() async {
    if (!_validate()) return;
    if (!_acceptTerms) {
      setState(() => _generalError = 'Please accept the Terms of Service.');
      return;
    }

    // Check if email is already registered before entering the long onboarding flow
    setState(() => _isLoading = true);

    try {
      // Attempt signup just to check — we'll delete the session immediately
      final response = await Supabase.instance.client.auth.signUp(
        email: _emailCtrl.text.trim(),
        password: _passwordCtrl.text,
      );

      if (response.user != null) {
        // Email was free — sign back out immediately, account creation
        // happens properly at the end of onboarding (step 5)
        await Supabase.instance.client.auth.signOut();
      }
    } on AuthException catch (e) {
      setState(() => _isLoading = false);
      if (e.message.contains('User already registered') ||
          e.code == 'user_already_exists') {
        setState(() => _emailError = 'This email is already registered. Please sign in.');
      } else {
        setState(() => _generalError = 'Something went wrong. Please try again.');
      }
      return;
    } catch (e) {
      setState(() {
        _isLoading = false;
        _generalError = 'Something went wrong. Please try again.';
      });
      return;
    }

    setState(() => _isLoading = false);
    if (!mounted) return;

    // Email is free — proceed to onboarding
    Navigator.of(context).pushReplacement(
      FadeSlideRoute(
        page: OnboardingBasicInfoNew(
          pendingInvites: widget.pendingInvites,
          email: _emailCtrl.text.trim(),
          password: _passwordCtrl.text,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: Column(
        children: [
          // ── Gradient header ──────────────────────────────────────────
          Container(
            width: double.infinity,
            decoration: const BoxDecoration(
              gradient: kGradientDiag,
              borderRadius: BorderRadius.only(
                bottomLeft: Radius.circular(24),
                bottomRight: Radius.circular(24),
              ),
            ),
            child: Padding(
              padding: EdgeInsets.fromLTRB(
                  20, MediaQuery.of(context).padding.top + 12, 20, 28),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  GestureDetector(
                    onTap: () {
                      Navigator.of(context).pushReplacement(
                        FadeSlideRoute(page: const SplashScreen()),
                      );
                    },
                    child: Container(
                      width: 34,
                      height: 34,
                      decoration: BoxDecoration(
                        color: Colors.white.withOpacity(0.2),
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(Icons.arrow_back,
                          color: Colors.white, size: 17),
                    ),
                  ),
                  const SizedBox(height: 16),
                  const Text('Create your account',
                      style: TextStyle(
                          fontSize: 22,
                          fontWeight: FontWeight.w700,
                          color: Colors.white)),
                  const SizedBox(height: 6),
                  Text('Join the Gym Buddy community',
                      style: TextStyle(
                          fontSize: 14,
                          color: Colors.white.withOpacity(0.8))),
                ],
              ),
            ),
          ),

          // ── Form ────────────────────────────────────────────────────
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(24, 24, 24, 24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  ObTextField(
                    label: 'Email',
                    hint: 'Enter your email',
                    icon: Icons.email_outlined,
                    controller: _emailCtrl,
                    keyboardType: TextInputType.emailAddress,
                    errorText: _emailError,
                    onChanged: (_) => setState(() => _emailError = null),
                  ),
                  const SizedBox(height: 16),
                  ObTextField(
                    label: 'Password',
                    hint: 'At least 6 characters',
                    icon: Icons.lock_outline,
                    controller: _passwordCtrl,
                    obscureText: !_showPassword,
                    errorText: _passwordError,
                    onChanged: (_) => setState(() => _passwordError = null),
                    suffixIcon: IconButton(
                      icon: Icon(_showPassword
                          ? Icons.visibility_off
                          : Icons.visibility,
                          size: 20),
                      onPressed: () =>
                          setState(() => _showPassword = !_showPassword),
                    ),
                  ),
                  const SizedBox(height: 16),
                  ObTextField(
                    label: 'Confirm password',
                    hint: 'Re-enter your password',
                    icon: Icons.lock_outline,
                    controller: _confirmCtrl,
                    obscureText: !_showConfirm,
                    errorText: _confirmError,
                    onChanged: (_) => setState(() => _confirmError = null),
                    suffixIcon: IconButton(
                      icon: Icon(_showConfirm
                          ? Icons.visibility_off
                          : Icons.visibility,
                          size: 20),
                      onPressed: () =>
                          setState(() => _showConfirm = !_showConfirm),
                    ),
                  ),
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      Checkbox(
                        value: _acceptTerms,
                        activeColor: kObBlue,
                        onChanged: (v) => setState(() {
                          _acceptTerms = v ?? false;
                          _generalError = null;
                        }),
                      ),
                      Expanded(
                        child: GestureDetector(
                          onTap: () =>
                              setState(() => _acceptTerms = !_acceptTerms),
                          child: RichText(
                            text: const TextSpan(
                              style: TextStyle(
                                  fontSize: 13, color: Color(0xFF374151)),
                              children: [
                                TextSpan(text: 'I accept the '),
                                TextSpan(
                                  text: 'Terms of Service',
                                  style: TextStyle(
                                      color: kObBlue,
                                      fontWeight: FontWeight.w600),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                  if (_generalError != null) ...[
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
                          Icon(Icons.error_outline,
                              color: Colors.red[700], size: 18),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(_generalError!,
                                style: TextStyle(
                                    fontSize: 13, color: Colors.red[700])),
                          ),
                        ],
                      ),
                    ),
                  ],
                  const SizedBox(height: 24),
                  ObGradientButton(
                    label: 'Sign up',
                    isLoading: _isLoading,
                    onTap: _next,
                  ),
                  const SizedBox(height: 14),
                  Center(
                    child: GestureDetector(
                      onTap: () {
                        Navigator.of(context).pushAndRemoveUntil(
                          FadeSlideRoute(page: const LoginScreen()),
                          (r) => false,
                        );
                      },
                      child: RichText(
                        text: TextSpan(
                          style: TextStyle(
                              fontSize: 14, color: Colors.grey[600]),
                          children: const [
                            TextSpan(text: 'Already have an account? '),
                            TextSpan(
                              text: 'Sign in',
                              style: TextStyle(
                                  color: kObBlue,
                                  fontWeight: FontWeight.w600),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  const _Divider(),
                  const SizedBox(height: 16),
                  const _GoogleButton(),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _Divider extends StatelessWidget {
  const _Divider();
  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        const Expanded(child: Divider()),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: Text('or',
              style: TextStyle(fontSize: 13, color: Colors.grey[400])),
        ),
        const Expanded(child: Divider()),
      ],
    );
  }
}

class _GoogleButton extends StatelessWidget {
  const _GoogleButton();
  @override
  Widget build(BuildContext context) {
    return Opacity(
      opacity: 0.5,
      child: SizedBox(
        width: double.infinity,
        child: OutlinedButton.icon(
          onPressed: null,
          icon: const _GoogleLogo(),
          label: const Text('Continue with Google',
              style: TextStyle(fontSize: 15, color: Color(0xFF374151))),
          style: OutlinedButton.styleFrom(
            padding: const EdgeInsets.symmetric(vertical: 14),
            side: const BorderSide(color: Color(0xFFE2E8F0)),
            shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14)),
          ),
        ),
      ),
    );
  }
}

class _GoogleLogo extends StatelessWidget {
  const _GoogleLogo();
  @override
  Widget build(BuildContext context) {
    return CustomPaint(
        size: const Size(20, 20), painter: _GooglePainter());
  }
}

class _GooglePainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final p = Paint()..style = PaintingStyle.fill;
    final c = Offset(size.width / 2, size.height / 2);
    final r = size.width / 2;
    p.color = const Color(0xFFEA4335);
    canvas.drawArc(
        Rect.fromCircle(center: c, radius: r), -1.57, 3.14, true, p);
    p.color = const Color(0xFF34A853);
    canvas.drawArc(
        Rect.fromCircle(center: c, radius: r), 1.57, 3.14, true, p);
    p.color = const Color(0xFFFBBC05);
    canvas.drawArc(
        Rect.fromCircle(center: c, radius: r), 2.36, 1.57, true, p);
    p.color = const Color(0xFF4285F4);
    canvas.drawArc(
        Rect.fromCircle(center: c, radius: r), -1.57, -1.57, true, p);
    p.color = Colors.white;
    canvas.drawCircle(c, r * 0.6, p);
  }

  @override
  bool shouldRepaint(_) => false;
}