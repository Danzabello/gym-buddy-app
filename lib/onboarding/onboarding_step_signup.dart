import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../login_screen.dart';
import '../theme/app_theme.dart';
import '../utils/input_validators.dart';
import 'onboarding_account.dart';
import 'onboarding_host.dart';
import 'onboarding_max.dart';
import 'onboarding_theme.dart';

// Hosted on GitHub Pages from docs/ -- same origin as invite.html.
const String _kTermsUrl =
    'https://danzabello.github.io/gym-buddy-app/terms.html';
const String _kPrivacyUrl =
    'https://danzabello.github.io/gym-buddy-app/privacy-policy.html';

/// Step 1: email and password. Creates the auth user, so every later step
/// (including the username check) runs signed in.
class SignUpStep extends StatefulWidget {
  const SignUpStep({super.key});

  @override
  State<SignUpStep> createState() => _SignUpStepState();
}

class _SignUpStepState extends State<SignUpStep> {
  bool _showPassword = false;
  bool _showConfirm = false;
  bool _busy = false;

  String? _emailError;
  String? _passwordError;
  String? _confirmError;
  String? _generalError;

  // Held as fields so they can be disposed -- a TapGestureRecognizer leaks if
  // it outlives the widget without disposal.
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
    super.dispose();
  }

  /// Failure surfaces as an inline message rather than an exception -- a dead
  /// link must never block signup.
  Future<void> _openLegalPage(String url) async {
    var launched = false;
    try {
      launched = await launchUrl(Uri.parse(url),
          mode: LaunchMode.externalApplication);
    } catch (_) {
      launched = false;
    }
    if (!launched && mounted) {
      setState(() =>
          _generalError = 'Could not open that page. Please try again.');
    }
  }

  bool _validate() {
    final draft = OnbScope.of(context).draft;
    final emailErr = InputValidators.email(draft.email.text);
    final passErr = InputValidators.password(draft.password.text);
    // The confirmation is a typo check only; the server hashes the password.
    final confirmErr = InputValidators.confirmPassword(
        draft.confirm.text, draft.password.text);
    setState(() {
      _emailError = emailErr;
      _passwordError = passErr;
      _confirmError = confirmErr;
      _generalError = null;
    });
    return emailErr == null && passErr == null && confirmErr == null;
  }

  Future<void> _create() async {
    if (_busy || !_validate()) return;
    final host = OnbScope.of(context);
    setState(() => _busy = true);
    final error = await createOnboardingAuthUser(
      email: host.draft.email.text.trim(),
      password: host.draft.password.text,
    );
    if (!mounted) return;
    setState(() {
      _busy = false;
      _generalError = error;
    });
    if (error == null) host.next();
  }

  @override
  Widget build(BuildContext context) {
    final host = OnbScope.of(context);
    final draft = host.draft;
    final c = AppColors.of(context);
    final cs = Theme.of(context).colorScheme;
    return OnbStepFrame(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          MaxStrip(
            anchor: host.anchors[MaxSpot.signUp]!,
            spot: MaxSpot.signUp,
            text: "Hi, I'm Max. I'll show you around.",
            bubbleVisible: host.bubbleVisible,
          ),
          const SizedBox(height: 24),
          Semantics(
            header: true,
            child: Text('Your streak starts with a buddy',
                style: TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.w800,
                    height: 1.2,
                    color: cs.onSurface)),
          ),
          const SizedBox(height: 6),
          Text('Check in together. Keep it alive.',
              style: TextStyle(fontSize: 15, color: c.subtleText)),
          const SizedBox(height: 24),
          ObTextField(
            label: 'Email',
            hint: 'Enter your email',
            icon: Icons.email_outlined,
            controller: draft.email,
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
            controller: draft.password,
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
            controller: draft.confirm,
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
          if (_generalError != null) ...[
            const SizedBox(height: 12),
            ObErrorBanner(_generalError!),
          ],
          const SizedBox(height: 24),
          ObPrimaryButton(
              label: 'Create account', isLoading: _busy, onTap: _create),
          const SizedBox(height: 14),
          Center(
            child: Text.rich(
              TextSpan(
                style: TextStyle(fontSize: 12, color: c.subtleText),
                children: [
                  const TextSpan(text: 'By continuing you agree to the '),
                  TextSpan(
                      text: 'Terms',
                      style: TextStyle(
                          color: cs.primary,
                          decoration: TextDecoration.underline),
                      recognizer: _termsTap),
                  const TextSpan(text: ' and '),
                  TextSpan(
                      text: 'Privacy Policy',
                      style: TextStyle(
                          color: cs.primary,
                          decoration: TextDecoration.underline),
                      recognizer: _privacyTap),
                  const TextSpan(text: '.'),
                ],
              ),
              textAlign: TextAlign.center,
            ),
          ),
          const SizedBox(height: 4),
          ObLinkButton(
            lead: 'Already have an account? ',
            action: 'Log in',
            onTap: () => Navigator.of(context).pushAndRemoveUntil(
              FadeSlideRoute(page: LoginScreen()),
              (r) => false,
            ),
          ),
        ],
      ),
    );
  }
}
