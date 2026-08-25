import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../services/workout_service.dart';
import 'dart:async';
import 'streak_complete_sheet.dart';
import 'package:gym_buddy_app/utils/debug_logger.dart';


/// Workout timer sheet for check-ins
/// Tracks workout duration based on user's selected goal
class WorkoutCheckInSheet extends StatefulWidget {
  final Future<bool> Function() onCheckInComplete;
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
    required Future<bool> Function() onCheckInComplete,
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
      debugLog('❌ Error checking active session: $e');
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
      debugLog('❌ Error checking existing workout: $e');
      _startNewWorkout();
    }
  }

  Future<void> _startNewWorkout() async {
    final userId = Supabase.instance.client.auth.currentUser?.id;
    if (userId == null) return;

    // ✅ RACE GUARD: another flow (e.g. invite accept) may have just created
    // a session — adopt its start time instead of overwriting it
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
        return;
      }
    } catch (e) {
      debugLog('⚠️ Race-guard check failed, starting fresh: $e');
    }

    _workoutStartTime = DateTime.now();

    try {
      // Save workout session WITH workout details for resume functionality
      await Supabase.instance.client.from('active_checkin_sessions').upsert({
        'user_id': userId,
        'started_at': _workoutStartTime!.toUtc().toIso8601String(), // ✅ ALWAYS UTC
        'workout_type': widget.workoutType,
        'workout_emoji': widget.workoutEmoji,
        'planned_duration': widget.plannedDuration,
      });
    } catch (e) {
      debugLog('❌ Error saving workout session: $e');
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
      // Clear the active session immediately
      await Supabase.instance.client
          .from('active_checkin_sessions')
          .delete()
          .eq('user_id', userId);
    } catch (e) {
      debugLog('❌ Error clearing session: $e');
    }

    // ✅ Close the sheet IMMEDIATELY — don't wait for check-in to finish
    if (mounted) {
      Navigator.pop(context, true);
    }

    // ✅ Do the heavy check-in work in the background AFTER sheet is gone
    try {
      final partnerBonusEarned = await widget.onCheckInComplete();

      if (partnerBonusEarned && mounted) {
        await Future.delayed(const Duration(milliseconds: 400));
        if (mounted) {
          await StreakCompleteSheet.show(context);
        }
      }
    } catch (e) {
      debugLog('❌ Error completing check-in: $e');
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
      debugLog('⚠️ Could not check workout type: $e');
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

        // Also cancel the user's own solo in_progress workout records.
        // buddy_id must be null: this sheet has no workout_id, so it can
        // only speak for solo workouts — shared workouts are cancelled
        // through cancelWorkout's fair logic, never swept from here.
        try {
          await Supabase.instance.client
              .from('workouts')
              .update({'status': 'cancelled', 'creator_cancelled': true})
              .eq('user_id', userId)
              .eq('status', 'in_progress')
              .isFilter('buddy_id', null);
        } catch (e) {
          debugLog('⚠️ Could not cancel workout record: $e');
        }
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
                  Flexible(
                    child: Text(
                      'Timer runs in background. Close this and continue using the app!',
                      style: TextStyle(
                        fontSize: 11,
                        color: Colors.grey[600],
                      ),
                      overflow: TextOverflow.ellipsis,
                      maxLines: 2,
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

