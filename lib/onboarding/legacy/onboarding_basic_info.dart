import 'package:flutter/material.dart';
import 'onboarding_username_avatar.dart';

class OnboardingBasicInfo extends StatefulWidget {
  const OnboardingBasicInfo({super.key});

  @override
  State<OnboardingBasicInfo> createState() => _OnboardingBasicInfoState();
}

class _OnboardingBasicInfoState extends State<OnboardingBasicInfo> {
  final TextEditingController _nameController = TextEditingController();
  final TextEditingController _ageController = TextEditingController();
  String? _selectedGender;
  String? _nameError;
  String? _ageError;

  final List<String> _genderOptions = ['Male', 'Female', 'Other', 'Prefer not to say'];

  bool _validateInputs() {
    String? nameError;
    String? ageError;
    if (_nameController.text.trim().isEmpty) nameError = 'Please enter your display name';
    if (_ageController.text.isEmpty) {
      ageError = 'Please enter your age';
    } else {
      final age = int.tryParse(_ageController.text);
      if (age == null) {
        ageError = 'Please enter a valid number';
      } else if (age < 16) {
        ageError = 'You must be at least 16 years old to use Gym Buddy';
      } else if (age > 120) {
        ageError = 'Please enter a valid age';
      }
    }
    setState(() { _nameError = nameError; _ageError = ageError; });
    return nameError == null && ageError == null;
  }

  void _next() {
    if (_validateInputs()) {
      Navigator.of(context).push(MaterialPageRoute(
        builder: (_) => OnboardingUsernameAvatar(userData: {
          'display_name': _nameController.text.trim(),
          'age': int.parse(_ageController.text),
          'gender': _selectedGender,
        }),
      ));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child: Column(
          children: [
            OnboardingHeader(step: 1, label: 'About You'),
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(24),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const SizedBox(height: 8),
                    const Text('Let\'s get to know you',
                        style: TextStyle(fontSize: 26, fontWeight: FontWeight.bold, color: Color(0xFF1E293B))),
                    const SizedBox(height: 6),
                    Text('This helps us personalize your experience',
                        style: TextStyle(fontSize: 15, color: Colors.grey[500])),
                    const SizedBox(height: 32),
                    OnboardingTextField(
                      label: 'Display Name',
                      controller: _nameController,
                      hint: 'What should we call you?',
                      icon: Icons.person_outline,
                      errorText: _nameError,
                      onChanged: (_) { if (_nameError != null) setState(() => _nameError = null); },
                    ),
                    const SizedBox(height: 20),
                    OnboardingTextField(
                      label: 'Age',
                      controller: _ageController,
                      hint: 'Your age',
                      icon: Icons.cake_outlined,
                      errorText: _ageError,
                      keyboardType: TextInputType.number,
                      onChanged: (_) { if (_ageError != null) setState(() => _ageError = null); },
                    ),
                    const SizedBox(height: 20),
                    const OnboardingLabel(text: 'Gender (Optional)'),
                    const SizedBox(height: 8),
                    DropdownButtonFormField<String>(
                      value: _selectedGender,
                      decoration: onboardingInputDecoration(hint: 'Select gender', icon: Icons.accessibility_outlined),
                      items: _genderOptions.map((g) => DropdownMenuItem(value: g, child: Text(g))).toList(),
                      onChanged: (v) => setState(() => _selectedGender = v),
                    ),
                    const SizedBox(height: 40),
                  ],
                ),
              ),
            ),
            OnboardingBottomNav(onNext: _next),
          ],
        ),
      ),
    );
  }
}

// ============================================================
// SHARED DESIGN COMPONENTS
// ============================================================

const kGradientColors = [Color(0xFF3B82F6), Color(0xFF8B5CF6)];
const kGradient = LinearGradient(colors: kGradientColors);

class OnboardingHeader extends StatelessWidget {
  final int step;
  final String label;

