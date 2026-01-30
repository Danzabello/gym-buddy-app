import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:confetti/confetti.dart';

/// A celebration overlay shown when completing a workout
/// Usage: WorkoutCelebration.show(context, workoutType: 'Cardio', duration: 45, buddyName: 'John');
class WorkoutCelebration {
  static OverlayEntry? _overlayEntry;
  static bool _isShowing = false;

  /// Show the celebration overlay
  static void show(
    BuildContext context, {
    required String workoutType,
    int? duration,
    String? buddyName,
  }) {
    // Don't show if already showing
    if (_isShowing) return;
    _isShowing = true;

    // Haptic feedback
    HapticFeedback.heavyImpact();

    _overlayEntry = OverlayEntry(
      builder: (context) => _CelebrationOverlay(
        workoutType: workoutType,
        duration: duration,
        buddyName: buddyName,
        onDismiss: hide,
      ),
    );

    Overlay.of(context).insert(_overlayEntry!);

    // Auto-dismiss after 4 seconds
    Future.delayed(const Duration(seconds: 4), () {
      hide();
    });
  }

  /// Hide the celebration overlay
  static void hide() {
    if (!_isShowing) return;
    _isShowing = false;
    _overlayEntry?.remove();
    _overlayEntry = null;
  }
}

class _CelebrationOverlay extends StatefulWidget {
  final String workoutType;
  final int? duration;
  final String? buddyName;
  final VoidCallback onDismiss;

  const _CelebrationOverlay({
    required this.workoutType,
    this.duration,
    this.buddyName,
    required this.onDismiss,
  });

  @override
  State<_CelebrationOverlay> createState() => _CelebrationOverlayState();
}

