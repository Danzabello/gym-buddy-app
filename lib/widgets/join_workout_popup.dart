import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'dart:async';
import 'user_avatar.dart';

/// Popup that shows when a buddy has started a workout you scheduled
/// Gives the creator the option to join within the quarter-time window
class JoinWorkoutPopup extends StatefulWidget {
  final String workoutId;
  final String workoutType;
  final String buddyName;
  final String? buddyAvatarId;
  final int plannedDurationMinutes;
  final int timeRemainingSeconds; // Time left to join
  final VoidCallback onJoin;
  final VoidCallback onDecline;

  const JoinWorkoutPopup({
    super.key,
    required this.workoutId,
    required this.workoutType,
    required this.buddyName,
    this.buddyAvatarId,
    required this.plannedDurationMinutes,
    required this.timeRemainingSeconds,
    required this.onJoin,
    required this.onDecline,
  });

  /// Show the popup as a dialog
  static Future<bool?> show(
    BuildContext context, {
    required String workoutId,
    required String workoutType,
    required String buddyName,
    String? buddyAvatarId,
    required int plannedDurationMinutes,
    required int timeRemainingSeconds,
    required VoidCallback onJoin,
    required VoidCallback onDecline,
  }) {
    HapticFeedback.mediumImpact();
    
    return showDialog<bool>(
      context: context,
      barrierDismissible: false,
      barrierColor: Colors.black87,
      builder: (context) => JoinWorkoutPopup(
        workoutId: workoutId,
        workoutType: workoutType,
        buddyName: buddyName,
        buddyAvatarId: buddyAvatarId,
        plannedDurationMinutes: plannedDurationMinutes,
        timeRemainingSeconds: timeRemainingSeconds,
        onJoin: onJoin,
        onDecline: onDecline,
      ),
    );
  }

  @override
  State<JoinWorkoutPopup> createState() => _JoinWorkoutPopupState();
}

