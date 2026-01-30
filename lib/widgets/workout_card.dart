import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'dart:async';

/// Workout card with buddy join system states
/// Shows different UI based on:
/// - scheduled: Normal scheduled workout
/// - waiting_to_join: Buddy started, waiting for creator to join
/// - in_progress: User is actively working out
/// - window_expired: Creator missed the join window
/// - buddy_completed: Buddy finished the workout
class WorkoutCard extends StatefulWidget {
  final Map<String, dynamic> workout;
  final String partnerName;
  final bool isCreator;
  final bool isBuddy;
  final String? buddyStatus;
  final String? workoutStatus;
  final VoidCallback? onStart;
  final VoidCallback? onComplete;
  final VoidCallback? onCancel;
  final VoidCallback? onAccept;
  final VoidCallback? onDecline;
  final VoidCallback? onJoin; // New: Creator joins buddy's workout
  final VoidCallback? onOpenTimer;

  const WorkoutCard({
    super.key,
    required this.workout,
    required this.partnerName,
    required this.isCreator,
    required this.isBuddy,
    this.buddyStatus,
    this.workoutStatus,
    this.onStart,
    this.onComplete,
    this.onCancel,
    this.onAccept,
    this.onDecline,
    this.onJoin,
    this.onOpenTimer,
  });

  @override
  State<WorkoutCard> createState() => _WorkoutCardState();
}

class _WorkoutCardState extends State<WorkoutCard> {
  Timer? _timer;
  int _joinWindowRemaining = 0; // seconds
  int _workoutElapsed = 0; // seconds

  @override
  void initState() {
    super.initState();
    _initTimers();
  }

