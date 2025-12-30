import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../home_screen.dart';
import '../services/coach_max_service.dart';

class OnboardingBuddyPreferences extends StatefulWidget {
  final Map<String, dynamic> userData;
  
  const OnboardingBuddyPreferences({
    super.key,
    required this.userData,
  });

  @override
  State<OnboardingBuddyPreferences> createState() => _OnboardingBuddyPreferencesState();
}

class _OnboardingBuddyPreferencesState extends State<OnboardingBuddyPreferences> {
  final CoachMaxService _coachMaxService = CoachMaxService();
  bool _lookingForBuddy = true;
  String _workoutStyle = 'both';
  bool _openToGroups = false;
  bool _isLoading = false;

  final List<String> _styleOptions = ['weights', 'cardio', 'both'];

  Future<void> _completeOnboarding() async {
    // Add buddy preferences to user data
    widget.userData['looking_for_buddy'] = _lookingForBuddy;
    widget.userData['preferred_workout_style'] = _workoutStyle;
    widget.userData['open_to_groups'] = _openToGroups;

    setState(() {
      _isLoading = true;
    });

    try {
      // Get current user
      final user = Supabase.instance.client.auth.currentUser;
      if (user == null) {
        throw Exception('No user logged in');
      }

      // ✅ CRITICAL: Save all user data + mark onboarding as complete
      // Now includes username!
      await Supabase.instance.client.from('user_profiles').upsert({
        'id': user.id,
        'display_name': widget.userData['display_name'],
        'username': widget.userData['username'],  // ✅ NEW: Save username
        'age': widget.userData['age'],
        'gender': widget.userData['gender'],
        'avatar_id': widget.userData['avatar_id'],
        'fitness_goals': widget.userData['fitness_goals'],
        'workout_days_per_week': widget.userData['workout_days_per_week'],
        'preferred_workout_time': widget.userData['preferred_workout_time'],
        'fitness_level': widget.userData['fitness_level'],
        'looking_for_buddy': _lookingForBuddy,
        'onboarding_completed': true,
        'updated_at': DateTime.now().toIso8601String(),
      });

      // Initialize Coach Max
      final coachMaxSuccess = await _coachMaxService.initializeCoachMaxForUser(user.id);
      if (!coachMaxSuccess) {
        throw Exception('Failed to initialize Coach Max');
      }

      // Navigate to home screen
      if (mounted) {
        Navigator.of(context).pushAndRemoveUntil(
          MaterialPageRoute(builder: (_) => const HomeScreen()),
          (route) => false,
        );
        
        // Show welcome message with Coach Max
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(_coachMaxService.getMotivationalMessage(
              currentStreak: 0,
              hasCheckedInToday: false,
              messageType: null,
            )),
            backgroundColor: Colors.green,
            duration: const Duration(seconds: 4),
          ),
        );
      }
    } catch (e) {
      // Show error
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error saving profile: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
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
                value: 1.0,
                backgroundColor: Colors.grey[300],
                valueColor: AlwaysStoppedAnimation<Color>(
                  Theme.of(context).colorScheme.primary,
                ),
              ),
              const SizedBox(height: 32),
              
              // Title
              const Text(
                'Find your perfect gym buddy',
                style: TextStyle(
                  fontSize: 28,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 8),
              const Text(
                'Last step! Tell us about your buddy preferences',
                style: TextStyle(
                  fontSize: 16,
                  color: Colors.grey,
                ),
              ),
              const SizedBox(height: 40),
              
              // Looking for buddy toggle
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.grey[50],
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Looking for a gym buddy?',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                        SizedBox(height: 4),
                        Text(
                          'We\'ll help you find workout partners',
                          style: TextStyle(
                            fontSize: 14,
                            color: Colors.grey,
                          ),
                        ),
                      ],
                    ),
                    Switch(
                      value: _lookingForBuddy,
                      onChanged: (value) {
                        setState(() => _lookingForBuddy = value);
                      },
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 24),
              
              // Workout style preference
              AnimatedOpacity(
                opacity: _lookingForBuddy ? 1.0 : 0.5,
                duration: const Duration(milliseconds: 200),
                child: IgnorePointer(
                  ignoring: !_lookingForBuddy,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Preferred workout style',
                        style: TextStyle(fontSize: 16, fontWeight: FontWeight.w500),
                      ),
                      const SizedBox(height: 12),
                      Row(
                        children: _styleOptions.map((style) {
                          final isSelected = _workoutStyle == style;
                          return Expanded(
                            child: Padding(
                              padding: const EdgeInsets.symmetric(horizontal: 4),
                              child: ChoiceChip(
                                label: Text(
                                  style[0].toUpperCase() + style.substring(1),
                                  style: const TextStyle(fontSize: 14),
                                ),
                                selected: isSelected,
                                onSelected: (selected) {
                                  if (selected) {
                                    setState(() => _workoutStyle = style);
                                  }
                                },
                              ),
                            ),
                          );
                        }).toList(),
                      ),
                      const SizedBox(height: 24),
                      
                      // Open to groups toggle
                      Container(
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: Colors.grey[50],
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            const Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'Open to group workouts?',
                                  style: TextStyle(
                                    fontSize: 16,
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                                SizedBox(height: 4),
                                Text(
                                  'Work out with multiple people',
                                  style: TextStyle(
                                    fontSize: 14,
                                    color: Colors.grey,
                                  ),
                                ),
                              ],
                            ),
                            Switch(
                              value: _openToGroups,
                              onChanged: (value) {
                                setState(() => _openToGroups = value);
                              },
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              
              const Spacer(),
              
              // Motivational message
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.blue[50],
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Row(
                  children: [
                    Icon(
                      Icons.rocket_launch,
                      color: Colors.blue[700],
                      size: 32,
                    ),
                    const SizedBox(width: 16),
                    const Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'You\'re all set!',
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          Text(
                            'Coach Max will be your training buddy!',
                            style: TextStyle(
                              fontSize: 14,
                              color: Colors.grey,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 24),
              
              // Navigation buttons
              Row(
                children: [
                  TextButton(
                    onPressed: _isLoading ? null : _previousPage,
                    child: const Text('Back'),
                  ),
                  const Spacer(),
                  ElevatedButton(
                    onPressed: _isLoading ? null : _completeOnboarding,
                    style: ElevatedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 32,
                        vertical: 12,
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      backgroundColor: Colors.green,
                    ),
                    child: _isLoading
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
                            Text('Complete Setup'),
                            SizedBox(width: 8),
                            Icon(Icons.check, size: 18),
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