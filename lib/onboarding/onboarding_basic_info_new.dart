import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'onboarding_theme.dart';
import '../widgets/avatar_picker_screen.dart';
import '../home_screen.dart';
import '../services/coach_max_service.dart';
import '../services/friend_service.dart';
import '../services/auth_service.dart';
import '../utils/input_validators.dart';

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
    return Scaffold(
      backgroundColor: Colors.white,
      body: Column(
        children: [
          ObHeader(step: 1, totalSteps: 5, label: 'About you'),
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(24, 24, 24, 24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text("Let's get to know you",
                      style: TextStyle(
                          fontSize: 22,
                          fontWeight: FontWeight.w700,
                          color: Color(0xFF1E293B))),
                  const SizedBox(height: 6),
                  Text('This helps us personalise your experience',
                      style: TextStyle(
                          fontSize: 14, color: Colors.grey[500])),
                  const SizedBox(height: 28),
                  ObTextField(
                    label: 'Display name',
                    hint: 'What should we call you?',
                    icon: Icons.person_outline,
                    controller: _nameCtrl,
                    inputFormatters: InputFormatters.displayName,  // 🔒 max 40, no control chars
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
                    inputFormatters: InputFormatters.age,          // 🔒 digits only, max "120"
                    errorText: _ageError,
                    onChanged: (_) => setState(() => _ageError = null),
                  ),
                  const SizedBox(height: 20),
                  const Text('Gender',
                      style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: Color(0xFF374151))),
                  const SizedBox(height: 4),
                  Text('(optional)',
                      style: TextStyle(
                          fontSize: 12, color: Colors.grey[400])),
                  const SizedBox(height: 8),
                  DropdownButtonFormField<String>(
                    value: _gender,
                    decoration: InputDecoration(
                      hintText: 'Select gender',
                      hintStyle:
                          TextStyle(color: Colors.grey[400]),
                      prefixIcon: const Icon(
                          Icons.accessibility_outlined,
                          color: Color(0xFF6B7280),
                          size: 20),
                      filled: true,
                      fillColor: const Color(0xFFF8FAFC),
                      border: OutlineInputBorder(
                          borderRadius:
                              BorderRadius.circular(12),
                          borderSide: const BorderSide(
                              color: Color(0xFFE2E8F0))),
                      enabledBorder: OutlineInputBorder(
                          borderRadius:
                              BorderRadius.circular(12),
                          borderSide: const BorderSide(
                              color: Color(0xFFE2E8F0))),
                      focusedBorder: OutlineInputBorder(
                          borderRadius:
                              BorderRadius.circular(12),
                          borderSide: const BorderSide(
                              color: kObBlue, width: 2)),
                      contentPadding:
                          const EdgeInsets.symmetric(
                              horizontal: 16, vertical: 14),
                    ),
                    items: _genders
                        .map((g) => DropdownMenuItem(
                            value: g, child: Text(g)))
                        .toList(),
                    onChanged: (v) =>
                        setState(() => _gender = v),
                  ),
                ],
              ),
            ),
          ),
          ObBottomNav(onNext: _next),
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
    if (_isChecking) {
      return const Padding(
        padding: EdgeInsets.all(12),
        child: SizedBox(
            width: 18,
            height: 18,
            child: CircularProgressIndicator(
                strokeWidth: 2, color: kObBlue)),
      );
    }
    if (_isAvailable) {
      return const Icon(Icons.check_circle,
          color: Color(0xFF10B981), size: 20);
    }
    if (_error != null) {
      return const Icon(Icons.error_outline,
          color: Colors.red, size: 20);
    }
    return const SizedBox.shrink();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: Column(
        children: [
          ObHeader(
              step: 2, totalSteps: 5, label: 'Your identity'),
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(24, 24, 24, 24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Choose a username',
                      style: TextStyle(
                          fontSize: 22,
                          fontWeight: FontWeight.w700,
                          color: Color(0xFF1E293B))),
                  const SizedBox(height: 6),
                  Text(
                      'This is how your buddies will find you',
                      style: TextStyle(
                          fontSize: 14,
                          color: Colors.grey[500])),
                  const SizedBox(height: 28),
                  // Username field with @ prefix
                  Column(
                    crossAxisAlignment:
                        CrossAxisAlignment.start,
                    children: [
                      const Text('Username',
                          style: TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w600,
                              color: Color(0xFF374151))),
                      const SizedBox(height: 8),
                      TextField(
                        controller: _ctrl,
                        inputFormatters: [
                          FilteringTextInputFormatter.allow(
                              RegExp(r'[a-zA-Z0-9_]')),
                          LengthLimitingTextInputFormatter(
                              20),
                        ],
                        decoration: InputDecoration(
                          hintText: 'e.g. workout_warrior',
                          hintStyle: TextStyle(
                              color: Colors.grey[400]),
                          prefixIcon: Padding(
                            padding: const EdgeInsets.only(
                                left: 14, right: 6,
                                top: 14, bottom: 14),
                            child: Text('@',
                                style: TextStyle(
                                    fontSize: 16,
                                    fontWeight:
                                        FontWeight.w600,
                                    color: _isAvailable
                                        ? kObBlue
                                        : Colors.grey)),
                          ),
                          prefixIconConstraints:
                              const BoxConstraints(
                                  minWidth: 0,
                                  minHeight: 0),
                          suffixIcon: _suffix(),
                          errorText: _error,
                          helperText: _isAvailable
                              ? 'Username available'
                              : null,
                          helperStyle: const TextStyle(
                              color: Color(0xFF10B981),
                              fontWeight: FontWeight.w500),
                          filled: true,
                          fillColor:
                              const Color(0xFFF8FAFC),
                          border: OutlineInputBorder(
                              borderRadius:
                                  BorderRadius.circular(
                                      12),
                              borderSide: const BorderSide(
                                  color:
                                      Color(0xFFE2E8F0))),
                          enabledBorder: OutlineInputBorder(
                              borderRadius:
                                  BorderRadius.circular(
                                      12),
                              borderSide: const BorderSide(
                                  color:
                                      Color(0xFFE2E8F0))),
                          focusedBorder: OutlineInputBorder(
                              borderRadius:
                                  BorderRadius.circular(
                                      12),
                              borderSide:
                                  const BorderSide(
                                      color: kObBlue,
                                      width: 2)),
                          errorBorder: OutlineInputBorder(
                              borderRadius:
                                  BorderRadius.circular(
                                      12),
                              borderSide: const BorderSide(
                                  color: Colors.red)),
                          contentPadding:
                              const EdgeInsets.symmetric(
                                  horizontal: 16,
                                  vertical: 14),
                        ),
                        onChanged: (v) {
                          if (_isAvailable || _error != null) {
                            setState(() {
                              _isAvailable = false;
                              _error = null;
                            });
                          }
                          Future.delayed(
                              const Duration(
                                  milliseconds: 600), () {
                            if (_ctrl.text == v &&
                                v.isNotEmpty &&
                                mounted) {
                              _check(v);
                            }
                          });
                        },
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text(
                      '3–20 characters · letters, numbers, underscores',
                      style: TextStyle(
                          fontSize: 12,
                          color: Colors.grey[400])),
                ],
              ),
            ),
          ),
          ObBottomNav(
            onBack: () => Navigator.of(context).pop(),
            onNext: _next,
          ),
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
      backgroundColor: Colors.white,
      body: Column(
        children: [
          ObHeader(
              step: 3,
              totalSteps: 5,
              label: 'Your profile icon'),
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
    return Scaffold(
      backgroundColor: Colors.white,
      body: Column(
        children: [
          ObHeader(
              step: 4, totalSteps: 5, label: 'Your goals'),
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(24, 24, 24, 24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('What are you training for?',
                      style: TextStyle(
                          fontSize: 22,
                          fontWeight: FontWeight.w700,
                          color: Color(0xFF1E293B))),
                  const SizedBox(height: 6),
                  Text('Select all that apply',
                      style: TextStyle(
                          fontSize: 14,
                          color: Colors.grey[500])),
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
                                ? const Color(0xFFEFF6FF)
                                : const Color(0xFFF8FAFC),
                            borderRadius:
                                BorderRadius.circular(12),
                            border: Border.all(
                              color: sel
                                  ? kObBlue
                                  : const Color(0xFFE2E8F0),
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
                                          ? const Color(
                                              0xFF1D4ED8)
                                          : const Color(
                                              0xFF374151))),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
                  if (_goalsError != null) ...[
                    const SizedBox(height: 8),
                    Text(_goalsError!,
                        style: const TextStyle(
                            color: Colors.red, fontSize: 13)),
                  ],
                  const SizedBox(height: 28),
                  const Text('Fitness level',
                      style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: Color(0xFF374151))),
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
                                ? const Color(0xFFEFF6FF)
                                : const Color(0xFFF8FAFC),
                            borderRadius:
                                BorderRadius.circular(12),
                            border: Border.all(
                              color: sel
                                  ? kObBlue
                                  : const Color(0xFFE2E8F0),
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
                                      ? kObBlue
                                      : Colors.transparent,
                                  border: Border.all(
                                    color: sel
                                        ? kObBlue
                                        : const Color(
                                            0xFFD1D5DB),
                                    width: 2,
                                  ),
                                ),
                                child: sel
                                    ? const Icon(Icons.check,
                                        size: 12,
                                        color: Colors.white)
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
                                                ? const Color(
                                                    0xFF1D4ED8)
                                                : const Color(
                                                    0xFF374151))),
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
                  }).toList(),
                ],
              ),
            ),
          ),
          ObBottomNav(
            onBack: () => Navigator.of(context).pop(),
            onNext: _next,
          ),
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
    setState(() => _isLoading = true);
    try {
      // ── Step 1: Create the account NOW (first time we touch Supabase Auth) ──
      final authService = AuthService();
      final signUpError = await authService.signUp(
        email: widget.email,
        password: widget.password,
      );

      if (signUpError != null) {
        // Handle duplicate email gracefully — try signing in instead
        // (edge case: user somehow completed this screen twice)
        if (signUpError.contains('user_already_exists') ||
            signUpError.contains('User already registered')) {
          final signInError = await authService.signIn(
            email: widget.email,
            password: widget.password,
          );
          if (signInError != null) {
            throw Exception('Account already exists. Please sign in.');
          }
        } else {
          throw Exception(signUpError);
        }
      }

      final user = Supabase.instance.client.auth.currentUser;
      if (user == null) throw Exception('Authentication failed');

      // ── Step 2: Save complete profile in one go ────────────────────────
      await Supabase.instance.client
          .from('user_profiles')
          .upsert({
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
      });

      // ── Step 3: Initialize Coach Max ───────────────────────────────────
      await _coachMaxService.initializeCoachMaxForUser(user.id);

      // ── Step 4: Fire pending friend invites ────────────────────────────
      if (widget.pendingInvites.isNotEmpty) {
        final friendService = FriendService();
        for (final invite in widget.pendingInvites) {
          try {
            await friendService.sendFriendRequest(invite['id']);
          } catch (_) {}
        }
      }

      if (mounted) {
        Navigator.of(context).pushAndRemoveUntil(
          FadeSlideRoute(page: const _OnboardingConfirmation()),
          (r) => false,
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text('Error saving profile: $e'),
              backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: Column(
        children: [
          ObHeader(
              step: 5, totalSteps: 5, label: 'Final step'),
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(24, 24, 24, 24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Find your gym buddy',
                      style: TextStyle(
                          fontSize: 22,
                          fontWeight: FontWeight.w700,
                          color: Color(0xFF1E293B))),
                  const SizedBox(height: 6),
                  Text('Tell us about your workout preferences',
                      style: TextStyle(
                          fontSize: 14,
                          color: Colors.grey[500])),
                  const SizedBox(height: 24),

                  // Looking for buddy toggle
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: const Color(0xFFF8FAFC),
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(
                          color: const Color(0xFFE2E8F0)),
                    ),
                    child: Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(10),
                          decoration: BoxDecoration(
                            color: const Color(0xFFEFF6FF),
                            borderRadius:
                                BorderRadius.circular(10),
                          ),
                          child: const Text('🤝',
                              style:
                                  TextStyle(fontSize: 22)),
                        ),
                        const SizedBox(width: 12),
                        const Expanded(
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
                                      color: Color(
                                          0xFF1E293B))),
                              SizedBox(height: 2),
                              Text(
                                  "We'll help you find workout partners",
                                  style: TextStyle(
                                      fontSize: 12,
                                      color: Color(
                                          0xFF6B7280))),
                            ],
                          ),
                        ),
                        Switch(
                          value: _lookingForBuddy,
                          onChanged: (v) => setState(
                              () => _lookingForBuddy = v),
                          activeColor: kObBlue,
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
                          const Text('Preferred workout style',
                              style: TextStyle(
                                  fontSize: 14,
                                  fontWeight: FontWeight.w600,
                                  color:
                                      Color(0xFF374151))),
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
                                            ? const Color(
                                                0xFFEFF6FF)
                                            : const Color(
                                                0xFFF8FAFC),
                                        borderRadius:
                                            BorderRadius
                                                .circular(12),
                                        border: Border.all(
                                          color: sel
                                              ? kObBlue
                                              : const Color(
                                                  0xFFE2E8F0),
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
                                                      ? const Color(
                                                          0xFF1D4ED8)
                                                      : const Color(
                                                          0xFF374151))),
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
                      gradient: const LinearGradient(
                        colors: [
                          Color(0xFFEFF6FF),
                          Color(0xFFF5F3FF)
                        ],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(
                          color: const Color(0xFFBFDBFE)),
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
                        const Expanded(
                          child: Column(
                            crossAxisAlignment:
                                CrossAxisAlignment.start,
                            children: [
                              Text('Almost there!',
                                  style: TextStyle(
                                      fontSize: 16,
                                      fontWeight:
                                          FontWeight.bold,
                                      color: Color(
                                          0xFF1E293B))),
                              SizedBox(height: 4),
                              Text(
                                  'Coach Max is ready to train with you from day one.',
                                  style: TextStyle(
                                      fontSize: 13,
                                      color: Color(
                                          0xFF6B7280))),
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
          ObBottomNav(
            onBack: () => Navigator.of(context).pop(),
            onNext: _finish,
            isLoading: _isLoading,
            nextChild: const Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text('Finish setup',
                    style: TextStyle(
                        color: Colors.white,
                        fontSize: 16,
                        fontWeight: FontWeight.w600)),
                SizedBox(width: 8),
                Icon(Icons.check_circle_outline,
                    color: Colors.white, size: 18),
              ],
            ),
          ),
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

  void _goHome() {
    final user = Supabase.instance.client.auth.currentUser;
    final msg = user != null
        ? _coachMaxService.getMotivationalMessage(
            currentStreak: 0, hasCheckedInToday: false)
        : "Let's go! Coach Max is ready for you.";

    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => const HomeScreen()),
      (r) => false,
    );

    Future.delayed(const Duration(milliseconds: 400), () {
      if (mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(msg),
          backgroundColor: const Color(0xFF10B981),
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
                        color: Colors.white.withOpacity(0.2),
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
                        color: Colors.white.withOpacity(0.8),
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