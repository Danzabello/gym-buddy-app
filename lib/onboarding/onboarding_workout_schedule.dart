import 'onboarding_buddy_preferences.dart';
import 'package:flutter/material.dart';

class OnboardingWorkoutSchedule extends StatefulWidget {
  final Map<String, dynamic> userData;
  
  const OnboardingWorkoutSchedule({
    super.key,
    required this.userData,
  });

  @override
  State<OnboardingWorkoutSchedule> createState() => _OnboardingWorkoutScheduleState();
}

class _OnboardingWorkoutScheduleState extends State<OnboardingWorkoutSchedule> {
  int _workoutDaysPerWeek = 3;
  String _preferredTime = 'morning';
  String _fitnessLevel = 'beginner';

  final List<String> _timeOptions = ['morning', 'afternoon', 'evening', 'flexible'];
  final List<String> _levelOptions = ['beginner', 'intermediate', 'advanced'];

  void _nextPage() {
    // Add workout preferences to user data
    widget.userData['workout_days_per_week'] = _workoutDaysPerWeek;
    widget.userData['preferred_workout_time'] = _preferredTime;
    widget.userData['fitness_level'] = _fitnessLevel;

    // Navigate to buddy preferences screen
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => OnboardingBuddyPreferences(userData: widget.userData),
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
        // ✅ FIX: Wrap entire content in SingleChildScrollView
        child: SingleChildScrollView(
          child: Padding(
            padding: const EdgeInsets.all(24.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Progress indicator
                LinearProgressIndicator(
                  value: 0.75,
                  backgroundColor: Colors.grey[300],
                  valueColor: AlwaysStoppedAnimation<Color>(
                    Theme.of(context).colorScheme.primary,
                  ),
                ),
                const SizedBox(height: 32),
                
                // Title
                const Text(
                  'Plan your workout schedule',
                  style: TextStyle(
                    fontSize: 28,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 8),
                const Text(
                  'We\'ll help you stay consistent',
                  style: TextStyle(
                    fontSize: 16,
                    color: Colors.grey,
                  ),
                ),
                const SizedBox(height: 40),
                
                // Days per week selector
                const Text(
                  'How many days per week do you want to work out?',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.w500),
                ),
                const SizedBox(height: 16),
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Colors.grey[50],
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Column(
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          IconButton(
                            onPressed: _workoutDaysPerWeek > 1 
                              ? () => setState(() => _workoutDaysPerWeek--) 
                              : null,
                            icon: const Icon(Icons.remove_circle_outline),
                          ),
                          const SizedBox(width: 24),
                          Text(
                            '$_workoutDaysPerWeek',
                            style: const TextStyle(
                              fontSize: 36,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const SizedBox(width: 24),
                          IconButton(
                            onPressed: _workoutDaysPerWeek < 7
                              ? () => setState(() => _workoutDaysPerWeek++)
                              : null,
                            icon: const Icon(Icons.add_circle_outline),
                          ),
                        ],
                      ),
                      Text(
                        _workoutDaysPerWeek == 1 ? 'day per week' : 'days per week',
                        style: TextStyle(color: Colors.grey[600]),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 32),
                
                // Preferred time selector
                const Text(
                  'When do you prefer to work out?',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.w500),
                ),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 12,
                  children: _timeOptions.map((time) {
                    final isSelected = _preferredTime == time;
                    return ChoiceChip(
                      label: Text(
                        time[0].toUpperCase() + time.substring(1),
                      ),
                      selected: isSelected,
                      onSelected: (selected) {
                        if (selected) {
                          setState(() => _preferredTime = time);
                        }
                      },
                    );
                  }).toList(),
                ),
                const SizedBox(height: 32),
                
                // Fitness level selector
                const Text(
                  'What\'s your current fitness level?',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.w500),
                ),
                const SizedBox(height: 12),
                ..._levelOptions.map((level) {
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: RadioListTile<String>(
                      title: Text(level[0].toUpperCase() + level.substring(1)),
                      subtitle: Text(_getLevelDescription(level)),
                      value: level,
                      groupValue: _fitnessLevel,
                      onChanged: (value) {
                        if (value != null) {
                          setState(() => _fitnessLevel = value);
                        }
                      },
                      contentPadding: const EdgeInsets.symmetric(horizontal: 16),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                        side: BorderSide(
                          color: _fitnessLevel == level 
                            ? Theme.of(context).colorScheme.primary 
                            : Colors.grey[300]!,
                        ),
                      ),
                    ),
                  );
                }).toList(),
                
                // ✅ FIX: Changed Spacer to SizedBox for ScrollView compatibility
                const SizedBox(height: 40),
                
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
      ),
    );
  }

  String _getLevelDescription(String level) {
    switch (level) {
      case 'beginner':
        return 'New to working out or returning after a break';
      case 'intermediate':
        return 'Work out regularly, familiar with exercises';
      case 'advanced':
        return 'Experienced, looking for challenging workouts';
      default:
        return '';
    }
  }
}