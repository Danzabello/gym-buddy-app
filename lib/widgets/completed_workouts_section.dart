import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../services/workout_service.dart';

/// Completed Workouts History Section
/// Shows recent completed workouts with stats and details
class CompletedWorkoutsSection extends StatefulWidget {
  const CompletedWorkoutsSection({super.key});

  @override
  State<CompletedWorkoutsSection> createState() => _CompletedWorkoutsSectionState();
}

class _CompletedWorkoutsSectionState extends State<CompletedWorkoutsSection> {
  final WorkoutService _workoutService = WorkoutService();
  List<Map<String, dynamic>> _completedWorkouts = [];
  bool _isLoading = true;
  bool _isExpanded = false;

  @override
  void initState() {
    super.initState();
    _loadCompletedWorkouts();
  }

  Future<void> _loadCompletedWorkouts() async {
    final workouts = await _workoutService.getCompletedWorkouts(limit: 10);
    if (mounted) {
      setState(() {
        _completedWorkouts = workouts;
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const SizedBox.shrink();
    }

    if (_completedWorkouts.isEmpty) {
      return const SizedBox.shrink();
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Header
        InkWell(
          onTap: () {
            HapticFeedback.selectionClick();
            setState(() => _isExpanded = !_isExpanded);
          },
          borderRadius: BorderRadius.circular(12),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [Colors.green[400]!, Colors.teal[400]!],
                    ),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Icon(
                    Icons.history,
                    color: Colors.white,
                    size: 20,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Completed Workouts',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                          color: Color(0xFF2C3E50),
                        ),
                      ),
                      Text(
                        '${_completedWorkouts.length} recent workouts',
                        style: TextStyle(
                          fontSize: 12,
                          color: Colors.grey[600],
                        ),
                      ),
                    ],
                  ),
                ),
                AnimatedRotation(
                  turns: _isExpanded ? 0.5 : 0,
                  duration: const Duration(milliseconds: 200),
                  child: Icon(
                    Icons.keyboard_arrow_down,
                    color: Colors.grey[600],
                  ),
                ),
              ],
            ),
          ),
        ),

        // Expandable content
        AnimatedCrossFade(
          firstChild: const SizedBox.shrink(),
          secondChild: Column(
            children: [
              const SizedBox(height: 12),
              ..._completedWorkouts.map((workout) => _buildCompletedWorkoutCard(workout)),
            ],
          ),
          crossFadeState: _isExpanded 
              ? CrossFadeState.showSecond 
              : CrossFadeState.showFirst,
          duration: const Duration(milliseconds: 300),
        ),
      ],
    );
  }

  Widget _buildCompletedWorkoutCard(Map<String, dynamic> workout) {
    final workoutType = workout['workout_type'] ?? 'Workout';
    final duration = workout['actual_duration_minutes'] ?? 0;
    final completedAt = workout['workout_completed_at'];
    final buddy = workout['buddy'];
    final creator = workout['creator'];
    
    // Get workout-specific color and icon
    final color = _getWorkoutColor(workoutType);
    final icon = _getWorkoutIcon(workoutType);

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: color.withOpacity(0.3)),
        boxShadow: [
          BoxShadow(
            color: color.withOpacity(0.1),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        children: [
          // Color bar on left
          Container(
            width: 6,
            height: 90,
            decoration: BoxDecoration(
              color: color,
              borderRadius: const BorderRadius.only(
                topLeft: Radius.circular(16),
                bottomLeft: Radius.circular(16),
              ),
            ),
          ),
          
          // Main content
          Expanded(
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Row(
                children: [
                  // Workout type icon (color-coded)
                  Container(
                    width: 48,
                    height: 48,
                    decoration: BoxDecoration(
                      color: color.withOpacity(0.15),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Icon(
                      icon,
                      color: color,
                      size: 26,
                    ),
                  ),
                  const SizedBox(width: 14),

                  // Details
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          workoutType,
                          style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                            color: Color(0xFF2C3E50),
                          ),
                        ),
                        const SizedBox(height: 6),
                        Row(
                          children: [
                            _buildDetailChip(
                              icon: Icons.timer,
                              text: _formatDuration(duration),
                            ),
                            const SizedBox(width: 10),
                            _buildDetailChip(
                              icon: Icons.calendar_today,
                              text: _formatCompletedDate(completedAt),
                            ),
                          ],
                        ),
                        if (buddy != null || creator != null) ...[
                          const SizedBox(height: 6),
                          Row(
                            children: [
                              Icon(Icons.people, size: 14, color: color),
                              const SizedBox(width: 4),
                              Text(
                                'with ${buddy?['display_name'] ?? creator?['display_name'] ?? 'buddy'}',
                                style: TextStyle(
                                  fontSize: 13,
                                  color: color,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ],
                          ),
                        ],
                      ],
                    ),
                  ),

                  // Checkmark or trophy
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: duration >= 60 ? Colors.amber[50] : Colors.green[50],
                      shape: BoxShape.circle,
                    ),
                    child: duration >= 90
                        ? const Text('🏆', style: TextStyle(fontSize: 18))
                        : duration >= 60
                            ? const Text('⭐', style: TextStyle(fontSize: 18))
                            : Icon(Icons.check, color: Colors.green[600], size: 20),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDetailChip({required IconData icon, required String text}) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 12, color: Colors.grey[600]),
        const SizedBox(width: 3),
        Text(
          text,
          style: TextStyle(
            fontSize: 12,
            color: Colors.grey[600],
            fontWeight: FontWeight.w500,
          ),
        ),
      ],
    );
  }

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

  String _formatDuration(int minutes) {
    if (minutes == 0) return '—';
    if (minutes < 60) return '${minutes}m';
    final hours = minutes ~/ 60;
    final mins = minutes % 60;
    return mins > 0 ? '${hours}h ${mins}m' : '${hours}h';
  }

  String _formatCompletedDate(String? dateStr) {
    if (dateStr == null) return 'Recently';
    try {
      final date = DateTime.parse(dateStr);
      final now = DateTime.now();
      final diff = now.difference(date);

      if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
      if (diff.inHours < 24) return '${diff.inHours}h ago';
      if (diff.inDays == 1) return 'Yesterday';
      if (diff.inDays < 7) return '${diff.inDays}d ago';
      
      return '${date.month}/${date.day}';
    } catch (e) {
      return 'Recently';
    }
  }
}