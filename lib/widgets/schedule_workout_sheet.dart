import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../theme/app_theme.dart';
import '../services/workout_service.dart';
import '../services/friend_service.dart';
import 'user_avatar.dart';

class ScheduleWorkoutSheet extends StatefulWidget {
  final String? preSelectedBuddyId;
  final String? preSelectedBuddyName;
  final VoidCallback? onWorkoutScheduled;

  const ScheduleWorkoutSheet({
    super.key,
    this.preSelectedBuddyId,
    this.preSelectedBuddyName,
    this.onWorkoutScheduled,
  });

  static void show(
    BuildContext context, {
    String? buddyId,
    String? buddyName,
    VoidCallback? onWorkoutScheduled,
  }) {
    HapticFeedback.mediumImpact();
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => ScheduleWorkoutSheet(
        preSelectedBuddyId: buddyId,
        preSelectedBuddyName: buddyName,
        onWorkoutScheduled: onWorkoutScheduled,
      ),
    );
  }

  @override
  State<ScheduleWorkoutSheet> createState() => _ScheduleWorkoutSheetState();
}

class _ScheduleWorkoutSheetState extends State<ScheduleWorkoutSheet> {
  final WorkoutService _workoutService = WorkoutService();
  final FriendService _friendService = FriendService();

  String _selectedType = 'Strength';
  DateTime _selectedDate = DateTime.now();
  TimeOfDay _selectedTime = TimeOfDay.now();
  int _duration = 60;
  bool _isCustomDuration = false;  // ✅ NEW
  String? _selectedBuddyId;
  String? _selectedBuddyName;
  String? _selectedBuddyAvatarId;
  List<Map<String, dynamic>> _friends = [];
  bool _isCreating = false;
  bool _isLoadingFriends = true;

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

  @override
  void initState() {
    super.initState();
    _selectedBuddyId   = widget.preSelectedBuddyId;
    _selectedBuddyName = widget.preSelectedBuddyName;
    _loadFriends();
  }

  Future<void> _loadFriends() async {
    final friends = await _friendService.getFriends();
    if (mounted) {
      setState(() {
        _friends = friends;
        _isLoadingFriends = false;
      });
    }
  }

