import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../services/workout_history_service.dart';

class WorkoutCalendarWidget extends StatefulWidget {
  const WorkoutCalendarWidget({super.key});

  @override
  State<WorkoutCalendarWidget> createState() => _WorkoutCalendarWidgetState();
}

class _WorkoutCalendarWidgetState extends State<WorkoutCalendarWidget> {
  final WorkoutHistoryService _historyService = WorkoutHistoryService();
  
  DateTime _currentMonth = DateTime.now();
  List<CalendarDay>? _calendarDays;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadCalendar();
  }

  Future<void> _loadCalendar() async {
    setState(() => _isLoading = true);
    
    final days = await _historyService.getCalendarMonth(_currentMonth);
    
    setState(() {
      _calendarDays = days;
      _isLoading = false;
    });
  }

  void _previousMonth() {
    setState(() {
      _currentMonth = DateTime(_currentMonth.year, _currentMonth.month - 1);
      _loadCalendar();
    });
  }

  void _nextMonth() {
    setState(() {
      _currentMonth = DateTime(_currentMonth.year, _currentMonth.month + 1);
      _loadCalendar();
    });
  }

  void _showWorkoutDetails(CalendarDay day) {
    if (day.workouts.isEmpty) return;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => _WorkoutDetailsSheet(workouts: day.workouts),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            Colors.orange.shade50,
            Colors.red.shade50,
          ],
        ),
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        children: [
          // Month Header
          _buildMonthHeader(),
          
          // Weekday Labels
          _buildWeekdayLabels(),
          
          // Calendar Grid
          if (_isLoading)
            const Padding(
              padding: EdgeInsets.all(40),
              child: CircularProgressIndicator(),
            )
          else if (_calendarDays != null)
            _buildCalendarGrid(),
        ],
      ),
    );
  }

  Widget _buildMonthHeader() {
    final monthName = DateFormat('MMMM yyyy').format(_currentMonth);
    final now = DateTime.now();
    final isCurrentMonth = _currentMonth.year == now.year && 
                          _currentMonth.month == now.month;
    
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          IconButton(
            icon: const Icon(Icons.chevron_left, size: 28),
            onPressed: _previousMonth,
            color: Colors.orange.shade700,
          ),
          Column(
            children: [
              Text(
                monthName,
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                  color: Colors.grey.shade800,
                ),
              ),
              if (isCurrentMonth)
                Container(
                  margin: const EdgeInsets.only(top: 4),
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                  decoration: BoxDecoration(
                    color: Colors.orange.shade100,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    'This Month',
                    style: TextStyle(
                      fontSize: 12,
                      color: Colors.orange.shade700,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
            ],
          ),
          IconButton(
            icon: const Icon(Icons.chevron_right, size: 28),
            onPressed: _nextMonth,
            color: Colors.orange.shade700,
          ),
        ],
      ),
    );
  }

  Widget _buildWeekdayLabels() {
    const weekdays = ['Sun', 'Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat'];
    
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceAround,
        children: weekdays.map((day) => Expanded(
          child: Center(
            child: Text(
              day,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: Colors.grey.shade600,
              ),
            ),
          ),
        )).toList(),
      ),
    );
  }

  Widget _buildCalendarGrid() {
    final firstDayOfMonth = DateTime(_currentMonth.year, _currentMonth.month, 1);
    final firstWeekday = firstDayOfMonth.weekday % 7; // 0 = Sunday
    
    // Add empty cells for days before month starts
    final List<Widget> cells = List.generate(
      firstWeekday,
      (index) => const SizedBox.shrink(),
    );
    
    // Add calendar day cells
    cells.addAll(_calendarDays!.map((day) => _buildCalendarDay(day)));
    
    return Padding(
      padding: const EdgeInsets.all(8),
      child: GridView.count(
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        crossAxisCount: 7,
        mainAxisSpacing: 8,
        crossAxisSpacing: 8,
        children: cells,
      ),
    );
  }

  Widget _buildCalendarDay(CalendarDay day) {
    return GestureDetector(
      onTap: () => _showWorkoutDetails(day),
      child: Container(
        decoration: BoxDecoration(
          color: day.isToday 
              ? Colors.orange.shade400
              : day.hasWorkout
                  ? Colors.green.shade100
                  : day.isFuture
                      ? Colors.grey.shade100
                      : Colors.white,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: day.isToday 
                ? Colors.orange.shade600
                : Colors.transparent,
            width: 2,
          ),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              day.dayNumber,
              style: TextStyle(
                fontSize: 14,
                fontWeight: day.isToday ? FontWeight.bold : FontWeight.w500,
                color: day.isToday
                    ? Colors.white
                    : day.isFuture
                        ? Colors.grey.shade400
                        : Colors.grey.shade800,
              ),
            ),
            if (day.hasWorkout) ...[
              const SizedBox(height: 2),
              Text(
                day.statusEmoji,
                style: const TextStyle(fontSize: 16),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

// ============================================
// WORKOUT DETAILS BOTTOM SHEET
// ============================================

class _WorkoutDetailsSheet extends StatelessWidget {
  final List<WorkoutLog> workouts;

  const _WorkoutDetailsSheet({required this.workouts});

  @override
  Widget build(BuildContext context) {
    final dateStr = DateFormat('EEEE, MMMM d, yyyy').format(workouts.first.workoutDate);
    
    return Container(
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Handle bar
          Center(
            child: Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.grey.shade300,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          const SizedBox(height: 20),
          
          // Date header
          Text(
            dateStr,
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: Colors.grey.shade800,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            '${workouts.length} workout${workouts.length > 1 ? 's' : ''} completed',
            style: TextStyle(
              fontSize: 14,
              color: Colors.grey.shade600,
            ),
          ),
          const SizedBox(height: 20),
          
          // Workout list
          ...workouts.map((workout) => _buildWorkoutCard(workout)),
          
          const SizedBox(height: 20),
          
          // Close button
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: () => Navigator.pop(context),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.orange.shade400,
                padding: const EdgeInsets.symmetric(vertical: 16),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              child: const Text(
                'Close',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                  color: Colors.white,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildWorkoutCard(WorkoutLog workout) {
    final timeStr = DateFormat('h:mm a').format(workout.workoutTime);
    
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [Colors.orange.shade50, Colors.red.shade50],
        ),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.orange.shade200),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                workout.workoutEmoji,
                style: const TextStyle(fontSize: 24),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      workout.workoutName,
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    Text(
                      workout.workoutCategory.toUpperCase(),
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.grey.shade600,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              _buildInfoChip(Icons.access_time, timeStr),
              const SizedBox(width: 8),
              if (workout.actualDurationMinutes != null)
                _buildInfoChip(
                  Icons.timer,
                  '${workout.actualDurationMinutes} min',
                ),
              if (workout.buddyName != null) ...[
                const SizedBox(width: 8),
                _buildInfoChip(Icons.person, workout.buddyName!),
              ],
            ],
          ),
          if (workout.notes != null && workout.notes!.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(
              workout.notes!,
              style: TextStyle(
                fontSize: 14,
                color: Colors.grey.shade700,
                fontStyle: FontStyle.italic,
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildInfoChip(IconData icon, String label) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.7),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: Colors.grey.shade600),
          const SizedBox(width: 4),
          Text(
            label,
            style: TextStyle(
              fontSize: 12,
              color: Colors.grey.shade700,
            ),
          ),
        ],
      ),
    );
  }
}