  @override
  void didUpdateWidget(WorkoutCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.workout['id'] != widget.workout['id'] ||
        oldWidget.workoutStatus != widget.workoutStatus) {
      _timer?.cancel();
      _initTimers();
    }
  }

  void _initTimers() {
    final startedAt = widget.workout['workout_started_at'];
    final plannedDuration = widget.workout['planned_duration_minutes'] ?? 30;
    final creatorJoined = widget.workout['creator_joined'] ?? false;
    final startedByUserId = widget.workout['started_by_user_id'];

    if (widget.workoutStatus == 'in_progress' && startedAt != null) {
      final startTime = DateTime.parse(startedAt);
      final now = DateTime.now();
      
      // Calculate elapsed time
      _workoutElapsed = now.difference(startTime).inSeconds;

      // Calculate join window (quarter of planned duration)
      final joinWindowMinutes = plannedDuration ~/ 4;
      final joinWindowEnd = startTime.add(Duration(minutes: joinWindowMinutes));
      _joinWindowRemaining = joinWindowEnd.difference(now).inSeconds;

      // Start timer to update every second
      _timer = Timer.periodic(const Duration(seconds: 1), (_) {
        if (mounted) {
          setState(() {
            _workoutElapsed++;
            if (_joinWindowRemaining > 0) {
              _joinWindowRemaining--;
            }
          });
        }
      });
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  // Determine card state for creator
  String _getCreatorState() {
    final creatorJoined = widget.workout['creator_joined'] ?? false;
    final startedByUserId = widget.workout['started_by_user_id'];
    final buddyId = widget.workout['buddy_id'];

    if (widget.workoutStatus == 'completed') {
      if (!creatorJoined && startedByUserId == buddyId) {
        return 'buddy_completed';
      }
      return 'completed';
    }

    if (widget.workoutStatus == 'in_progress') {
      // Buddy started, creator hasn't joined
      if (startedByUserId == buddyId && !creatorJoined) {
        if (_joinWindowRemaining > 0) {
          return 'waiting_to_join';
        } else {
          return 'window_expired';
        }
      }
      // Creator has joined or started
      if (creatorJoined || startedByUserId == widget.workout['user_id']) {
        return 'in_progress';
      }
    }

    return 'scheduled';
  }

  @override
  Widget build(BuildContext context) {
    final isIncomingInvite = widget.isBuddy && widget.buddyStatus == 'pending';
    
    // Determine state if creator
    final creatorState = widget.isCreator ? _getCreatorState() : null;

    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: _getCardShadowColor(creatorState),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
        border: _getCardBorder(creatorState, isIncomingInvite),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Main content
          Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _buildWorkoutIcon(creatorState),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              widget.workout['workout_type'] ?? 'Workout',
                              style: const TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                          _buildStatusChip(creatorState),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Row(
                        children: [
                          Icon(Icons.person, size: 14, color: Colors.blue[600]),
                          const SizedBox(width: 4),
                          Text(
                            'with ${widget.partnerName}',
                            style: TextStyle(
                              fontSize: 13,
                              color: Colors.blue[600],
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      _buildInfoTags(),
                    ],
                  ),
                ),
              ],
            ),
          ),

          // State-specific content
          if (creatorState == 'waiting_to_join') _buildJoinWindowSection(),
          if (creatorState == 'window_expired') _buildWindowExpiredSection(),
          if (creatorState == 'buddy_completed') _buildBuddyCompletedSection(),
          if (creatorState == 'in_progress' || 
              (widget.isBuddy && widget.workoutStatus == 'in_progress'))
            _buildInProgressSection(),

          // Actions
          if (isIncomingInvite) _buildInviteActions(),
          if (!isIncomingInvite) _buildWorkoutActions(creatorState),
        ],
      ),
    );
  }

  Color _getCardShadowColor(String? state) {
    switch (state) {
      case 'waiting_to_join':
        return Colors.orange.withOpacity(0.2);
      case 'in_progress':
        return Colors.green.withOpacity(0.2);
      case 'window_expired':
        return Colors.grey.withOpacity(0.15);
      case 'buddy_completed':
        return Colors.green.withOpacity(0.15);
      default:
        return Colors.black.withOpacity(0.06);
    }
  }

  Border? _getCardBorder(String? state, bool isInvite) {
    if (state == 'waiting_to_join') {
      return Border.all(color: Colors.orange[300]!, width: 2);
    }
    if (state == 'in_progress') {
      return Border.all(color: Colors.green[300]!, width: 2);
    }
    if (isInvite) {
      return Border.all(color: Colors.blue[300]!, width: 2);
    }
    return null;
  }

  Widget _buildWorkoutIcon(String? state) {
    final workoutType = widget.workout['workout_type'] ?? 'Workout';
    final color = _getWorkoutColor(workoutType);
    final icon = _getWorkoutIcon(workoutType);

    return Container(
      width: 56,
      height: 56,
      decoration: BoxDecoration(
        color: state == 'window_expired' 
            ? Colors.grey[100] 
            : color.withOpacity(0.15),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Icon(
        icon, 
        color: state == 'window_expired' ? Colors.grey[400] : color, 
        size: 28,
      ),
    );
  }

  Widget _buildStatusChip(String? state) {
    Color bgColor;
    Color textColor;
    String label;

    switch (state) {
      case 'waiting_to_join':
        bgColor = Colors.orange[100]!;
        textColor = Colors.orange[800]!;
        label = '⏳ Waiting';
        break;
      case 'in_progress':
        bgColor = Colors.green[100]!;
        textColor = Colors.green[800]!;
        label = '🔥 Active';
        break;
      case 'window_expired':
        bgColor = Colors.grey[200]!;
        textColor = Colors.grey[600]!;
        label = '❌ Missed';
        break;
      case 'buddy_completed':
        bgColor = Colors.green[100]!;
        textColor = Colors.green[800]!;
        label = '✅ Done';
        break;
      default:
        // Check if it's a pending invite for buddy
        if (widget.isBuddy && widget.buddyStatus == 'pending') {
          bgColor = Colors.blue[100]!;
          textColor = Colors.blue[800]!;
          label = '📨 Invite';
        } else if (widget.workoutStatus == 'in_progress') {
          bgColor = Colors.green[100]!;
          textColor = Colors.green[800]!;
          label = '🔥 Active';
        } else {
          bgColor = Colors.blue[50]!;
          textColor = Colors.blue[700]!;
          label = '📅 Scheduled';
        }
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w600,
          color: textColor,
        ),
      ),
    );
  }

  Widget _buildInfoTags() {
    return Wrap(
      spacing: 8,
      runSpacing: 4,
      children: [
        _buildInfoTag(
          icon: Icons.calendar_today,
          text: _formatDate(widget.workout['workout_date']),
        ),
        _buildInfoTag(
          icon: Icons.access_time,
          text: _formatTime(widget.workout['workout_time']),
        ),
        if (widget.workout['planned_duration_minutes'] != null)
          _buildInfoTag(
            icon: Icons.timer,
            text: _formatDuration(widget.workout['planned_duration_minutes']),
          ),
      ],
    );
  }

  Widget _buildInfoTag({required IconData icon, required String text}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: Colors.grey[100],
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 12, color: Colors.grey[600]),
          const SizedBox(width: 4),
          Text(
            text,
            style: TextStyle(fontSize: 12, color: Colors.grey[700]),
          ),
        ],
      ),
    );
  }

  Widget _buildJoinWindowSection() {
    final joinMinutes = _joinWindowRemaining ~/ 60;
    final joinSeconds = _joinWindowRemaining % 60;

    return Container(
      margin: const EdgeInsets.fromLTRB(16, 0, 16, 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [Colors.orange[50]!, Colors.amber[50]!],
        ),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.orange[200]!),
      ),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.timer, color: Colors.orange[600], size: 22),
              const SizedBox(width: 8),
              Text(
                'Waiting for you to join!',
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.bold,
                  color: Colors.orange[800],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          
          // Countdown
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Text(
              '$joinMinutes:${joinSeconds.toString().padLeft(2, '0')}',
              style: TextStyle(
                fontSize: 28,
                fontWeight: FontWeight.bold,
                color: _joinWindowRemaining < 60 ? Colors.red : Colors.orange[700],
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
          ),
          const SizedBox(height: 8),
          
          Text(
            'left to join',
            style: TextStyle(
              fontSize: 13,
              color: Colors.grey[600],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildWindowExpiredSection() {
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 0, 16, 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.grey[100],
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        children: [
          Icon(Icons.info_outline, color: Colors.grey[500], size: 22),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              '${widget.partnerName} started without you',
              style: TextStyle(
                fontSize: 14,
                color: Colors.grey[600],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBuddyCompletedSection() {
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 0, 16, 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [Colors.green[50]!, Colors.teal[50]!],
        ),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.green[200]!),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: Colors.green[100],
              shape: BoxShape.circle,
            ),
            child: Icon(Icons.check, color: Colors.green[600], size: 20),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${widget.partnerName} completed the workout!',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: Colors.green[800],
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  'Helped the streak grow 🎉',
                  style: TextStyle(
                    fontSize: 12,
                    color: Colors.green[600],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildInProgressSection() {
    final plannedDuration = widget.workout['planned_duration_minutes'] ?? 30;
    final goalSeconds = plannedDuration * 60;
    final progress = (_workoutElapsed / goalSeconds).clamp(0.0, 1.0);
    final hasReachedGoal = _workoutElapsed >= goalSeconds;

    final elapsedMinutes = _workoutElapsed ~/ 60;
    final elapsedSeconds = _workoutElapsed % 60;

    return GestureDetector(
      onTap: widget.onOpenTimer,
      child: Container(
        margin: const EdgeInsets.fromLTRB(16, 0, 16, 12),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: hasReachedGoal
                ? [Colors.green[50]!, Colors.green[100]!]
                : [Colors.blue[50]!, Colors.blue[100]!],
          ),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: hasReachedGoal ? Colors.green[300]! : Colors.blue[300]!,
          ),
        ),
        child: Column(
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  hasReachedGoal ? Icons.check_circle : Icons.timer,
                  color: hasReachedGoal ? Colors.green[600] : Colors.blue[600],
                  size: 24,
                ),
                const SizedBox(width: 10),
                Text(
                  '${elapsedMinutes.toString().padLeft(2, '0')}:${elapsedSeconds.toString().padLeft(2, '0')}',
                  style: TextStyle(
                    fontSize: 32,
                    fontWeight: FontWeight.bold,
                    color: hasReachedGoal ? Colors.green[700] : Colors.blue[700],
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
                const SizedBox(width: 10),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: hasReachedGoal ? Colors.green[200] : Colors.blue[200],
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    '/ ${plannedDuration}m',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: hasReachedGoal ? Colors.green[800] : Colors.blue[800],
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            
            // Progress bar
            ClipRRect(
              borderRadius: BorderRadius.circular(6),
              child: LinearProgressIndicator(
                value: progress,
                minHeight: 8,
                backgroundColor: Colors.white.withOpacity(0.5),
                valueColor: AlwaysStoppedAnimation<Color>(
                  hasReachedGoal ? Colors.green[500]! : Colors.blue[500]!,
                ),
              ),
            ),
            const SizedBox(height: 8),
            
            Text(
              hasReachedGoal 
                  ? '🎉 Goal reached! Ready to complete!' 
                  : 'Working out...',
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: hasReachedGoal ? Colors.green[700] : Colors.grey[600],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildInviteActions() {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
      child: Column(
        children: [
          Text(
            '${widget.workout['creator']?['display_name'] ?? 'Someone'} invited you!',
            style: TextStyle(
              fontSize: 13,
              color: Colors.grey[600],
              fontStyle: FontStyle.italic,
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: ElevatedButton.icon(
                  onPressed: () {
                    HapticFeedback.lightImpact();
                    widget.onAccept?.call();
                  },
                  icon: const Icon(Icons.check, size: 18),
                  label: const Text('Accept'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.green[500],
                    foregroundColor: Colors.white,
                    elevation: 0,
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () {
                    HapticFeedback.lightImpact();
                    widget.onDecline?.call();
                  },
                  icon: Icon(Icons.close, size: 18, color: Colors.red[400]),
                  label: Text('Decline', style: TextStyle(color: Colors.red[400])),
                  style: OutlinedButton.styleFrom(
                    side: BorderSide(color: Colors.red[300]!),
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildWorkoutActions(String? creatorState) {
    // No actions for expired or completed states
    if (creatorState == 'window_expired' || creatorState == 'buddy_completed') {
      return const SizedBox.shrink();
    }

    // Join button for waiting state
    if (creatorState == 'waiting_to_join') {
      return Container(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        child: SizedBox(
          width: double.infinity,
          child: ElevatedButton.icon(
            onPressed: () {
              HapticFeedback.heavyImpact();
              widget.onJoin?.call();
            },
            icon: const Icon(Icons.play_arrow, size: 22),
            label: const Text('Join Workout'),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.orange[500],
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(vertical: 14),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14),
              ),
            ),
          ),
        ),
      );
    }

    // In progress - show locked/unlocked complete button
    if (creatorState == 'in_progress' || 
        (widget.isBuddy && widget.workoutStatus == 'in_progress')) {
      final plannedDuration = widget.workout['planned_duration_minutes'] ?? 30;
      final hasReachedGoal = _workoutElapsed >= (plannedDuration * 60);

      return Container(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        child: SizedBox(
          width: double.infinity,
          child: ElevatedButton.icon(
            onPressed: hasReachedGoal
                ? () {
                    HapticFeedback.heavyImpact();
                    widget.onComplete?.call();
                  }
                : null,
            icon: Icon(
              hasReachedGoal ? Icons.check_circle : Icons.lock,
              size: 20,
            ),
            label: Text(hasReachedGoal ? 'Complete Workout' : 'Complete Goal First'),
            style: ElevatedButton.styleFrom(
              backgroundColor: hasReachedGoal ? Colors.green[500] : Colors.grey[300],
              foregroundColor: hasReachedGoal ? Colors.white : Colors.grey[600],
              disabledBackgroundColor: Colors.grey[300],
              disabledForegroundColor: Colors.grey[600],
              padding: const EdgeInsets.symmetric(vertical: 14),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14),
              ),
            ),
          ),
        ),
      );
    }

    // Scheduled - show start button
    if (widget.workoutStatus == 'scheduled') {
      return Container(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        child: Row(
          children: [
            Expanded(
              child: ElevatedButton.icon(
                onPressed: () {
                  HapticFeedback.lightImpact();
                  widget.onStart?.call();
                },
                icon: const Icon(Icons.play_arrow, size: 20),
                label: const Text('Start Workout'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: _getWorkoutColor(widget.workout['workout_type']),
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                ),
              ),
            ),
            if (widget.isCreator) ...[
              const SizedBox(width: 12),
              Container(
                decoration: BoxDecoration(
                  color: Colors.red[50],
                  borderRadius: BorderRadius.circular(14),
                ),
                child: IconButton(
                  onPressed: () {
                    HapticFeedback.lightImpact();
                    widget.onCancel?.call();
                  },
                  icon: Icon(Icons.close, color: Colors.red[400]),
                  tooltip: 'Cancel',
                ),
              ),
            ],
          ],
        ),
      );
    }

    return const SizedBox.shrink();
  }

  // Helper methods
  Color _getWorkoutColor(String? type) {
    switch (type?.toLowerCase()) {
      case 'cardio': return Colors.red[600]!;
      case 'strength': return Colors.blue[600]!;
      case 'leg day':
      case 'lower body': return Colors.orange[600]!;
      case 'upper body': return Colors.purple[600]!;
      case 'full body': return Colors.indigo[600]!;
      case 'hiit': return Colors.deepOrange[600]!;
      case 'yoga': return Colors.teal[600]!;
      default: return Colors.green[600]!;
    }
  }

  IconData _getWorkoutIcon(String? type) {
    switch (type?.toLowerCase()) {
      case 'cardio': return Icons.directions_run;
      case 'strength': return Icons.fitness_center;
      case 'upper body': return Icons.accessibility_new;
      case 'lower body':
      case 'leg day': return Icons.directions_walk;
      case 'full body': return Icons.sports_gymnastics;
      case 'hiit': return Icons.flash_on;
      case 'yoga': return Icons.self_improvement;
      default: return Icons.sports;
    }
  }

  String _formatDate(String? dateStr) {
    if (dateStr == null) return '';
    try {
      final date = DateTime.parse(dateStr);
      final now = DateTime.now();
      final today = DateTime(now.year, now.month, now.day);
      final tomorrow = today.add(const Duration(days: 1));
      final workoutDate = DateTime(date.year, date.month, date.day);

      if (workoutDate == today) return 'Today';
      if (workoutDate == tomorrow) return 'Tomorrow';

      final days = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
      return '${days[date.weekday - 1]}, ${date.month}/${date.day}';
    } catch (e) {
      return dateStr;
    }
  }

  String _formatTime(String? timeStr) {
    if (timeStr == null) return '';
    try {
      final parts = timeStr.split(':');
      final hour = int.parse(parts[0]);
      final minute = int.parse(parts[1]);
      final period = hour >= 12 ? 'PM' : 'AM';
      final displayHour = hour > 12 ? hour - 12 : (hour == 0 ? 12 : hour);
      return '$displayHour:${minute.toString().padLeft(2, '0')} $period';
    } catch (e) {
      return timeStr;
    }
  }

  String _formatDuration(int? minutes) {
    if (minutes == null) return '';
    if (minutes < 60) return '${minutes}m';
    final hours = minutes ~/ 60;
    final mins = minutes % 60;
    return mins > 0 ? '${hours}h ${mins}m' : '${hours}h';
  }
}