  Future<void> _scheduleWorkout() async {
    setState(() => _isCreating = true);
    final timeString =
        '${_selectedTime.hour.toString().padLeft(2, '0')}:${_selectedTime.minute.toString().padLeft(2, '0')}:00';

    final error = await _workoutService.createWorkout(
      workoutType: _selectedType,
      date: _selectedDate,
      time: timeString,
      plannedDurationMinutes: _duration,
      buddyId: _selectedBuddyId,
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
                  child: Text(_selectedBuddyId != null
                      ? 'Workout invite sent to $_selectedBuddyName! 🎉'
                      : 'Workout scheduled! 💪'),
                ),
              ],
            ),
            backgroundColor: Colors.green[600],
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

  // ✅ NEW — Custom duration picker (matches QuickScheduleSheet)
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

    return Container(
      decoration: BoxDecoration(
        color: appColors.cardBackground,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
      ),
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              margin: const EdgeInsets.only(top: 12),
              width: 40, height: 4,
              decoration: BoxDecoration(
                color: appColors.divider,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(20),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: Colors.green.withOpacity(0.15),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Icon(Icons.calendar_today,
                        color: Colors.green[400], size: 24),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Schedule Workout',
                            style: TextStyle(
                              fontSize: 20, fontWeight: FontWeight.bold,
                              color: Theme.of(context).colorScheme.onSurface,
                            )),
                        if (_selectedBuddyName != null)
                          Text('with $_selectedBuddyName',
                              style: TextStyle(
                                  fontSize: 14, color: appColors.subtleText)),
                      ],
                    ),
                  ),
                  IconButton(
                    onPressed: () => Navigator.pop(context),
                    icon: Icon(Icons.close, color: appColors.subtleText),
                  ),
                ],
              ),
            ),
            Divider(height: 1, color: appColors.divider),
            Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Workout Type',
                      style: TextStyle(
                        fontSize: 16, fontWeight: FontWeight.w600,
                        color: Theme.of(context).colorScheme.onSurface,
                      )),
                  const SizedBox(height: 12),
                  _buildWorkoutTypeGrid(appColors),
                  const SizedBox(height: 24),
                  if (widget.preSelectedBuddyId == null) ...[
                    Text('Workout Buddy',
                        style: TextStyle(
                          fontSize: 16, fontWeight: FontWeight.w600,
                          color: Theme.of(context).colorScheme.onSurface,
                        )),
                    const SizedBox(height: 12),
                    _buildBuddySelector(appColors),
                    const SizedBox(height: 24),
                  ],
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
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(16)),
                        elevation: 2,
                      ),
                      child: _isCreating
                          ? const SizedBox(
                              width: 24, height: 24,
                              child: CircularProgressIndicator(
                                  strokeWidth: 2, color: Colors.white))
                          : Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(_selectedBuddyId != null
                                    ? Icons.send : Icons.check, size: 20),
                                const SizedBox(width: 8),
                                Text(
                                  _selectedBuddyId != null
                                      ? 'Send Invite to $_selectedBuddyName'
                                      : 'Schedule Workout',
                                  style: const TextStyle(
                                      fontSize: 16, fontWeight: FontWeight.bold),
                                ),
                              ],
                            ),
                    ),
                  ),
                  SizedBox(height: MediaQuery.of(context).padding.bottom + 16),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildWorkoutTypeGrid(AppColors appColors) {
    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 4, crossAxisSpacing: 10, mainAxisSpacing: 10,
        childAspectRatio: 0.9,
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
              color: isSelected
                  ? color.withOpacity(0.12)
                  : appColors.sectionBackground,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: isSelected ? color[400]! : appColors.cardBorder,
                width: isSelected ? 2 : 1,
              ),
            ),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(type['icon'] as IconData,
                    color: isSelected ? color[400] : appColors.subtleText,
                    size: 24),
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

  Widget _buildBuddySelector(AppColors appColors) {
    if (_isLoadingFriends) {
      return Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: appColors.sectionBackground,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: appColors.cardBorder),
        ),
        child: const Center(
          child: SizedBox(width: 20, height: 20,
              child: CircularProgressIndicator(strokeWidth: 2)),
        ),
      );
    }

    return GestureDetector(
      onTap: _friends.isEmpty ? null : _showBuddyPicker,
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: appColors.sectionBackground,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: _selectedBuddyId != null
                ? Colors.green[400]! : appColors.cardBorder,
          ),
        ),
        child: Row(
          children: [
            if (_selectedBuddyAvatarId != null)
              UserAvatar(avatarId: _selectedBuddyAvatarId!, size: 40)
            else
              Container(
                width: 40, height: 40,
                decoration: BoxDecoration(
                  color: _selectedBuddyId != null
                      ? Colors.green.withOpacity(0.15)
                      : appColors.cardBorder,
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  _selectedBuddyId != null ? Icons.people : Icons.person,
                  color: _selectedBuddyId != null
                      ? Colors.green[400] : appColors.subtleText,
                  size: 20,
                ),
              ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    _selectedBuddyId != null
                        ? _selectedBuddyName ?? 'Unknown'
                        : 'Solo Workout',
                    style: TextStyle(
                      fontSize: 15, fontWeight: FontWeight.w600,
                      color: _selectedBuddyId != null
                          ? Colors.green[400]
                          : Theme.of(context).colorScheme.onSurface,
                    ),
                  ),
                  if (_friends.isNotEmpty)
                    Text(
                      _selectedBuddyId != null
                          ? 'Tap to change'
                          : '${_friends.length} friends available',
                      style: TextStyle(fontSize: 12, color: appColors.subtleText),
                    ),
                ],
              ),
            ),
            if (_friends.isNotEmpty)
              Icon(Icons.chevron_right, color: appColors.subtleText)
            else
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: Text('Add Friends',
                    style: TextStyle(fontSize: 12, color: Colors.blue[400])),
              ),
          ],
        ),
      ),
    );
  }

  void _showBuddyPicker() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => _BuddyPickerSheet(
        friends: _friends,
        selectedBuddyId: _selectedBuddyId,
        onSelect: (buddyId, buddyName, avatarId) {
          setState(() {
            _selectedBuddyId       = buddyId;
            _selectedBuddyName     = buddyName;
            _selectedBuddyAvatarId = avatarId;
          });
          Navigator.pop(context);
        },
      ),
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
          color: appColors.sectionBackground,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: appColors.cardBorder),
        ),
        child: Row(
          children: [
            Icon(Icons.calendar_today, color: appColors.subtleText, size: 20),
            const SizedBox(width: 12),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Date',
                    style: TextStyle(fontSize: 11, color: appColors.subtleText)),
                Text(_formatDate(_selectedDate),
                    style: TextStyle(
                      fontSize: 14, fontWeight: FontWeight.w600,
                      color: Theme.of(context).colorScheme.onSurface,
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
        final time = await showTimePicker(
            context: context, initialTime: _selectedTime);
        if (time != null) setState(() => _selectedTime = time);
      },
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: appColors.sectionBackground,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: appColors.cardBorder),
        ),
        child: Row(
          children: [
            Icon(Icons.access_time, color: appColors.subtleText, size: 20),
            const SizedBox(width: 12),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Time',
                    style: TextStyle(fontSize: 11, color: appColors.subtleText)),
                Text(_selectedTime.format(context),
                    style: TextStyle(
                      fontSize: 14, fontWeight: FontWeight.w600,
                      color: Theme.of(context).colorScheme.onSurface,
                    )),
              ],
            ),
          ],
        ),
      ),
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

  Widget _buildDurationSelector(AppColors appColors) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text('Duration',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600,
                    color: Theme.of(context).colorScheme.onSurface)),
            Text(_formatDuration(_duration),
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold,
                    color: _durationColor(_duration))),  // ← dynamic colour
          ],
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            ...[30, 45, 60].map((m) {
              final isSelected = _duration == m && !_isCustomDuration;
              return Expanded(
                child: Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: GestureDetector(
                    onTap: () {
                      HapticFeedback.selectionClick();
                      setState(() { _duration = m; _isCustomDuration = false; });
                    },
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 200),
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      decoration: BoxDecoration(
                        color: isSelected
                            ? _durationColor(m).withOpacity(0.12)
                            : appColors.sectionBackground,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: isSelected ? _durationColor(m) : appColors.cardBorder,
                          width: isSelected ? 2 : 1,
                        ),
                      ),
                      child: Text(_formatDuration(m),
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
                            color: isSelected ? _durationColor(m) : appColors.subtleText,
                          )),
                    ),
                  ),
                ),
              );
            }),
            // Custom chip
            Expanded(
              child: GestureDetector(
                onTap: () {
                  HapticFeedback.selectionClick();
                  _showCustomDurationDialog();
                },
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  decoration: BoxDecoration(
                    color: _isCustomDuration
                        ? _durationColor(_duration).withOpacity(0.12)
                        : appColors.sectionBackground,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: _isCustomDuration
                          ? _durationColor(_duration) : appColors.cardBorder,
                      width: _isCustomDuration ? 2 : 1,
                    ),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.edit, size: 14,
                          color: _isCustomDuration
                              ? _durationColor(_duration) : appColors.subtleText),
                      const SizedBox(width: 4),
                      Text(
                        _isCustomDuration ? _formatDuration(_duration) : 'Custom',
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: _isCustomDuration
                              ? FontWeight.bold : FontWeight.w500,
                          color: _isCustomDuration
                              ? _durationColor(_duration) : appColors.subtleText,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }

  String _formatDate(DateTime date) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final tomorrow = today.add(const Duration(days: 1));
    final sel = DateTime(date.year, date.month, date.day);
    if (sel == today) return 'Today';
    if (sel == tomorrow) return 'Tomorrow';
    const days = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
    return '${days[date.weekday - 1]}, ${date.month}/${date.day}';
  }

  String _formatDuration(int minutes) {
    if (minutes < 60) return '${minutes}m';
    final h = minutes ~/ 60;
    final m = minutes % 60;
    return m > 0 ? '${h}h ${m}m' : '${h}h';
  }
}