  const OnboardingHeader({super.key, required this.step, required this.label});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(24, 16, 24, 12),
      child: Column(
        children: [
          Row(
            children: List.generate(7, (i) {
              if (i.isEven) {
                final dotStep = (i ~/ 2) + 1;
                return _StepDot(active: dotStep <= step, current: dotStep == step);
              } else {
                final lineStep = (i ~/ 2) + 1;
                return Expanded(child: _StepLine(active: lineStep < step));
              }
            }),
          ),
          const SizedBox(height: 8),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('Step $step of 4', style: TextStyle(fontSize: 12, color: Colors.grey[400])),
              ShaderMask(
                shaderCallback: (bounds) => kGradient.createShader(bounds),
                child: Text(label,
                    style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Colors.white)),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _StepDot extends StatelessWidget {
  final bool active;
  final bool current;
  const _StepDot({required this.active, required this.current});

  @override
  Widget build(BuildContext context) {
    if (active) {
      return Container(
        width: current ? 12 : 10,
        height: current ? 12 : 10,
        decoration: const BoxDecoration(shape: BoxShape.circle, gradient: kGradient),
      );
    }
    return Container(
      width: 10, height: 10,
      decoration: const BoxDecoration(shape: BoxShape.circle, color: Color(0xFFE2E8F0)),
    );
  }
}

class _StepLine extends StatelessWidget {
  final bool active;
  const _StepLine({required this.active});

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 2,
      decoration: BoxDecoration(
        gradient: active ? kGradient : null,
        color: active ? null : const Color(0xFFE2E8F0),
      ),
    );
  }
}

class OnboardingLabel extends StatelessWidget {
  final String text;
  const OnboardingLabel({super.key, required this.text});

  @override
  Widget build(BuildContext context) {
    return Text(text,
        style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: Color(0xFF374151)));
  }
}

class OnboardingTextField extends StatelessWidget {
  final String label;
  final TextEditingController controller;
  final String hint;
  final IconData icon;
  final String? errorText;
  final TextInputType? keyboardType;
  final void Function(String)? onChanged;

  const OnboardingTextField({
    super.key,
    required this.label,
    required this.controller,
    required this.hint,
    required this.icon,
    this.errorText,
    this.keyboardType,
    this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        OnboardingLabel(text: label),
        const SizedBox(height: 8),
        TextField(
          controller: controller,
          keyboardType: keyboardType,
          onChanged: onChanged,
          decoration: onboardingInputDecoration(hint: hint, icon: icon, errorText: errorText),
        ),
      ],
    );
  }
}

InputDecoration onboardingInputDecoration({
  required String hint,
  required IconData icon,
  String? errorText,
}) {
  return InputDecoration(
    hintText: hint,
    hintStyle: TextStyle(color: Colors.grey[400]),
    prefixIcon: Icon(icon, color: const Color(0xFF6B7280), size: 20),
    errorText: errorText,
    filled: true,
    fillColor: const Color(0xFFF8FAFC),
    border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: Color(0xFFE2E8F0))),
    enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: Color(0xFFE2E8F0))),
    focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: Color(0xFF3B82F6), width: 2)),
    errorBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: Colors.red)),
    focusedErrorBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: Colors.red, width: 2)),
    contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
  );
}

class OnboardingBottomNav extends StatelessWidget {
  final VoidCallback? onBack;
  final VoidCallback? onNext;
  final Widget? nextChild;
  final bool isLoading;

  const OnboardingBottomNav({
    super.key,
    this.onBack,
    this.onNext,
    this.nextChild,
    this.isLoading = false,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(24, 12, 24, 24),
      decoration: BoxDecoration(
        color: Colors.white,
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.06), blurRadius: 10, offset: const Offset(0, -4))],
      ),
      child: Row(
        children: [
          if (onBack != null)
            TextButton.icon(
              onPressed: onBack,
              icon: Icon(Icons.arrow_back, size: 18, color: Colors.grey[500]),
              label: Text('Back', style: TextStyle(color: Colors.grey[500], fontSize: 15)),
            ),
          const Spacer(),
          Container(
            decoration: BoxDecoration(
              gradient: kGradient,
              borderRadius: BorderRadius.circular(12),
              boxShadow: [BoxShadow(color: const Color(0xFF3B82F6).withOpacity(0.3), blurRadius: 12, offset: const Offset(0, 4))],
            ),
            child: ElevatedButton(
              onPressed: isLoading ? null : onNext,
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.transparent,
                shadowColor: Colors.transparent,
                padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 14),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
              child: isLoading
                  ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                  : nextChild ?? const Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text('Next', style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w600)),
                        SizedBox(width: 8),
                        Icon(Icons.arrow_forward, color: Colors.white, size: 18),
                      ],
                    ),
            ),
          ),
        ],
      ),
    );
  }
}