import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'onboarding_basic_info.dart';
import 'onboarding_goals.dart';

class OnboardingUsernameAvatar extends StatefulWidget {
  final Map<String, dynamic> userData;
  const OnboardingUsernameAvatar({super.key, required this.userData});

  @override
  State<OnboardingUsernameAvatar> createState() => _OnboardingUsernameAvatarState();
}

class _OnboardingUsernameAvatarState extends State<OnboardingUsernameAvatar> {
  final _usernameController = TextEditingController();
  bool _isChecking = false;
  String? _errorMessage;
  bool _isAvailable = false;
  int _selectedAvatarIndex = 0;

  final List<Map<String, String>> _avatars = [
    {'id': 'lion', 'emoji': '🦁'},
    {'id': 'bear', 'emoji': '🐻'},
    {'id': 'eagle', 'emoji': '🦅'},
    {'id': 'shark', 'emoji': '🦈'},
    {'id': 'wolf', 'emoji': '🐺'},
    {'id': 'gorilla', 'emoji': '🦍'},
    {'id': 'buffalo', 'emoji': '🦬'},
    {'id': 'robot', 'emoji': '🤖'},
    {'id': 'flexed', 'emoji': '💪'},
    {'id': 'weightlifter', 'emoji': '🏋️'},
    {'id': 'runner', 'emoji': '🏃'},
  ];

  @override
  void dispose() {
    _usernameController.dispose();
    super.dispose();
  }

  String? _validateFormat(String username) {
    if (username.isEmpty) return 'Username is required';
    if (username.length < 3) return 'At least 3 characters required';
    if (username.length > 20) return '20 characters maximum';
    if (!RegExp(r'^[a-zA-Z0-9_]+$').hasMatch(username)) return 'Letters, numbers, and underscores only';
    if (username.startsWith('_') || username.endsWith('_')) return 'Cannot start or end with underscore';
    return null;
  }

  Future<void> _checkAvailability(String username) async {
    final formatError = _validateFormat(username);
    if (formatError != null) {
      setState(() { _errorMessage = formatError; _isAvailable = false; });
      return;
    }
    setState(() { _isChecking = true; _errorMessage = null; _isAvailable = false; });
    try {
      final response = await Supabase.instance.client
          .from('user_profiles').select('id').eq('username', username.toLowerCase()).maybeSingle();
      if (mounted) {
        setState(() {
          _isChecking = false;
          if (response != null) {
            _errorMessage = 'Username already taken';
            _isAvailable = false;
          } else {
            _isAvailable = true;
          }
        });
      }
    } catch (e) {
      if (mounted) setState(() { _isChecking = false; _errorMessage = 'Error checking username'; });
    }
  }

  void _next() {
    if (!_isAvailable) {
      if (_usernameController.text.isEmpty) {
        setState(() => _errorMessage = 'Please choose a username');
      }
      return;
    }
    widget.userData['username'] = _usernameController.text.toLowerCase();
    widget.userData['avatar_id'] = _avatars[_selectedAvatarIndex]['id'];
    Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => OnboardingGoals(userData: widget.userData),
    ));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child: Column(
          children: [
            const OnboardingHeader(step: 2, label: 'Your Identity'),
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(24),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const SizedBox(height: 8),
                    const Text('Create your profile',
                        style: TextStyle(fontSize: 26, fontWeight: FontWeight.bold, color: Color(0xFF1E293B))),
                    const SizedBox(height: 6),
                    Text('Choose a username and pick your avatar',
                        style: TextStyle(fontSize: 15, color: Colors.grey[500])),
                    const SizedBox(height: 32),

                    // Username field
                    const OnboardingLabel(text: 'Username'),
                    const SizedBox(height: 8),
                    TextField(
                      controller: _usernameController,
                      autofocus: false,
                      inputFormatters: [
                        FilteringTextInputFormatter.allow(RegExp(r'[a-zA-Z0-9_]')),
                        LengthLimitingTextInputFormatter(20),
                      ],
                      decoration: InputDecoration(
                        hintText: 'e.g. workout_warrior',
                        hintStyle: TextStyle(color: Colors.grey[400]),
                        prefixIcon: const Icon(Icons.alternate_email, color: Color(0xFF6B7280), size: 20),
                        suffixIcon: _buildSuffixIcon(),
                        errorText: _errorMessage,
                        helperText: _isAvailable ? '✓ Username available' : null,
                        helperStyle: const TextStyle(color: Color(0xFF10B981), fontWeight: FontWeight.w500),
                        filled: true,
                        fillColor: const Color(0xFFF8FAFC),
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: Color(0xFFE2E8F0))),
                        enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: Color(0xFFE2E8F0))),
                        focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: Color(0xFF3B82F6), width: 2)),
                        errorBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: Colors.red)),
                        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                      ),
                      onChanged: (value) {
                        if (_isAvailable || _errorMessage != null) {
                          setState(() { _isAvailable = false; _errorMessage = null; });
                        }
                        Future.delayed(const Duration(milliseconds: 600), () {
                          if (_usernameController.text == value && value.isNotEmpty && mounted) {
                            _checkAvailability(value);
                          }
                        });
                      },
                    ),
                    const SizedBox(height: 8),
                    Text('3-20 characters • letters, numbers, underscores only',
                        style: TextStyle(fontSize: 12, color: Colors.grey[400])),

                    const SizedBox(height: 32),

                    // Avatar picker
                    const OnboardingLabel(text: 'Choose Your Avatar'),
                    const SizedBox(height: 16),
                    GridView.builder(
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                        crossAxisCount: 4,
                        crossAxisSpacing: 12,
                        mainAxisSpacing: 12,
                        childAspectRatio: 1,
                      ),
                      itemCount: _avatars.length,
                      itemBuilder: (context, index) {
                        final isSelected = _selectedAvatarIndex == index;
                        return GestureDetector(
                          onTap: () {
                            HapticFeedback.selectionClick();
                            setState(() => _selectedAvatarIndex = index);
                          },
                          child: AnimatedContainer(
                            duration: const Duration(milliseconds: 200),
                            decoration: BoxDecoration(
                              color: isSelected ? const Color(0xFFEFF6FF) : const Color(0xFFF8FAFC),
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(
                                color: isSelected ? const Color(0xFF3B82F6) : const Color(0xFFE2E8F0),
                                width: isSelected ? 2 : 1,
                              ),
                              boxShadow: isSelected ? [BoxShadow(color: const Color(0xFF3B82F6).withOpacity(0.2), blurRadius: 8, offset: const Offset(0, 2))] : [],
                            ),
                            child: Center(
                              child: Text(_avatars[index]['emoji']!,
                                  style: TextStyle(fontSize: isSelected ? 32 : 28)),
                            ),
                          ),
                        );
                      },
                    ),
                    const SizedBox(height: 40),
                  ],
                ),
              ),
            ),
            OnboardingBottomNav(
              onBack: () => Navigator.of(context).pop(),
              onNext: _next,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSuffixIcon() {
    if (_isChecking) {
      return const Padding(
        padding: EdgeInsets.all(12),
        child: SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2)),
      );
    }
    if (_isAvailable) return const Icon(Icons.check_circle, color: Color(0xFF10B981));
    if (_errorMessage != null) return const Icon(Icons.error_outline, color: Colors.red);
    return const SizedBox.shrink();
  }
}