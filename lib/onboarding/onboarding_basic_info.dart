import 'package:flutter/material.dart';
import 'onboarding_username.dart';

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

    if (_nameController.text.isEmpty) {
      nameError = 'Please enter your display name';
    }

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

    setState(() {
      _nameError = nameError;
      _ageError = ageError;
    });

    return nameError == null && ageError == null;
  }

  void _nextPage() {
    if (_validateInputs()) {
      final userData = {
        'display_name': _nameController.text,
        'age': int.parse(_ageController.text),
        'gender': _selectedGender,
      };

      Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => OnboardingUsername(userData: userData),
        ),
      );
    }
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
                value: 0.15,
                backgroundColor: Colors.grey[300],
                valueColor: AlwaysStoppedAnimation<Color>(
                  Theme.of(context).colorScheme.primary,
                ),
              ),
              const SizedBox(height: 32),

              // Title
              const Text(
                'Let\'s get to know you',
                style: TextStyle(
                  fontSize: 28,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 8),
              const Text(
                'This helps us personalize your experience',
                style: TextStyle(
                  fontSize: 16,
                  color: Colors.grey,
                ),
              ),
              const SizedBox(height: 40),

              // Name field
              TextField(
                controller: _nameController,
                onChanged: (_) {
                  if (_nameError != null) setState(() => _nameError = null);
                },
                decoration: InputDecoration(
                  labelText: 'Display Name',
                  hintText: 'What should we call you?',
                  prefixIcon: const Icon(Icons.person_outline),
                  errorText: _nameError,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  filled: true,
                  fillColor: Colors.grey[50],
                ),
              ),
              const SizedBox(height: 20),

              // Age field
              TextField(
                controller: _ageController,
                keyboardType: TextInputType.number,
                onChanged: (_) {
                  if (_ageError != null) setState(() => _ageError = null);
                },
                decoration: InputDecoration(
                  labelText: 'Age',
                  hintText: 'Your age',
                  prefixIcon: const Icon(Icons.cake_outlined),
                  errorText: _ageError,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  filled: true,
                  fillColor: Colors.grey[50],
                ),
              ),
              const SizedBox(height: 20),

              // Gender dropdown
              DropdownButtonFormField<String>(
                value: _selectedGender,
                decoration: InputDecoration(
                  labelText: 'Gender (Optional)',
                  prefixIcon: const Icon(Icons.accessibility),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  filled: true,
                  fillColor: Colors.grey[50],
                ),
                items: _genderOptions.map((String gender) {
                  return DropdownMenuItem<String>(
                    value: gender,
                    child: Text(gender),
                  );
                }).toList(),
                onChanged: (String? newValue) {
                  setState(() {
                    _selectedGender = newValue;
                  });
                },
              ),

              const Spacer(),

              // Navigation buttons
              Row(
                children: [
                  ElevatedButton(
                    onPressed: _nextPage,
                    style: ElevatedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 32,
                        vertical: 12,
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    child: const Row(
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
}