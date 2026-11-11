import 'dart:io' show Platform;

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';

import '../services/auth_service.dart';
import '../theme/app_theme.dart';
import 'onboarding_theme.dart';

/// The "or" divider, the "Continue with Google" button and its own error
/// banner, shared by the log-in screen and the sign-up step.
///
/// A cancelled picker does nothing at all. A failure shows the approved
/// message. [onSignedIn] runs once Supabase has a session and answers whether
/// the screen carried on; false shows the same message.
class GoogleSignInSection extends StatefulWidget {
  final Future<bool> Function() onSignedIn;

  /// The sign-in attempt; null uses [AuthService.signInWithGoogle]. For tests.
  final Future<GoogleSignInResult> Function()? signIn;

  /// Whether to show at all; null means Android only (the one platform with a
  /// Google client configured).
  final bool? show;

  const GoogleSignInSection(
      {super.key, required this.onSignedIn, this.signIn, this.show});

  @override
  State<GoogleSignInSection> createState() => _GoogleSignInSectionState();
}

class _GoogleSignInSectionState extends State<GoogleSignInSection> {
  bool _busy = false;
  String? _error;

  Future<void> _tap() async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    final result = await (widget.signIn ?? AuthService().signInWithGoogle)();
    var ok = result == GoogleSignInResult.success;
    if (ok) ok = await widget.onSignedIn();
    if (!mounted) return;
    setState(() {
      _busy = false;
      if (result != GoogleSignInResult.cancelled && !ok) {
        _error = kGoogleSignInErrorMessage;
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    if (!(widget.show ?? (!kIsWeb && Platform.isAndroid))) {
      return const SizedBox.shrink();
    }
    final c = AppColors.of(context);
    final cs = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SizedBox(height: 20),
        Row(children: [
          Expanded(child: Divider(color: c.divider, height: 1)),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Text('or',
                style: TextStyle(fontSize: 14, color: c.subtleText)),
          ),
          Expanded(child: Divider(color: c.divider, height: 1)),
        ]),
        const SizedBox(height: 20),
        if (_error != null) ...[
          ObErrorBanner(_error!),
          const SizedBox(height: 12),
        ],
        OutlinedButton(
          onPressed: _busy ? null : _tap,
          style: OutlinedButton.styleFrom(
            minimumSize: const Size.fromHeight(56),
            foregroundColor: cs.onSurface,
            side: BorderSide(color: c.info, width: 1.5),
            shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(18)),
          ),
          child: _busy
              ? SizedBox(
                  width: 22,
                  height: 22,
                  child: CircularProgressIndicator(
                      color: cs.onSurface, strokeWidth: 2.5))
              : const Text('Continue with Google',
                  style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700)),
        ),
      ],
    );
  }
}
