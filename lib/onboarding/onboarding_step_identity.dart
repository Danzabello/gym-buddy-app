import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../theme/app_theme.dart';
import '../utils/input_validators.dart';
import '../widgets/user_avatar.dart';
import 'onboarding_draft.dart';
import 'onboarding_host.dart';
import 'onboarding_max.dart';
import 'onboarding_theme.dart';

/// Step 4: display name, age and username, with a live preview card.
class IdentityStep extends StatefulWidget {
  const IdentityStep({super.key});

  @override
  State<IdentityStep> createState() => _IdentityStepState();
}

class _IdentityStepState extends State<IdentityStep> {
  bool _isChecking = false;
  bool _isAvailable = false;
  String? _usernameError;
  String? _nameError;
  String? _ageError;

  @override
  void initState() {
    super.initState();
    final username = OnbScope.read(context).draft.username.text;
    if (username.isNotEmpty) _check(username);
  }

  String? _formatError(String username) {
    if (username.isEmpty) return 'Username is required';
    if (username.length < 3) return 'At least 3 characters';
    if (username.length > 20) return '20 characters maximum';
    if (!RegExp(r'^[a-zA-Z0-9_]+$').hasMatch(username)) {
      return 'Letters, numbers, and underscores only';
    }
    if (username.startsWith('_') || username.endsWith('_')) {
      return 'Cannot start or end with underscore';
    }
    return null;
  }

  Future<void> _check(String username) async {
    final fmtErr = _formatError(username);
    if (fmtErr != null) {
      setState(() {
        _usernameError = fmtErr;
        _isAvailable = false;
      });
      return;
    }
    setState(() {
      _isChecking = true;
      _usernameError = null;
      _isAvailable = false;
    });
    try {
      final res = await Supabase.instance.client
          .from('user_profiles')
          .select('id')
          .eq('username', username.toLowerCase())
          .maybeSingle();
      if (mounted) {
        setState(() {
          _isChecking = false;
          // The user's own row (written early by a Join on step 5, then
          // resumed or reached with Back) does not make the name taken.
          if (res != null &&
              res['id'] != Supabase.instance.client.auth.currentUser?.id) {
            _usernameError = 'Username already taken';
            _isAvailable = false;
          } else {
            _isAvailable = true;
          }
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _isChecking = false;
          _usernameError = 'Error checking username';
        });
      }
    }
  }

  void _next() {
    final host = OnbScope.of(context);
    final draft = host.draft;
    final nameErr = InputValidators.displayName(draft.name.text);
    final ageErr = InputValidators.age(draft.age.text);
    setState(() {
      _nameError = nameErr;
      _ageError = ageErr;
      if (!_isAvailable) {
        _usernameError = draft.username.text.isEmpty
            ? 'Choose a username'
            : _usernameError;
      }
    });
    if (nameErr != null || ageErr != null || !_isAvailable) return;
    host.next();
  }

