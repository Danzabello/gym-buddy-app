import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../services/workout_history_service.dart';
import '../theme/app_theme.dart';
import 'dart:async' show unawaited;
import '../services/achievement_service.dart';

class WorkoutSelectionModal extends StatefulWidget {
  final Function(WorkoutTemplate, int, String?, List<AchievementUnlockResult>) onWorkoutSelected;

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

  // Which category is drilled into. null = showing the category grid.
  String? _drillCategory;

  // Category grid definitions: (db key, label, icon).
  List<(String, String, IconData)> get _categoryDefs => const [
        ('strength', 'Strength', Icons.fitness_center),
        ('cardio', 'Cardio', Icons.directions_run),
        ('hiit', 'HIIT', Icons.bolt),
        ('yoga', 'Yoga / stretch', Icons.self_improvement),
        ('outside', 'Outside', Icons.park),
        ('sports', 'Sports', Icons.sports_tennis),
        ('swimming', 'Swimming', Icons.pool),
        ('cycling', 'Cycling', Icons.directions_bike),
        ('martial_arts', 'Martial arts', Icons.sports_mma),
        ('recovery', 'Recovery', Icons.spa),
      ];

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

  List<WorkoutTemplate> _templatesFor(String category) {
    if (_templates == null) return [];
    return _templates!.where((t) => t.category == category).toList();
  }

  String _labelFor(String category) => _categoryDefs
      .firstWhere((c) => c.$1 == category, orElse: () => (category, category, Icons.category))
      .$2;

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

  void _acceptRandom() async {
    if (_randomTemplate == null) return;
    HapticFeedback.heavyImpact();

    final results = await AchievementService().checkFeelingLucky();
    
    Navigator.pop(context);
    widget.onWorkoutSelected(_randomTemplate!, _randomDuration, null, results);
  }

  // ── Duration picker ───────────────────────────────────────────
  // Categorized workouts enforce a 20-minute minimum.
  static const int _minCategoryDuration = 20;

  void _showCustomDurationDialog(WorkoutTemplate template) {
    HapticFeedback.lightImpact();
    final colors = AppColors.of(context);
    int customDuration = max(_minCategoryDuration, template.defaultDurationMinutes);

    showDialog(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (dialogContext, setDialogState) {
          // Dynamic colour by duration band (shared pattern with the
          // schedule sheets — see _durationColor).
          final dialColor = _durationColor(customDuration);
          return AlertDialog(
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
                        _labelFor(template.category).toUpperCase(),
                        style: TextStyle(
                          fontSize: 12,
                          color: colors.subtleText,
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
                  // Big readout — colour tracks the duration band.
                  AnimatedContainer(
                    duration: const Duration(milliseconds: 200),
                    padding: const EdgeInsets.symmetric(
                        horizontal: 32, vertical: 20),
                    decoration: BoxDecoration(
                      color: dialColor.withOpacity(0.12),
                      borderRadius: BorderRadius.circular(24),
                      border: Border.all(
                          color: dialColor.withOpacity(0.4), width: 2),
                    ),
                    child: FittedBox(
                      fit: BoxFit.scaleDown,
                      child: Text(
                        _formatDuration(customDuration),
                        style: TextStyle(
                          fontSize: 52,
                          fontWeight: FontWeight.bold,
                          color: dialColor,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 24),
                  SliderTheme(
                    data: SliderTheme.of(dialogContext).copyWith(
                      activeTrackColor: dialColor,
                      inactiveTrackColor: colors.cardBorder,
                      thumbColor: dialColor,
                      overlayColor: dialColor.withOpacity(0.2),
                      trackHeight: 10,
                      thumbShape:
                          const RoundSliderThumbShape(enabledThumbRadius: 16),
                      overlayShape:
                          const RoundSliderOverlayShape(overlayRadius: 28),
                    ),
                    child: Slider(
                      value: customDuration.toDouble(),
                      min: _minCategoryDuration.toDouble(),
                      max: 180,
                      divisions: (180 - _minCategoryDuration) ~/ 5,
                      onChanged: (value) {
                        final rounded = (value / 5).round() * 5;
                        HapticFeedback.selectionClick();
                        setDialogState(() => customDuration = rounded);
                      },
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text('20 min',
                            style: TextStyle(
                                color: colors.subtleText, fontSize: 13)),
                        Text('3 hours',
                            style: TextStyle(
                                color: colors.subtleText, fontSize: 13)),
                      ],
                    ),
                  ),
                  const SizedBox(height: 20),
                  Wrap(
                    spacing: 10,
                    runSpacing: 10,
                    alignment: WrapAlignment.center,
                    children: [30, 60, 90, 120].map((mins) {
                      final isSelected = customDuration == mins;
                      final chipColor = _durationColor(mins);
                      return GestureDetector(
                        onTap: () {
                          HapticFeedback.lightImpact();
                          setDialogState(() => customDuration = mins);
                        },
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 200),
                          padding: const EdgeInsets.symmetric(
                              horizontal: 18, vertical: 12),
                          decoration: BoxDecoration(
                            color: isSelected
                                ? chipColor.withOpacity(0.15)
                                : colors.sectionBackground,
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(
                              color:
                                  isSelected ? chipColor : colors.cardBorder,
                              width: isSelected ? 2 : 1,
                            ),
                          ),
                          child: Text(
                            _formatDuration(mins),
                            style: TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.w600,
                              color: isSelected
                                  ? chipColor
                                  : Theme.of(dialogContext)
                                      .colorScheme
                                      .onSurface,
                            ),
                          ),
                        ),
                      );
                    }).toList(),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialogContext),
                child: Text('Cancel',
                    style: TextStyle(color: colors.subtleText)),
              ),
              ElevatedButton(
                onPressed: () {
                  Navigator.pop(dialogContext);
                  Navigator.pop(context);
                  widget.onWorkoutSelected(template, customDuration, null, []);
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: colors.streakOrange,
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
          );
        },
      ),
    );
  }

