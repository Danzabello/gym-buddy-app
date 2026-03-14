import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../home_screen.dart';
import '../services/coach_max_service.dart';
import 'onboarding_basic_info.dart';

class OnboardingBuddyPreferences extends StatefulWidget {
  final Map<String, dynamic> userData;
  const OnboardingBuddyPreferences({super.key, required this.userData});

  @override
  State<OnboardingBuddyPreferences> createState() => _OnboardingBuddyPreferencesState();
}

class _OnboardingBuddyPreferencesState extends State<OnboardingBuddyPreferences> {
  final CoachMaxService _coachMaxService = CoachMaxService();
  bool _lookingForBuddy = true;
  String _workoutStyle = 'both';
  bool _isLoading = false;

  final List<Map<String, String>> _styleOptions = [
    {'value': 'weights', 'label': 'Weights', 'emoji': '🏋️'},
    {'value': 'cardio', 'label': 'Cardio', 'emoji': '🏃'},
    {'value': 'both', 'label': 'Both', 'emoji': '⚡'},
  ];

  Future<void> _complete() async {
    setState(() => _isLoading = true);
    try {
      final user = Supabase.instance.client.auth.currentUser;
      if (user == null) throw Exception('No user logged in');

      await Supabase.instance.client.from('user_profiles').upsert({
        'id': user.id,
        'display_name': widget.userData['display_name'],
        'username': widget.userData['username'],
        'age': widget.userData['age'],
        'gender': widget.userData['gender'],
        'avatar_id': widget.userData['avatar_id'],
        'fitness_goals': widget.userData['fitness_goals'],
        'fitness_level': widget.userData['fitness_level'],
        'looking_for_buddy': _lookingForBuddy,
        'preferred_workout_style': _workoutStyle,
        'onboarding_completed': true,
        'updated_at': DateTime.now().toIso8601String(),
      });

      final coachMaxSuccess = await _coachMaxService.initializeCoachMaxForUser(user.id);
      if (!coachMaxSuccess) throw Exception('Failed to initialize Coach Max');

      if (mounted) {
        Navigator.of(context).pushAndRemoveUntil(
          MaterialPageRoute(builder: (_) => const HomeScreen()),
          (route) => false,
        );
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(_coachMaxService.getMotivationalMessage(currentStreak: 0, hasCheckedInToday: false)),
            backgroundColor: const Color(0xFF10B981),
            duration: const Duration(seconds: 4),
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error saving profile: $e'), backgroundColor: Colors.red),
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
      body: SafeArea(
        child: Column(
          children: [
            const OnboardingHeader(step: 4, label: 'Final Step'),
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(24),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const SizedBox(height: 8),
                    const Text('Find your gym buddy',
                        style: TextStyle(fontSize: 26, fontWeight: FontWeight.bold, color: Color(0xFF1E293B))),
                    const SizedBox(height: 6),
                    Text('Tell us about your workout preferences',
                        style: TextStyle(fontSize: 15, color: Colors.grey[500])),
                    const SizedBox(height: 32),

                    // Looking for buddy toggle
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: const Color(0xFFF8FAFC),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: const Color(0xFFE2E8F0)),
                      ),
                      child: Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.all(10),
                            decoration: BoxDecoration(
                              color: const Color(0xFFEFF6FF),
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: const Text('🤝', style: TextStyle(fontSize: 22)),
                          ),
                          const SizedBox(width: 12),
                          const Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text('Looking for a gym buddy?',
                                    style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: Color(0xFF1E293B))),
                                SizedBox(height: 2),
                                Text('We\'ll help you find workout partners',
                                    style: TextStyle(fontSize: 12, color: Color(0xFF6B7280))),
                              ],
                            ),
                          ),
                          Switch(
                            value: _lookingForBuddy,
                            onChanged: (v) => setState(() => _lookingForBuddy = v),
                            activeColor: const Color(0xFF3B82F6),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 24),

                    // Workout style
                    AnimatedOpacity(
                      opacity: _lookingForBuddy ? 1.0 : 0.4,
                      duration: const Duration(milliseconds: 200),
                      child: IgnorePointer(
                        ignoring: !_lookingForBuddy,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const OnboardingLabel(text: 'Preferred Workout Style'),
                            const SizedBox(height: 12),
                            Row(
                              children: _styleOptions.map((style) {
                                final isSelected = _workoutStyle == style['value'];
                                return Expanded(
                                  child: Padding(
                                    padding: EdgeInsets.only(right: style['value'] != 'both' ? 8 : 0),
                                    child: GestureDetector(
                                      onTap: () => setState(() => _workoutStyle = style['value']!),
                                      child: AnimatedContainer(
                                        duration: const Duration(milliseconds: 200),
                                        padding: const EdgeInsets.symmetric(vertical: 14),
                                        decoration: BoxDecoration(
                                          color: isSelected ? const Color(0xFFEFF6FF) : const Color(0xFFF8FAFC),
                                          borderRadius: BorderRadius.circular(12),
                                          border: Border.all(
                                            color: isSelected ? const Color(0xFF3B82F6) : const Color(0xFFE2E8F0),
                                            width: isSelected ? 2 : 1,
                                          ),
                                        ),
                                        child: Column(
                                          children: [
                                            Text(style['emoji']!, style: const TextStyle(fontSize: 22)),
                                            const SizedBox(height: 4),
                                            Text(style['label']!,
                                                style: TextStyle(
                                                  fontSize: 13,
                                                  fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
                                                  color: isSelected ? const Color(0xFF1D4ED8) : const Color(0xFF374151),
                                                )),
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

                    const SizedBox(height: 32),

                    // You're all set card
                    Container(
                      padding: const EdgeInsets.all(20),
                      decoration: BoxDecoration(
                        gradient: const LinearGradient(
                          colors: [Color(0xFFEFF6FF), Color(0xFFF5F3FF)],
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                        ),
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: const Color(0xFFBFDBFE)),
                      ),
                      child: Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              gradient: kGradient,
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: const Text('🤖', style: TextStyle(fontSize: 24)),
                          ),
                          const SizedBox(width: 16),
                          const Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text('You\'re all set!',
                                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Color(0xFF1E293B))),
                                SizedBox(height: 4),
                                Text('Coach Max will be your training buddy from day one!',
                                    style: TextStyle(fontSize: 13, color: Color(0xFF6B7280))),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 40),
                  ],
                ),
              ),
            ),
            OnboardingBottomNav(
              onBack: () => Navigator.of(context).pop(),
              onNext: _complete,
              isLoading: _isLoading,
              nextChild: const Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text('Let\'s Go!', style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w600)),
                  SizedBox(width: 8),
                  Icon(Icons.rocket_launch, color: Colors.white, size: 18),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}