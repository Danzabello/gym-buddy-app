import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../services/workout_history_service.dart';
import '../utils/input_validators.dart';
import 'dart:async' show unawaited;
import '../services/achievement_service.dart';

class WorkoutSelectionModal extends StatefulWidget {
  final Function(WorkoutTemplate, int, String?) onWorkoutSelected;

  const WorkoutSelectionModal({
    super.key,
    required this.onWorkoutSelected,
  });

  @override
  State<WorkoutSelectionModal> createState() => _WorkoutSelectionModalState();
}

class _WorkoutSelectionModalState extends State<WorkoutSelectionModal>
    with SingleTickerProviderStateMixin {
  final WorkoutHistoryService _historyService = WorkoutHistoryService();

  List<WorkoutTemplate>? _templates;
  bool _isLoading = true;
  String _selectedCategory = 'all';

  // ── Randomiser state ──────────────────────────────────────────
  bool _showRandomResult = false;
  WorkoutTemplate? _randomTemplate;
  int _randomDuration = 30;

  // Shake animation controller
  late AnimationController _shakeController;
  late Animation<double> _shakeAnimation;

  @override
  void initState() {
    super.initState();
    _loadTemplates();

    _shakeController = AnimationController(
      duration: const Duration(milliseconds: 600),
      vsync: this,
    );

    _shakeAnimation = TweenSequence([
      TweenSequenceItem(tween: Tween(begin: 0.0, end: -8.0), weight: 1),
      TweenSequenceItem(tween: Tween(begin: -8.0, end: 8.0), weight: 2),
      TweenSequenceItem(tween: Tween(begin: 8.0, end: -8.0), weight: 2),
      TweenSequenceItem(tween: Tween(begin: -8.0, end: 8.0), weight: 2),
      TweenSequenceItem(tween: Tween(begin: 8.0, end: 0.0), weight: 1),
    ]).animate(CurvedAnimation(
      parent: _shakeController,
      curve: Curves.easeInOut,
    ));
  }

  @override
  void dispose() {
    _shakeController.dispose();
    super.dispose();
  }

  Future<void> _loadTemplates() async {
    setState(() => _isLoading = true);
    final templates = await _historyService.getWorkoutTemplates();
    setState(() {
      _templates = templates;
      _isLoading = false;
    });
  }

  List<WorkoutTemplate> get _filteredTemplates {
    if (_templates == null) return [];
    if (_selectedCategory == 'all') return _templates!;
    return _templates!.where((t) => t.category == _selectedCategory).toList();
  }

  // ── Randomiser logic ──────────────────────────────────────────
  void _randomise() {
    if (_templates == null || _templates!.isEmpty) return;

    HapticFeedback.heavyImpact();
    _shakeController.forward(from: 0);

    final random = Random();
    final template = _templates![random.nextInt(_templates!.length)];
    final durations = [15, 30, 45, 60];
    final duration = durations[random.nextInt(durations.length)];

    setState(() {
      _randomTemplate = template;
      _randomDuration = duration;
      _showRandomResult = true;
    });
  }

  void _reRoll() {
    HapticFeedback.mediumImpact();
    _shakeController.forward(from: 0);

    final random = Random();
    final template = _templates![random.nextInt(_templates!.length)];
    final durations = [15, 30, 45, 60];
    final duration = durations[random.nextInt(durations.length)];

    setState(() {
      _randomTemplate = template;
      _randomDuration = duration;
    });
  }

  void _acceptRandom() {
    if (_randomTemplate == null) return;
    HapticFeedback.heavyImpact();
    // 🏆 Feeling Lucky achievement — fire-and-forget
    unawaited(AchievementService().checkFeelingLucky());
    Navigator.pop(context);
    widget.onWorkoutSelected(_randomTemplate!, _randomDuration, null);
  }

  // ── Quick select (existing flow) ──────────────────────────────
  void _quickSelectTemplate(WorkoutTemplate template) {
    HapticFeedback.lightImpact();
    Navigator.pop(context);
    widget.onWorkoutSelected(template, template.defaultDurationMinutes, null);
  }

  void _showCustomDurationDialog(WorkoutTemplate template) {
    HapticFeedback.lightImpact();
    int customDuration = template.defaultDurationMinutes;
    final notesController = TextEditingController();

    showDialog(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (dialogContext, setDialogState) => AlertDialog(
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          title: Row(
            children: [
              Text(template.emoji, style: const TextStyle(fontSize: 28)),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(template.name,
                        style: const TextStyle(fontSize: 18)),
                    Text(
                      template.category.toUpperCase(),
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.grey[600],
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Colors.orange[50],
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: Colors.orange[200]!),
                  ),
                  child: Column(
                    children: [
                      const Text('Duration',
                          style: TextStyle(
                              fontWeight: FontWeight.w600, fontSize: 15)),
                      const SizedBox(height: 12),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          _buildDurationButton(
                            icon: Icons.remove,
                            onTap: customDuration > 15
                                ? () => setDialogState(
                                    () => customDuration -= 5)
                                : null,
                          ),
                          const SizedBox(width: 20),
                          Text(
                            '$customDuration min',
                            style: TextStyle(
                              fontSize: 28,
                              fontWeight: FontWeight.bold,
                              color: Colors.orange[700],
                            ),
                          ),
                          const SizedBox(width: 20),
                          _buildDurationButton(
                            icon: Icons.add,
                            onTap: customDuration < 180
                                ? () => setDialogState(
                                    () => customDuration += 5)
                                : null,
                            isAdd: true,
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: notesController,
                  inputFormatters: InputFormatters.workoutNotes,
                  maxLines: 2,
                  maxLength: InputLimits.notesMax,
                  decoration: InputDecoration(
                    hintText: 'Add notes (optional)',
                    hintStyle: TextStyle(color: Colors.grey[400]),
                    filled: true,
                    fillColor: Colors.grey[50],
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide.none,
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide(color: Colors.grey[300]!),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide(color: Colors.orange[400]!, width: 2),
                    ),
                    contentPadding: const EdgeInsets.all(14),
                    prefixIcon: Icon(Icons.notes, color: Colors.grey[400]),
                    counterStyle: TextStyle(color: Colors.grey[400], fontSize: 11),
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: Text('Cancel',
                  style: TextStyle(color: Colors.grey[600])),
            ),
            ElevatedButton(
              onPressed: () {
                final notesError = InputValidators.workoutNotes(notesController.text);
                if (notesError != null) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text(notesError),
                      backgroundColor: Colors.red[600],
                      behavior: SnackBarBehavior.floating,
                    ),
                  );
                  return;
                }
                Navigator.pop(dialogContext);
                Navigator.pop(context);
                final notes = InputValidators.truncate(
                  notesController.text, InputLimits.notesMax,
                );
                widget.onWorkoutSelected(template, customDuration, notes);
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.orange[600],
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(
                    horizontal: 24, vertical: 12),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              child: const Text('Start Workout',
                  style: TextStyle(fontWeight: FontWeight.bold)),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDurationButton({
    required IconData icon,
    required VoidCallback? onTap,
    bool isAdd = false,
  }) {
    final isEnabled = onTap != null;
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: isEnabled
              ? (isAdd ? Colors.orange[100] : Colors.grey[200])
              : Colors.grey[100],
          shape: BoxShape.circle,
        ),
        child: Icon(
          icon,
          size: 24,
          color: isEnabled
              ? (isAdd ? Colors.orange[700] : Colors.grey[700])
              : Colors.grey[300],
        ),
      ),
    );
  }

  // ══════════════════════════════════════════════════════════════
  // BUILD
  // ══════════════════════════════════════════════════════════════
  @override
  Widget build(BuildContext context) {
    final bottomPadding = MediaQuery.of(context).viewInsets.bottom;

    return Container(
      height: MediaQuery.of(context).size.height * 0.85,
      decoration: const BoxDecoration(
        color: Color(0xFFF8F9FC),
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: Column(
        children: [
          // ── Handle bar ────────────────────────────────────────
          Padding(
            padding: const EdgeInsets.only(top: 12, bottom: 4),
            child: Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.grey[300],
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),

          // ── Header ────────────────────────────────────────────
          Padding(
            padding:
                const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            child: Row(
              children: [
                Text(
                  'Choose Workout',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: Colors.grey.shade800,
                  ),
                ),
                const Spacer(),
                IconButton(
                  icon: const Icon(Icons.close),
                  onPressed: () => Navigator.pop(context),
                ),
              ],
            ),
          ),

          // ── Randomiser section ────────────────────────────────
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
            child: _showRandomResult
                ? _buildRandomResult()
                : _buildRandomiserButton(),
          ),

          Divider(color: Colors.grey[200], height: 1),

          // ── Category filter ───────────────────────────────────
          _buildCategoryFilter(),
          const SizedBox(height: 8),
          Divider(color: Colors.grey[200], height: 1),

          // ── Template list ─────────────────────────────────────
          if (_isLoading)
            const Expanded(
              child: Center(child: CircularProgressIndicator()),
            )
          else
            Expanded(
              child: ListView.builder(
                padding:
                    EdgeInsets.fromLTRB(16, 12, 16, bottomPadding + 16),
                itemCount: _filteredTemplates.length,
                itemBuilder: (context, index) {
                  return _buildTemplateCard(_filteredTemplates[index]);
                },
              ),
            ),
        ],
      ),
    );
  }

  // ── Randomiser button (before rolling) ───────────────────────
  Widget _buildRandomiserButton() {
    return GestureDetector(
      onTap: _randomise,
      child: Container(
        width: double.infinity,
        padding:
            const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            colors: [Color(0xFF4B6EF5), Color(0xFF7B4FD4)],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            BoxShadow(
              color: const Color(0xFF4B6EF5).withOpacity(0.3),
              blurRadius: 12,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Row(
          children: [
            AnimatedBuilder(
              animation: _shakeAnimation,
              builder: (_, child) => Transform.translate(
                offset: Offset(_shakeAnimation.value, 0),
                child: child,
              ),
              child: const Text('🎲',
                  style: TextStyle(fontSize: 32)),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Feeling Lucky?',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  Text(
                    'Tap to randomise your workout',
                    style: TextStyle(
                      color: Colors.white.withOpacity(0.75),
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
            ),
            Container(
              padding: const EdgeInsets.symmetric(
                  horizontal: 14, vertical: 8),
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.2),
                borderRadius: BorderRadius.circular(20),
              ),
              child: const Text(
                'Roll!',
                style: TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w700,
                  fontSize: 14,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ── Random result card (after rolling) ───────────────────────
  Widget _buildRandomResult() {
    if (_randomTemplate == null) return const SizedBox.shrink();

    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 350),
      transitionBuilder: (child, animation) => SlideTransition(
        position: Tween<Offset>(
          begin: const Offset(0, -0.3),
          end: Offset.zero,
        ).animate(CurvedAnimation(
          parent: animation,
          curve: Curves.easeOutBack,
        )),
        child: FadeTransition(opacity: animation, child: child),
      ),
      child: Container(
        key: ValueKey(_randomTemplate!.id + _randomDuration.toString()),
        width: double.infinity,
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
              color: const Color(0xFF4B6EF5).withOpacity(0.3),
              width: 2),
          boxShadow: [
            BoxShadow(
              color: const Color(0xFF4B6EF5).withOpacity(0.08),
              blurRadius: 12,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header row
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: const Color(0xFF4B6EF5).withOpacity(0.1),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      AnimatedBuilder(
                        animation: _shakeAnimation,
                        builder: (_, child) => Transform.translate(
                          offset: Offset(_shakeAnimation.value, 0),
                          child: child,
                        ),
                        child: const Text('🎲', style: TextStyle(fontSize: 12)),
                      ),
                      SizedBox(width: 4),
                      Text(
                        'Your Random Workout',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          color: Color(0xFF4B6EF5),
                        ),
                      ),
                    ],
                  ),
                ),
                const Spacer(),
                GestureDetector(
                  onTap: () =>
                      setState(() => _showRandomResult = false),
                  child: Icon(Icons.close,
                      size: 18, color: Colors.grey[400]),
                ),
              ],
            ),

            const SizedBox(height: 14),

            // Workout info
            Row(
              children: [
                Container(
                  width: 56,
                  height: 56,
                  decoration: BoxDecoration(
                    color: const Color(0xFF4B6EF5).withOpacity(0.08),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Center(
                    child: Text(_randomTemplate!.emoji,
                        style: const TextStyle(fontSize: 30)),
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        _randomTemplate!.name,
                        style: const TextStyle(
                          fontSize: 17,
                          fontWeight: FontWeight.w700,
                          color: Color(0xFF1A1A2E),
                        ),
                      ),
                      const SizedBox(height: 2),
                      Row(
                        children: [
                          Icon(Icons.timer_outlined,
                              size: 14,
                              color: Colors.grey[500]),
                          const SizedBox(width: 4),
                          Text(
                            '$_randomDuration minutes',
                            style: TextStyle(
                              fontSize: 13,
                              color: Colors.grey[600],
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),

            const SizedBox(height: 14),

            // Action buttons
            Row(
              children: [
                // Re-roll
                Expanded(
                  child: GestureDetector(
                    onTap: _reRoll,
                    child: Container(
                      padding:
                          const EdgeInsets.symmetric(vertical: 12),
                      decoration: BoxDecoration(
                        color: Colors.grey[100],
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                            color: Colors.grey[300]!, width: 1.5),
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                        AnimatedBuilder(
                          animation: _shakeAnimation,
                          builder: (_, child) => Transform.translate(
                            offset: Offset(_shakeAnimation.value, 0),
                            child: child,
                          ),
                          child: const Text('🎲', style: TextStyle(fontSize: 16)),
                        ),
                          const SizedBox(width: 6),
                          Text(
                            'Re-roll',
                            style: TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w600,
                              color: Colors.grey[700],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),

                const SizedBox(width: 10),

                // Let's Go!
                Expanded(
                  flex: 2,
                  child: GestureDetector(
                    onTap: _acceptRandom,
                    child: Container(
                      padding:
                          const EdgeInsets.symmetric(vertical: 12),
                      decoration: BoxDecoration(
                        gradient: const LinearGradient(
                          colors: [
                            Color(0xFF4B6EF5),
                            Color(0xFF7B4FD4)
                          ],
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                        ),
                        borderRadius: BorderRadius.circular(12),
                        boxShadow: [
                          BoxShadow(
                            color: const Color(0xFF4B6EF5)
                                .withOpacity(0.3),
                            blurRadius: 8,
                            offset: const Offset(0, 3),
                          ),
                        ],
                      ),
                      child: const Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Text('💪',
                              style: TextStyle(fontSize: 16)),
                          SizedBox(width: 6),
                          Text(
                            "Let's Go!",
                            style: TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w700,
                              color: Colors.white,
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
        ),
      ),
    );
  }

  // ── Category filter ───────────────────────────────────────────
  Widget _buildCategoryFilter() {
    final categories = [
      ('all', 'All', '🏆'),
      ('strength', 'Strength', '💪'),
      ('cardio', 'Cardio', '🏃'),
      ('hiit', 'HIIT', '⚡'),
      ('yoga', 'Yoga', '🧘'),
      ('sports', 'Sports', '⚽'),
      ('other', 'Other', '✨'),
    ];

    return SizedBox(
      height: 50,
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        itemCount: categories.length,
        itemBuilder: (context, index) {
          final (value, label, emoji) = categories[index];
          final isSelected = _selectedCategory == value;

          return Padding(
            padding: const EdgeInsets.only(right: 8),
            child: FilterChip(
              label: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(emoji, style: const TextStyle(fontSize: 16)),
                  const SizedBox(width: 6),
                  Text(label),
                ],
              ),
              selected: isSelected,
              onSelected: (_) =>
                  setState(() => _selectedCategory = value),
              backgroundColor: Colors.grey[100],
              selectedColor: Colors.orange[100],
              checkmarkColor: Colors.orange[800],
              side: BorderSide(
                color: isSelected
                    ? Colors.orange[400]!
                    : Colors.grey[300]!,
              ),
              labelStyle: TextStyle(
                fontSize: 13,
                color: isSelected
                    ? Colors.orange[900]
                    : Colors.grey[700],
                fontWeight: isSelected
                    ? FontWeight.w600
                    : FontWeight.normal,
              ),
            ),
          );
        },
      ),
    );
  }

  // ── Template card ─────────────────────────────────────────────
  Widget _buildTemplateCard(WorkoutTemplate template) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.grey[200]!),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.03),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: () => _quickSelectTemplate(template),
          onLongPress: () => _showCustomDurationDialog(template),
          borderRadius: BorderRadius.circular(14),
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Row(
              children: [
                Container(
                  width: 50,
                  height: 50,
                  decoration: BoxDecoration(
                    color: Colors.orange[50],
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Center(
                    child: Text(template.emoji,
                        style: const TextStyle(fontSize: 26)),
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        template.name,
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      if (template.description != null) ...[
                        const SizedBox(height: 2),
                        Text(
                          template.description!,
                          style: TextStyle(
                            fontSize: 13,
                            color: Colors.grey[600],
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: Colors.orange[50],
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        '${template.defaultDurationMinutes}m',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: Colors.orange[700],
                        ),
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'hold to customise',
                      style: TextStyle(
                        fontSize: 10,
                        color: Colors.grey[400],
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}