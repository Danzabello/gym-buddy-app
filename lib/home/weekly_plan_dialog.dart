part of '../home_screen.dart';


// ═══════════════════════════════════════════════════════════════
// WEEKLY PLAN DIALOG — Editorial stepper redesign
// Returns breakDays (int) on confirm, null on cancel.
// ═══════════════════════════════════════════════════════════════
class _WeeklyPlanDialog extends StatefulWidget {
  final int initialWorkoutDays;
  const _WeeklyPlanDialog({required this.initialWorkoutDays});

  @override
  State<_WeeklyPlanDialog> createState() => _WeeklyPlanDialogState();
}

class _WeeklyPlanDialogState extends State<_WeeklyPlanDialog>
    with SingleTickerProviderStateMixin {
  late int _workoutDays;
  late AnimationController _numAnim;
  late Animation<double> _scaleAnim;

  static const int _min = 4;
  static const int _max = 7;

  @override
  void initState() {
    super.initState();
    _workoutDays = widget.initialWorkoutDays.clamp(_min, _max);
    _numAnim = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 120),
    );
    _scaleAnim = Tween<double>(begin: 1.0, end: 1.18).animate(
      CurvedAnimation(parent: _numAnim, curve: Curves.easeOut),
    );
  }

  @override
  void dispose() {
    _numAnim.dispose();
    super.dispose();
  }

  void _step(int delta) {
    final next = (_workoutDays + delta).clamp(_min, _max);
    if (next == _workoutDays) return;
    setState(() => _workoutDays = next);
    _numAnim.forward(from: 0).then((_) => _numAnim.reverse());
  }

  double get _trackProgress =>
      (_workoutDays - _min) / (_max - _min);

  @override
  Widget build(BuildContext context) {
    final appColors = AppColors.of(context);
    final cs = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final breakDays = 7 - _workoutDays;

    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 40),
      child: Container(
        decoration: BoxDecoration(
          color: appColors.cardBackground,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: appColors.cardBorder, width: 0.5),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // ── Header ──────────────────────────────────────────
            Container(
              padding: const EdgeInsets.fromLTRB(20, 20, 20, 16),
              decoration: BoxDecoration(
                border: Border(
                  bottom: BorderSide(
                      color: appColors.cardBorder, width: 0.5),
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'THIS WEEK',
                    style: TextStyle(
                      fontSize: 9,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 1.2,
                      color: const Color(0xFFF97316),
                    ),
                  ),
                  const SizedBox(height: 4),
                  RichText(
                    text: TextSpan(
                      style: TextStyle(
                        fontSize: 28,
                        fontWeight: FontWeight.w900,
                        letterSpacing: -1.5,
                        height: 0.9,
                        color: cs.onSurface,
                      ),
                      children: [
                        const TextSpan(text: 'WORKOUT\n'),
                        TextSpan(
                          text: 'PLAN',
                          style: TextStyle(
                            color: isDark
                                ? const Color(0xFF7C3AED)
                                : const Color(0xFF6D28D9),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),

            // ── Body ─────────────────────────────────────────────
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 20, 20, 0),
              child: Column(
                children: [
                  // Big animated number
                  ScaleTransition(
                    scale: _scaleAnim,
                    child: Column(
                      children: [
                        Text(
                          '$_workoutDays',
                          style: const TextStyle(
                            fontSize: 72,
                            fontWeight: FontWeight.w900,
                            letterSpacing: -4,
                            height: 1,
                            color: Color(0xFFF97316),
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          'workout day${_workoutDays == 1 ? '' : 's'}',
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w700,
                            letterSpacing: 0.3,
                            color: appColors.subtleText,
                          ),
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(height: 20),

                  // Stepper row: − track +
                  Row(
                    children: [
                      _StepButton(
                        label: '−',
                        enabled: _workoutDays > _min,
                        onTap: () => _step(-1),
                        appColors: appColors,
                        cs: cs,
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          children: [
                            // Gradient track
                            ClipRRect(
                              borderRadius: BorderRadius.circular(3),
                              child: SizedBox(
                                height: 5,
                                child: Stack(
                                  children: [
                                    Container(
                                        color: appColors.divider),
                                    FractionallySizedBox(
                                      widthFactor: _trackProgress,
                                      child: Container(
                                        decoration: const BoxDecoration(
                                          gradient: LinearGradient(
                                            colors: [
                                              Color(0xFFF97316),
                                              Color(0xFF7C3AED),
                                            ],
                                          ),
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                            const SizedBox(height: 6),
                            Row(
                              mainAxisAlignment:
                                  MainAxisAlignment.spaceBetween,
                              children: [
                                Text('4 days',
                                    style: TextStyle(
                                        fontSize: 10,
                                        color: appColors.subtleText)),
                                Text('7 days',
                                    style: TextStyle(
                                        fontSize: 10,
                                        color: appColors.subtleText)),
                              ],
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 12),
                      _StepButton(
                        label: '+',
                        enabled: _workoutDays < _max,
                        onTap: () => _step(1),
                        appColors: appColors,
                        cs: cs,
                        accent: true,
                      ),
                    ],
                  ),

                  const SizedBox(height: 20),

                  // Break days info row
                  AnimatedContainer(
                    duration: const Duration(milliseconds: 200),
                    padding: const EdgeInsets.symmetric(
                        horizontal: 16, vertical: 12),
                    decoration: BoxDecoration(
                      color: const Color(0xFF3B82F6).withValues(alpha: 0.08),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                          color:
                              const Color(0xFF3B82F6).withValues(alpha: 0.2),
                          width: 0.5),
                    ),
                    child: Row(
                      children: [
                        const Text('🌙',
                            style: TextStyle(fontSize: 18)),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            '$breakDays break day${breakDays == 1 ? '' : 's'}',
                            style: const TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.w700,
                              color: Color(0xFF3B82F6),
                            ),
                          ),
                        ),
                        Text(
                          '$breakDays',
                          style: TextStyle(
                            fontSize: 28,
                            fontWeight: FontWeight.w900,
                            letterSpacing: -1,
                            color: const Color(0xFF3B82F6)
                                .withValues(alpha: 0.35),
                          ),
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(height: 12),

                  Text(
                    'Your streak stays safe on break days.',
                    style: TextStyle(
                      fontSize: 11,
                      color: appColors.subtleText,
                      height: 1.4,
                    ),
                    textAlign: TextAlign.center,
                  ),

                  const SizedBox(height: 20),
                ],
              ),
            ),

            // ── Actions ──────────────────────────────────────────
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
              child: Row(
                children: [
                  Expanded(
                    child: GestureDetector(
                      onTap: () => Navigator.pop(context),
                      child: Container(
                        padding:
                            const EdgeInsets.symmetric(vertical: 14),
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                              color: appColors.cardBorder, width: 0.5),
                        ),
                        child: Center(
                          child: Text(
                            'Cancel',
                            style: TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w600,
                              color: appColors.subtleText,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    flex: 2,
                    child: GestureDetector(
                      onTap: () => Navigator.pop(context, breakDays),
                      child: Container(
                        padding:
                            const EdgeInsets.symmetric(vertical: 14),
                        decoration: BoxDecoration(
                          color: const Color(0xFFF97316),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: const Center(
                          child: Text(
                            'Set Plan',
                            style: TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w800,
                              color: Colors.white,
                              letterSpacing: 0.2,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Stepper button ──────────────────────────────────────────────
class _StepButton extends StatelessWidget {
  final String label;
  final bool enabled;
  final bool accent;
  final VoidCallback onTap;
  final AppColors appColors;
  final ColorScheme cs;

  const _StepButton({
    required this.label,
    required this.enabled,
    required this.onTap,
    required this.appColors,
    required this.cs,
    this.accent = false,
  });

  @override
  Widget build(BuildContext context) {
      final active = enabled && accent;
      return GestureDetector(
        onTap: enabled ? onTap : null,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          width: 44,
          height: 44,
          decoration: BoxDecoration(
            color: active
                ? const Color(0xFFF97316)
                : appColors.sectionBackground,
            shape: BoxShape.circle,
            border: Border.all(
              color: active
                  ? const Color(0xFFF97316)
                  : appColors.cardBorder,
              width: 0.5,
            ),
          ),
          child: Center(
            child: Text(
              label,
              style: TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.w700,
                height: 1,
                color: !enabled
                    ? appColors.subtleText.withValues(alpha: 0.4)
                    : active
                        ? Colors.white
                        : cs.onSurface,
              ),
            ),
          ),
        ),
      );
    }
}
