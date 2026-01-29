import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'dart:async';

/// Redesigned workout card with embedded timer for in_progress workouts
/// Shows timer progress directly in the card - no need to open a separate sheet
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
  final VoidCallback? onOpenTimer; // New: Open the full timer sheet

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
    this.onOpenTimer,
  });

  @override
  State<WorkoutCard> createState() => _WorkoutCardState();
}

class _WorkoutCardState extends State<WorkoutCard> {
  Timer? _timer;
  Duration _elapsed = Duration.zero;
  DateTime? _startTime;

  @override
  void initState() {
    super.initState();
    _initTimer();
  }

  @override
  void didUpdateWidget(WorkoutCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Reinitialize timer if workout changed
    if (oldWidget.workout['id'] != widget.workout['id'] ||
        oldWidget.workoutStatus != widget.workoutStatus) {
      _timer?.cancel();
      _initTimer();
    }
  }

  void _initTimer() {
    if (widget.workoutStatus == 'in_progress') {
      final startedAt = widget.workout['workout_started_at'];
      if (startedAt != null) {
        _startTime = DateTime.parse(startedAt);
        _updateElapsed();
        _timer = Timer.periodic(const Duration(seconds: 1), (_) {
          if (mounted) _updateElapsed();
        });
      }
    }
  }