  // Duration band colour + label — copied from schedule_workout_sheet.dart /
  // quick_schedule_sheet.dart to reuse their duration-picker visual language.
  // (Candidate for extraction to a shared util; kept local to stay surgical.)
  Color _durationColor(int minutes) {
    if (minutes <= 20) return Colors.grey[500]!;
    if (minutes <= 30) return Colors.blue[600]!;
    if (minutes <= 45) return Colors.green[600]!;
    if (minutes <= 60) return Colors.teal[600]!;
    if (minutes <= 75) return Colors.purple[600]!;
    if (minutes <= 90) return Colors.deepPurple[600]!;
    return Colors.red[600]!;
  }

  String _formatDuration(int minutes) {
    if (minutes < 60) return '${minutes}m';
    final h = minutes ~/ 60;
    final m = minutes % 60;
    return m > 0 ? '${h}h ${m}m' : '${h}h';
  }

  // ══════════════════════════════════════════════════════════════
  // BUILD
  // ══════════════════════════════════════════════════════════════
  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    final bottomPadding = MediaQuery.of(context).viewInsets.bottom;
    final inGrid = _drillCategory == null;

    return Container(
      height: MediaQuery.of(context).size.height * 0.85,
      decoration: BoxDecoration(
        color: colors.sectionBackground,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
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
                color: colors.divider,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),

          // ── Header ────────────────────────────────────────────
          Padding(
            padding:
                const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
            child: Row(
              children: [
                if (inGrid)
                  const SizedBox(width: 8)
                else
                  IconButton(
                    icon: const Icon(Icons.arrow_back),
                    tooltip: 'Back to categories',
                    onPressed: () {
                      HapticFeedback.lightImpact();
                      setState(() => _drillCategory = null);
                    },
                  ),
                Text(
                  inGrid ? 'Choose Workout' : _labelFor(_drillCategory!),
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: Theme.of(context).colorScheme.onSurface,
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

          // ── Randomiser section (grid step only) ───────────────
          if (inGrid) ...[
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
              child: _showRandomResult
                  ? _buildRandomResult()
                  : _buildRandomiserButton(),
            ),
            Divider(color: colors.divider, height: 1),
          ],

          // ── Body ──────────────────────────────────────────────
          if (_isLoading)
            const Expanded(
              child: Center(child: CircularProgressIndicator()),
            )
          else if (inGrid)
            Expanded(child: _buildCategoryGrid(bottomPadding))
          else
            Expanded(child: _buildSubcategoryList(bottomPadding)),
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
    final colors = AppColors.of(context);

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
          color: colors.cardBackground,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: colors.cardBorder, width: 2),
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
                      size: 18, color: colors.subtleText),
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
                        style: TextStyle(
                          fontSize: 17,
                          fontWeight: FontWeight.w700,
                          color: Theme.of(context).colorScheme.onSurface,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Row(
                        children: [
                          Icon(Icons.timer_outlined,
                              size: 14,
                              color: colors.subtleText),
                          const SizedBox(width: 4),
                          Text(
                            '$_randomDuration minutes',
                            style: TextStyle(
                              fontSize: 13,
                              color: colors.subtleText,
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
                        color: colors.sectionBackground,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                            color: colors.cardBorder, width: 1.5),
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
                              color: Theme.of(context).colorScheme.onSurface,
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

  // ── Category grid (drill-in step 1) ───────────────────────────
  Widget _buildCategoryGrid(double bottomPadding) {
    return GridView.count(
      crossAxisCount: 2,
      childAspectRatio: 2.4,
      mainAxisSpacing: 10,
      crossAxisSpacing: 10,
      padding: EdgeInsets.fromLTRB(16, 12, 16, bottomPadding + 16),
      children: [
        for (final (key, label, icon) in _categoryDefs)
          _buildCategoryTile(key, label, icon),
      ],
    );
  }

  Widget _buildCategoryTile(String key, String label, IconData icon) {
    final colors = AppColors.of(context);
    return Material(
      color: colors.cardBackground,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: () {
          HapticFeedback.lightImpact();
          setState(() => _drillCategory = key);
        },
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: colors.cardBorder),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          child: Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: colors.streakOrange.withOpacity(0.12),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(icon, color: colors.streakOrange, size: 24),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  label,
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                  ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ── Subcategory list (drill-in step 2) ────────────────────────
  Widget _buildSubcategoryList(double bottomPadding) {
    final templates = _templatesFor(_drillCategory!);
    return ListView.builder(
      padding: EdgeInsets.fromLTRB(16, 12, 16, bottomPadding + 16),
      itemCount: templates.length,
      itemBuilder: (context, index) => _buildTemplateCard(templates[index]),
    );
  }

  // ── Template card ─────────────────────────────────────────────
  Widget _buildTemplateCard(WorkoutTemplate template) {
    final colors = AppColors.of(context);
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: colors.cardBackground,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: colors.cardBorder),
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
          onTap: () => _showCustomDurationDialog(template),
          borderRadius: BorderRadius.circular(14),
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Row(
              children: [
                Container(
                  width: 50,
                  height: 50,
                  decoration: BoxDecoration(
                    color: colors.streakOrange.withOpacity(0.12),
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
                            color: colors.subtleText,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: colors.streakOrange.withOpacity(0.12),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    '${template.defaultDurationMinutes}m',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: colors.streakOrange,
                    ),
                  ),
                ),
                const SizedBox(width: 6),
                Icon(Icons.chevron_right, size: 20, color: colors.subtleText),
              ],
            ),
          ),
        ),
      ),
    );
  }
}