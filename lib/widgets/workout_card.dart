import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Clean, modern workout card for the Schedule page
/// Use this to replace the workout cards in _buildWorkoutList()
class WorkoutCard extends StatelessWidget {
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
  });

  @override
  Widget build(BuildContext context) {
    final isIncomingInvite = isBuddy && buddyStatus == 'pending';
    final creator = workout['creator'];

    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: isIncomingInvite
                ? Colors.blue.withOpacity(0.15)
                : Colors.black.withOpacity(0.06),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
        border: isIncomingInvite
            ? Border.all(color: Colors.blue[300]!, width: 2)
            : null,
      ),
      child: Column(
        children: [
          // Main content
          Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                // Workout type icon
                Container(
                  width: 56,
                  height: 56,
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [
                        _getWorkoutColor(workout['workout_type']),
                        _getWorkoutColor(workout['workout_type']).withOpacity(0.7),
                      ],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Icon(
                    _getWorkoutIcon(workout['workout_type']),
                    color: Colors.white,
                    size: 28,
                  ),
                ),

                const SizedBox(width: 16),

                // Info section
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Title row with status
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              workout['workout_type'] ?? 'Workout',
                              style: const TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                          _buildStatusChip(workoutStatus),
                        ],
                      ),

                      const SizedBox(height: 4),

                      // Partner
                      Row(
                        children: [
                          Icon(Icons.person, size: 14, color: Colors.blue[600]),
                          const SizedBox(width: 4),
                          Text(
                            'with $partnerName',
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
                            text: _formatDate(workout['workout_date']),
                          ),
                          _buildInfoTag(
                            icon: Icons.access_time,
                            text: _formatTime(workout['workout_time']),
                          ),
                          if (workout['planned_duration_minutes'] != null)
                            _buildInfoTag(
                              icon: Icons.timer,
                              text: _formatDuration(workout['planned_duration_minutes']),
                            ),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),

          // Invite actions (if incoming invite)
          if (isIncomingInvite)
            _buildInviteActions(creator),

          // Regular actions (if not an invite)
          if (!isIncomingInvite && (workoutStatus == 'scheduled' || workoutStatus == 'in_progress'))
            _buildWorkoutActions(),
        ],
      ),
    );
  }

  Widget _buildStatusChip(String? status) {
    Color bgColor;
    Color textColor;
    String label;

    switch (status?.toLowerCase()) {
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
        label = 'Scheduled';
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
          fontSize: 11,
          fontWeight: FontWeight.bold,
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
            style: TextStyle(
              fontSize: 11,
              color: Colors.grey[700],
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildInviteActions(Map<String, dynamic>? creator) {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
      child: Column(
        children: [
          const Divider(),
          const SizedBox(height: 8),
          Row(
            children: [
              Icon(Icons.mail_outline, size: 18, color: Colors.blue[600]),
              const SizedBox(width: 8),
              Text(
                '${creator?['display_name'] ?? 'Someone'} invited you!',
                style: TextStyle(
                  fontSize: 13,
                  color: Colors.grey[700],
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: ElevatedButton(
                  onPressed: () {
                    HapticFeedback.lightImpact();
                    onAccept?.call();
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.green[500],
                    foregroundColor: Colors.white,
                    elevation: 0,
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  child: const Text(
                    'Accept',
                    style: TextStyle(fontWeight: FontWeight.bold),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: OutlinedButton(
                  onPressed: () {
                    HapticFeedback.lightImpact();
                    onDecline?.call();
                  },
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Colors.grey[600],
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    side: BorderSide(color: Colors.grey[300]!),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  child: const Text(
                    'Decline',
                    style: TextStyle(fontWeight: FontWeight.w500),
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
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
      child: Row(
        children: [
          if (workoutStatus == 'scheduled')
            Expanded(
              child: ElevatedButton(
                onPressed: () {
                  HapticFeedback.lightImpact();
                  onStart?.call();
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: _getWorkoutColor(workout['workout_type']),
                  foregroundColor: Colors.white,
                  elevation: 0,
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                child: const Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.play_arrow, size: 20),
                    SizedBox(width: 4),
                    Text('Start', style: TextStyle(fontWeight: FontWeight.bold)),
                  ],
                ),
              ),
            ),
          if (workoutStatus == 'in_progress')
            Expanded(
              child: ElevatedButton(
                onPressed: () {
                  HapticFeedback.lightImpact();
                  onComplete?.call();
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.green[500],
                  foregroundColor: Colors.white,
                  elevation: 0,
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                child: const Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.check_circle, size: 20),
                    SizedBox(width: 4),
                    Text('Complete', style: TextStyle(fontWeight: FontWeight.bold)),
                  ],
                ),
              ),
            ),
          if (isCreator && workoutStatus == 'scheduled') ...[
            const SizedBox(width: 12),
            Container(
              decoration: BoxDecoration(
                color: Colors.red[50],
                borderRadius: BorderRadius.circular(12),
              ),
              child: IconButton(
                onPressed: () {
                  HapticFeedback.lightImpact();
                  onCancel?.call();
                },
                icon: Icon(Icons.delete_outline, color: Colors.red[400], size: 22),
                tooltip: 'Cancel',
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

  String _formatTime(String? time) {
    if (time == null) return '';
    try {
      final parts = time.split(':');
      int hour = int.parse(parts[0]);
      final minute = parts[1];
      final period = hour >= 12 ? 'PM' : 'AM';
      if (hour > 12) hour -= 12;
      if (hour == 0) hour = 12;
      return '$hour:$minute $period';
    } catch (e) {
      return time;
    }
  }

  String _formatDuration(int? minutes) {
    if (minutes == null) return '';
    final hours = minutes ~/ 60;
    final mins = minutes % 60;
    if (hours > 0) {
      return mins > 0 ? '${hours}h ${mins}m' : '${hours}h';
    }
    return '${mins}m';
  }
}