import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'dart:async';

/// Workout timer sheet for check-ins
/// Requires minimum 15 minutes of workout before check-in is allowed
class WorkoutCheckInSheet extends StatefulWidget {
  final VoidCallback onCheckInComplete;

  const WorkoutCheckInSheet({
    super.key,
    required this.onCheckInComplete,
  });

  /// Show as a bottom sheet
  static Future<bool?> show(BuildContext context, {required VoidCallback onCheckInComplete}) {
    HapticFeedback.mediumImpact();
    
    return showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      isDismissible: false, // Prevent accidental dismiss
      enableDrag: false,
      backgroundColor: Colors.transparent,
      builder: (context) => WorkoutCheckInSheet(
        onCheckInComplete: onCheckInComplete,
      ),
    );
  }

  @override
  State<WorkoutCheckInSheet> createState() => _WorkoutCheckInSheetState();
}

class _WorkoutCheckInSheetState extends State<WorkoutCheckInSheet> 
    with WidgetsBindingObserver {
  
  static const int _minimumMinutes = 15;
  
  DateTime? _workoutStartTime;
  Timer? _timer;
  Duration _elapsed = Duration.zero;
  bool _isCompleting = false;
  bool _hasReachedMinimum = false;
  
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
    {'emoji': '🚀', 'text': 'Launch yourself towards your goals. No stopping now!'},
    {'emoji': '🎯', 'text': 'Stay focused. Every rep brings you closer to your goal.'},
    {'emoji': '👊', 'text': 'Punch through the pain. Strength is on the other side.'},
    {'emoji': '🌟', 'text': 'You\'re a star in the making. Keep shining!'},
    {'emoji': '🦁', 'text': 'Unleash the beast! Show this workout who\'s boss.'},
    {'emoji': '⏰', 'text': 'Time invested in yourself is never wasted.'},
    {'emoji': '🏆', 'text': 'Winners don\'t quit. You\'re almost there!'},
    {'emoji': '💎', 'text': 'Pressure makes diamonds. Embrace the challenge!'},
    {'emoji': '🌊', 'text': 'Ride the wave of momentum. Don\'t stop now!'},
    {'emoji': '🔋', 'text': 'Recharging your body and mind. Keep going!'},
  ];
  
  static const List<Map<String, String>> _completedMessages = [
    {'emoji': '🔥', 'text': 'Amazing work! You can check in now or keep going!'},
    {'emoji': '🎉', 'text': 'You crushed it! Ready to claim your streak?'},
    {'emoji': '👑', 'text': 'Royalty! You\'ve earned your check-in. Keep going?'},
    {'emoji': '🏅', 'text': 'Medal-worthy performance! Check in when ready.'},
    {'emoji': '💪', 'text': 'Beast mode complete! Your streak awaits.'},
    {'emoji': '⭐', 'text': 'Superstar! You can check in or push further!'},
    {'emoji': '🚀', 'text': 'Mission accomplished! Ready for liftoff?'},
    {'emoji': '🎊', 'text': 'Celebration time! You\'ve hit the goal!'},
  ];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    
    // Start with a random message
    _currentMessageIndex = DateTime.now().millisecondsSinceEpoch % _motivationalMessages.length;
    
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
      // App going to background - save current time
      _pausedAt = DateTime.now();
      _timer?.cancel();
    } else if (state == AppLifecycleState.resumed) {
      // App coming back - calculate elapsed time
      if (_workoutStartTime != null) {
        _updateElapsedTime();
        _startTimer();
      }
    }
  }

  Future<void> _checkExistingWorkout() async {
    final userId = Supabase.instance.client.auth.currentUser?.id;
    if (userId == null) return;

    // Check if there's an active workout session
    try {
      final existing = await Supabase.instance.client
          .from('active_checkin_sessions')
          .select()
          .eq('user_id', userId)
          .maybeSingle();

      if (existing != null && existing['started_at'] != null) {
        // Resume existing workout
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
                  Text('Resumed workout from ${_formatTime(_workoutStartTime!)}'),
                ],
              ),
              backgroundColor: Colors.blue[600],
              duration: const Duration(seconds: 2),
            ),
          );
        }
      } else {
        // Start new workout
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
    
    // Save to database so it persists if app closes
    try {
      await Supabase.instance.client
          .from('active_checkin_sessions')
          .upsert({
            'user_id': userId,
            'started_at': _workoutStartTime!.toIso8601String(),
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
    
    // Rotate message every 5 minutes (300 seconds)
    final newMessageIndex = (newElapsed.inSeconds ~/ 300) % _motivationalMessages.length;
    
    setState(() {
      _elapsed = newElapsed;
      _hasReachedMinimum = _elapsed.inMinutes >= _minimumMinutes;
      
      // Update message index if it changed
      if (newMessageIndex != _currentMessageIndex) {
        _currentMessageIndex = newMessageIndex;
      }
    });
  }

  Future<void> _completeCheckIn() async {
    if (!_hasReachedMinimum || _isCompleting) return;

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

      // Call the check-in callback
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
              'If you cancel now, this progress won\'t count towards your streak.',
              style: TextStyle(fontSize: 14, color: Colors.grey[600]),
            ),
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
            child: const Text('Cancel Workout'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      final userId = Supabase.instance.client.auth.currentUser?.id;
      if (userId != null) {
        // Clear the active session
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
    final hour = time.hour > 12 ? time.hour - 12 : time.hour;
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
    final remaining = Duration(minutes: _minimumMinutes) - _elapsed;
    if (remaining.isNegative) return '0:00';
    
    final minutes = remaining.inMinutes;
    final seconds = remaining.inSeconds % 60;
    return '$minutes:${seconds.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    final progress = (_elapsed.inSeconds / (Duration(minutes: _minimumMinutes).inSeconds)).clamp(0.0, 1.0);
    
    return Container(
      height: MediaQuery.of(context).size.height * 0.75,
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: Column(
        children: [
          // Handle bar
          Container(
            margin: const EdgeInsets.only(top: 12),
            width: 40,
            height: 4,
            decoration: BoxDecoration(
              color: Colors.grey[300],
              borderRadius: BorderRadius.circular(2),
            ),
          ),

          Expanded(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                children: [
                  // Header
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    decoration: BoxDecoration(
                      color: _hasReachedMinimum ? Colors.green[50] : Colors.orange[50],
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          _hasReachedMinimum ? Icons.check_circle : Icons.fitness_center,
                          color: _hasReachedMinimum ? Colors.green[700] : Colors.orange[700],
                          size: 20,
                        ),
                        const SizedBox(width: 8),
                        Text(
                          _hasReachedMinimum ? 'Ready to Check In!' : 'Workout in Progress',
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.bold,
                            color: _hasReachedMinimum ? Colors.green[700] : Colors.orange[700],
                          ),
                        ),
                      ],
                    ),
                  ),

                  const Spacer(),

                  // Timer display
                  Text(
                    _formatDuration(_elapsed),
                    style: TextStyle(
                      fontSize: 72,
                      fontWeight: FontWeight.bold,
                      color: _hasReachedMinimum ? Colors.green[700] : Colors.grey[800],
                      fontFeatures: const [FontFeature.tabularFigures()],
                    ),
                  ),

                  const SizedBox(height: 24),

                  // Progress bar
                  Column(
                    children: [
                      ClipRRect(
                        borderRadius: BorderRadius.circular(10),
                        child: LinearProgressIndicator(
                          value: progress,
                          minHeight: 12,
                          backgroundColor: Colors.grey[200],
                          valueColor: AlwaysStoppedAnimation<Color>(
                            _hasReachedMinimum ? Colors.green[600]! : Colors.orange[600]!,
                          ),
                        ),
                      ),
                      const SizedBox(height: 12),
                      Text(
                        _hasReachedMinimum 
                            ? '✓ $_minimumMinutes minute minimum reached!'
                            : '${_formatRemainingTime()} until check-in unlocks',
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: _hasReachedMinimum ? Colors.green[700] : Colors.grey[600],
                        ),
                      ),
                    ],
                  ),

                  const Spacer(),

                  // Motivational message (rotates every 5 minutes)
                  AnimatedSwitcher(
                    duration: const Duration(milliseconds: 500),
                    child: Container(
                      key: ValueKey<int>(_hasReachedMinimum ? -1 : _currentMessageIndex),
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: _hasReachedMinimum ? Colors.green[50] : Colors.blue[50],
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: Row(
                        children: [
                          Text(
                            _hasReachedMinimum 
                                ? _completedMessages[_currentMessageIndex % _completedMessages.length]['emoji']!
                                : _motivationalMessages[_currentMessageIndex]['emoji']!,
                            style: const TextStyle(fontSize: 32),
                          ),
                          const SizedBox(width: 16),
                          Expanded(
                            child: Text(
                              _hasReachedMinimum 
                                  ? _completedMessages[_currentMessageIndex % _completedMessages.length]['text']!
                                  : _motivationalMessages[_currentMessageIndex]['text']!,
                              style: TextStyle(
                                fontSize: 14,
                                color: _hasReachedMinimum ? Colors.green[900] : Colors.blue[900],
                                height: 1.4,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),

                  const SizedBox(height: 24),

                  // Complete button
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      onPressed: _hasReachedMinimum && !_isCompleting 
                          ? _completeCheckIn 
                          : null,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.green[600],
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 18),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16),
                        ),
                        elevation: _hasReachedMinimum ? 4 : 0,
                        disabledBackgroundColor: Colors.grey[300],
                        disabledForegroundColor: Colors.grey[500],
                      ),
                      child: _isCompleting
                          ? const SizedBox(
                              width: 24,
                              height: 24,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Colors.white,
                              ),
                            )
                          : Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(
                                  _hasReachedMinimum 
                                      ? Icons.check_circle 
                                      : Icons.lock,
                                  size: 24,
                                ),
                                const SizedBox(width: 12),
                                Text(
                                  _hasReachedMinimum 
                                      ? 'Complete Check-In'
                                      : 'Unlocks in ${_formatRemainingTime()}',
                                  style: const TextStyle(
                                    fontSize: 18,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ],
                            ),
                    ),
                  ),

                  const SizedBox(height: 12),

                  // Cancel button
                  TextButton(
                    onPressed: _cancelWorkout,
                    child: Text(
                      'Cancel Workout',
                      style: TextStyle(
                        fontSize: 14,
                        color: Colors.grey[600],
                      ),
                    ),
                  ),

                  SizedBox(height: MediaQuery.of(context).padding.bottom),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}