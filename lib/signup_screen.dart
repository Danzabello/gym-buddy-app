import 'package:gym_buddy_app/login_screen.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import 'onboarding/onboarding_theme.dart';
import 'onboarding/onboarding_basic_info_new.dart';
import 'onboarding/splash_screen.dart';
import 'theme/app_theme.dart';
import 'utils/input_validators.dart';

// Hosted on GitHub Pages from docs/ -- same origin as invite.html.
const String _kTermsUrl =
    'https://danzabello.github.io/gym-buddy-app/terms.html';
const String _kPrivacyUrl =
    'https://danzabello.github.io/gym-buddy-app/privacy-policy.html';


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
  bool _acceptTerms = false;

  String? _emailError;
  String? _passwordError;
  String? _confirmError;
  String? _generalError;

  // Held as fields (not built inline) so they can be disposed -- a
  // TapGestureRecognizer leaks if it outlives the widget without disposal.
  late final TapGestureRecognizer _termsTap;
  late final TapGestureRecognizer _privacyTap;

  @override
  void initState() {
    super.initState();
    _termsTap = TapGestureRecognizer()
      ..onTap = () => _openLegalPage(_kTermsUrl);
    _privacyTap = TapGestureRecognizer()
      ..onTap = () => _openLegalPage(_kPrivacyUrl);
  }

  @override
  void dispose() {
    _termsTap.dispose();
    _privacyTap.dispose();
    _emailCtrl.dispose();
    _passwordCtrl.dispose();
    _confirmCtrl.dispose();
    super.dispose();
  }

  /// Opens a legal page in the device browser. Failure surfaces as an inline
  /// message rather than an exception -- a dead link must never block signup.
  Future<void> _openLegalPage(String url) async {
    var launched = false;
    try {
      launched = await launchUrl(
        Uri.parse(url),
        mode: LaunchMode.externalApplication,
      );
    } catch (_) {
      launched = false;
    }
    if (!launched && mounted) {
      setState(() =>
          _generalError = 'Could not open that page. Please try again.');
    }
  }

  bool _validate() {
    final emailErr = InputValidators.email(_emailCtrl.text);
    final passErr = InputValidators.password(_passwordCtrl.text);
    final confirmErr = InputValidators.confirmPassword(
      _confirmCtrl.text,
      _passwordCtrl.text,
    );

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
      setState(() => _generalError =
          'Please accept the Terms of Service and Privacy Policy.');
      return;
    }

    // S4 audit fix: the early signUp()-then-signOut() probe that used to
    // live here created a real orphaned auth account on every attempt
    // (the existing orphan-cleanup logic in main.dart can't find these,
    // since it only runs for accounts with an active session, and this
    // probe always signs out immediately) AND let anyone enumerate
    // registered emails via the distinct "already registered" message.
    // The real signUp() call already lives in OnboardingBasicInfoNew's
    // _finish() (the actual last step) and handles the duplicate-email
    // case there -- no need to probe up front.
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
    final c = AppColors.of(context);
    final cs = Theme.of(context).colorScheme;
    return Scaffold(
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(24, 16, 24, 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Align(
                alignment: Alignment.centerLeft,
                child: ObBackButton(
                  onTap: () => Navigator.of(context).pushReplacement(
                    FadeSlideRoute(page: const SplashScreen()),
                  ),
                ),
              ),
              const SizedBox(height: 24),
              const ObHeading(
                eyebrow: true,
                title: 'Create your account',
                body: 'Takes a minute. Your buddy is next.',
              ),
              const SizedBox(height: 28),
              ObTextField(
                label: 'Email',
                hint: 'Enter your email',
                icon: Icons.email_outlined,
                controller: _emailCtrl,
                keyboardType: TextInputType.emailAddress,
                inputFormatters: InputFormatters.email,
                errorText: _emailError,
                onChanged: (_) => setState(() => _emailError = null),
              ),
              const SizedBox(height: 16),
              ObTextField(
                label: 'Password',
                hint: 'At least 8 characters',
                icon: Icons.lock_outline,
                controller: _passwordCtrl,
                obscureText: !_showPassword,
                inputFormatters: InputFormatters.password,
                errorText: _passwordError,
                onChanged: (_) => setState(() => _passwordError = null),
                suffixIcon: ObVisibilityButton(
                  shown: _showPassword,
                  showLabel: 'Show password',
                  hideLabel: 'Hide password',
                  onPressed: () => setState(() => _showPassword = !_showPassword),
                ),
              ),
              const SizedBox(height: 16),
              ObTextField(
                label: 'Confirm password',
                hint: 'Re-enter your password',
                icon: Icons.lock_outline,
                controller: _confirmCtrl,
                obscureText: !_showConfirm,
                inputFormatters: InputFormatters.password,
                errorText: _confirmError,
                onChanged: (_) => setState(() => _confirmError = null),
                suffixIcon: ObVisibilityButton(
                  shown: _showConfirm,
                  showLabel: 'Show confirmation password',
                  hideLabel: 'Hide confirmation password',
                  onPressed: () => setState(() => _showConfirm = !_showConfirm),
                ),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  SizedBox(
                    width: 48,
                    height: 48,
                    child: Checkbox(
                      value: _acceptTerms,
                      activeColor: cs.primary,
                      checkColor: Theme.of(context).scaffoldBackgroundColor,
                      side: BorderSide(color: c.info, width: 2),
                      onChanged: (v) => setState(() {
                        _acceptTerms = v ?? false;
                        _generalError = null;
                      }),
                    ),
                  ),
                  Expanded(
                    child: GestureDetector(
                      onTap: () => setState(() => _acceptTerms = !_acceptTerms),
                      child: Text.rich(
                        TextSpan(
                          style: TextStyle(fontSize: 14, color: cs.onSurface),
                          children: [
                            const TextSpan(text: 'I accept the '),
                            TextSpan(
                              text: 'Terms of Service',
                              style: TextStyle(
                                  color: cs.primary,
                                  fontWeight: FontWeight.w600,
                                  decoration: TextDecoration.underline),
                              recognizer: _termsTap,
                            ),
                            const TextSpan(text: ' and '),
                            TextSpan(
                              text: 'Privacy Policy',
                              style: TextStyle(
                                  color: cs.primary,
                                  fontWeight: FontWeight.w600,
                                  decoration: TextDecoration.underline),
                              recognizer: _privacyTap,
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
                ObErrorBanner(_generalError!),
              ],
              const SizedBox(height: 24),
              ObPrimaryButton(label: 'Sign up', onTap: _next),
              const SizedBox(height: 8),
              ObLinkButton(
                lead: 'Already have an account? ',
                action: 'Sign in',
                onTap: () => Navigator.of(context).pushAndRemoveUntil(
                  FadeSlideRoute(page: LoginScreen()),
                  (r) => false,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