  void _updateElapsed() {
    if (_startTime != null) {
      setState(() {
        _elapsed = DateTime.now().difference(_startTime!);
      });
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  int get _goalMinutes => widget.workout['planned_duration_minutes'] ?? 30;
  bool get _hasReachedGoal => _elapsed.inMinutes >= _goalMinutes;
  double get _progress => (_elapsed.inSeconds / (_goalMinutes * 60)).clamp(0.0, 1.0);

  @override
  Widget build(BuildContext context) {
    final isInProgress = widget.workoutStatus == 'in_progress';
    final isIncomingInvite = widget.isBuddy && widget.buddyStatus == 'pending';
    final cancelRequestedBy = widget.workout['cancel_requested_by'];
    final hasCancelRequest = cancelRequestedBy != null;

    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: isInProgress
                ? Colors.orange.withOpacity(0.2)
                : isIncomingInvite
                    ? Colors.blue.withOpacity(0.15)
                    : Colors.black.withOpacity(0.06),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
        border: isInProgress
            ? Border.all(color: Colors.orange[300]!, width: 2)
            : isIncomingInvite
                ? Border.all(color: Colors.blue[300]!, width: 2)
                : null,
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
                // Workout type icon
                _buildWorkoutIcon(),
                const SizedBox(width: 14),

                // Details
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Title row
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
                          _buildStatusChip(),
                        ],
                      ),

                      const SizedBox(height: 4),

                      // Partner
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

                      // Date, Time, Duration row
                      Wrap(
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
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),

          // Cancel request banner (if someone requested cancel)
          if (hasCancelRequest) _buildCancelRequestBanner(cancelRequestedBy),

          // Timer section for in_progress workouts
          if (isInProgress) _buildTimerSection(),

          // Invite actions (if incoming invite)
          if (isIncomingInvite) _buildInviteActions(),

          // Regular actions
          if (!isIncomingInvite) _buildWorkoutActions(),
        ],
      ),
    );
  }

  Widget _buildWorkoutIcon() {
    final workoutType = widget.workout['workout_type'] ?? 'Workout';
    final color = _getWorkoutColor(workoutType);
    final icon = _getWorkoutIcon(workoutType);
    final isInProgress = widget.workoutStatus == 'in_progress';

    return Container(
      width: 56,
      height: 56,
      decoration: BoxDecoration(
        color: color.withOpacity(0.15),
        borderRadius: BorderRadius.circular(16),
        border: isInProgress
            ? Border.all(color: color.withOpacity(0.5), width: 2)
            : null,
      ),
      child: Icon(icon, color: color, size: 28),
    );
  }

  Widget _buildStatusChip() {
    Color bgColor;
    Color textColor;
    String label;

    switch (widget.workoutStatus?.toLowerCase()) {
      case 'in_progress':
        bgColor = Colors.orange[100]!;
        textColor = Colors.orange[800]!;
        label = '🔥 Active';
        break;
      case 'completed':
        bgColor = Colors.green[100]!;
        textColor = Colors.green[800]!;
        label = '✓ Done';
        break;
      default:
        bgColor = Colors.blue[50]!;
        textColor = Colors.blue[700]!;
        label = '📅 Scheduled';
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

  Widget _buildCancelRequestBanner(String? requestedBy) {
    final currentUserId = widget.workout['user_id'] == requestedBy
        ? widget.workout['user_id']
        : widget.workout['buddy_id'];
    final isMyRequest = requestedBy == currentUserId;

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.red[50],
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.red[200]!),
      ),
      child: Row(
        children: [
          Icon(Icons.warning_amber_rounded, color: Colors.red[600], size: 20),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              isMyRequest
                  ? 'You requested to cancel. Waiting for your buddy to confirm.'
                  : 'Your buddy requested to cancel this workout.',
              style: TextStyle(fontSize: 13, color: Colors.red[800]),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTimerSection() {
    return GestureDetector(
      onTap: () {
        HapticFeedback.lightImpact();
        widget.onOpenTimer?.call();
      },
      child: Container(
        margin: const EdgeInsets.fromLTRB(16, 0, 16, 12),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: _hasReachedGoal
                ? [Colors.green[50]!, Colors.green[100]!]
                : [Colors.orange[50]!, Colors.orange[100]!],
          ),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: _hasReachedGoal ? Colors.green[300]! : Colors.orange[300]!,
          ),
        ),
        child: Column(
          children: [
            // Timer display
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  _hasReachedGoal ? Icons.check_circle : Icons.timer,
                  color: _hasReachedGoal ? Colors.green[600] : Colors.orange[600],
                  size: 28,
                ),
                const SizedBox(width: 12),
                Text(
                  _formatElapsed(_elapsed),
                  style: TextStyle(
                    fontSize: 36,
                    fontWeight: FontWeight.bold,
                    color: _hasReachedGoal ? Colors.green[700] : Colors.orange[800],
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
                const SizedBox(width: 12),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: _hasReachedGoal
                        ? Colors.green[200]
                        : Colors.orange[200],
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    'Goal: ${_goalMinutes}m',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: _hasReachedGoal
                          ? Colors.green[800]
                          : Colors.orange[900],
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
                value: _progress,
                minHeight: 8,
                backgroundColor: Colors.white.withOpacity(0.5),
                valueColor: AlwaysStoppedAnimation<Color>(
                  _hasReachedGoal ? Colors.green[500]! : Colors.orange[500]!,
                ),
              ),
            ),
            const SizedBox(height: 8),

            // Status text
            Text(
              _hasReachedGoal
                  ? '🎉 Goal reached! Ready to complete!'
                  : '${_formatRemaining()} remaining',
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: _hasReachedGoal ? Colors.green[700] : Colors.grey[600],
              ),
            ),

            const SizedBox(height: 8),

            // Tap hint
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.touch_app, size: 14, color: Colors.grey[500]),
                const SizedBox(width: 4),
                Text(
                  'Tap to open full timer',
                  style: TextStyle(fontSize: 11, color: Colors.grey[500]),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildInviteActions() {
    final creator = widget.workout['creator'];
    final creatorName = creator?['display_name'] ?? 'Someone';

    return Container(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
      child: Column(
        children: [
          Text(
            '$creatorName invited you to work out together!',
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

  Widget _buildWorkoutActions() {
    final isInProgress = widget.workoutStatus == 'in_progress';
    final isScheduled = widget.workoutStatus == 'scheduled';
    final cancelRequestedBy = widget.workout['cancel_requested_by'];

    return Container(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
      child: Row(
        children: [
          // Start button (for scheduled workouts)
          if (isScheduled)
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
                  elevation: 0,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                ),
              ),
            ),

          // Complete button (for in_progress workouts - LOCKED until goal)
          if (isInProgress)
            Expanded(
              child: ElevatedButton.icon(
                onPressed: _hasReachedGoal
                    ? () {
                        HapticFeedback.heavyImpact();
                        widget.onComplete?.call();
                      }
                    : null,
                icon: Icon(
                  _hasReachedGoal ? Icons.check_circle : Icons.lock,
                  size: 20,
                ),
                label: Text(_hasReachedGoal ? 'Complete' : 'Complete Goal First'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: _hasReachedGoal ? Colors.green[500] : Colors.grey[300],
                  foregroundColor: _hasReachedGoal ? Colors.white : Colors.grey[600],
                  disabledBackgroundColor: Colors.grey[300],
                  disabledForegroundColor: Colors.grey[600],
                  elevation: 0,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                ),
              ),
            ),

          // Cancel button
          if (isScheduled || isInProgress) ...[
            const SizedBox(width: 12),
            Container(
              decoration: BoxDecoration(
                color: cancelRequestedBy != null ? Colors.red[100] : Colors.red[50],
                borderRadius: BorderRadius.circular(14),
                border: Border.all(
                  color: cancelRequestedBy != null ? Colors.red[400]! : Colors.red[200]!,
                ),
              ),
              child: IconButton(
                onPressed: () {
                  HapticFeedback.lightImpact();
                  widget.onCancel?.call();
                },
                icon: Icon(
                  cancelRequestedBy != null ? Icons.cancel : Icons.close,
                  color: Colors.red[600],
                  size: 22,
                ),
                tooltip: cancelRequestedBy != null ? 'Confirm Cancel' : 'Request Cancel',
              ),
            ),
          ],
        ],
      ),
    );
  }

  // Helper methods
  Color _getWorkoutColor(String? type) {
    switch (type?.toLowerCase()) {
      case 'cardio':
        return Colors.red[600]!;
      case 'strength':
      case 'weights':
        return Colors.blue[600]!;
      case 'legs':
      case 'leg day':
      case 'lower body':
        return Colors.orange[600]!;
      case 'upper body':
        return Colors.purple[600]!;
      case 'full body':
        return Colors.indigo[600]!;
      case 'hiit':
        return Colors.deepOrange[600]!;
      case 'yoga':
        return Colors.teal[600]!;
      default:
        return Colors.green[600]!;
    }
  }

  IconData _getWorkoutIcon(String? type) {
    switch (type?.toLowerCase()) {
      case 'cardio':
        return Icons.directions_run;
      case 'strength':
      case 'weights':
        return Icons.fitness_center;
      case 'upper body':
        return Icons.accessibility_new;
      case 'lower body':
      case 'legs':
      case 'leg day':
        return Icons.directions_walk;
      case 'full body':
        return Icons.sports_gymnastics;
      case 'hiit':
        return Icons.flash_on;
      case 'yoga':
        return Icons.self_improvement;
      default:
        return Icons.sports;
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

  String _formatElapsed(Duration duration) {
    final minutes = duration.inMinutes;
    final seconds = duration.inSeconds % 60;
    return '${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';
  }

  String _formatRemaining() {
    final remaining = Duration(minutes: _goalMinutes) - _elapsed;
    if (remaining.isNegative) return '0:00';
    final minutes = remaining.inMinutes;
    final seconds = remaining.inSeconds % 60;
    return '$minutes:${seconds.toString().padLeft(2, '0')}';
  }
}