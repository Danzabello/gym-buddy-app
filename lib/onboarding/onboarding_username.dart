import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'onboarding_avatar_selection.dart';

class OnboardingUsername extends StatefulWidget {
  final Map<String, dynamic> userData;

  const OnboardingUsername({
    super.key,
    required this.userData,
  });

  @override
  State<OnboardingUsername> createState() => _OnboardingUsernameState();
}

class _OnboardingUsernameState extends State<OnboardingUsername> {
  final _usernameController = TextEditingController();
  bool _isChecking = false;
  bool _isSaving = false;
  String? _errorMessage;
  bool _isAvailable = false;

  @override
  void dispose() {
    _usernameController.dispose();
    super.dispose();
  }

  // Validate username format
  String? _validateFormat(String username) {
    if (username.isEmpty) {
      return 'Username is required';
    }
    if (username.length < 3) {
      return 'Username must be at least 3 characters';
    }
    if (username.length > 20) {
      return 'Username must be 20 characters or less';
    }
    if (!RegExp(r'^[a-zA-Z0-9_]+$').hasMatch(username)) {
      return 'Only letters, numbers, and underscores allowed';
    }
    if (username.startsWith('_') || username.endsWith('_')) {
      return 'Cannot start or end with underscore';
    }
    return null;
  }

  // Check if username is available
  Future<void> _checkAvailability(String username) async {
    final formatError = _validateFormat(username);
    if (formatError != null) {
      setState(() {
        _errorMessage = formatError;
        _isAvailable = false;
      });
      return;
    }

    setState(() {
      _isChecking = true;
      _errorMessage = null;
      _isAvailable = false;
    });

    try {
      final response = await Supabase.instance.client
          .from('user_profiles')
          .select('id')
          .eq('username', username.toLowerCase())
          .maybeSingle();

      if (mounted) {
        setState(() {
          _isChecking = false;
          if (response != null) {
            _errorMessage = 'Username is already taken';
            _isAvailable = false;
          } else {
            _errorMessage = null;
            _isAvailable = true;
          }
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isChecking = false;
          _errorMessage = 'Error checking username';
          _isAvailable = false;
        });
      }
    }
  }

  Future<void> _saveAndContinue() async {
    if (!_isAvailable) return;

    setState(() => _isSaving = true);

    try {
      // Add username to userData (will be saved at the end of onboarding)
      widget.userData['username'] = _usernameController.text.toLowerCase();

      // Navigate to avatar selection
      Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => OnboardingAvatarSelection(userData: widget.userData),
        ),
      );
    } catch (e) {
      if (mounted) {
        setState(() {
          _isSaving = false;
          _errorMessage = 'Something went wrong';
        });
      }
    }
  }

  void _previousPage() {
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Progress indicator
              LinearProgressIndicator(
                value: 0.3,
                backgroundColor: Colors.grey[300],
                valueColor: AlwaysStoppedAnimation<Color>(
                  Theme.of(context).colorScheme.primary,
                ),
              ),
              
              const SizedBox(height: 32),
              
              // Title
              const Text(
                'Choose your username',
                style: TextStyle(
                  fontSize: 28,
                  fontWeight: FontWeight.bold,
                ),
              ),
              
              const SizedBox(height: 8),
              
              // Subtitle
              Text(
                'This is how friends will find and add you. Choose carefully - you can\'t change it later!',
                style: TextStyle(
                  fontSize: 16,
                  color: Colors.grey[600],
                ),
              ),
              
              const SizedBox(height: 32),
              
              // Username input
              TextField(
                controller: _usernameController,
                autofocus: true,
                textInputAction: TextInputAction.done,
                inputFormatters: [
                  FilteringTextInputFormatter.allow(RegExp(r'[a-zA-Z0-9_]')),
                  LengthLimitingTextInputFormatter(20),
                ],
                decoration: InputDecoration(
                  labelText: 'Username',
                  hintText: 'e.g., Workout_Warrior42',
                  prefixIcon: const Icon(Icons.alternate_email),
                  prefixText: '@',
                  suffixIcon: _buildSuffixIcon(),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  filled: true,
                  fillColor: Colors.grey[50],
                  errorText: _errorMessage,
                  helperText: _isAvailable ? 'Username is available!' : null,
                  helperStyle: TextStyle(color: Colors.green[600]),
                ),
                onChanged: (value) {
                  // Debounce the availability check
                  Future.delayed(const Duration(milliseconds: 500), () {
                    if (_usernameController.text == value && value.isNotEmpty) {
                      _checkAvailability(value);
                    }
                  });
                  
                  // Clear status when typing
                  if (_isAvailable || _errorMessage != null) {
                    setState(() {
                      _isAvailable = false;
                      _errorMessage = null;
                    });
                  }
                },
                onSubmitted: (_) {
                  if (_isAvailable) _saveAndContinue();
                },
              ),
              
              const SizedBox(height: 16),
              
              // Rules
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.grey[100],
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Username rules:',
                      style: TextStyle(
                        fontWeight: FontWeight.w600,
                        color: Colors.grey[700],
                      ),
                    ),
                    const SizedBox(height: 8),
                    _buildRule('3-20 characters'),
                    _buildRule('Letters, numbers, and underscores only'),
                    _buildRule('Cannot start or end with underscore'),
                    _buildRule('Cannot be changed after setup'),
                  ],
                ),
              ),
              
              const Spacer(),
              
              // Navigation buttons
              Row(
                children: [
                  TextButton(
                    onPressed: _isSaving ? null : _previousPage,
                    child: const Text('Back'),
                  ),
                  const Spacer(),
                  ElevatedButton(
                    onPressed: _isAvailable && !_isSaving ? _saveAndContinue : null,
                    style: ElevatedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 32,
                        vertical: 12,
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    child: _isSaving
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(
                              color: Colors.white,
                              strokeWidth: 2,
                            ),
                          )
                        : const Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text('Next'),
                              SizedBox(width: 8),
                              Icon(Icons.arrow_forward, size: 18),
                            ],
                          ),
                  ),
                ],
              ),
              const SizedBox(height: 20),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSuffixIcon() {
    if (_isChecking) {
      return const Padding(
        padding: EdgeInsets.all(12),
        child: SizedBox(
          width: 20,
          height: 20,
          child: CircularProgressIndicator(strokeWidth: 2),
        ),
      );
    }
    if (_isAvailable) {
      return Icon(Icons.check_circle, color: Colors.green[600]);
    }
    if (_errorMessage != null) {
      return Icon(Icons.error, color: Colors.red[600]);
    }
    return const SizedBox.shrink();
  }

  Widget _buildRule(String text) {
    return Padding(
      padding: const EdgeInsets.only(top: 4),
      child: Row(
        children: [
          Icon(Icons.circle, size: 6, color: Colors.grey[500]),
          const SizedBox(width: 8),
          Text(
            text,
            style: TextStyle(
              fontSize: 14,
              color: Colors.grey[600],
            ),
          ),
        ],
      ),
    );
  }
}