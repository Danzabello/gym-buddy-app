import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'onboarding_theme.dart';
import '../widgets/avatar_picker_screen.dart';
import '../home_screen.dart';
import '../theme/app_theme.dart';
import '../services/coach_max_service.dart';
import '../services/friend_service.dart';
import '../services/auth_service.dart';
import '../utils/input_validators.dart';
import '../utils/timezone_sync.dart';
import 'package:flutter/foundation.dart';
import '../services/invite_service.dart';
import '../services/notification_service.dart';
import 'onboarding_notifications.dart';
import 'package:gym_buddy_app/utils/debug_logger.dart';

/// Profile columns other users may read (LIVE-10 allowlist), as far as the
/// onboarding payload carries them.
const kDiscoveryProfileFields = {
  'display_name', 'username', 'avatar_id', 'avatar_border', 'fitness_level',
  'looking_for_buddy',
};

/// True when the profile insert hit this user's existing row (primary key),
/// not the username unique key.
bool isOwnProfileDuplicate(Object e) =>
    e is PostgrestException &&
    e.code == '23505' &&
    e.message.contains('user_profiles_pkey');

Map<String, dynamic> discoveryFieldsOf(Map<String, dynamic> profile) => {
      for (final k in kDiscoveryProfileFields)
        if (profile.containsKey(k)) k: profile[k],
    };

// ═══════════════════════════════════════════════════════════════════════════
// STEP 1 — Basic info
// ═══════════════════════════════════════════════════════════════════════════
class OnboardingBasicInfoNew extends StatefulWidget {
  final List<Map<String, dynamic>> pendingInvites;
  final String email;
  final String password;

  const OnboardingBasicInfoNew({
    super.key,
    this.pendingInvites = const [],
    required this.email,
    required this.password,
  });

  @override
  State<OnboardingBasicInfoNew> createState() =>
      _OnboardingBasicInfoNewState();
}