  Widget _suffix() {
    final c = AppColors.of(context);
    if (_isChecking) {
      return Padding(
        padding: const EdgeInsets.all(14),
        child: SizedBox(
            width: 20,
            height: 20,
            child: CircularProgressIndicator(
                strokeWidth: 2, color: Theme.of(context).colorScheme.primary)),
      );
    }
    if (_isAvailable) {
      return Padding(
        padding: const EdgeInsets.only(right: 12),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.check_circle, color: c.success, size: 20),
            const SizedBox(width: 4),
            Text('Available',
                style: TextStyle(
                    fontSize: 14, fontWeight: FontWeight.w600, color: c.success)),
          ],
        ),
      );
    }
    if (_usernameError != null) {
      return Icon(Icons.error_outline, color: c.danger, size: 20);
    }
    return const SizedBox.shrink();
  }

  @override
  Widget build(BuildContext context) {
    final host = OnbScope.of(context);
    final draft = host.draft;
    final c = AppColors.of(context);
    final cs = Theme.of(context).colorScheme;
    return OnbStepFrame(
      footer: ObPrimaryButton(label: 'Continue', onTap: _next),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          MaxStrip(
            anchor: host.anchors[MaxSpot.identity]!,
            spot: MaxSpot.identity,
            text: 'Now, what should I call you?',
            bubbleVisible: host.bubbleVisible,
          ),
          const SizedBox(height: 20),
          Semantics(
            header: true,
            child: Text('Your identity',
                style: TextStyle(
                    fontSize: 30, fontWeight: FontWeight.w800, color: cs.onSurface)),
          ),
          const SizedBox(height: 6),
          Text('Your buddy will see this name.',
              style: TextStyle(fontSize: 16, color: c.subtleText)),
          const SizedBox(height: 22),
          ObTextField(
            label: 'Display name',
            hint: 'What should we call you?',
            icon: Icons.person_outline,
            controller: draft.name,
            inputFormatters: InputFormatters.displayName,
            errorText: _nameError,
            onChanged: (_) {
              if (_nameError != null) setState(() => _nameError = null);
            },
          ),
          const SizedBox(height: 16),
          ObTextField(
            label: 'Age',
            hint: 'Your age',
            icon: Icons.cake_outlined,
            controller: draft.age,
            keyboardType: TextInputType.number,
            inputFormatters: InputFormatters.age,
            errorText: _ageError,
            onChanged: (_) {
              if (_ageError != null) setState(() => _ageError = null);
            },
          ),
          const SizedBox(height: 16),
          const ObFieldLabel('Username'),
          const SizedBox(height: 8),
          TextField(
            controller: draft.username,
            cursorColor: cs.primary,
            style: TextStyle(fontSize: 16, color: cs.onSurface),
            inputFormatters: [
              FilteringTextInputFormatter.allow(RegExp(r'[a-zA-Z0-9_]')),
              LengthLimitingTextInputFormatter(20),
            ],
            decoration: obInputDecoration(
              context,
              hint: 'e.g. workout_warrior',
              prefixIcon: Padding(
                padding: const EdgeInsets.only(left: 16, right: 6),
                child: Text('@',
                    style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                        color: cs.primary)),
              ),
              prefixIconConstraints:
                  const BoxConstraints(minWidth: 0, minHeight: 0),
              suffixIcon: _suffix(),
              errorText: _usernameError,
            ),
            onChanged: (v) {
              if (_isAvailable || _usernameError != null) {
                setState(() {
                  _isAvailable = false;
                  _usernameError = null;
                });
              }
              Future.delayed(const Duration(milliseconds: 600), () {
                if (draft.username.text == v && v.isNotEmpty && mounted) {
                  _check(v);
                }
              });
            },
          ),
          const SizedBox(height: 8),
          Text(
              '3 to 20 characters. Letters, numbers and underscores. '
              'No underscore at the start or end.',
              style: TextStyle(fontSize: 13, color: c.subtleText)),
          const SizedBox(height: 22),
          _PreviewCard(draft: draft),
        ],
      ),
    );
  }
}

class _PreviewCard extends StatelessWidget {
  final OnboardingDraft draft;
  const _PreviewCard({required this.draft});

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    final cs = Theme.of(context).colorScheme;
    final ring = draft.ringColor ?? c.avatarRing;
    return Semantics(
      container: true,
      label: 'Preview of your profile',
      excludeSemantics: true,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        decoration: BoxDecoration(
          color: c.claySurface,
          borderRadius: BorderRadius.circular(20),
          boxShadow: c.clayShadow(),
        ),
        child: Stack(
          children: [
            Positioned(
              top: 0,
              right: 0,
              child: Text('PREVIEW',
                  style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 1.2,
                      color: c.subtleText)),
            ),
            ListenableBuilder(
              listenable: Listenable.merge([draft.name, draft.username]),
              builder: (_, __) {
                final name = draft.name.text.trim();
                final username = draft.username.text;
                return Row(
                  children: [
                    Container(
                      width: 56,
                      height: 56,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: c.inputFill,
                        border: Border.all(color: ring, width: 3),
                      ),
                      child: Center(
                          child: UserAvatar(
                              avatarId: draft.avatarId, size: 44, bare: true)),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Padding(
                        padding: const EdgeInsets.only(top: 14),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(name.isEmpty ? 'Your name' : name,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                    fontSize: 17,
                                    fontWeight: FontWeight.w700,
                                    color: name.isEmpty
                                        ? c.subtleText
                                        : cs.onSurface)),
                            Text('@${username.isEmpty ? 'username' : username}',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                    fontSize: 14, color: c.subtleText)),
                          ],
                        ),
                      ),
                    ),
                  ],
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}