class _JoinWorkoutPopupState extends State<JoinWorkoutPopup>
    with SingleTickerProviderStateMixin {
  late int _remainingSeconds;
  Timer? _timer;
  late AnimationController _pulseController;
  late Animation<double> _pulseAnimation;

  @override
  void initState() {
    super.initState();
    _remainingSeconds = widget.timeRemainingSeconds;
    
    // Start countdown timer
    _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (mounted) {
        setState(() {
          _remainingSeconds--;
          if (_remainingSeconds <= 0) {
            timer.cancel();
            Navigator.of(context).pop(false);
            widget.onDecline();
          }
        });
      }
    });

    // Pulse animation for avatar
    _pulseController = AnimationController(
      duration: const Duration(milliseconds: 1500),
      vsync: this,
    )..repeat(reverse: true);
    
    _pulseAnimation = Tween<double>(begin: 1.0, end: 1.08).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _timer?.cancel();
    _pulseController.dispose();
    super.dispose();
  }

  String _formatTime(int seconds) {
    final minutes = seconds ~/ 60;
    final secs = seconds % 60;
    return '${minutes}:${secs.toString().padLeft(2, '0')}';
  }

  String _formatDuration(int minutes) {
    if (minutes < 60) return '${minutes}m';
    final hours = minutes ~/ 60;
    final mins = minutes % 60;
    return mins > 0 ? '${hours}h ${mins}m' : '${hours}h';
  }

  Color _getUrgencyColor() {
    if (_remainingSeconds < 60) return Colors.red;
    if (_remainingSeconds < 180) return Colors.orange;
    return Colors.green;
  }

  String _getWorkoutEmoji(String type) {
    switch (type.toLowerCase()) {
      case 'cardio': return '🏃';
      case 'strength': return '💪';
      case 'hiit': return '⚡';
      case 'leg day':
      case 'lower body': return '🦵';
      case 'upper body': return '💪';
      case 'full body': return '🏋️';
      case 'yoga': return '🧘';
      default: return '🏋️';
    }
  }

  @override
  Widget build(BuildContext context) {
    final urgencyColor = _getUrgencyColor();
    final workoutTimeRemaining = widget.plannedDurationMinutes - 
        ((widget.plannedDurationMinutes ~/ 4) - (_remainingSeconds ~/ 60));

    return Dialog(
      backgroundColor: Colors.transparent,
      elevation: 0,
      child: Container(
        constraints: const BoxConstraints(maxWidth: 380),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(28),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.2),
              blurRadius: 30,
              spreadRadius: 5,
            ),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Header with gradient
            Container(
              padding: const EdgeInsets.fromLTRB(24, 32, 24, 24),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [Colors.green[400]!, Colors.teal[500]!],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius: const BorderRadius.only(
                  topLeft: Radius.circular(28),
                  topRight: Radius.circular(28),
                ),
              ),
              child: Column(
                children: [
                  // Animated buddy avatar
                  ScaleTransition(
                    scale: _pulseAnimation,
                    child: Stack(
                      alignment: Alignment.center,
                      children: [
                        // Glow ring
                        Container(
                          width: 100,
                          height: 100,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            border: Border.all(
                              color: Colors.white.withOpacity(0.5),
                              width: 4,
                            ),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.white.withOpacity(0.3),
                                blurRadius: 20,
                                spreadRadius: 5,
                              ),
                            ],
                          ),
                        ),
                        // Avatar
                        Container(
                          width: 88,
                          height: 88,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: Colors.white,
                            border: Border.all(color: Colors.white, width: 4),
                          ),
                          child: ClipOval(
                            child: widget.buddyAvatarId != null
                                ? UserAvatar(
                                    avatarId: widget.buddyAvatarId!,
                                    size: 80,
                                  )
                                : Container(
                                    color: Colors.orange[100],
                                    child: const Center(
                                      child: Text('🏋️', style: TextStyle(fontSize: 40)),
                                    ),
                                  ),
                          ),
                        ),
                        // Activity indicator
                        Positioned(
                          bottom: 0,
                          right: 0,
                          child: Container(
                            padding: const EdgeInsets.all(6),
                            decoration: BoxDecoration(
                              color: Colors.green[600],
                              shape: BoxShape.circle,
                              border: Border.all(color: Colors.white, width: 3),
                            ),
                            child: const Icon(
                              Icons.fitness_center,
                              color: Colors.white,
                              size: 16,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),
                  
                  // Title
                  Text(
                    '${widget.buddyName} is working out!',
                    style: const TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 8),
                  
                  // Workout type pill
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.2),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          _getWorkoutEmoji(widget.workoutType),
                          style: const TextStyle(fontSize: 18),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          '${widget.workoutType} • ${_formatDuration(widget.plannedDurationMinutes)}',
                          style: const TextStyle(
                            fontSize: 14,
                            color: Colors.white,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),

            // Body content
            Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                children: [
                  // Countdown section
                  Container(
                    padding: const EdgeInsets.all(20),
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: [
                          urgencyColor.withOpacity(0.1),
                          urgencyColor.withOpacity(0.05),
                        ],
                      ),
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(
                        color: urgencyColor.withOpacity(0.3),
                        width: 2,
                      ),
                    ),
                    child: Column(
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.timer_outlined, color: urgencyColor, size: 24),
                            const SizedBox(width: 10),
                            Text(
                              'Join window closes in',
                              style: TextStyle(
                                fontSize: 14,
                                color: Colors.grey[700],
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),
                        
                        // Big countdown
                        Text(
                          _formatTime(_remainingSeconds),
                          style: TextStyle(
                            fontSize: 48,
                            fontWeight: FontWeight.bold,
                            color: urgencyColor,
                            fontFeatures: const [FontFeature.tabularFigures()],
                          ),
                        ),
                        
                        const SizedBox(height: 8),
                        
                        // Progress bar
                        ClipRRect(
                          borderRadius: BorderRadius.circular(4),
                          child: LinearProgressIndicator(
                            value: _remainingSeconds / widget.timeRemainingSeconds,
                            minHeight: 6,
                            backgroundColor: urgencyColor.withOpacity(0.2),
                            valueColor: AlwaysStoppedAnimation<Color>(urgencyColor),
                          ),
                        ),
                        
                        const SizedBox(height: 12),
                        
                        Text(
                          '~${workoutTimeRemaining}m remaining to complete workout',
                          style: TextStyle(
                            fontSize: 13,
                            color: Colors.grey[600],
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 24),

                  // Action buttons
                  Row(
                    children: [
                      // Not Now button
                      Expanded(
                        child: OutlinedButton(
                          onPressed: () {
                            HapticFeedback.lightImpact();
                            Navigator.of(context).pop(false);
                            widget.onDecline();
                          },
                          style: OutlinedButton.styleFrom(
                            padding: const EdgeInsets.symmetric(vertical: 16),
                            side: BorderSide(color: Colors.grey[300]!, width: 2),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(16),
                            ),
                          ),
                          child: Text(
                            'Not Now',
                            style: TextStyle(
                              fontSize: 16,
                              color: Colors.grey[600],
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      
                      // Join button
                      Expanded(
                        flex: 2,
                        child: ElevatedButton(
                          onPressed: () {
                            HapticFeedback.heavyImpact();
                            Navigator.of(context).pop(true);
                            widget.onJoin();
                          },
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.green[500],
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(vertical: 16),
                            elevation: 4,
                            shadowColor: Colors.green.withOpacity(0.4),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(16),
                            ),
                          ),
                          child: const Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(Icons.play_arrow_rounded, size: 24),
                              SizedBox(width: 8),
                              Text(
                                'Join Workout',
                                style: TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),

                  const SizedBox(height: 16),

                  // Bottom hint
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.info_outline, size: 14, color: Colors.grey[400]),
                      const SizedBox(width: 6),
                      Text(
                        'You can also join from the Schedule tab',
                        style: TextStyle(
                          fontSize: 12,
                          color: Colors.grey[500],
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Popup shown when trying to invite someone already in a workout
class BuddyInWorkoutPopup extends StatelessWidget {
  final String buddyName;
  final String? buddyAvatarId;

  const BuddyInWorkoutPopup({
    super.key,
    required this.buddyName,
    this.buddyAvatarId,
  });

  static Future<void> show(
    BuildContext context, {
    required String buddyName,
    String? buddyAvatarId,
  }) {
    HapticFeedback.mediumImpact();
    
    return showDialog(
      context: context,
      builder: (context) => BuddyInWorkoutPopup(
        buddyName: buddyName,
        buddyAvatarId: buddyAvatarId,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: Colors.transparent,
      child: Container(
        constraints: const BoxConstraints(maxWidth: 340),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(24),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.15),
              blurRadius: 20,
              spreadRadius: 5,
            ),
          ],
        ),
        child: Padding(
          padding: const EdgeInsets.all(28),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Avatar with workout indicator
              Stack(
                alignment: Alignment.center,
                children: [
                  Container(
                    width: 90,
                    height: 90,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      gradient: LinearGradient(
                        colors: [Colors.orange[300]!, Colors.deepOrange[400]!],
                      ),
                    ),
                    padding: const EdgeInsets.all(4),
                    child: Container(
                      decoration: const BoxDecoration(
                        shape: BoxShape.circle,
                        color: Colors.white,
                      ),
                      child: buddyAvatarId != null
                          ? ClipOval(
                              child: UserAvatar(
                                avatarId: buddyAvatarId!,
                                size: 82,
                              ),
                            )
                          : Center(
                              child: Text(
                                buddyName.isNotEmpty ? buddyName[0].toUpperCase() : '?',
                                style: TextStyle(
                                  fontSize: 36,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.orange[700],
                                ),
                              ),
                            ),
                    ),
                  ),
                  // Workout badge
                  Positioned(
                    bottom: 0,
                    right: 0,
                    child: Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: Colors.orange[500],
                        shape: BoxShape.circle,
                        border: Border.all(color: Colors.white, width: 3),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.orange.withOpacity(0.3),
                            blurRadius: 8,
                          ),
                        ],
                      ),
                      child: const Icon(
                        Icons.fitness_center,
                        color: Colors.white,
                        size: 18,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 24),

              // Title
              Text(
                'Already Working Out! 🏋️',
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                  color: Colors.grey[800],
                ),
              ),
              const SizedBox(height: 12),

              // Message
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                decoration: BoxDecoration(
                  color: Colors.orange[50],
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Row(
                  children: [
                    Icon(Icons.info_outline, color: Colors.orange[700], size: 20),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        '$buddyName is currently in a workout. Try again when they\'re done!',
                        style: TextStyle(
                          fontSize: 14,
                          color: Colors.orange[900],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 24),

              // OK Button
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: () => Navigator.of(context).pop(),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.orange[500],
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    elevation: 2,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                  ),
                  child: const Text(
                    'Got it!',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                    ),
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

/// Popup shown when the join window has expired
class MissedWorkoutPopup extends StatelessWidget {
  final String buddyName;
  final String? buddyAvatarId;

  const MissedWorkoutPopup({
    super.key,
    required this.buddyName,
    this.buddyAvatarId,
  });

  static Future<void> show(
    BuildContext context, {
    required String buddyName,
    String? buddyAvatarId,
  }) {
    HapticFeedback.lightImpact();
    
    return showDialog(
      context: context,
      builder: (context) => MissedWorkoutPopup(
        buddyName: buddyName,
        buddyAvatarId: buddyAvatarId,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: Colors.transparent,
      child: Container(
        constraints: const BoxConstraints(maxWidth: 340),
        padding: const EdgeInsets.all(28),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(24),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 80,
              height: 80,
              decoration: BoxDecoration(
                color: Colors.grey[100],
                shape: BoxShape.circle,
              ),
              child: Icon(
                Icons.timer_off_outlined,
                color: Colors.grey[400],
                size: 40,
              ),
            ),
            const SizedBox(height: 20),

            Text(
              'Window Closed',
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.bold,
                color: Colors.grey[800],
              ),
            ),
            const SizedBox(height: 12),

            Text(
              'Sorry, $buddyName has already started working out without you',
              style: TextStyle(
                fontSize: 15,
                color: Colors.grey[600],
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 24),

            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: () => Navigator.of(context).pop(),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.grey[200],
                  foregroundColor: Colors.grey[700],
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  elevation: 0,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                ),
                child: const Text(
                  'OK',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Popup shown when buddy completed the workout
class BuddyCompletedWorkoutPopup extends StatelessWidget {
  final String buddyName;
  final String? buddyAvatarId;

  const BuddyCompletedWorkoutPopup({
    super.key,
    required this.buddyName,
    this.buddyAvatarId,
  });

  static Future<void> show(
    BuildContext context, {
    required String buddyName,
    String? buddyAvatarId,
  }) {
    HapticFeedback.mediumImpact();
    
    return showDialog(
      context: context,
      builder: (context) => BuddyCompletedWorkoutPopup(
        buddyName: buddyName,
        buddyAvatarId: buddyAvatarId,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: Colors.transparent,
      child: Container(
        constraints: const BoxConstraints(maxWidth: 340),
        padding: const EdgeInsets.all(28),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(24),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 90,
              height: 90,
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [Colors.green[400]!, Colors.teal[400]!],
                ),
                shape: BoxShape.circle,
                boxShadow: [
                  BoxShadow(
                    color: Colors.green.withOpacity(0.3),
                    blurRadius: 20,
                    offset: const Offset(0, 8),
                  ),
                ],
              ),
              child: const Icon(
                Icons.check_circle_outline,
                color: Colors.white,
                size: 50,
              ),
            ),
            const SizedBox(height: 24),

            const Text(
              'Workout Complete! 🎉',
              style: TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 12),

            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              decoration: BoxDecoration(
                color: Colors.green[50],
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text(
                '$buddyName completed the workout and helped the streak grow!',
                style: TextStyle(
                  fontSize: 15,
                  color: Colors.green[800],
                ),
                textAlign: TextAlign.center,
              ),
            ),
            const SizedBox(height: 24),

            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: () => Navigator.of(context).pop(),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.green[500],
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  elevation: 2,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                ),
                child: const Text(
                  'Awesome! 💪',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}