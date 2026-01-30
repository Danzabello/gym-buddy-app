import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../services/workout_service.dart';
import 'dart:async';

/// Workout timer sheet for check-ins
/// Tracks workout duration based on user's selected goal
class WorkoutCheckInSheet extends StatefulWidget {
  final VoidCallback onCheckInComplete;
  final String? workoutType;
  final String? workoutEmoji;
  final int? plannedDuration;

  const WorkoutCheckInSheet({
    super.key,
    required this.onCheckInComplete,
    this.workoutType,
    this.workoutEmoji,
    this.plannedDuration,
  });

  /// Show as a bottom sheet
  static Future<bool?> show(
    BuildContext context, {
    required Future<void> Function() onCheckInComplete,
    String? workoutType,
    String? workoutEmoji,
    int? plannedDuration,
  }) async {
    return showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      isDismissible: true,
      enableDrag: true,
      backgroundColor: Colors.transparent,
      builder: (context) => WorkoutCheckInSheet(
        onCheckInComplete: onCheckInComplete,
        workoutType: workoutType,
        workoutEmoji: workoutEmoji,
        plannedDuration: plannedDuration,
      ),
    );
  }

  /// Static method to check if there's an active workout session
  /// Returns the session data if exists, null otherwise
  static Future<Map<String, dynamic>?> getActiveSession() async {
    final userId = Supabase.instance.client.auth.currentUser?.id;
    if (userId == null) return null;

    try {
      final existing = await Supabase.instance.client
          .from('active_checkin_sessions')
          .select()
          .eq('user_id', userId)
          .maybeSingle();

      return existing;
    } catch (e) {
      print('❌ Error checking active session: $e');
      return null;
    }
  }

  @override
  State<WorkoutCheckInSheet> createState() => _WorkoutCheckInSheetState();
}