// ── Buddy picker sheet ──────────────────────────────────────────
class _BuddyPickerSheet extends StatefulWidget {
  final List<Map<String, dynamic>> friends;
  final String? selectedBuddyId;
  final Function(String? buddyId, String? buddyName, String? avatarId) onSelect;

  const _BuddyPickerSheet({
    required this.friends,
    required this.selectedBuddyId,
    required this.onSelect,
  });

  @override
  State<_BuddyPickerSheet> createState() => _BuddyPickerSheetState();
}

class _BuddyPickerSheetState extends State<_BuddyPickerSheet> {
  final TextEditingController _searchController = TextEditingController();
  List<Map<String, dynamic>> _filteredFriends = [];

  @override
  void initState() {
    super.initState();
    _filteredFriends = widget.friends;
  }

  void _filter(String query) {
    setState(() {
      _filteredFriends = query.isEmpty
          ? widget.friends
          : widget.friends.where((f) {
              final name = (f['display_name'] ?? '').toLowerCase();
              final user = (f['username'] ?? '').toLowerCase();
              return name.contains(query.toLowerCase()) ||
                  user.contains(query.toLowerCase());
            }).toList();
    });
  }

  @override
  Widget build(BuildContext context) {
    final appColors = AppColors.of(context);

    return Container(
      height: MediaQuery.of(context).size.height * 0.6,
      decoration: BoxDecoration(
        color: appColors.cardBackground,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: Column(
        children: [
          Container(
            margin: const EdgeInsets.only(top: 12),
            width: 40, height: 4,
            decoration: BoxDecoration(
              color: appColors.divider,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(20),
            child: Row(
              children: [
                Icon(Icons.people, color: Colors.green[400], size: 24),
                const SizedBox(width: 12),
                Text('Choose Workout Buddy',
                    style: TextStyle(
                      fontSize: 18, fontWeight: FontWeight.bold,
                      color: Theme.of(context).colorScheme.onSurface,
                    )),
                const Spacer(),
                Text('${widget.friends.length} friends',
                    style: TextStyle(fontSize: 13, color: appColors.subtleText)),
              ],
            ),
          ),
          if (widget.friends.length > 5)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: TextField(
                controller: _searchController,
                onChanged: _filter,
                style: TextStyle(color: Theme.of(context).colorScheme.onSurface),
                decoration: InputDecoration(
                  hintText: 'Search friends...',
                  hintStyle: TextStyle(color: appColors.subtleText),
                  prefixIcon: Icon(Icons.search, color: appColors.subtleText),
                  filled: true,
                  fillColor: appColors.sectionBackground,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide.none,
                  ),
                  contentPadding: const EdgeInsets.symmetric(vertical: 12),
                ),
              ),
            ),
          const SizedBox(height: 12),
          _buildOption(
            context: context,
            appColors: appColors,
            name: 'Solo Workout',
            subtitle: 'Work out by yourself',
            avatarId: null,
            isSolo: true,
            isSelected: widget.selectedBuddyId == null,
            onTap: () => widget.onSelect(null, null, null),
          ),
          Divider(height: 1, color: appColors.divider),
          Expanded(
            child: _filteredFriends.isEmpty
                ? Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.search_off, size: 48, color: appColors.divider),
                        const SizedBox(height: 12),
                        Text('No friends found',
                            style: TextStyle(color: appColors.subtleText)),
                      ],
                    ),
                  )
                : ListView.builder(
                    padding: const EdgeInsets.only(bottom: 20),
                    itemCount: _filteredFriends.length,
                    itemBuilder: (context, index) {
                      final friend = _filteredFriends[index];
                      final isSelected =
                          widget.selectedBuddyId == friend['id'];
                      return _buildOption(
                        context: context,
                        appColors: appColors,
                        name: friend['display_name'] ?? 'Unknown',
                        subtitle: friend['username'] != null
                            ? '@${friend['username']}' : null,
                        avatarId: friend['avatar_id'] as String?,
                        isSolo: false,
                        isSelected: isSelected,
                        onTap: () => widget.onSelect(
                          friend['id'],
                          friend['display_name'],
                          friend['avatar_id'] as String?,
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildOption({
    required BuildContext context,
    required AppColors appColors,
    required String name,
    String? subtitle,
    String? avatarId,
    required bool isSolo,
    required bool isSelected,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: () {
        HapticFeedback.selectionClick();
        onTap();
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
        color: isSelected
            ? Colors.green.withOpacity(0.08) : Colors.transparent,
        child: Row(
          children: [
            if (!isSolo && avatarId != null)
              UserAvatar(avatarId: avatarId, size: 44)
            else
              Container(
                width: 44, height: 44,
                decoration: BoxDecoration(
                  color: isSelected
                      ? Colors.green.withOpacity(0.15)
                      : appColors.sectionBackground,
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  isSolo ? Icons.person : Icons.people,
                  color: isSelected
                      ? Colors.green[400] : appColors.subtleText,
                  size: 22,
                ),
              ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(name,
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight:
                            isSelected ? FontWeight.bold : FontWeight.w500,
                        color: isSelected
                            ? Colors.green[400]
                            : Theme.of(context).colorScheme.onSurface,
                      )),
                  if (subtitle != null)
                    Text(subtitle,
                        style: TextStyle(
                            fontSize: 12, color: appColors.subtleText)),
                ],
              ),
            ),
            if (isSelected)
              Container(
                padding: const EdgeInsets.all(4),
                decoration: BoxDecoration(
                    color: Colors.green[500], shape: BoxShape.circle),
                child: const Icon(Icons.check, color: Colors.white, size: 16),
              ),
          ],
        ),
      ),
    );
  }
}