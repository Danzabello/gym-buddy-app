import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../services/workout_service.dart';

/// Quick schedule sheet - pre-filled with the buddy you're viewing
class QuickScheduleSheet extends StatefulWidget {
  final String buddyUserId;
  final String buddyDisplayName;
  final VoidCallback? onWorkoutScheduled;

  const QuickScheduleSheet({
    super.key,
    required this.buddyUserId,
    required this.buddyDisplayName,
    this.onWorkoutScheduled,
  });

  static void show(
    BuildContext context, {
    required String buddyUserId,
    required String buddyDisplayName,
    VoidCallback? onWorkoutScheduled,
  }) {
    HapticFeedback.mediumImpact();

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => QuickScheduleSheet(
        buddyUserId: buddyUserId,
        buddyDisplayName: buddyDisplayName,
        onWorkoutScheduled: onWorkoutScheduled,
      ),
    );
  }

  @override
  State<QuickScheduleSheet> createState() => _QuickScheduleSheetState();
}

class _QuickScheduleSheetState extends State<QuickScheduleSheet> {
  final WorkoutService _workoutService = WorkoutService();

  String _selectedType = 'Strength';
  DateTime _selectedDate = DateTime.now();
  TimeOfDay _selectedTime = TimeOfDay.now();
  int _duration = 60;
  bool _isCustomDuration = false;
  bool _isCreating = false;

  final List<Map<String, dynamic>> _workoutTypes = [
    {'name': 'Strength', 'icon': Icons.fitness_center, 'color': Colors.blue},
    {'name': 'Cardio', 'icon': Icons.directions_run, 'color': Colors.red},
    {'name': 'HIIT', 'icon': Icons.flash_on, 'color': Colors.orange},
    {'name': 'Leg Day', 'icon': Icons.directions_walk, 'color': Colors.purple},
    {'name': 'Upper Body', 'icon': Icons.accessibility_new, 'color': Colors.teal},
    {'name': 'Full Body', 'icon': Icons.sports_gymnastics, 'color': Colors.indigo},
    {'name': 'Yoga', 'icon': Icons.self_improvement, 'color': Colors.green},
    {'name': 'Other', 'icon': Icons.sports, 'color': Colors.grey},
  ];

  final List<int> _presetDurations = [30, 45, 60];