class _CelebrationOverlayState extends State<_CelebrationOverlay>
    with SingleTickerProviderStateMixin {
  late AnimationController _animationController;
  late Animation<double> _scaleAnimation;
  late Animation<double> _fadeAnimation;

  // Confetti controllers - created fresh each time
  late ConfettiController _confettiLeft;
  late ConfettiController _confettiRight;
  late ConfettiController _confettiTop;
  
  bool _disposed = false;

  @override
  void initState() {
    super.initState();

    // Animation controller
    _animationController = AnimationController(
      duration: const Duration(milliseconds: 600),
      vsync: this,
    );

    _scaleAnimation = CurvedAnimation(
      parent: _animationController,
      curve: Curves.elasticOut,
    );

    _fadeAnimation = CurvedAnimation(
      parent: _animationController,
      curve: Curves.easeIn,
    );

    // Create confetti controllers
    _confettiLeft = ConfettiController(duration: const Duration(seconds: 3));
    _confettiRight = ConfettiController(duration: const Duration(seconds: 3));
    _confettiTop = ConfettiController(duration: const Duration(seconds: 3));

    // Start animations
    _animationController.forward();
    
    // Delay confetti slightly for better effect
    Future.delayed(const Duration(milliseconds: 200), () {
      if (!_disposed && mounted) {
        _confettiLeft.play();
        _confettiRight.play();
        _confettiTop.play();
      }
    });
  }

  @override
  void dispose() {
    _disposed = true;
    _animationController.dispose();
    // Dispose confetti controllers properly
    _confettiLeft.dispose();
    _confettiRight.dispose();
    _confettiTop.dispose();
    super.dispose();
  }

  String _getCelebrationMessage() {
    final duration = widget.duration ?? 0;
    if (duration >= 90) return "Beast Mode! 🦁";
    if (duration >= 60) return "Incredible! 💪";
    if (duration >= 45) return "Awesome Work! 🔥";
    if (duration >= 30) return "Great Job! ⭐";
    return "Nice Work! 👏";
  }

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: GestureDetector(
        onTap: widget.onDismiss,
        child: Container(
          color: Colors.black54,
          child: Stack(
            children: [
              // Left confetti
              Align(
                alignment: Alignment.topLeft,
                child: ConfettiWidget(
                  confettiController: _confettiLeft,
                  blastDirection: -0.5, // Diagonal right-down
                  emissionFrequency: 0.05,
                  numberOfParticles: 20,
                  maxBlastForce: 20,
                  minBlastForce: 10,
                  gravity: 0.2,
                  colors: const [
                    Colors.green,
                    Colors.blue,
                    Colors.pink,
                    Colors.orange,
                    Colors.purple,
                    Colors.yellow,
                  ],
                ),
              ),

              // Right confetti
              Align(
                alignment: Alignment.topRight,
                child: ConfettiWidget(
                  confettiController: _confettiRight,
                  blastDirection: 3.6, // Diagonal left-down
                  emissionFrequency: 0.05,
                  numberOfParticles: 20,
                  maxBlastForce: 20,
                  minBlastForce: 10,
                  gravity: 0.2,
                  colors: const [
                    Colors.red,
                    Colors.blue,
                    Colors.green,
                    Colors.yellow,
                    Colors.purple,
                    Colors.orange,
                  ],
                ),
              ),

              // Top center confetti
              Align(
                alignment: Alignment.topCenter,
                child: ConfettiWidget(
                  confettiController: _confettiTop,
                  blastDirection: 1.5708, // Down
                  emissionFrequency: 0.05,
                  numberOfParticles: 30,
                  maxBlastForce: 15,
                  minBlastForce: 5,
                  gravity: 0.3,
                  colors: const [
                    Colors.green,
                    Colors.blue,
                    Colors.pink,
                    Colors.orange,
                    Colors.purple,
                    Colors.red,
                    Colors.yellow,
                  ],
                ),
              ),

              // Center celebration card
              Center(
                child: FadeTransition(
                  opacity: _fadeAnimation,
                  child: ScaleTransition(
                    scale: _scaleAnimation,
                    child: Container(
                      margin: const EdgeInsets.all(32),
                      padding: const EdgeInsets.all(32),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(24),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withOpacity(0.3),
                            blurRadius: 20,
                            spreadRadius: 5,
                          ),
                        ],
                      ),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          // Trophy icon
                          Container(
                            width: 100,
                            height: 100,
                            decoration: BoxDecoration(
                              color: Colors.amber.shade50,
                              shape: BoxShape.circle,
                              border: Border.all(
                                color: Colors.amber,
                                width: 3,
                              ),
                            ),
                            child: const Center(
                              child: Text(
                                '🏆',
                                style: TextStyle(fontSize: 50),
                              ),
                            ),
                          ),
                          const SizedBox(height: 24),

                          // Celebration message
                          Text(
                            _getCelebrationMessage(),
                            style: const TextStyle(
                              fontSize: 28,
                              fontWeight: FontWeight.bold,
                              color: Colors.black87,
                            ),
                          ),
                          const SizedBox(height: 8),

                          // Workout completed text
                          Text(
                            'Workout Completed!',
                            style: TextStyle(
                              fontSize: 18,
                              color: Colors.grey.shade600,
                            ),
                          ),
                          const SizedBox(height: 16),

                          // Workout type and duration
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 16,
                              vertical: 8,
                            ),
                            decoration: BoxDecoration(
                              gradient: LinearGradient(
                                colors: [
                                  Colors.green.shade400,
                                  Colors.green.shade600,
                                ],
                              ),
                              borderRadius: BorderRadius.circular(20),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text(
                                  widget.workoutType,
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                                if (widget.duration != null) ...[
                                  const SizedBox(width: 8),
                                  Container(
                                    width: 1,
                                    height: 16,
                                    color: Colors.white54,
                                  ),
                                  const SizedBox(width: 8),
                                  Text(
                                    '${widget.duration} min',
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ],
                              ],
                            ),
                          ),

                          // Buddy name if present
                          if (widget.buddyName != null) ...[
                            const SizedBox(height: 12),
                            Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                const Icon(
                                  Icons.people,
                                  size: 18,
                                  color: Colors.blue,
                                ),
                                const SizedBox(width: 6),
                                Text(
                                  'with ${widget.buddyName}',
                                  style: TextStyle(
                                    fontSize: 14,
                                    color: Colors.grey.shade700,
                                  ),
                                ),
                              ],
                            ),
                          ],

                          const SizedBox(height: 24),

                          // Streak check-in indicator
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 6,
                            ),
                            decoration: BoxDecoration(
                              color: Colors.orange.shade50,
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(
                                color: Colors.orange.shade200,
                              ),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(
                                  Icons.local_fire_department,
                                  size: 18,
                                  color: Colors.orange.shade700,
                                ),
                                const SizedBox(width: 6),
                                Text(
                                  'Streak updated!',
                                  style: TextStyle(
                                    fontSize: 13,
                                    color: Colors.orange.shade700,
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                              ],
                            ),
                          ),

                          const SizedBox(height: 16),

                          // Tap to dismiss
                          Text(
                            'Tap anywhere to continue',
                            style: TextStyle(
                              fontSize: 12,
                              color: Colors.grey.shade400,
                            ),
                          ),
                        ],
                      ),
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