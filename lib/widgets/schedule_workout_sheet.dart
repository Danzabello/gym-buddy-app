import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../services/workout_service.dart';
import '../services/friend_service.dart';

/// Modern bottom sheet for scheduling a workout
/// Can be used standalone or with a pre-selected buddy
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

  /// Show as a bottom sheet
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
  String? _selectedBuddyId;
  String? _selectedBuddyName;
  List<Map<String, dynamic>> _friends = [];
  bool _isCreating = false;
  bool _isLoadingFriends = true;

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

  @override
  void initState() {
    super.initState();
    _selectedBuddyId = widget.preSelectedBuddyId;
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
                  child: Text(
                    _selectedBuddyId != null
                        ? 'Workout invite sent to $_selectedBuddyName! 🎉'
                        : 'Workout scheduled! 💪',
                  ),
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
          SnackBar(
            content: Text('Error: $error'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom,
      ),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
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
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: Colors.green[100],
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child:
                        Icon(Icons.calendar_today, color: Colors.green[700], size: 24),
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
                        if (_selectedBuddyName != null)
                          Text(
                            'with $_selectedBuddyName',
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

            Padding(
              padding: const EdgeInsets.all(20),
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

                  // Buddy Selection (if not pre-selected)
                  if (widget.preSelectedBuddyId == null) ...[
                    const Text(
                      'Workout Buddy',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 12),
                    _buildBuddySelector(),
                    const SizedBox(height: 24),
                  ],

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
                                Icon(
                                  _selectedBuddyId != null
                                      ? Icons.send
                                      : Icons.check,
                                  size: 20,
                                ),
                                const SizedBox(width: 8),
                                Text(
                                  _selectedBuddyId != null
                                      ? 'Send Invite to $_selectedBuddyName'
                                      : 'Schedule Workout',
                                  style: const TextStyle(
                                    fontSize: 16,
                                    fontWeight: FontWeight.bold,
                                  ),
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

  Widget _buildWorkoutTypeGrid() {
    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 4,
        crossAxisSpacing: 10,
        mainAxisSpacing: 10,
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
            setState(() => _selectedType = type['name']);
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

  Widget _buildBuddySelector() {
    if (_isLoadingFriends) {
      return Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.grey[50],
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.grey[200]!),
        ),
        child: const Center(
          child: SizedBox(
            width: 20,
            height: 20,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
        ),
      );
    }

    // Compact selector - tap to open friend picker
    return GestureDetector(
      onTap: _friends.isEmpty ? null : _showBuddyPicker,
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.grey[50],
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: _selectedBuddyId != null ? Colors.green[300]! : Colors.grey[200]!,
          ),
        ),
        child: Row(
          children: [
            // Avatar/Icon
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: _selectedBuddyId != null ? Colors.green[100] : Colors.grey[200],
                shape: BoxShape.circle,
              ),
              child: Icon(
                _selectedBuddyId != null ? Icons.people : Icons.person,
                color: _selectedBuddyId != null ? Colors.green[700] : Colors.grey[600],
                size: 20,
              ),
            ),
            const SizedBox(width: 12),
            
            // Name and status
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    _selectedBuddyId != null 
                        ? _selectedBuddyName ?? 'Unknown'
                        : 'Solo Workout',
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                      color: _selectedBuddyId != null ? Colors.green[700] : Colors.grey[800],
                    ),
                  ),
                  if (_friends.isNotEmpty)
                    Text(
                      _selectedBuddyId != null 
                          ? 'Tap to change'
                          : '${_friends.length} friends available',
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.grey[500],
                      ),
                    ),
                ],
              ),
            ),
            
            // Action indicator
            if (_friends.isNotEmpty)
              Icon(
                Icons.chevron_right,
                color: Colors.grey[400],
              )
            else
              TextButton(
                onPressed: () {
                  Navigator.pop(context);
                  // Navigate to friends tab
                },
                child: Text(
                  'Add Friends',
                  style: TextStyle(
                    fontSize: 12,
                    color: Colors.blue[600],
                  ),
                ),
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
        onSelect: (String? buddyId, String? buddyName) {
          setState(() {
            _selectedBuddyId = buddyId;
            _selectedBuddyName = buddyName;
          });
          Navigator.pop(context);
        },
      ),
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
            _buildDurationChip(30),
            const SizedBox(width: 8),
            _buildDurationChip(45),
            const SizedBox(width: 8),
            _buildDurationChip(60),
            const SizedBox(width: 8),
            _buildDurationChip(90),
          ],
        ),
      ],
    );
  }

  Widget _buildDurationChip(int minutes) {
    final isSelected = _duration == minutes;

    return Expanded(
      child: GestureDetector(
        onTap: () {
          HapticFeedback.selectionClick();
          setState(() => _duration = minutes);
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

/// Bottom sheet for picking a workout buddy with search
class _BuddyPickerSheet extends StatefulWidget {
  final List<Map<String, dynamic>> friends;
  final String? selectedBuddyId;
  final Function(String? buddyId, String? buddyName) onSelect;

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

  void _filterFriends(String query) {
    setState(() {
      if (query.isEmpty) {
        _filteredFriends = widget.friends;
      } else {
        _filteredFriends = widget.friends.where((friend) {
          final name = (friend['display_name'] ?? '').toLowerCase();
          final username = (friend['username'] ?? '').toLowerCase();
          return name.contains(query.toLowerCase()) || 
                 username.contains(query.toLowerCase());
        }).toList();
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      height: MediaQuery.of(context).size.height * 0.6,
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
            child: Row(
              children: [
                Icon(Icons.people, color: Colors.green[700], size: 24),
                const SizedBox(width: 12),
                const Text(
                  'Choose Workout Buddy',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const Spacer(),
                Text(
                  '${widget.friends.length} friends',
                  style: TextStyle(
                    fontSize: 13,
                    color: Colors.grey[500],
                  ),
                ),
              ],
            ),
          ),

          // Search bar (only show if more than 5 friends)
          if (widget.friends.length > 5)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: TextField(
                controller: _searchController,
                onChanged: _filterFriends,
                decoration: InputDecoration(
                  hintText: 'Search friends...',
                  prefixIcon: Icon(Icons.search, color: Colors.grey[400]),
                  filled: true,
                  fillColor: Colors.grey[100],
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide.none,
                  ),
                  contentPadding: const EdgeInsets.symmetric(vertical: 12),
                ),
              ),
            ),

          const SizedBox(height: 12),

          // Solo option at top
          _buildPickerOption(
            name: 'Solo Workout',
            subtitle: 'Work out by yourself',
            icon: Icons.person,
            isSelected: widget.selectedBuddyId == null,
            onTap: () => widget.onSelect(null, null),
          ),

          const Divider(height: 1),

          // Friends list
          Expanded(
            child: _filteredFriends.isEmpty
                ? Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.search_off, size: 48, color: Colors.grey[300]),
                        const SizedBox(height: 12),
                        Text(
                          'No friends found',
                          style: TextStyle(color: Colors.grey[500]),
                        ),
                      ],
                    ),
                  )
                : ListView.builder(
                    padding: const EdgeInsets.only(bottom: 20),
                    itemCount: _filteredFriends.length,
                    itemBuilder: (context, index) {
                      final friend = _filteredFriends[index];
                      final isSelected = widget.selectedBuddyId == friend['id'];
                      
                      return _buildPickerOption(
                        name: friend['display_name'] ?? 'Unknown',
                        subtitle: friend['username'] != null 
                            ? '@${friend['username']}'
                            : null,
                        icon: Icons.people,
                        isSelected: isSelected,
                        onTap: () => widget.onSelect(
                          friend['id'],
                          friend['display_name'],
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildPickerOption({
    required String name,
    String? subtitle,
    required IconData icon,
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
        color: isSelected ? Colors.green[50] : Colors.transparent,
        child: Row(
          children: [
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: isSelected ? Colors.green[100] : Colors.grey[100],
                shape: BoxShape.circle,
              ),
              child: Icon(
                icon,
                color: isSelected ? Colors.green[700] : Colors.grey[600],
                size: 22,
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    name,
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
                      color: isSelected ? Colors.green[700] : Colors.grey[800],
                    ),
                  ),
                  if (subtitle != null)
                    Text(
                      subtitle,
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.grey[500],
                      ),
                    ),
                ],
              ),
            ),
            if (isSelected)
              Container(
                padding: const EdgeInsets.all(4),
                decoration: BoxDecoration(
                  color: Colors.green[600],
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.check,
                  color: Colors.white,
                  size: 16,
                ),
              ),
          ],
        ),
      ),
    );
  }
}