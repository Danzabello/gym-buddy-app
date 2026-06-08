import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../theme/app_theme.dart';
import '../services/workout_history_service.dart';

class WorkoutHistoryList extends StatefulWidget {
  const WorkoutHistoryList({super.key});

  @override
  State<WorkoutHistoryList> createState() => _WorkoutHistoryListState();
}

class _WorkoutHistoryListState extends State<WorkoutHistoryList> {
  final WorkoutHistoryService _historyService = WorkoutHistoryService();
  List<WorkoutLog>? _workouts;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadHistory();
  }

  Future<void> _loadHistory() async {
    setState(() => _isLoading = true);
    final workouts = await _historyService.getWorkoutHistory(limit: 50);
    setState(() {
      _workouts = workouts;
      _isLoading = false;
    });
  }

  Color _durationColor(int? minutes) {
    if (minutes == null) return AppColors.of(context).subtleText;
    if (minutes <= 20)  return Colors.grey[500]!;
    if (minutes <= 30)  return Colors.blue[600]!;
    if (minutes <= 45)  return Colors.green[600]!;
    if (minutes <= 60)  return Colors.teal[600]!;
    if (minutes <= 75)  return Colors.purple[600]!;
    if (minutes <= 90)  return Colors.deepPurple[600]!;
    return Colors.red[600]!;
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(40),
          child: CircularProgressIndicator(),
        ),
      );
    }

    if (_workouts == null || _workouts!.isEmpty) {
      return _buildEmptyState();
    }

    final groupedWorkouts = <String, List<WorkoutLog>>{};
    for (var workout in _workouts!) {
      final dateKey = DateFormat('yyyy-MM-dd').format(workout.workoutDate);
      groupedWorkouts.putIfAbsent(dateKey, () => []).add(workout);
    }

    final sortedDates = groupedWorkouts.keys.toList()
      ..sort((a, b) => b.compareTo(a));

    return RefreshIndicator(
      onRefresh: _loadHistory,
      child: ListView.builder(
        padding: const EdgeInsets.all(16),
        itemCount: sortedDates.length,
        itemBuilder: (context, index) {
          final dateKey = sortedDates[index];
          final date = DateTime.parse(dateKey);
          final workouts = groupedWorkouts[dateKey]!;
          return _buildDateGroup(date, workouts);
        },
      ),
    );
  }

  Widget _buildEmptyState() {
    final appColors = AppColors.of(context);
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.fitness_center, size: 80, color: appColors.subtleText),  // ✅
          const SizedBox(height: 16),
          Text(
            'No Workouts Yet',
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.bold,
              color: Theme.of(context).colorScheme.onSurface,  // ✅
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Complete your first workout to see it here!',
            style: TextStyle(fontSize: 14, color: appColors.subtleText),  // ✅
          ),
        ],
      ),
    );
  }

  Widget _buildDateGroup(DateTime date, List<WorkoutLog> workouts) {
    final appColors = AppColors.of(context);
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final yesterday = today.subtract(const Duration(days: 1));
    final workoutDate = DateTime(date.year, date.month, date.day);

    String dateLabel;
    if (workoutDate.isAtSameMomentAs(today)) {
      dateLabel = 'Today';
    } else if (workoutDate.isAtSameMomentAs(yesterday)) {
      dateLabel = 'Yesterday';
    } else {
      dateLabel = DateFormat('EEEE, MMMM d').format(date);
    }

    final totalMinutes = workouts
        .map((w) => w.actualDurationMinutes ?? 0)
        .reduce((a, b) => a + b);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(left: 4, top: 8, bottom: 12),
          child: Row(
            children: [
              Text(
                dateLabel,
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  color: Theme.of(context).colorScheme.onSurface,  // ✅
                ),
              ),
              const SizedBox(width: 12),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: appColors.streakOrange.withOpacity(0.15),  // ✅
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  '${workouts.length} workout${workouts.length > 1 ? 's' : ''} · $totalMinutes min',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: appColors.streakOrange,  // ✅
                  ),
                ),
              ),
            ],
          ),
        ),
        ...workouts.map((workout) => _buildWorkoutCard(workout)),
        const SizedBox(height: 8),
      ],
    );
  }

  Widget _buildWorkoutCard(WorkoutLog workout) {
    final appColors = AppColors.of(context);
    final timeStr = DateFormat('h:mm a').format(workout.workoutTime);

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: appColors.cardBackground,  // ✅ was orange gradient
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: appColors.cardBorder),  // ✅
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            // Emoji icon
            Container(
              width: 50, height: 50,
              decoration: BoxDecoration(
                color: appColors.sectionBackground,  // ✅ was Colors.white.withOpacity(0.8)
                borderRadius: BorderRadius.circular(12),
              ),
              child: Center(
                child: Text(workout.workoutEmoji,
                    style: const TextStyle(fontSize: 24)),
              ),
            ),
            const SizedBox(width: 16),

            // Workout info
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    workout.workoutName,
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: Theme.of(context).colorScheme.onSurface,  // ✅
                    ),
                  ),
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      Icon(Icons.access_time, size: 14, color: appColors.subtleText),  // ✅
                      const SizedBox(width: 4),
                      Text(timeStr,
                          style: TextStyle(fontSize: 13, color: appColors.subtleText)),  // ✅
                      if (workout.actualDurationMinutes != null) ...[
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                          decoration: BoxDecoration(
                            color: _durationColor(workout.actualDurationMinutes).withOpacity(0.12),
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(
                              color: _durationColor(workout.actualDurationMinutes).withOpacity(0.4),
                            ),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.timer, size: 12,
                                  color: _durationColor(workout.actualDurationMinutes)),
                              const SizedBox(width: 4),
                              Text(
                                '${workout.actualDurationMinutes}m',
                                style: TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w700,
                                  color: _durationColor(workout.actualDurationMinutes),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ],
                  ),
                  if (workout.buddyName != null) ...[
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        Icon(Icons.person, size: 14, color: appColors.subtleText),  // ✅
                        const SizedBox(width: 4),
                        Text(
                          'with ${workout.buddyName}',
                          style: TextStyle(
                            fontSize: 13,
                            color: appColors.subtleText,  // ✅
                            fontStyle: FontStyle.italic,
                          ),
                        ),
                      ],
                    ),
                  ],
                ],
              ),
            ),

            // Category badge
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: appColors.sectionBackground,  // ✅ was Colors.white.withOpacity(0.8)
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: appColors.cardBorder),  // ✅ added for definition
              ),
              child: Text(
                workout.workoutCategory.toUpperCase(),
                style: TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.bold,
                  color: appColors.streakOrange,  // ✅ was Colors.orange.shade700
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}