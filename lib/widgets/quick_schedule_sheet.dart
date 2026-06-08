import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../services/workout_service.dart';
import '../theme/app_theme.dart';

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
    {'name': 'Strength',   'icon': Icons.fitness_center,    'color': Colors.blue},
    {'name': 'Cardio',     'icon': Icons.directions_run,    'color': Colors.red},
    {'name': 'HIIT',       'icon': Icons.flash_on,          'color': Colors.orange},
    {'name': 'Leg Day',    'icon': Icons.directions_walk,   'color': Colors.purple},
    {'name': 'Upper Body', 'icon': Icons.accessibility_new, 'color': Colors.teal},
    {'name': 'Full Body',  'icon': Icons.sports_gymnastics, 'color': Colors.indigo},
    {'name': 'Yoga',       'icon': Icons.self_improvement,  'color': Colors.green},
    {'name': 'Other',      'icon': Icons.sports,            'color': Colors.grey},
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
                Expanded(child: Text('Workout invite sent to ${widget.buddyDisplayName}! 🎉')),
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
          SnackBar(content: Text('Error: $error'), backgroundColor: Colors.red),
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
      builder: (sheetContext) {
        final appColors = AppColors.of(sheetContext);
        return StatefulBuilder(
          builder: (sheetContext, setSheetState) {
            final dialColor = _durationColor(tempDuration);
            return Container(
            padding: EdgeInsets.fromLTRB(
              24, 20, 24, MediaQuery.of(sheetContext).padding.bottom + 20,
            ),
            decoration: BoxDecoration(
              color: appColors.cardBackground,
              borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 40, height: 4,
                  decoration: BoxDecoration(
                    color: appColors.divider,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                const SizedBox(height: 20),
                Text('Set Duration',
                    style: TextStyle(
                      fontSize: 20, fontWeight: FontWeight.bold,
                      color: Theme.of(sheetContext).colorScheme.onSurface,
                    )),
                const SizedBox(height: 24),
                AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  padding: const EdgeInsets.symmetric(horizontal: 40, vertical: 24),
                  decoration: BoxDecoration(
                    color: dialColor.withOpacity(0.12),
                    borderRadius: BorderRadius.circular(24),
                    border: Border.all(color: dialColor.withOpacity(0.4), width: 2),
                  ),
                  child: Text(_formatDuration(tempDuration),
                      style: TextStyle(
                        fontSize: 52, fontWeight: FontWeight.bold,
                        color: dialColor,
                      )),
                ),
                const SizedBox(height: 28),
                SliderTheme(
                  data: SliderTheme.of(sheetContext).copyWith(
                    activeTrackColor: dialColor,
                    inactiveTrackColor: appColors.cardBorder,
                    thumbColor: dialColor,
                    overlayColor: dialColor.withOpacity(0.2),
                    trackHeight: 10,
                    thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 16),
                    overlayShape: const RoundSliderOverlayShape(overlayRadius: 28),
                  ),
                  child: Slider(
                    value: tempDuration.toDouble(),
                    min: 10, max: 180, divisions: 34,
                    onChanged: (value) {
                      final rounded = (value / 5).round() * 5;
                      HapticFeedback.selectionClick();
                      setSheetState(() => tempDuration = rounded);
                    },
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text('10 min', style: TextStyle(color: appColors.subtleText, fontSize: 13)),
                      Text('3 hours', style: TextStyle(color: appColors.subtleText, fontSize: 13)),
                    ],
                  ),
                ),
                const SizedBox(height: 24),
                Wrap(
                  spacing: 10, runSpacing: 10,
                  alignment: WrapAlignment.center,
                  children: [15, 30, 45, 60, 90, 120].map((mins) {
                    final isSelected = tempDuration == mins;
                    final chipColor = _durationColor(mins);
                    return GestureDetector(
                      onTap: () {
                        HapticFeedback.lightImpact();
                        setSheetState(() => tempDuration = mins);
                      },
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 200),
                        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
                        decoration: BoxDecoration(
                          color: isSelected
                              ? chipColor.withOpacity(0.15)
                              : appColors.sectionBackground,
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(
                            color: isSelected ? chipColor : appColors.cardBorder,
                            width: isSelected ? 2 : 1,
                          ),
                        ),
                        child: Text(_formatDuration(mins),
                            style: TextStyle(
                              fontSize: 15, fontWeight: FontWeight.w600,
                              color: isSelected ? chipColor
                                  : Theme.of(sheetContext).colorScheme.onSurface,
                            )),
                      ),
                    );
                  }).toList(),
                ),
                const SizedBox(height: 28),
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
                      backgroundColor: dialColor,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 18),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(16)),
                      ),
                      child: const Text('Set Duration',
                          style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold)),
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final appColors = AppColors.of(context);
    final bottomPadding = MediaQuery.of(context).padding.bottom;

    return Container(
      constraints: BoxConstraints(maxHeight: MediaQuery.of(context).size.height * 0.85),
      decoration: BoxDecoration(
        color: appColors.cardBackground,  // ✅
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            margin: const EdgeInsets.only(top: 12, bottom: 8),
            width: 40, height: 4,
            decoration: BoxDecoration(
              color: appColors.divider,  // ✅
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 8, 12, 8),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: Colors.green.withOpacity(0.12),  // ✅ subtle in dark too
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(Icons.calendar_today, color: Colors.green[600], size: 24),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Schedule Workout',
                          style: TextStyle(
                            fontSize: 20, fontWeight: FontWeight.bold,
                            color: Theme.of(context).colorScheme.onSurface,  // ✅
                          )),
                      Text('with ${widget.buddyDisplayName}',
                          style: TextStyle(fontSize: 14, color: appColors.subtleText)),  // ✅
                    ],
                  ),
                ),
                IconButton(
                  onPressed: () => Navigator.pop(context),
                  icon: Icon(Icons.close, color: appColors.subtleText),  // ✅
                ),
              ],
            ),
          ),
          Divider(height: 1, color: appColors.divider),  // ✅
          Flexible(
            child: SingleChildScrollView(
              padding: EdgeInsets.fromLTRB(20, 20, 20, bottomPadding + 20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Workout Type',
                      style: TextStyle(
                        fontSize: 16, fontWeight: FontWeight.w600,
                        color: Theme.of(context).colorScheme.onSurface,  // ✅
                      )),
                  const SizedBox(height: 12),
                  _buildWorkoutTypeGrid(appColors),
                  const SizedBox(height: 24),
                  Row(
                    children: [
                      Expanded(child: _buildDatePicker(appColors)),
                      const SizedBox(width: 16),
                      Expanded(child: _buildTimePicker(appColors)),
                    ],
                  ),
                  const SizedBox(height: 24),
                  _buildDurationSelector(appColors),
                  const SizedBox(height: 32),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      onPressed: _isCreating ? null : _scheduleWorkout,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.green[600],
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                        elevation: 2,
                      ),
                      child: _isCreating
                          ? const SizedBox(width: 24, height: 24,
                              child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                          : Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                const Icon(Icons.send, size: 20),
                                const SizedBox(width: 10),
                                Text('Send Invite to ${widget.buddyDisplayName}',
                                    style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
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

  Widget _buildWorkoutTypeGrid(AppColors appColors) {
    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 4, crossAxisSpacing: 8, mainAxisSpacing: 8, childAspectRatio: 1,
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
              color: isSelected ? color.withOpacity(0.12) : appColors.sectionBackground,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: isSelected ? color[400]! : appColors.cardBorder,  // ✅
                width: isSelected ? 2 : 1,
              ),
            ),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(type['icon'] as IconData,
                    color: isSelected ? color[400] : appColors.subtleText, size: 24),
                const SizedBox(height: 4),
                Text(type['name'] as String,
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
                      color: isSelected ? color[400] : appColors.subtleText,
                    ),
                    textAlign: TextAlign.center,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildDatePicker(AppColors appColors) {
    return GestureDetector(
      onTap: () async {
        final date = await showDatePicker(
          context: context,
          initialDate: _selectedDate,
          firstDate: DateTime.now(),
          lastDate: DateTime.now().add(const Duration(days: 365)),
        );
        if (date != null) setState(() => _selectedDate = date);
      },
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: appColors.sectionBackground,  // ✅
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: appColors.cardBorder),  // ✅
        ),
        child: Row(
          children: [
            Icon(Icons.calendar_today, color: appColors.subtleText, size: 20),  // ✅
            const SizedBox(width: 12),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Date', style: TextStyle(fontSize: 11, color: appColors.subtleText)),  // ✅
                Text(_formatDate(_selectedDate),
                    style: TextStyle(
                      fontSize: 14, fontWeight: FontWeight.w600,
                      color: Theme.of(context).colorScheme.onSurface,  // ✅
                    )),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTimePicker(AppColors appColors) {
    return GestureDetector(
      onTap: () async {
        final time = await showTimePicker(context: context, initialTime: _selectedTime);
        if (time != null) setState(() => _selectedTime = time);
      },
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: appColors.sectionBackground,  // ✅
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: appColors.cardBorder),  // ✅
        ),
        child: Row(
          children: [
            Icon(Icons.access_time, color: appColors.subtleText, size: 20),  // ✅
            const SizedBox(width: 12),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Time', style: TextStyle(fontSize: 11, color: appColors.subtleText)),  // ✅
                Text(_selectedTime.format(context),
                    style: TextStyle(
                      fontSize: 14, fontWeight: FontWeight.w600,
                      color: Theme.of(context).colorScheme.onSurface,  // ✅
                    )),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDurationSelector(AppColors appColors) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text('Duration',
                style: TextStyle(
                  fontSize: 16, fontWeight: FontWeight.w600,
                  color: Theme.of(context).colorScheme.onSurface,  // ✅
                )),
            Text(_formatDuration(_duration),
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.green[700])),
          ],
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            ..._presetDurations.map((mins) => Expanded(
                  child: Padding(
                    padding: EdgeInsets.only(right: mins != _presetDurations.last ? 8 : 0),
                    child: _buildDurationChip(mins, appColors),
                  ),
                )),
            const SizedBox(width: 8),
            Expanded(child: _buildCustomDurationChip(appColors)),
          ],
        ),
      ],
    );
  }

  Color _durationColor(int minutes) {
    if (minutes <= 20)  return Colors.grey[500]!;
    if (minutes <= 30)  return Colors.blue[600]!;
    if (minutes <= 45)  return Colors.green[600]!;
    if (minutes <= 60)  return Colors.teal[600]!;
    if (minutes <= 75)  return Colors.purple[600]!;
    if (minutes <= 90)  return Colors.deepPurple[600]!;
    return Colors.red[600]!;
  }

  Widget _buildDurationChip(int minutes, AppColors appColors) {
    final isSelected = _duration == minutes && !_isCustomDuration;
    return GestureDetector(
      onTap: () {
        HapticFeedback.selectionClick();
        setState(() { _duration = minutes; _isCustomDuration = false; });
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(vertical: 12),
        decoration: BoxDecoration(
          color: isSelected
              ? _durationColor(minutes).withOpacity(0.12)
              : appColors.sectionBackground,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: isSelected ? _durationColor(minutes) : appColors.cardBorder,
            width: isSelected ? 2 : 1,
          ),
        ),
        child: Text(
          _formatDuration(minutes),
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: 14,
            fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
            color: isSelected ? _durationColor(minutes) : appColors.subtleText,
          ),
        ),
      ),
    );
  }

  Widget _buildCustomDurationChip(AppColors appColors) {
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
          color: isSelected
              ? _durationColor(_duration).withOpacity(0.12)
              : appColors.sectionBackground,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: isSelected ? _durationColor(_duration) : appColors.cardBorder,
            width: isSelected ? 2 : 1,
          ),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.edit, size: 14,
                color: isSelected
                    ? _durationColor(_duration)
                    : appColors.subtleText),
            const SizedBox(width: 4),
            Text(
              isSelected ? _formatDuration(_duration) : 'Custom',
              style: TextStyle(
                fontSize: 13,
                fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
                color: isSelected
                    ? _durationColor(_duration)
                    : appColors.subtleText,
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