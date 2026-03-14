import 'package:flutter/material.dart';
import 'onboarding_basic_info.dart';
import 'onboarding_buddy_preferences.dart';

class OnboardingGoals extends StatefulWidget {
  final Map<String, dynamic> userData;
  const OnboardingGoals({super.key, required this.userData});

  @override
  State<OnboardingGoals> createState() => _OnboardingGoalsState();
}

class _OnboardingGoalsState extends State<OnboardingGoals> {
  final List<String> _selectedGoals = [];
  String _fitnessLevel = 'beginner';
  String? _goalsError;

  final List<Map<String, dynamic>> _goals = [
    {'title': 'Build Muscle', 'emoji': '💪', 'value': 'build_muscle'},
    {'title': 'Lose Weight', 'emoji': '🔥', 'value': 'lose_weight'},
    {'title': 'Endurance', 'emoji': '🏃', 'value': 'improve_endurance'},
    {'title': 'Get Stronger', 'emoji': '🏋️', 'value': 'increase_strength'},
    {'title': 'Stay Active', 'emoji': '⚡', 'value': 'stay_active'},
    {'title': 'Train for Event', 'emoji': '🏆', 'value': 'train_for_event'},
  ];

  final List<Map<String, dynamic>> _levels = [
    {'label': 'Beginner', 'value': 'beginner', 'desc': 'New to working out or returning after a break'},
    {'label': 'Intermediate', 'value': 'intermediate', 'desc': 'Work out regularly, familiar with exercises'},
    {'label': 'Advanced', 'value': 'advanced', 'desc': 'Experienced, looking for challenging workouts'},
  ];

  void _toggleGoal(String goal) {
    setState(() {
      if (_selectedGoals.contains(goal)) {
        _selectedGoals.remove(goal);
      } else {
        _selectedGoals.add(goal);
      }
      if (_selectedGoals.isNotEmpty) _goalsError = null;
    });
  }

  void _next() {
    if (_selectedGoals.isEmpty) {
      setState(() => _goalsError = 'Please select at least one goal');
      return;
    }
    widget.userData['fitness_goals'] = _selectedGoals;
    widget.userData['fitness_level'] = _fitnessLevel;
    Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => OnboardingBuddyPreferences(userData: widget.userData),
    ));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child: Column(
          children: [
            const OnboardingHeader(step: 3, label: 'Your Goals'),
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(24),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const SizedBox(height: 8),
                    const Text('What are you training for?',
                        style: TextStyle(fontSize: 26, fontWeight: FontWeight.bold, color: Color(0xFF1E293B))),
                    const SizedBox(height: 6),
                    Text('Select all that apply',
                        style: TextStyle(fontSize: 15, color: Colors.grey[500])),
                    const SizedBox(height: 24),

                    // Goals grid
                    GridView.builder(
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                        crossAxisCount: 2,
                        crossAxisSpacing: 12,
                        mainAxisSpacing: 12,
                        childAspectRatio: 1.6,
                      ),
                      itemCount: _goals.length,
                      itemBuilder: (context, index) {
                        final goal = _goals[index];
                        final isSelected = _selectedGoals.contains(goal['value']);
                        return GestureDetector(
                          onTap: () => _toggleGoal(goal['value']),
                          child: AnimatedContainer(
                            duration: const Duration(milliseconds: 200),
                            decoration: BoxDecoration(
                              color: isSelected ? const Color(0xFFEFF6FF) : const Color(0xFFF8FAFC),
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(
                                color: isSelected ? const Color(0xFF3B82F6) : const Color(0xFFE2E8F0),
                                width: isSelected ? 2 : 1,
                              ),
                            ),
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Text(goal['emoji']!, style: const TextStyle(fontSize: 22)),
                                const SizedBox(width: 8),
                                Flexible(
                                  child: Text(
                                    goal['title']!,
                                    style: TextStyle(
                                      fontSize: 13,
                                      fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
                                      color: isSelected ? const Color(0xFF1D4ED8) : const Color(0xFF374151),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        );
                      },
                    ),

                    if (_goalsError != null) ...[
                      const SizedBox(height: 8),
                      Text(_goalsError!, style: const TextStyle(color: Colors.red, fontSize: 13)),
                    ],

                    const SizedBox(height: 32),

                    // Fitness level
                    const OnboardingLabel(text: 'Fitness Level'),
                    const SizedBox(height: 12),
                    ..._levels.map((level) {
                      final isSelected = _fitnessLevel == level['value'];
                      return Padding(
                        padding: const EdgeInsets.only(bottom: 10),
                        child: GestureDetector(
                          onTap: () => setState(() => _fitnessLevel = level['value']),
                          child: AnimatedContainer(
                            duration: const Duration(milliseconds: 200),
                            padding: const EdgeInsets.all(16),
                            decoration: BoxDecoration(
                              color: isSelected ? const Color(0xFFEFF6FF) : const Color(0xFFF8FAFC),
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(
                                color: isSelected ? const Color(0xFF3B82F6) : const Color(0xFFE2E8F0),
                                width: isSelected ? 2 : 1,
                              ),
                            ),
                            child: Row(
                              children: [
                                Container(
                                  width: 20,
                                  height: 20,
                                  decoration: BoxDecoration(
                                    shape: BoxShape.circle,
                                    border: Border.all(
                                      color: isSelected ? const Color(0xFF3B82F6) : const Color(0xFFD1D5DB),
                                      width: 2,
                                    ),
                                  ),
                                  child: isSelected
                                      ? Center(
                                          child: Container(
                                            width: 10, height: 10,
                                            decoration: const BoxDecoration(shape: BoxShape.circle, color: Color(0xFF3B82F6)),
                                          ),
                                        )
                                      : null,
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(level['label']!,
                                          style: TextStyle(
                                            fontSize: 15,
                                            fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
                                            color: isSelected ? const Color(0xFF1D4ED8) : const Color(0xFF374151),
                                          )),
                                      const SizedBox(height: 2),
                                      Text(level['desc']!,
                                          style: TextStyle(fontSize: 12, color: Colors.grey[500])),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      );
                    }).toList(),
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
}