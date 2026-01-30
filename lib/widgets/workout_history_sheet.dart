import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'quick_schedule_sheet.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Shows the workout history between you and a specific buddy
class WorkoutHistorySheet extends StatefulWidget {
  final String buddyUserId;
  final String buddyDisplayName;
  final String buddyAvatarId;

  const WorkoutHistorySheet({
    super.key,
    required this.buddyUserId,
    required this.buddyDisplayName,
    required this.buddyAvatarId,
  });

  static void show(
    BuildContext context, {
    required String buddyUserId,
    required String buddyDisplayName,
    required String buddyAvatarId,
  }) {
    HapticFeedback.mediumImpact();
    
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => WorkoutHistorySheet(
        buddyUserId: buddyUserId,
        buddyDisplayName: buddyDisplayName,
        buddyAvatarId: buddyAvatarId,
      ),
    );
  }

  @override
  State<WorkoutHistorySheet> createState() => _WorkoutHistorySheetState();
}

class _WorkoutHistorySheetState extends State<WorkoutHistorySheet> {
  List<Map<String, dynamic>> _workouts = [];
  bool _isLoading = true;
  int _totalWorkouts = 0;
  int _totalMinutes = 0;

  @override
  void initState() {
    super.initState();
    _loadWorkoutHistory();
  }

