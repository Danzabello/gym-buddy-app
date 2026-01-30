import 'onboarding_workout_schedule.dart';
import 'package:flutter/material.dart';

class OnboardingFitnessGoals extends StatefulWidget {
  final Map<String, dynamic> userData;
  
  const OnboardingFitnessGoals({
    super.key,
    required this.userData,
  });

  @override
  State<OnboardingFitnessGoals> createState() => _OnboardingFitnessGoalsState();
}

class _OnboardingFitnessGoalsState extends State<OnboardingFitnessGoals> {
  final List<String> _selectedGoals = [];
  
  final List<Map<String, dynamic>> _fitnessGoals = [
    {'title': 'Build Muscle', 'icon': Icons.fitness_center, 'value': 'build_muscle'},
    {'title': 'Lose Weight', 'icon': Icons.trending_down, 'value': 'lose_weight'},
    {'title': 'Improve Endurance', 'icon': Icons.directions_run, 'value': 'improve_endurance'},
    {'title': 'Increase Strength', 'icon': Icons.sports_martial_arts, 'value': 'increase_strength'},
    {'title': 'Stay Active', 'icon': Icons.accessibility_new, 'value': 'stay_active'},
    {'title': 'Train for Event', 'icon': Icons.emoji_events, 'value': 'train_for_event'},
  ];

  void _toggleGoal(String goal) {
    setState(() {
      if (_selectedGoals.contains(goal)) {
        _selectedGoals.remove(goal);
      } else {
        _selectedGoals.add(goal);
      }
    });
  }

  void _nextPage() {
    if (_selectedGoals.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please select at least one fitness goal')),
      );
      return;
    }

    // Add fitness goals to user data
    widget.userData['fitness_goals'] = _selectedGoals;

    // Navigate to workout schedule screen
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => OnboardingWorkoutSchedule(userData: widget.userData),
      ),
    );
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
                value: 0.5,
                backgroundColor: Colors.grey[300],
                valueColor: AlwaysStoppedAnimation<Color>(
                  Theme.of(context).colorScheme.primary,
                ),
              ),
              const SizedBox(height: 32),
              
              // Title
              const Text(
                'What are your fitness goals?',
                style: TextStyle(
                  fontSize: 28,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 8),
              const Text(
                'Select all that apply',
                style: TextStyle(
                  fontSize: 16,
                  color: Colors.grey,
                ),
              ),
              const SizedBox(height: 32),
              
              // Goals Grid
              Expanded(
                child: GridView.builder(
                  gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 2,
                    childAspectRatio: 1.3,
                    crossAxisSpacing: 16,
                    mainAxisSpacing: 16,
                  ),
                  itemCount: _fitnessGoals.length,
                  itemBuilder: (context, index) {
                    final goal = _fitnessGoals[index];
                    final isSelected = _selectedGoals.contains(goal['value']);
                    
                    return GestureDetector(
                      onTap: () => _toggleGoal(goal['value']),
                      child: Container(
                        decoration: BoxDecoration(
                          color: isSelected 
                            ? Theme.of(context).colorScheme.primary.withOpacity(0.1)
                            : Colors.grey[50],
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(
                            color: isSelected
                              ? Theme.of(context).colorScheme.primary
                              : Colors.grey[300]!,
                            width: 2,
                          ),
                        ),
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(
                              goal['icon'],
                              size: 40,
                              color: isSelected
                                ? Theme.of(context).colorScheme.primary
                                : Colors.grey[600],
                            ),
                            const SizedBox(height: 8),
                            Text(
                              goal['title'],
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                fontSize: 14,
                                fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                                color: isSelected
                                  ? Theme.of(context).colorScheme.primary
                                  : Colors.grey[800],
                              ),
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
              ),
              
              const SizedBox(height: 24),
              
              // Navigation buttons
              Row(
                children: [
                  TextButton(
                    onPressed: _previousPage,
                    child: const Text('Back'),
                  ),
                  const Spacer(),
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


