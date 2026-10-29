import 'package:flutter/material.dart';
import 'onboarding/onboarding_host.dart';

/// Entry point from the intro and the log-in screen: sign-up is step 1 of the
/// onboarding host.
class SignUpScreen extends StatelessWidget {
  const SignUpScreen({super.key});

  @override
  Widget build(BuildContext context) => const OnboardingHost();
}