  Future<void> _loadWorkoutHistory() async {
    try {
      final currentUserId = Supabase.instance.client.auth.currentUser?.id;
      if (currentUserId == null) return;

      // Get completed workouts where both users participated
      final response = await Supabase.instance.client
          .from('workouts')
          .select('*')
          .eq('status', 'completed')
          .or('and(user_id.eq.$currentUserId,buddy_id.eq.${widget.buddyUserId}),and(user_id.eq.${widget.buddyUserId},buddy_id.eq.$currentUserId)')
          .order('workout_date', ascending: false)
          .limit(50);

      int totalMinutes = 0;
      for (var workout in response) {
        if (workout['actual_duration_minutes'] != null) {
          totalMinutes += workout['actual_duration_minutes'] as int;
        } else if (workout['planned_duration_minutes'] != null) {
          totalMinutes += workout['planned_duration_minutes'] as int;
        }
      }

      if (mounted) {
        setState(() {
          _workouts = List<Map<String, dynamic>>.from(response);
          _totalWorkouts = _workouts.length;
          _totalMinutes = totalMinutes;
          _isLoading = false;
        });
      }
    } catch (e) {
      print('❌ Error loading workout history: $e');
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      initialChildSize: 0.75,
      minChildSize: 0.5,
      maxChildSize: 0.95,
      builder: (context, scrollController) => Container(
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
            
            // Header
            Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                children: [
                  Row(
                    children: [
                      Icon(Icons.history, color: Colors.purple[600], size: 28),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Workout History',
                              style: const TextStyle(
                                fontSize: 20,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            Text(
                              'with ${widget.buddyDisplayName}',
                              style: TextStyle(
                                fontSize: 14,
                                color: Colors.grey[600],
                              ),
                            ),
                          ],
                        ),
                      ),
                      IconButton(
                        onPressed: () => Navigator.pop(context),
                        icon: Icon(Icons.close, color: Colors.grey[400]),
                      ),
                    ],
                  ),
                  
                  const SizedBox(height: 16),
                  
                  // Stats summary
                  _buildStatsSummary(),
                ],
              ),
            ),
            
            const Divider(height: 1),
            
            // Workout list
            Expanded(
              child: _isLoading
                  ? const Center(child: CircularProgressIndicator())
                  : _workouts.isEmpty
                      ? _buildEmptyState()
                      : ListView.builder(
                          controller: scrollController,
                          padding: const EdgeInsets.all(16),
                          itemCount: _workouts.length,
                          itemBuilder: (context, index) {
                            return _buildWorkoutCard(_workouts[index]);
                          },
                        ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStatsSummary() {
    final hours = _totalMinutes ~/ 60;
    final minutes = _totalMinutes % 60;
    final timeString = hours > 0 
        ? '${hours}h ${minutes}m' 
        : '${minutes}m';

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [Colors.purple[50]!, Colors.blue[50]!],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.purple[100]!),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: [
          _buildStatItem(
            icon: Icons.fitness_center,
            value: '$_totalWorkouts',
            label: 'Workouts\nTogether',
            color: Colors.purple[700]!,
          ),
          Container(
            height: 40,
            width: 1,
            color: Colors.purple[200],
          ),
          _buildStatItem(
            icon: Icons.timer,
            value: timeString,
            label: 'Total\nTime',
            color: Colors.blue[700]!,
          ),
        ],
      ),
    );
  }

  Widget _buildStatItem({
    required IconData icon,
    required String value,
    required String label,
    required Color color,
  }) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, color: color, size: 24),
        const SizedBox(height: 4),
        Text(
          value,
          style: TextStyle(
            fontSize: 24,
            fontWeight: FontWeight.bold,
            color: color,
          ),
        ),
        Text(
          label,
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: 11,
            color: Colors.grey[600],
            height: 1.2,
          ),
        ),
      ],
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.fitness_center,
              size: 64,
              color: Colors.grey[300],
            ),
            const SizedBox(height: 16),
            Text(
              'No workouts yet!',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: Colors.grey[600],
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Complete a workout with ${widget.buddyDisplayName} to see it here.',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 14,
                color: Colors.grey[500],
              ),
            ),
            const SizedBox(height: 24),
            ElevatedButton.icon(
              onPressed: () {
                Navigator.pop(context);
                // Open the schedule sheet with the buddy pre-selected
                QuickScheduleSheet.show(
                  context,
                  buddyUserId: widget.buddyUserId,
                  buddyDisplayName: widget.buddyDisplayName,
                );
              },
              icon: const Icon(Icons.add),
              label: const Text('Schedule Workout'),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.purple[600],
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildWorkoutCard(Map<String, dynamic> workout) {
    final workoutType = workout['workout_type'] ?? 'Workout';
    final workoutDate = workout['workout_date'];
    final duration = workout['actual_duration_minutes'] ?? 
                     workout['planned_duration_minutes'] ?? 0;
    
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.grey[200]!),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.03),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        children: [
          // Workout type icon
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              color: _getWorkoutColor(workoutType).withOpacity(0.1),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(
              _getWorkoutIcon(workoutType),
              color: _getWorkoutColor(workoutType),
              size: 24,
            ),
          ),
          
          const SizedBox(width: 16),
          
          // Info
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  workoutType,
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 4),
                Row(
                  children: [
                    Icon(Icons.calendar_today, size: 14, color: Colors.grey[500]),
                    const SizedBox(width: 4),
                    Text(
                      _formatDate(workoutDate),
                      style: TextStyle(
                        fontSize: 13,
                        color: Colors.grey[600],
                      ),
                    ),
                    const SizedBox(width: 12),
                    Icon(Icons.timer, size: 14, color: Colors.grey[500]),
                    const SizedBox(width: 4),
                    Text(
                      _formatDuration(duration),
                      style: TextStyle(
                        fontSize: 13,
                        color: Colors.grey[600],
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          
          // Completed badge
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: Colors.green[50],
              shape: BoxShape.circle,
            ),
            child: Icon(
              Icons.check,
              color: Colors.green[600],
              size: 16,
            ),
          ),
        ],
      ),
    );
  }

  String _formatDate(String? dateStr) {
    if (dateStr == null) return 'Unknown';
    try {
      final date = DateTime.parse(dateStr);
      final now = DateTime.now();
      final today = DateTime(now.year, now.month, now.day);
      final yesterday = today.subtract(const Duration(days: 1));
      final workoutDate = DateTime(date.year, date.month, date.day);
      
      if (workoutDate == today) return 'Today';
      if (workoutDate == yesterday) return 'Yesterday';
      
      final months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 
                      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
      return '${months[date.month - 1]} ${date.day}';
    } catch (e) {
      return dateStr;
    }
  }

  String _formatDuration(int minutes) {
    if (minutes < 60) return '${minutes}m';
    final hours = minutes ~/ 60;
    final mins = minutes % 60;
    return mins > 0 ? '${hours}h ${mins}m' : '${hours}h';
  }

  Color _getWorkoutColor(String type) {
    switch (type.toLowerCase()) {
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

  IconData _getWorkoutIcon(String type) {
    switch (type.toLowerCase()) {
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
}