  Future<void> _scheduleWorkout() async {
    setState(() => _isCreating = true);

    final timeString =
        '${_selectedTime.hour.toString().padLeft(2, '0')}:${_selectedTime.minute.toString().padLeft(2, '0')}:00';

    final error = await _workoutService.createWorkout(
      workoutType: _selectedType,
      date: _selectedDate,
      time: timeString,
      plannedDurationMinutes: _duration,
      buddyId: widget.buddyUserId,
    );

    setState(() => _isCreating = false);

    if (error == null) {
      widget.onWorkoutScheduled?.call();
      if (mounted) {
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Row(
              children: [
                const Icon(Icons.check_circle, color: Colors.white),
                const SizedBox(width: 12),
                Expanded(
                  child: Text('Workout invite sent to ${widget.buddyDisplayName}! 🎉'),
                ),
              ],
            ),
            backgroundColor: Colors.green,
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          ),
        );
      }
    } else {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error: $error'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  void _showCustomDurationDialog() {
    int tempDuration = _isCustomDuration ? _duration : 60;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) => StatefulBuilder(
        builder: (sheetContext, setSheetState) => Container(
          padding: EdgeInsets.fromLTRB(
            24,
            20,
            24,
            MediaQuery.of(sheetContext).padding.bottom + 20,
          ),
          decoration: const BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Handle bar
              Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.grey[300],
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(height: 20),

              // Title
              Text(
                'Set Duration',
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                  color: Colors.grey[800],
                ),
              ),
              const SizedBox(height: 24),

              // Big duration display
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 40, vertical: 24),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [Colors.green[50]!, Colors.green[100]!],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  borderRadius: BorderRadius.circular(24),
                  border: Border.all(color: Colors.green[200]!, width: 2),
                ),
                child: Text(
                  _formatDuration(tempDuration),
                  style: TextStyle(
                    fontSize: 52,
                    fontWeight: FontWeight.bold,
                    color: Colors.green[700],
                  ),
                ),
              ),
              const SizedBox(height: 28),

              // Slider
              SliderTheme(
                data: SliderTheme.of(context).copyWith(
                  activeTrackColor: Colors.green[400],
                  inactiveTrackColor: Colors.grey[200],
                  thumbColor: Colors.green[600],
                  overlayColor: Colors.green.withOpacity(0.2),
                  trackHeight: 10,
                  thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 16),
                  overlayShape: const RoundSliderOverlayShape(overlayRadius: 28),
                ),
                child: Slider(
                  value: tempDuration.toDouble(),
                  min: 10,
                  max: 180,
                  divisions: 34,
                  onChanged: (value) {
                    final rounded = (value / 5).round() * 5;
                    HapticFeedback.selectionClick();
                    setSheetState(() => tempDuration = rounded);
                  },
                ),
              ),

              // Min/Max labels
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      '10 min',
                      style: TextStyle(
                        color: Colors.grey[500],
                        fontSize: 13,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    Text(
                      '3 hours',
                      style: TextStyle(
                        color: Colors.grey[500],
                        fontSize: 13,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 24),

              // Quick preset buttons
              Wrap(
                spacing: 10,
                runSpacing: 10,
                alignment: WrapAlignment.center,
                children: [15, 30, 45, 60, 90, 120].map((mins) {
                  final isSelected = tempDuration == mins;
                  return GestureDetector(
                    onTap: () {
                      HapticFeedback.lightImpact();
                      setSheetState(() => tempDuration = mins);
                    },
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 200),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 18,
                        vertical: 12,
                      ),
                      decoration: BoxDecoration(
                        color: isSelected ? Colors.green[500] : Colors.grey[100],
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(
                          color: isSelected ? Colors.green[600]! : Colors.grey[300]!,
                          width: isSelected ? 2 : 1,
                        ),
                        boxShadow: isSelected
                            ? [
                                BoxShadow(
                                  color: Colors.green.withOpacity(0.3),
                                  blurRadius: 8,
                                  offset: const Offset(0, 2),
                                ),
                              ]
                            : null,
                      ),
                      child: Text(
                        _formatDuration(mins),
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                          color: isSelected ? Colors.white : Colors.grey[700],
                        ),
                      ),
                    ),
                  );
                }).toList(),
              ),
              const SizedBox(height: 28),

              // Confirm button
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: () {
                    HapticFeedback.mediumImpact();
                    setState(() {
                      _duration = tempDuration;
                      _isCustomDuration = true;
                    });
                    Navigator.pop(sheetContext);
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.green[600],
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 18),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                    ),
                    elevation: 2,
                  ),
                  child: const Text(
                    'Set Duration',
                    style: TextStyle(
                      fontSize: 17,
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

  @override
  Widget build(BuildContext context) {
    final bottomPadding = MediaQuery.of(context).padding.bottom;

    return Container(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.of(context).size.height * 0.85,
      ),
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Handle bar
          Container(
            margin: const EdgeInsets.only(top: 12, bottom: 8),
            width: 40,
            height: 4,
            decoration: BoxDecoration(
              color: Colors.grey.shade300,
              borderRadius: BorderRadius.circular(2),
            ),
          ),

          // Header
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 8, 12, 8),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: Colors.green[50],
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(Icons.calendar_today, color: Colors.green[700], size: 24),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Schedule Workout',
                        style: TextStyle(
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
          ),

          const Divider(height: 1),

          Flexible(
            child: SingleChildScrollView(
              padding: EdgeInsets.fromLTRB(20, 20, 20, bottomPadding + 20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Workout Type Selection
                  const Text(
                    'Workout Type',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 12),
                  _buildWorkoutTypeGrid(),

                  const SizedBox(height: 24),

                  // Date & Time Row
                  Row(
                    children: [
                      Expanded(child: _buildDatePicker()),
                      const SizedBox(width: 16),
                      Expanded(child: _buildTimePicker()),
                    ],
                  ),

                  const SizedBox(height: 24),

                  // Duration
                  _buildDurationSelector(),

                  const SizedBox(height: 32),

                  // Schedule Button
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      onPressed: _isCreating ? null : _scheduleWorkout,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.green[600],
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16),
                        ),
                        elevation: 2,
                      ),
                      child: _isCreating
                          ? const SizedBox(
                              width: 24,
                              height: 24,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Colors.white,
                              ),
                            )
                          : Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                const Icon(Icons.send, size: 20),
                                const SizedBox(width: 10),
                                Text(
                                  'Send Invite to ${widget.buddyDisplayName}',
                                  style: const TextStyle(
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
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildWorkoutTypeGrid() {
    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 4,
        crossAxisSpacing: 8,
        mainAxisSpacing: 8,
        childAspectRatio: 1,
      ),
      itemCount: _workoutTypes.length,
      itemBuilder: (context, index) {
        final type = _workoutTypes[index];
        final isSelected = _selectedType == type['name'];
        final color = type['color'] as MaterialColor;

        return GestureDetector(
          onTap: () {
            HapticFeedback.selectionClick();
            setState(() => _selectedType = type['name'] as String);
          },
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            decoration: BoxDecoration(
              color: isSelected ? color[50] : Colors.grey[50],
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: isSelected ? color[400]! : Colors.grey[200]!,
                width: isSelected ? 2 : 1,
              ),
            ),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  type['icon'] as IconData,
                  color: isSelected ? color[700] : Colors.grey[500],
                  size: 24,
                ),
                const SizedBox(height: 4),
                Text(
                  type['name'] as String,
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
                    color: isSelected ? color[700] : Colors.grey[600],
                  ),
                  textAlign: TextAlign.center,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildDatePicker() {
    return GestureDetector(
      onTap: () async {
        final date = await showDatePicker(
          context: context,
          initialDate: _selectedDate,
          firstDate: DateTime.now(),
          lastDate: DateTime.now().add(const Duration(days: 365)),
        );
        if (date != null) {
          setState(() => _selectedDate = date);
        }
      },
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.grey[50],
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.grey[200]!),
        ),
        child: Row(
          children: [
            Icon(Icons.calendar_today, color: Colors.grey[600], size: 20),
            const SizedBox(width: 12),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Date',
                  style: TextStyle(
                    fontSize: 11,
                    color: Colors.grey[500],
                  ),
                ),
                Text(
                  _formatDate(_selectedDate),
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTimePicker() {
    return GestureDetector(
      onTap: () async {
        final time = await showTimePicker(
          context: context,
          initialTime: _selectedTime,
        );
        if (time != null) {
          setState(() => _selectedTime = time);
        }
      },
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.grey[50],
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.grey[200]!),
        ),
        child: Row(
          children: [
            Icon(Icons.access_time, color: Colors.grey[600], size: 20),
            const SizedBox(width: 12),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Time',
                  style: TextStyle(
                    fontSize: 11,
                    color: Colors.grey[500],
                  ),
                ),
                Text(
                  _selectedTime.format(context),
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDurationSelector() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            const Text(
              'Duration',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w600,
              ),
            ),
            Text(
              _formatDuration(_duration),
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.bold,
                color: Colors.green[700],
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            ..._presetDurations.map((mins) => Expanded(
                  child: Padding(
                    padding: EdgeInsets.only(
                      right: mins != _presetDurations.last ? 8 : 0,
                    ),
                    child: _buildDurationChip(mins),
                  ),
                )),
            const SizedBox(width: 8),
            Expanded(child: _buildCustomDurationChip()),
          ],
        ),
      ],
    );
  }

  Widget _buildDurationChip(int minutes) {
    final isSelected = _duration == minutes && !_isCustomDuration;

    return GestureDetector(
      onTap: () {
        HapticFeedback.selectionClick();
        setState(() {
          _duration = minutes;
          _isCustomDuration = false;
        });
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(vertical: 12),
        decoration: BoxDecoration(
          color: isSelected ? Colors.green[50] : Colors.grey[50],
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: isSelected ? Colors.green[400]! : Colors.grey[200]!,
            width: isSelected ? 2 : 1,
          ),
        ),
        child: Text(
          _formatDuration(minutes),
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: 14,
            fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
            color: isSelected ? Colors.green[700] : Colors.grey[600],
          ),
        ),
      ),
    );
  }

  Widget _buildCustomDurationChip() {
    final isSelected = _isCustomDuration;

    return GestureDetector(
      onTap: () {
        HapticFeedback.selectionClick();
        _showCustomDurationDialog();
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(vertical: 12),
        decoration: BoxDecoration(
          color: isSelected ? Colors.green[50] : Colors.grey[50],
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: isSelected ? Colors.green[400]! : Colors.grey[200]!,
            width: isSelected ? 2 : 1,
          ),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.edit,
              size: 14,
              color: isSelected ? Colors.green[700] : Colors.grey[600],
            ),
            const SizedBox(width: 4),
            Text(
              isSelected ? _formatDuration(_duration) : 'Custom',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 13,
                fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
                color: isSelected ? Colors.green[700] : Colors.grey[600],
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _formatDate(DateTime date) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final tomorrow = today.add(const Duration(days: 1));
    final selected = DateTime(date.year, date.month, date.day);

    if (selected == today) return 'Today';
    if (selected == tomorrow) return 'Tomorrow';

    final days = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
    return '${days[date.weekday - 1]}, ${date.month}/${date.day}';
  }

  String _formatDuration(int minutes) {
    if (minutes < 60) return '${minutes}m';
    final hours = minutes ~/ 60;
    final mins = minutes % 60;
    return mins > 0 ? '${hours}h ${mins}m' : '${hours}h';
  }
}