class _WorkoutCheckInSheetState extends State<WorkoutCheckInSheet>
    with WidgetsBindingObserver {
  DateTime? _workoutStartTime;
  Timer? _timer;
  Duration _elapsed = Duration.zero;
  bool _isCompleting = false;

  // For background tracking
  DateTime? _pausedAt;

  // Motivational messages that rotate
  int _currentMessageIndex = 0;

  static const List<Map<String, String>> _motivationalMessages = [
    {'emoji': '💪', 'text': 'Keep pushing! Every minute counts towards your streak.'},
    {'emoji': '🔥', 'text': 'You\'re on fire! Stay strong and keep moving.'},
    {'emoji': '⚡', 'text': 'Energy flows where focus goes. You got this!'},
    {'emoji': '🏋️', 'text': 'Champions are made when no one is watching.'},
    {'emoji': '💯', 'text': 'Give it 100%! Your future self will thank you.'},
    {'emoji': '🚀', 'text': 'Launch yourself towards your goals!'},
    {'emoji': '🎯', 'text': 'Stay focused. Every rep counts.'},
    {'emoji': '👊', 'text': 'Punch through! Strength awaits.'},
    {'emoji': '🌟', 'text': 'You\'re a star in the making!'},
    {'emoji': '🦁', 'text': 'Unleash the beast!'},
  ];

  static const List<Map<String, String>> _completedMessages = [
    {'emoji': '🔥', 'text': 'Goal reached! Amazing work!'},
    {'emoji': '🎉', 'text': 'You crushed your goal!'},
    {'emoji': '👑', 'text': 'Royalty! Goal completed!'},
    {'emoji': '🏅', 'text': 'Medal-worthy performance!'},
    {'emoji': '💪', 'text': 'Beast mode complete!'},
    {'emoji': '⭐', 'text': 'Superstar! Goal smashed!'},
  ];

  int get _goalMinutes => widget.plannedDuration ?? 30;
  bool get _hasReachedGoal => _elapsed.inMinutes >= _goalMinutes;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _currentMessageIndex =
        DateTime.now().millisecondsSinceEpoch % _motivationalMessages.length;
    _checkExistingWorkout();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _timer?.cancel();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused) {
      _pausedAt = DateTime.now();
      _timer?.cancel();
    } else if (state == AppLifecycleState.resumed) {
      if (_workoutStartTime != null) {
        _updateElapsedTime();
        _startTimer();
      }
    }
  }

  Future<void> _checkExistingWorkout() async {
    final userId = Supabase.instance.client.auth.currentUser?.id;
    if (userId == null) return;

    try {
      final existing = await Supabase.instance.client
          .from('active_checkin_sessions')
          .select()
          .eq('user_id', userId)
          .maybeSingle();

      if (existing != null && existing['started_at'] != null) {
        _workoutStartTime = DateTime.parse(existing['started_at']);
        _updateElapsedTime();
        _startTimer();

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Row(
                children: [
                  const Icon(Icons.play_arrow, color: Colors.white),
                  const SizedBox(width: 12),
                  Text('Resumed from ${_formatTime(_workoutStartTime!)}'),
                ],
              ),
              backgroundColor: Colors.blue[600],
              duration: const Duration(seconds: 2),
              behavior: SnackBarBehavior.floating,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
          );
        }
      } else {
        _startNewWorkout();
      }
    } catch (e) {
      print('❌ Error checking existing workout: $e');
      _startNewWorkout();
    }
  }

  Future<void> _startNewWorkout() async {
    final userId = Supabase.instance.client.auth.currentUser?.id;
    if (userId == null) return;

    _workoutStartTime = DateTime.now();

    try {
      // Save workout session WITH workout details for resume functionality
      await Supabase.instance.client.from('active_checkin_sessions').upsert({
        'user_id': userId,
        'started_at': _workoutStartTime!.toIso8601String(),
        'workout_type': widget.workoutType,
        'workout_emoji': widget.workoutEmoji,
        'planned_duration': widget.plannedDuration,
      });
    } catch (e) {
      print('❌ Error saving workout session: $e');
    }

    _startTimer();
  }

  void _startTimer() {
    _timer?.cancel();
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      _updateElapsedTime();
    });
  }

  void _updateElapsedTime() {
    if (_workoutStartTime == null) return;

    final newElapsed = DateTime.now().difference(_workoutStartTime!);
    final newMessageIndex =
        (newElapsed.inSeconds ~/ 300) % _motivationalMessages.length;

    setState(() {
      _elapsed = newElapsed;
      if (newMessageIndex != _currentMessageIndex) {
        _currentMessageIndex = newMessageIndex;
      }
    });
  }

  Future<void> _completeCheckIn() async {
    if (_isCompleting) return;

    setState(() => _isCompleting = true);
    HapticFeedback.heavyImpact();

    final userId = Supabase.instance.client.auth.currentUser?.id;
    if (userId == null) {
      setState(() => _isCompleting = false);
      return;
    }

    try {
      // Clear the active session
      await Supabase.instance.client
          .from('active_checkin_sessions')
          .delete()
          .eq('user_id', userId);

      // Call the check-in callback - this triggers the streak update
      widget.onCheckInComplete();

      if (mounted) {
        Navigator.pop(context, true);
      }
    } catch (e) {
      print('❌ Error completing check-in: $e');
      setState(() => _isCompleting = false);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error completing check-in: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Future<void> _cancelWorkout() async {
    final userId = Supabase.instance.client.auth.currentUser?.id;
    if (userId == null) return;

    // ✅ FIRST: Check if this is a buddy workout by looking for workout_id
    String? workoutId;
    bool isBuddyWorkout = false;
    
    try {
      final session = await Supabase.instance.client
          .from('active_checkin_sessions')
          .select('workout_id')
          .eq('user_id', userId)
          .maybeSingle();
      
      workoutId = session?['workout_id'];
      isBuddyWorkout = workoutId != null;
    } catch (e) {
      print('⚠️ Could not check workout type: $e');
    }

    // ✅ Show context-appropriate dialog
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Row(
          children: [
            Icon(Icons.warning_amber_rounded, color: Colors.orange[700], size: 28),
            const SizedBox(width: 12),
            const Text('Cancel Workout?'),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'You\'ve been working out for ${_formatDuration(_elapsed)}.',
              style: const TextStyle(fontSize: 15),
            ),
            const SizedBox(height: 12),
            Text(
              isBuddyWorkout
                  ? 'If you cancel now, this progress won\'t count towards YOUR streak.'
                  : 'If you cancel now, this progress won\'t count towards your streak.',
              style: TextStyle(fontSize: 14, color: Colors.grey[600]),
            ),
            // ✅ Only show buddy message for buddy workouts
            if (isBuddyWorkout) ...[
              const SizedBox(height: 8),
              Text(
                'Your buddy can still complete their workout.',
                style: TextStyle(fontSize: 13, color: Colors.blue[600], fontStyle: FontStyle.italic),
              ),
            ],
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Keep Going'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: Text(isBuddyWorkout ? 'Cancel My Workout' : 'Cancel Workout'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      // Cancel the workout
      if (workoutId != null) {
        // Buddy workout - use fair cancel logic
        final workoutService = WorkoutService();
        await workoutService.cancelWorkout(workoutId);
      } else {
        // Solo workout - just delete the session
        await Supabase.instance.client
            .from('active_checkin_sessions')
            .delete()
            .eq('user_id', userId);
      }

      if (mounted) {
        Navigator.pop(context, false);
      }
    }
  }

  String _formatTime(DateTime time) {
    final hour = time.hour > 12 ? time.hour - 12 : (time.hour == 0 ? 12 : time.hour);
    final period = time.hour >= 12 ? 'PM' : 'AM';
    final minute = time.minute.toString().padLeft(2, '0');
    return '$hour:$minute $period';
  }

  String _formatDuration(Duration duration) {
    final minutes = duration.inMinutes;
    final seconds = duration.inSeconds % 60;
    return '${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';
  }

  String _formatRemainingTime() {
    final remaining = Duration(minutes: _goalMinutes) - _elapsed;
    if (remaining.isNegative) return '0:00';

    final minutes = remaining.inMinutes;
    final seconds = remaining.inSeconds % 60;
    return '$minutes:${seconds.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    final progress =
        (_elapsed.inSeconds / (Duration(minutes: _goalMinutes).inSeconds))
            .clamp(0.0, 1.0);
    final bottomPadding = MediaQuery.of(context).padding.bottom;

    // FIX: Use intrinsic height - only as tall as content needs
    return Container(
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: EdgeInsets.fromLTRB(24, 0, 24, bottomPadding > 0 ? bottomPadding : 16),
          child: Column(
            mainAxisSize: MainAxisSize.min, // KEY: Only as tall as needed
            children: [
              // Handle bar
              Container(
                margin: const EdgeInsets.only(top: 12, bottom: 16),
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.grey.shade300,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),

              // Header with workout type
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: _hasReachedGoal
                        ? [Colors.green[400]!, Colors.green[600]!]
                        : [Colors.orange[400]!, Colors.orange[600]!],
                  ),
                  borderRadius: BorderRadius.circular(16),
                  boxShadow: [
                    BoxShadow(
                      color: (_hasReachedGoal ? Colors.green : Colors.orange)
                          .withOpacity(0.3),
                      blurRadius: 12,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      widget.workoutEmoji ?? '💪',
                      style: const TextStyle(fontSize: 28),
                    ),
                    const SizedBox(width: 12),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          widget.workoutType ?? 'Workout',
                          style: const TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                            color: Colors.white,
                          ),
                        ),
                        Text(
                          _hasReachedGoal
                              ? '✓ Goal reached!'
                              : 'Goal: $_goalMinutes min',
                          style: TextStyle(
                            fontSize: 13,
                            color: Colors.white.withOpacity(0.9),
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 24),

              // Timer display
              Container(
                padding: const EdgeInsets.symmetric(vertical: 20, horizontal: 32),
                decoration: BoxDecoration(
                  color: Colors.grey[50],
                  borderRadius: BorderRadius.circular(24),
                  border: Border.all(
                    color: _hasReachedGoal
                        ? Colors.green.withOpacity(0.3)
                        : Colors.grey.withOpacity(0.2),
                    width: 2,
                  ),
                ),
                child: Column(
                  children: [
                    Text(
                      _formatDuration(_elapsed),
                      style: TextStyle(
                        fontSize: 56, // Slightly smaller
                        fontWeight: FontWeight.w700,
                        color: _hasReachedGoal ? Colors.green[700] : Colors.grey[800],
                        fontFeatures: const [FontFeature.tabularFigures()],
                        letterSpacing: 2,
                      ),
                    ),
                    const SizedBox(height: 12),

                    // Progress bar
                    ClipRRect(
                      borderRadius: BorderRadius.circular(8),
                      child: LinearProgressIndicator(
                        value: progress,
                        minHeight: 8,
                        backgroundColor: Colors.grey[200],
                        valueColor: AlwaysStoppedAnimation<Color>(
                          _hasReachedGoal ? Colors.green[500]! : Colors.orange[500]!,
                        ),
                      ),
                    ),
                    const SizedBox(height: 10),
                    Text(
                      _hasReachedGoal
                          ? '🎉 Goal reached! Ready to check in!'
                          : '${_formatRemainingTime()} until goal',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: _hasReachedGoal ? Colors.green[700] : Colors.grey[600],
                      ),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 16),

              // Motivational message
              AnimatedSwitcher(
                duration: const Duration(milliseconds: 500),
                child: Container(
                  key: ValueKey<int>(_hasReachedGoal ? -1 : _currentMessageIndex),
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: _hasReachedGoal ? Colors.green[50] : Colors.blue[50],
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(
                      color: _hasReachedGoal
                          ? Colors.green.withOpacity(0.2)
                          : Colors.blue.withOpacity(0.2),
                    ),
                  ),
                  child: Row(
                    children: [
                      Text(
                        _hasReachedGoal
                            ? _completedMessages[_currentMessageIndex %
                                _completedMessages.length]['emoji']!
                            : _motivationalMessages[_currentMessageIndex]['emoji']!,
                        style: const TextStyle(fontSize: 24),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          _hasReachedGoal
                              ? _completedMessages[_currentMessageIndex %
                                  _completedMessages.length]['text']!
                              : _motivationalMessages[_currentMessageIndex]['text']!,
                          style: TextStyle(
                            fontSize: 13,
                            color: _hasReachedGoal
                                ? Colors.green[900]
                                : Colors.blue[900],
                            height: 1.3,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),

              const SizedBox(height: 12),

              // Info message - more compact
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.info_outline, color: Colors.grey[500], size: 16),
                  const SizedBox(width: 8),
                  Text(
                    'Timer runs in background. Close this and continue using the app!',
                    style: TextStyle(
                      fontSize: 11,
                      color: Colors.grey[600],
                    ),
                  ),
                ],
              ),

              const SizedBox(height: 20),

              // Complete button - LOCKED until goal reached!
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: (_hasReachedGoal && !_isCompleting) ? _completeCheckIn : null,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: _hasReachedGoal ? Colors.green[600] : Colors.grey[400],
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                    elevation: _hasReachedGoal ? 2 : 0,
                    shadowColor: Colors.green.withOpacity(0.4),
                    disabledBackgroundColor: Colors.grey[300],
                    disabledForegroundColor: Colors.grey[600],
                  ),
                  child: _isCompleting
                      ? const SizedBox(
                          width: 24,
                          height: 24,
                          child: CircularProgressIndicator(
                            strokeWidth: 2.5,
                            color: Colors.white,
                          ),
                        )
                      : Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(
                              _hasReachedGoal ? Icons.check_circle : Icons.lock,
                              size: 20,
                            ),
                            const SizedBox(width: 10),
                            Text(
                              _hasReachedGoal 
                                  ? 'Complete Check-In' 
                                  : 'Complete Goal to Check In',
                              style: const TextStyle(
                                fontSize: 15,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ],
                        ),
                ),
              ),

              const SizedBox(height: 4),

              // Cancel button - tighter spacing
              TextButton(
                onPressed: _cancelWorkout,
                style: TextButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                ),
                child: Text(
                  'Cancel Workout',
                  style: TextStyle(
                    fontSize: 14,
                    color: Colors.grey[500],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// =============================================================================
// WORKOUT SELECTION SHEET - Updated with Custom Duration option
// =============================================================================

/// Data class for workout types
class WorkoutType {
  final String name;
  final String description;
  final String emoji;
  final String category;
  final int defaultDuration;

  const WorkoutType({
    required this.name,
    required this.description,
    required this.emoji,
    required this.category,
    required this.defaultDuration,
  });
}

/// Workout selection sheet with categories and custom duration
class WorkoutSelectionSheet extends StatefulWidget {
  final Function(String workoutType, String emoji, int duration) onWorkoutSelected;

  const WorkoutSelectionSheet({
    super.key,
    required this.onWorkoutSelected,
  });

  static Future<void> show(
    BuildContext context, {
    required Function(String workoutType, String emoji, int duration) onWorkoutSelected,
  }) {
    return showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      isDismissible: true,
      enableDrag: true,
      backgroundColor: Colors.transparent,
      builder: (context) => WorkoutSelectionSheet(onWorkoutSelected: onWorkoutSelected),
    );
  }

  @override
  State<WorkoutSelectionSheet> createState() => _WorkoutSelectionSheetState();
}

class _WorkoutSelectionSheetState extends State<WorkoutSelectionSheet> {
  String _selectedCategory = 'All';

  static const List<String> _categories = [
    'All',
    'Strength',
    'Cardio',
    'HIIT',
    'Yoga',
    'Sports',
  ];

  static const Map<String, String> _categoryEmojis = {
    'All': '🏆',
    'Strength': '💪',
    'Cardio': '🏃',
    'HIIT': '⚡',
    'Yoga': '🧘',
    'Sports': '⚽',
  };

  static const List<WorkoutType> _workoutTypes = [
    // Yoga
    WorkoutType(
      name: 'Vinyasa Flow',
      description: 'Dynamic flowing yoga practice',
      emoji: '🧘',
      category: 'Yoga',
      defaultDuration: 60,
    ),
    WorkoutType(
      name: 'Restorative Yoga',
      description: 'Gentle stretching and relaxation',
      emoji: '🕉️',
      category: 'Yoga',
      defaultDuration: 45,
    ),
    WorkoutType(
      name: 'Power Yoga',
      description: 'Strength-building yoga sequences',
      emoji: '🧘‍♂️',
      category: 'Yoga',
      defaultDuration: 50,
    ),
    // Strength
    WorkoutType(
      name: 'Upper Body Strength',
      description: 'Chest, shoulders, back, and arms',
      emoji: '💪',
      category: 'Strength',
      defaultDuration: 45,
    ),
    WorkoutType(
      name: 'Lower Body Strength',
      description: 'Legs, glutes, and core workout',
      emoji: '🦵',
      category: 'Strength',
      defaultDuration: 45,
    ),
    WorkoutType(
      name: 'Full Body Strength',
      description: 'Complete strength training session',
      emoji: '🏋️',
      category: 'Strength',
      defaultDuration: 60,
    ),
    WorkoutType(
      name: 'Core & Abs',
      description: 'Focused core strengthening',
      emoji: '🔥',
      category: 'Strength',
      defaultDuration: 30,
    ),
    // Cardio
    WorkoutType(
      name: 'Running',
      description: 'Outdoor or treadmill run',
      emoji: '🏃',
      category: 'Cardio',
      defaultDuration: 30,
    ),
    WorkoutType(
      name: 'Cycling',
      description: 'Bike ride or spin class',
      emoji: '🚴',
      category: 'Cardio',
      defaultDuration: 45,
    ),
    WorkoutType(
      name: 'Swimming',
      description: 'Pool laps or water workout',
      emoji: '🏊',
      category: 'Cardio',
      defaultDuration: 45,
    ),
    WorkoutType(
      name: 'Jump Rope',
      description: 'High-intensity skipping',
      emoji: '⏱️',
      category: 'Cardio',
      defaultDuration: 20,
    ),
    // HIIT
    WorkoutType(
      name: 'HIIT Circuit',
      description: 'High-intensity interval training',
      emoji: '⚡',
      category: 'HIIT',
      defaultDuration: 30,
    ),
    WorkoutType(
      name: 'Tabata',
      description: '20 sec work, 10 sec rest intervals',
      emoji: '💥',
      category: 'HIIT',
      defaultDuration: 25,
    ),
    WorkoutType(
      name: 'Boot Camp',
      description: 'Mixed cardio and strength HIIT',
      emoji: '🎖️',
      category: 'HIIT',
      defaultDuration: 45,
    ),
    // Sports
    WorkoutType(
      name: 'Basketball',
      description: 'Shooting hoops or pickup game',
      emoji: '🏀',
      category: 'Sports',
      defaultDuration: 60,
    ),
    WorkoutType(
      name: 'Tennis',
      description: 'Singles or doubles match',
      emoji: '🎾',
      category: 'Sports',
      defaultDuration: 60,
    ),
    WorkoutType(
      name: 'Soccer',
      description: 'Football practice or match',
      emoji: '⚽',
      category: 'Sports',
      defaultDuration: 90,
    ),
    WorkoutType(
      name: 'Martial Arts',
      description: 'Boxing, MMA, or traditional arts',
      emoji: '🥊',
      category: 'Sports',
      defaultDuration: 60,
    ),
  ];

  List<WorkoutType> get _filteredWorkouts {
    if (_selectedCategory == 'All') {
      return _workoutTypes;
    }
    return _workoutTypes.where((w) => w.category == _selectedCategory).toList();
  }

  void _showCustomDurationDialog(WorkoutType workout) {
    int customDuration = workout.defaultDuration;

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          title: Row(
            children: [
              Text(workout.emoji, style: const TextStyle(fontSize: 28)),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  workout.name,
                  style: const TextStyle(fontSize: 18),
                ),
              ),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'Set your workout goal',
                style: TextStyle(color: Colors.grey[600]),
              ),
              const SizedBox(height: 24),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  // Decrease button
                  IconButton(
                    onPressed: customDuration > 5
                        ? () => setDialogState(() => customDuration -= 5)
                        : null,
                    icon: Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: Colors.grey[200],
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(Icons.remove, size: 20),
                    ),
                  ),
                  const SizedBox(width: 16),
                  // Duration display
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                    decoration: BoxDecoration(
                      color: Colors.orange[50],
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: Colors.orange[200]!),
                    ),
                    child: Text(
                      '$customDuration min',
                      style: TextStyle(
                        fontSize: 28,
                        fontWeight: FontWeight.bold,
                        color: Colors.orange[800],
                      ),
                    ),
                  ),
                  const SizedBox(width: 16),
                  // Increase button
                  IconButton(
                    onPressed: customDuration < 180
                        ? () => setDialogState(() => customDuration += 5)
                        : null,
                    icon: Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: Colors.orange[100],
                        shape: BoxShape.circle,
                      ),
                      child: Icon(Icons.add, size: 20, color: Colors.orange[800]),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              // Quick presets
              Wrap(
                spacing: 8,
                children: [15, 30, 45, 60, 90].map((mins) {
                  final isSelected = customDuration == mins;
                  return ActionChip(
                    label: Text('$mins'),
                    backgroundColor: isSelected ? Colors.orange[100] : Colors.grey[100],
                    side: BorderSide(
                      color: isSelected ? Colors.orange[400]! : Colors.grey[300]!,
                    ),
                    onPressed: () => setDialogState(() => customDuration = mins),
                  );
                }).toList(),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: Text('Cancel', style: TextStyle(color: Colors.grey[600])),
            ),
            ElevatedButton(
              onPressed: () {
                Navigator.pop(context); // Close dialog
                Navigator.pop(this.context); // Close selection sheet
                widget.onWorkoutSelected(workout.name, workout.emoji, customDuration);
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.orange[600],
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              child: const Text('Start Workout'),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final bottomPadding = MediaQuery.of(context).padding.bottom;

    return Container(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.of(context).size.height * 0.85,
      ),
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Handle bar
          Container(
            margin: const EdgeInsets.only(top: 12, bottom: 8),
            width: 40,
            height: 4,
            decoration: BoxDecoration(
              color: Colors.grey.shade300,
              borderRadius: BorderRadius.circular(2),
            ),
          ),

          // Header
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  'Select Workout Type',
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                IconButton(
                  onPressed: () => Navigator.pop(context),
                  icon: const Icon(Icons.close),
                ),
              ],
            ),
          ),

          // Category filter chips
          SizedBox(
            height: 50,
            child: ListView.builder(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 16),
              itemCount: _categories.length,
              itemBuilder: (context, index) {
                final category = _categories[index];
                final isSelected = _selectedCategory == category;
                return Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: FilterChip(
                    label: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(_categoryEmojis[category] ?? ''),
                        const SizedBox(width: 6),
                        Text(category),
                      ],
                    ),
                    selected: isSelected,
                    onSelected: (_) => setState(() => _selectedCategory = category),
                    backgroundColor: Colors.grey[100],
                    selectedColor: Colors.orange[100],
                    checkmarkColor: Colors.orange[800],
                    side: BorderSide(
                      color: isSelected ? Colors.orange[400]! : Colors.grey[300]!,
                    ),
                    labelStyle: TextStyle(
                      color: isSelected ? Colors.orange[900] : Colors.grey[700],
                      fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
                    ),
                  ),
                );
              },
            ),
          ),

          const SizedBox(height: 8),
          Divider(color: Colors.grey[200], height: 1),

          // Workout list
          Flexible(
            child: ListView.builder(
              padding: EdgeInsets.fromLTRB(16, 8, 16, bottomPadding + 16),
              itemCount: _filteredWorkouts.length + 1, // +1 for custom option
              itemBuilder: (context, index) {
                // Custom duration option at the end
                if (index == _filteredWorkouts.length) {
                  return _buildCustomWorkoutTile();
                }

                final workout = _filteredWorkouts[index];
                return _buildWorkoutTile(workout);
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildWorkoutTile(WorkoutType workout) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.grey[200]!),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.03),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: () {
            HapticFeedback.lightImpact();
            // Use default duration directly
            Navigator.pop(context);
            widget.onWorkoutSelected(
              workout.name,
              workout.emoji,
              workout.defaultDuration,
            );
          },
          borderRadius: BorderRadius.circular(14),
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Row(
              children: [
                // Emoji container
                Container(
                  width: 48,
                  height: 48,
                  decoration: BoxDecoration(
                    color: Colors.orange[50],
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Center(
                    child: Text(
                      workout.emoji,
                      style: const TextStyle(fontSize: 24),
                    ),
                  ),
                ),
                const SizedBox(width: 14),
                // Info
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        workout.name,
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        workout.description,
                        style: TextStyle(
                          fontSize: 13,
                          color: Colors.grey[600],
                        ),
                      ),
                    ],
                  ),
                ),
                // Duration + custom button
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      '${workout.defaultDuration} min',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: Colors.grey[700],
                      ),
                    ),
                    const SizedBox(width: 8),
                    // Custom duration button
                    GestureDetector(
                      onTap: () {
                        HapticFeedback.lightImpact();
                        _showCustomDurationDialog(workout);
                      },
                      child: Container(
                        padding: const EdgeInsets.all(6),
                        decoration: BoxDecoration(
                          color: Colors.orange[50],
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: Colors.orange[200]!),
                        ),
                        child: Icon(
                          Icons.edit,
                          size: 16,
                          color: Colors.orange[700],
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildCustomWorkoutTile() {
    return Container(
      margin: const EdgeInsets.only(bottom: 8, top: 8),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [Colors.purple[50]!, Colors.blue[50]!],
        ),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.purple[200]!),
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: () {
            HapticFeedback.lightImpact();
            _showFullCustomDialog();
          },
          borderRadius: BorderRadius.circular(14),
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Row(
              children: [
                // Icon container
                Container(
                  width: 48,
                  height: 48,
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [Colors.purple[400]!, Colors.blue[400]!],
                    ),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Center(
                    child: Icon(Icons.add, color: Colors.white, size: 28),
                  ),
                ),
                const SizedBox(width: 14),
                // Info
                const Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Custom Workout',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      SizedBox(height: 2),
                      Text(
                        'Set your own workout type and duration',
                        style: TextStyle(
                          fontSize: 13,
                          color: Colors.grey,
                        ),
                      ),
                    ],
                  ),
                ),
                Icon(Icons.arrow_forward_ios, size: 16, color: Colors.grey[400]),
              ],
            ),
          ),
        ),
      ),
    );
  }

  void _showFullCustomDialog() {
    String customName = '';
    int customDuration = 30;
    String selectedEmoji = '🏋️';

    final emojis = ['🏋️', '💪', '🏃', '🚴', '🧘', '🥊', '⚽', '🏀', '🏊', '⚡', '🔥', '💥'];

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          title: const Text('Custom Workout'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Workout name
                TextField(
                  decoration: InputDecoration(
                    labelText: 'Workout Name',
                    hintText: 'e.g., Morning Run',
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  onChanged: (value) => customName = value,
                ),
                const SizedBox(height: 20),

                // Emoji selector
                const Text('Choose an emoji:', style: TextStyle(fontWeight: FontWeight.w500)),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: emojis.map((emoji) {
                    final isSelected = selectedEmoji == emoji;
                    return GestureDetector(
                      onTap: () => setDialogState(() => selectedEmoji = emoji),
                      child: Container(
                        width: 44,
                        height: 44,
                        decoration: BoxDecoration(
                          color: isSelected ? Colors.orange[100] : Colors.grey[100],
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(
                            color: isSelected ? Colors.orange[400]! : Colors.grey[300]!,
                            width: isSelected ? 2 : 1,
                          ),
                        ),
                        child: Center(
                          child: Text(emoji, style: const TextStyle(fontSize: 22)),
                        ),
                      ),
                    );
                  }).toList(),
                ),
                const SizedBox(height: 20),

                // Duration
                const Text('Duration:', style: TextStyle(fontWeight: FontWeight.w500)),
                const SizedBox(height: 8),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    IconButton(
                      onPressed: customDuration > 5
                          ? () => setDialogState(() => customDuration -= 5)
                          : null,
                      icon: const Icon(Icons.remove_circle_outline),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
                      decoration: BoxDecoration(
                        color: Colors.orange[50],
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        '$customDuration min',
                        style: TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                          color: Colors.orange[800],
                        ),
                      ),
                    ),
                    IconButton(
                      onPressed: customDuration < 180
                          ? () => setDialogState(() => customDuration += 5)
                          : null,
                      icon: const Icon(Icons.add_circle_outline),
                    ),
                  ],
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: Text('Cancel', style: TextStyle(color: Colors.grey[600])),
            ),
            ElevatedButton(
              onPressed: customName.trim().isNotEmpty
                  ? () {
                      Navigator.pop(context); // Close dialog
                      Navigator.pop(this.context); // Close selection sheet
                      widget.onWorkoutSelected(
                        customName.trim(),
                        selectedEmoji,
                        customDuration,
                      );
                    }
                  : null,
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.orange[600],
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              child: const Text('Start Workout'),
            ),
          ],
        ),
      ),
    );
  }
}