class _OnboardingBasicInfoNewState
    extends State<OnboardingBasicInfoNew> {
  final _nameCtrl = TextEditingController();
  final _ageCtrl = TextEditingController();
  String? _gender;
  String? _nameError;
  String? _ageError;

  final _genders = [
    'Male',
    'Female',
    'Other',
    'Prefer not to say'
  ];

  bool _validate() {
    final nameErr = InputValidators.displayName(_nameCtrl.text);
    final ageErr = InputValidators.age(_ageCtrl.text);
    setState(() {
      _nameError = nameErr;
      _ageError = ageErr;
    });
    return nameErr == null && ageErr == null;
  }

  void _next() {
    if (!_validate()) return;
    Navigator.of(context).push(FadeSlideRoute(page: _OnboardingUsername(
        userData: {
          'display_name': _nameCtrl.text.trim(),
          'age': int.parse(_ageCtrl.text),
          'gender': _gender,
        },
        pendingInvites: widget.pendingInvites,
        email: widget.email,
        password: widget.password,
      ),
    ));
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _ageCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    final cs = Theme.of(context).colorScheme;
    return Scaffold(
      body: Column(
        children: [
          ObStepHeader(
            step: 1,
            onBack: Navigator.of(context).canPop()
                ? () => Navigator.of(context).pop()
                : null,
          ),
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(24, 16, 24, 24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const ObHeading(
                    title: 'About you',
                    body: 'So your buddy knows who they are training with.',
                  ),
                  const SizedBox(height: 28),
                  ObTextField(
                    label: 'Display name',
                    hint: 'What should we call you?',
                    icon: Icons.person_outline,
                    controller: _nameCtrl,
                    inputFormatters: InputFormatters.displayName,
                    errorText: _nameError,
                    onChanged: (_) => setState(() => _nameError = null),
                  ),
                  const SizedBox(height: 20),
                  ObTextField(
                    label: 'Age',
                    hint: 'Your age',
                    icon: Icons.cake_outlined,
                    controller: _ageCtrl,
                    keyboardType: TextInputType.number,
                    inputFormatters: InputFormatters.age,
                    errorText: _ageError,
                    onChanged: (_) => setState(() => _ageError = null),
                  ),
                  const SizedBox(height: 20),
                  const ObFieldLabel('Gender', optional: true),
                  const SizedBox(height: 8),
                  DropdownButtonFormField<String>(
                    initialValue: _gender,
                    dropdownColor: c.cardBackground,
                    style: TextStyle(fontSize: 16, color: cs.onSurface),
                    iconEnabledColor: c.subtleText,
                    decoration: obInputDecoration(
                      context,
                      hint: 'Select gender',
                      prefixIcon: Icon(Icons.accessibility_outlined,
                          color: c.subtleText, size: 20),
                    ),
                    items: _genders
                        .map((g) => DropdownMenuItem(value: g, child: Text(g)))
                        .toList(),
                    onChanged: (v) => setState(() => _gender = v),
                  ),
                ],
              ),
            ),
          ),
          ObStepFooter(onNext: _next),
        ],
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// STEP 2 — Username
// ═══════════════════════════════════════════════════════════════════════════
class _OnboardingUsername extends StatefulWidget {
  final Map<String, dynamic> userData;
  final List<Map<String, dynamic>> pendingInvites;
  final String email;
  final String password;
  const _OnboardingUsername(
      {required this.userData, required this.pendingInvites,
       required this.email, required this.password});

  @override
  State<_OnboardingUsername> createState() =>
      _OnboardingUsernameState();
}

class _OnboardingUsernameState
    extends State<_OnboardingUsername> {
  final _ctrl = TextEditingController();
  bool _isChecking = false;
  bool _isAvailable = false;
  String? _error;

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
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
        _error = fmtErr;
        _isAvailable = false;
      });
      return;
    }
    setState(() {
      _isChecking = true;
      _error = null;
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
          if (res != null) {
            _error = 'Username already taken';
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
          _error = 'Error checking username';
        });
      }
    }
  }

  void _next() {
    if (!_isAvailable) {
      setState(() =>
          _error = _ctrl.text.isEmpty ? 'Choose a username' : _error);
      return;
    }
    final data = {
      ...widget.userData,
      'username': _ctrl.text.toLowerCase(),
    };
    Navigator.of(context).push(FadeSlideRoute(page: _OnboardingAvatarPicker(
        userData: data,
        pendingInvites: widget.pendingInvites,
        email: widget.email,
        password: widget.password,
      ),
    ));
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
    if (_error != null) {
      return Icon(Icons.error_outline, color: c.danger, size: 20);
    }
    return const SizedBox.shrink();
  }

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    final cs = Theme.of(context).colorScheme;
    return Scaffold(
      body: Column(
        children: [
          ObStepHeader(step: 2, onBack: () => Navigator.of(context).pop()),
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(24, 16, 24, 24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const ObHeading(
                    title: 'Your identity',
                    body: 'Pick a username. Buddies find you with it.',
                  ),
                  const SizedBox(height: 28),
                  const ObFieldLabel('Username'),
                  const SizedBox(height: 8),
                  TextField(
                    controller: _ctrl,
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
                      errorText: _error,
                    ),
                    onChanged: (v) {
                      if (_isAvailable || _error != null) {
                        setState(() {
                          _isAvailable = false;
                          _error = null;
                        });
                      }
                      Future.delayed(const Duration(milliseconds: 600), () {
                        if (_ctrl.text == v && v.isNotEmpty && mounted) {
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
                ],
              ),
            ),
          ),
          ObStepFooter(onNext: _next),
        ],
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// STEP 3 — Avatar picker (wrapper for existing widget)
// ═══════════════════════════════════════════════════════════════════════════
class _OnboardingAvatarPicker extends StatelessWidget {
  final Map<String, dynamic> userData;
  final List<Map<String, dynamic>> pendingInvites;
  final String email;
  final String password;
  const _OnboardingAvatarPicker(
      {required this.userData, required this.pendingInvites,
       required this.email, required this.password});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Column(
        children: [
          ObStepHeader(step: 3, onBack: () => Navigator.of(context).pop()),
          Expanded(
            child: AvatarPickerScreen(
              showHeader: false,
              onCompleteWithData: (avatarId, borderStyle) {
                Navigator.of(context).push(FadeSlideRoute(page: _OnboardingGoals(
                    userData: {
                      ...userData,
                      'avatar_id': avatarId,
                      'avatar_border': borderStyle,
                    },
                    pendingInvites: pendingInvites,
                    email: email,
                    password: password,
                  ),
                ));
              },
            ),
          ),
        ],
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// STEP 4 — Goals
// ═══════════════════════════════════════════════════════════════════════════
class _OnboardingGoals extends StatefulWidget {
  final Map<String, dynamic> userData;
  final List<Map<String, dynamic>> pendingInvites;
  final String email;
  final String password;
  const _OnboardingGoals(
      {required this.userData, required this.pendingInvites,
       required this.email, required this.password});

  @override
  State<_OnboardingGoals> createState() =>
      _OnboardingGoalsState();
}

class _OnboardingGoalsState extends State<_OnboardingGoals> {
  final _selectedGoals = <String>[];
  String _level = 'beginner';
  String? _goalsError;

  final _goals = [
    {'title': 'Build Muscle', 'emoji': '💪', 'value': 'build_muscle'},
    {'title': 'Lose Weight', 'emoji': '🔥', 'value': 'lose_weight'},
    {'title': 'Endurance', 'emoji': '🏃', 'value': 'improve_endurance'},
    {'title': 'Get Stronger', 'emoji': '🏋️', 'value': 'increase_strength'},
    {'title': 'Stay Active', 'emoji': '⚡', 'value': 'stay_active'},
    {'title': 'Train for Event', 'emoji': '🏆', 'value': 'train_for_event'},
  ];

  final _levels = [
    {'label': 'Beginner', 'value': 'beginner', 'desc': 'New to working out'},
    {'label': 'Intermediate', 'value': 'intermediate', 'desc': 'Work out regularly'},
    {'label': 'Advanced', 'value': 'advanced', 'desc': 'Experienced athlete'},
  ];

  void _toggle(String v) {
    setState(() {
      _selectedGoals.contains(v)
          ? _selectedGoals.remove(v)
          : _selectedGoals.add(v);
      if (_selectedGoals.isNotEmpty) _goalsError = null;
    });
  }

  void _next() {
    if (_selectedGoals.isEmpty) {
      setState(
          () => _goalsError = 'Select at least one goal');
      return;
    }
    Navigator.of(context).push(FadeSlideRoute(page: _OnboardingBuddyPrefs(
        userData: {
          ...widget.userData,
          'fitness_goals': _selectedGoals,
          'fitness_level': _level,
        },
        pendingInvites: widget.pendingInvites,
        email: widget.email,
        password: widget.password,
      ),
    ));
  }

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    final cs = Theme.of(context).colorScheme;
    return Scaffold(
      body: Column(
        children: [
          ObStepHeader(step: 4, onBack: () => Navigator.of(context).pop()),
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(24, 24, 24, 24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('What are you training for?',
                      style: TextStyle(
                          fontSize: 22,
                          fontWeight: FontWeight.w700,
                          color: cs.onSurface)),
                  const SizedBox(height: 6),
                  Text('Select all that apply',
                      style: TextStyle(
                          fontSize: 14,
                          color: c.subtleText)),
                  const SizedBox(height: 20),
                  GridView.builder(
                    shrinkWrap: true,
                    physics:
                        const NeverScrollableScrollPhysics(),
                    gridDelegate:
                        const SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: 2,
                      crossAxisSpacing: 12,
                      mainAxisSpacing: 12,
                      childAspectRatio: 1.6,
                    ),
                    itemCount: _goals.length,
                    itemBuilder: (_, i) {
                      final g = _goals[i];
                      final sel = _selectedGoals
                          .contains(g['value']);
                      return GestureDetector(
                        onTap: () => _toggle(g['value']!),
                        child: AnimatedContainer(
                          duration:
                              const Duration(milliseconds: 180),
                          decoration: BoxDecoration(
                            color: sel
                                ? c.claySurface
                                : c.inputFill,
                            borderRadius:
                                BorderRadius.circular(12),
                            border: Border.all(
                              color: sel
                                  ? cs.primary
                                  : c.info,
                              width: sel ? 2 : 1,
                            ),
                          ),
                          child: Row(
                            mainAxisAlignment:
                                MainAxisAlignment.center,
                            children: [
                              Text(g['emoji']!,
                                  style: const TextStyle(
                                      fontSize: 22)),
                              const SizedBox(width: 8),
                              Text(g['title']!,
                                  style: TextStyle(
                                      fontSize: 13,
                                      fontWeight: sel
                                          ? FontWeight.w700
                                          : FontWeight.w500,
                                      color: sel
                                          ? cs.primary
                                          : cs.onSurface)),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
                  if (_goalsError != null) ...[
                    const SizedBox(height: 8),
                    Text(_goalsError!,
                        style: TextStyle(
                            color: c.danger, fontSize: 13)),
                  ],
                  const SizedBox(height: 28),
                  Text('Fitness level',
                      style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: cs.onSurface)),
                  const SizedBox(height: 12),
                  ..._levels.map((l) {
                    final sel = _level == l['value'];
                    return Padding(
                      padding:
                          const EdgeInsets.only(bottom: 10),
                      child: GestureDetector(
                        onTap: () =>
                            setState(() => _level = l['value']!),
                        child: AnimatedContainer(
                          duration: const Duration(
                              milliseconds: 180),
                          padding: const EdgeInsets.all(14),
                          decoration: BoxDecoration(
                            color: sel
                                ? c.claySurface
                                : c.inputFill,
                            borderRadius:
                                BorderRadius.circular(12),
                            border: Border.all(
                              color: sel
                                  ? cs.primary
                                  : c.info,
                              width: sel ? 2 : 1,
                            ),
                          ),
                          child: Row(
                            children: [
                              Container(
                                width: 20,
                                height: 20,
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  color: sel
                                      ? cs.primary
                                      : Colors.transparent,
                                  border: Border.all(
                                    color: sel
                                        ? cs.primary
                                        : c.info,
                                    width: 2,
                                  ),
                                ),
                                child: sel
                                    ? Icon(Icons.check,
                                        size: 12,
                                        color: Theme.of(context).scaffoldBackgroundColor)
                                    : null,
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment:
                                      CrossAxisAlignment.start,
                                  children: [
                                    Text(l['label']!,
                                        style: TextStyle(
                                            fontSize: 15,
                                            fontWeight: sel
                                                ? FontWeight
                                                    .w700
                                                : FontWeight
                                                    .w500,
                                            color: sel
                                                ? cs.primary
                                                : cs.onSurface)),
                                    Text(l['desc']!,
                                        style: TextStyle(
                                            fontSize: 12,
                                            color: Colors
                                                .grey[500])),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    );
                  }),
                ],
              ),
            ),
          ),
          ObStepFooter(onNext: _next),
        ],
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// STEP 5 — Buddy preferences
// ═══════════════════════════════════════════════════════════════════════════
class _OnboardingBuddyPrefs extends StatefulWidget {
  final Map<String, dynamic> userData;
  final List<Map<String, dynamic>> pendingInvites;
  final String email;
  final String password;
  const _OnboardingBuddyPrefs(
      {required this.userData, required this.pendingInvites,
       required this.email, required this.password});

  @override
  State<_OnboardingBuddyPrefs> createState() =>
      _OnboardingBuddyPrefsState();
}

class _OnboardingBuddyPrefsState
    extends State<_OnboardingBuddyPrefs> {
  final _coachMaxService = CoachMaxService();
  bool _lookingForBuddy = true;
  String _style = 'both';
  bool _isLoading = false;

  final _styles = [
    {'value': 'weights', 'label': 'Weights', 'emoji': '🏋️'},
    {'value': 'cardio', 'label': 'Cardio', 'emoji': '🏃'},
    {'value': 'both', 'label': 'Both', 'emoji': '⚡'},
  ];

Future<void> _finish() async {
  if (_isLoading) return;
  // Captured before the first await: the buddy-request snackbar below fires
  // after many awaits, and ScaffoldMessenger sits above the Navigator.
  final messenger = ScaffoldMessenger.of(context);
  final successColor = AppColors.of(context).success;
  setState(() => _isLoading = true);
  try {
    // ── Step 1: Create the account NOW (first time we touch Supabase Auth) ──
    final authService = AuthService();
    final signUpError = await authService.signUp(
      email: widget.email,
      password: widget.password,
    );

    if (signUpError != null) {
      if (signUpError.contains('user_already_exists') ||
          signUpError.contains('User already registered')) {
        final signInError = await authService.signIn(
          email: widget.email,
          password: widget.password,
        );
        if (signInError != null) {
          // S4 audit fix: was 'Account already exists. Please sign in.',
          // which directly confirms the email's existence to whoever is
          // typing (the classic email-enumeration signal). This message
          // is now identical to other signup failures below, regardless
          // of the real reason -- it doesn't confirm or deny anything.
          throw Exception('We could not complete your signup. Please check your details and try again, or sign in if you already have an account.');
        }
        // Check if this is an orphaned account (signed in but never finished onboarding)
        final existingUser = Supabase.instance.client.auth.currentUser;
        if (existingUser != null) {
          final hasProfile = await Supabase.instance.client
              .rpc('get_my_profile')
              .select('onboarding_completed')
              .maybeSingle();
          final completed = hasProfile?['onboarding_completed'] == true;
          if (!completed) {
            // Orphaned — delete and let signup continue fresh.
            // Token first: the delete-account failure below is swallowed, and
            // in that path the auth user survives with its token row intact.
            await NotificationService().removeToken();
            try {
              await Supabase.instance.client.functions.invoke('delete-account');
            } catch (_) {}
            await Supabase.instance.client.auth.signOut();
            // Retry signup
            final retryError = await authService.signUp(
              email: widget.email,
              password: widget.password,
            );
            if (retryError != null) throw Exception(retryError);
          }
        }
      } else {
        // S4 audit fix: was throwing the raw Supabase error message
        // directly. Generic message for consistency -- matches the
        // duplicate-email branch above, doesn't leak internals.
        throw Exception('Something went wrong creating your account. Please try again.');
      }
    }

    final user = Supabase.instance.client.auth.currentUser;
    if (user == null) throw Exception('Authentication failed');

    // ── Step 2: Save complete profile in one go ────────────────────────────
    final profile = {
      'id': user.id,
      'display_name': widget.userData['display_name'],
      'username': widget.userData['username'],
      'age': widget.userData['age'],
      'gender': widget.userData['gender'],
      'avatar_id': widget.userData['avatar_id'],
      'avatar_border': widget.userData['avatar_border'] ?? 'simple',
      'fitness_goals': widget.userData['fitness_goals'],
      'fitness_level': widget.userData['fitness_level'],
      'looking_for_buddy': _lookingForBuddy,
      'preferred_workout_style': _style,
      'onboarding_completed': true,
      'updated_at': DateTime.now().toIso8601String(),
    };
    try {
      await Supabase.instance.client.from('user_profiles').insert(profile);
    } catch (e) {
      if (!isOwnProfileDuplicate(e)) rethrow;
      // A completed account re-running signup: refresh the public fields only.
      await Supabase.instance.client
          .from('user_profiles')
          .update(discoveryFieldsOf(profile))
          .eq('id', user.id);
    }

    // Capture the device timezone for this brand-new profile.
    await syncDeviceTimezone();

    // Register this handset for push. Sign-up is the one entry point that
    // never ran NotificationService.initialize() — main.dart only calls it
    // when a session already exists at launch, and login_screen only on
    // sign-in — so without this a newly-registered account had no
    // device_tokens row (and no _fcm, which made removeToken() a no-op on
    // its first sign-out) until the next cold start.
    await NotificationService().initialize();

    // ── Step 3: Initialize Coach Max ───────────────────────────────────────
    await _coachMaxService.initializeCoachMaxForUser(user.id);

    // ── Step 4: Check for pending invite code (from deep link) ────────────
    final inviteService = InviteService();
    final pendingCode = await inviteService.consumePendingInviteCode();

    if (pendingCode != null) {
      if (kDebugMode) debugLog('🔗 Found pending invite code: $pendingCode — attempting auto-pair');
      final inviterId = await inviteService.acceptInvite(pendingCode);

      if (inviterId != null) {
        if (kDebugMode) debugLog('✅ Invite accepted — auto-pairing with inviter: $inviterId');
        await _createBuddyTeam(user.id, inviterId);
      } else {
        if (kDebugMode) debugLog('⚠️ Invite code was invalid or already used — skipping auto-pair');
      }
    }

    // ── Step 5: Fire pending friend invites (from onboarding search) ──────
    // One summary snackbar for the batch, not one per request. Previously the
    // results were discarded and exceptions swallowed, so a user who picked
    // buddies here had no way to know none of them landed.
    if (widget.pendingInvites.isNotEmpty) {
      final friendService = FriendService();
      var sent = 0;
      var failed = 0;
      for (final invite in widget.pendingInvites) {
        final result = await friendService.sendFriendRequest(invite['id']);
        if (result == FriendRequestResult.sent) {
          sent++;
        } else {
          failed++;
        }
      }

      if (mounted) {
        messenger.showSnackBar(SnackBar(
          content: Text(failed == 0
              ? '$sent buddy request${sent == 1 ? '' : 's'} sent'
              : "$sent sent, $failed couldn't be sent"),
          backgroundColor:
              failed == 0 ? successColor : AppColors.of(context).warn,
          behavior: SnackBarBehavior.floating,
        ));
      }
    }

    if (mounted) {
      Navigator.of(context).pushAndRemoveUntil(
        FadeSlideRoute(page: const _OnboardingConfirmation()),
        (r) => false,
      );
    }
  } catch (e) {
    debugLog('Onboarding profile save failed: $e');
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
            content: Text('Could not save profile. Please try again.'),
            backgroundColor: AppColors.of(context).danger),
      );
    }
  } finally {
    if (mounted) setState(() => _isLoading = false);
  }
}

// ── Auto-create a buddy team between new user and inviter ─────────────────
Future<void> _createBuddyTeam(String newUserId, String inviterId) async {
  try {
    final teamId = await Supabase.instance.client.rpc(
      'create_invite_team',
      params: {
        'p_inviter_id': inviterId,
        'p_invitee_id': newUserId,
      },
    );
    if (kDebugMode) debugLog('🎉 Buddy team created via RPC: $teamId');
  } catch (e) {
    if (kDebugMode) debugLog('❌ _createBuddyTeam failed: $e');
  }
}

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    final cs = Theme.of(context).colorScheme;
    return Scaffold(
      body: Column(
        children: [
          ObStepHeader(step: 5, onBack: () => Navigator.of(context).pop()),
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(24, 24, 24, 24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Find your gym buddy',
                      style: TextStyle(
                          fontSize: 22,
                          fontWeight: FontWeight.w700,
                          color: cs.onSurface)),
                  const SizedBox(height: 6),
                  Text('Tell us about your workout preferences',
                      style: TextStyle(
                          fontSize: 14,
                          color: c.subtleText)),
                  const SizedBox(height: 24),

                  // Looking for buddy toggle
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: c.inputFill,
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(
                          color: c.info),
                    ),
                    child: Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(10),
                          decoration: BoxDecoration(
                            color: c.claySurface,
                            borderRadius:
                                BorderRadius.circular(10),
                          ),
                          child: const Text('🤝',
                              style:
                                  TextStyle(fontSize: 22)),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment:
                                CrossAxisAlignment.start,
                            children: [
                              Text(
                                  'Looking for a gym buddy?',
                                  style: TextStyle(
                                      fontSize: 15,
                                      fontWeight:
                                          FontWeight.w600,
                                      color: cs.onSurface)),
                              SizedBox(height: 2),
                              Text(
                                  "We'll help you find workout partners",
                                  style: TextStyle(
                                      fontSize: 12,
                                      color: c.subtleText)),
                            ],
                          ),
                        ),
                        Switch(
                          value: _lookingForBuddy,
                          onChanged: (v) => setState(
                              () => _lookingForBuddy = v),
                          activeThumbColor: cs.primary,
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(height: 20),

                  // Workout style
                  AnimatedOpacity(
                    opacity: _lookingForBuddy ? 1.0 : 0.4,
                    duration:
                        const Duration(milliseconds: 200),
                    child: IgnorePointer(
                      ignoring: !_lookingForBuddy,
                      child: Column(
                        crossAxisAlignment:
                            CrossAxisAlignment.start,
                        children: [
                          Text('Preferred workout style',
                              style: TextStyle(
                                  fontSize: 14,
                                  fontWeight: FontWeight.w600,
                                  color:
                                      cs.onSurface)),
                          const SizedBox(height: 12),
                          Row(
                            children: _styles.map((s) {
                              final sel =
                                  _style == s['value'];
                              return Expanded(
                                child: Padding(
                                  padding: EdgeInsets.only(
                                    right:
                                        s['value'] != 'both'
                                            ? 8
                                            : 0,
                                  ),
                                  child: GestureDetector(
                                    onTap: () => setState(
                                        () => _style =
                                            s['value']!),
                                    child: AnimatedContainer(
                                      duration: const Duration(
                                          milliseconds: 180),
                                      padding:
                                          const EdgeInsets.symmetric(
                                              vertical: 14),
                                      decoration:
                                          BoxDecoration(
                                        color: sel
                                            ? c.claySurface
                                            : c.inputFill,
                                        borderRadius:
                                            BorderRadius
                                                .circular(12),
                                        border: Border.all(
                                          color: sel
                                              ? cs.primary
                                              : c.info,
                                          width:
                                              sel ? 2 : 1,
                                        ),
                                      ),
                                      child: Column(
                                        children: [
                                          Text(s['emoji']!,
                                              style:
                                                  const TextStyle(
                                                      fontSize:
                                                          22)),
                                          const SizedBox(
                                              height: 4),
                                          Text(s['label']!,
                                              style: TextStyle(
                                                  fontSize:
                                                      13,
                                                  fontWeight: sel
                                                      ? FontWeight
                                                          .w700
                                                      : FontWeight
                                                          .w500,
                                                  color: sel
                                                      ? cs.primary
                                                      : cs.onSurface)),
                                        ],
                                      ),
                                    ),
                                  ),
                                ),
                              );
                            }).toList(),
                          ),
                        ],
                      ),
                    ),
                  ),

                  const SizedBox(height: 24),

                  // Coach Max card
                  Container(
                    padding: const EdgeInsets.all(20),
                    decoration: BoxDecoration(
                      color: c.claySurface,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(
                          color: c.info),
                    ),
                    child: Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            gradient: kGradient,
                            borderRadius:
                                BorderRadius.circular(12),
                          ),
                          child: const Text('🤖',
                              style:
                                  TextStyle(fontSize: 24)),
                        ),
                        const SizedBox(width: 16),
                        Expanded(
                          child: Column(
                            crossAxisAlignment:
                                CrossAxisAlignment.start,
                            children: [
                              Text('Almost there!',
                                  style: TextStyle(
                                      fontSize: 16,
                                      fontWeight:
                                          FontWeight.bold,
                                      color: cs.onSurface)),
                              SizedBox(height: 4),
                              Text(
                                  'Coach Max is ready to train with you from day one.',
                                  style: TextStyle(
                                      fontSize: 13,
                                      color: c.subtleText)),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
          ObStepFooter(
              onNext: _finish, label: 'Finish setup', isLoading: _isLoading),
        ],
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// CONFIRMATION — "You're all set"
// ═══════════════════════════════════════════════════════════════════════════
class _OnboardingConfirmation extends StatefulWidget {
  const _OnboardingConfirmation();

  @override
  State<_OnboardingConfirmation> createState() =>
      _OnboardingConfirmationState();
}

class _OnboardingConfirmationState
    extends State<_OnboardingConfirmation>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  late final Animation<double> _scale;
  late final Animation<double> _fade;
  final _coachMaxService = CoachMaxService();

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
        vsync: this,
        duration: const Duration(milliseconds: 700));
    _scale = Tween<double>(begin: 0.7, end: 1.0).animate(
        CurvedAnimation(
            parent: _ctrl, curve: Curves.elasticOut));
    _fade = CurvedAnimation(
        parent: _ctrl, curve: Curves.easeOut);
    _ctrl.forward();
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  Future<void> _goHome() async {
    final seen = await notificationRationaleSeen();
    if (!mounted) return;
    if (seen) return _toHome();
    Navigator.of(context).push(FadeSlideRoute(
        page: OnboardingNotifications(onContinue: _toHome)));
  }

  void _toHome() {
    final user = Supabase.instance.client.auth.currentUser;
    final msg = user != null
        ? _coachMaxService.getMotivationalMessage(
            currentStreak: 0, hasCheckedInToday: false)
        : "Let's go! Coach Max is ready for you.";

    // Captured before navigating: this screen is disposed by the time the
    // delayed snackbar fires, but ScaffoldMessenger sits above the Navigator
    // (MaterialApp), so it outlives the route change and shows on HomeScreen.
    final messenger = ScaffoldMessenger.of(context);
    final successColor = AppColors.of(context).success;

    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => const HomeScreen()),
      (r) => false,
    );

    Future.delayed(const Duration(milliseconds: 400), () {
      messenger.showSnackBar(
        SnackBar(
          content: Text(msg),
          backgroundColor: successColor,
          duration: const Duration(seconds: 4),
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12)),
        ),
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(gradient: kGradientDiag),
        child: SafeArea(
          child: FadeTransition(
            opacity: _fade,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 32),
              child: Column(
                children: [
                  const Spacer(),
                  ScaleTransition(
                    scale: _scale,
                    child: Container(
                      width: 100,
                      height: 100,
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.2),
                        shape: BoxShape.circle,
                      ),
                      child: const Center(
                        child: Text('🎉',
                            style: TextStyle(fontSize: 52)),
                      ),
                    ),
                  ),
                  const SizedBox(height: 28),
                  const Text("You're all set!",
                      style: TextStyle(
                          fontSize: 30,
                          fontWeight: FontWeight.w700,
                          color: Colors.white),
                      textAlign: TextAlign.center),
                  const SizedBox(height: 12),
                  Text(
                    'Your profile is ready. Coach Max is waiting. Time to build some streaks.',
                    style: TextStyle(
                        fontSize: 16,
                        color: Colors.white.withValues(alpha: 0.8),
                        height: 1.5),
                    textAlign: TextAlign.center,
                  ),
                  const Spacer(),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      onPressed: _goHome,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.white,
                        foregroundColor: kObBlue,
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14)),
                        elevation: 0,
                      ),
                      child: const Text(
                        "Let's train",
                        style: TextStyle(
                            fontSize: 16, fontWeight: FontWeight.w700),
                      ),
                    ),
                  ),
                  const SizedBox(height: 32),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}