part of '../home_screen.dart';

// ═══════════════════════════════════════════════════════════════
// WEEKLY PLAN DIALOG
// Cannot be dismissed: no barrier tap, no Back, no cancel. It saves the plan
// itself and closes, with the saved break-day count, only after a save worked.
// ═══════════════════════════════════════════════════════════════

/// Opens on this many workout days (5 = 2 break days).
const int kWeeklyPlanDefaultWorkoutDays = 5;

/// One look per number of workout days. The only place the tier colours live
/// (owner spec, 2026-11-20: raw hex on purpose, these are not theme colours).
class _Tier {
  const _Tier({
    required this.label,
    required this.accent,
    required this.numberColor,
    required this.onAccent,
    required this.numberSize,
    required this.numberGlow,
    required this.cardGlow,
    required this.note,
  });
  final String label;
  final Color accent;
  final Color numberColor;
  final Color onAccent; // text on an accent fill
  final double numberSize;
  final double numberGlow; // blur of the number's text shadow
  final double cardGlow; // blur of the card's glow
  final String note;
}

// Index = workout days - 4.
const List<_Tier> _tiers = [
  _Tier(
    label: 'Steady',
    accent: Color(0xFF3DDC84),
    numberColor: Color(0xFF7CF0B0),
    onAccent: Color(0xFF08201A),
    numberSize: 64,
    numberGlow: 0,
    cardGlow: 8,
    note: 'Plenty of rest. A break day keeps your streak safe.',
  ),
  _Tier(
    label: 'Solid',
    accent: Color(0xFFF5C842),
    numberColor: Color(0xFFFFD95E),
    onAccent: Color(0xFF241A00),
    numberSize: 76,
    numberGlow: 10,
    cardGlow: 16,
    note: 'A good balance. A break day keeps your streak safe.',
  ),
  _Tier(
    label: 'Heavy',
    accent: Color(0xFFFF8A2B),
    numberColor: Color(0xFFFFA057),
    onAccent: Color(0xFF2A1200),
    numberSize: 88,
    numberGlow: 22,
    cardGlow: 26,
    note: 'One day to recover. Make it count.',
  ),
  _Tier(
    label: 'Beast mode',
    accent: Color(0xFFE5243B),
    numberColor: Color(0xFFFF5468),
    onAccent: Color(0xFFFFFFFF),
    numberSize: 100,
    numberGlow: 34,
    cardGlow: 40,
    note: 'No rest at all. Every day counts.',
  ),
];

/// A tier's numbers, so two tiers can be blended while the look changes.
class _Look {
  const _Look(this.accent, this.numberColor, this.onAccent, this.numberSize, this.numberGlow,
      this.cardGlow);
  factory _Look.of(_Tier t) =>
      _Look(t.accent, t.numberColor, t.onAccent, t.numberSize, t.numberGlow, t.cardGlow);

  final Color accent;
  final Color numberColor;
  final Color onAccent;
  final double numberSize;
  final double numberGlow;
  final double cardGlow;

  static _Look lerp(_Look a, _Look b, double t) => _Look(
        Color.lerp(a.accent, b.accent, t)!,
        Color.lerp(a.numberColor, b.numberColor, t)!,
        Color.lerp(a.onAccent, b.onAccent, t)!,
        ui.lerpDouble(a.numberSize, b.numberSize, t)!,
        ui.lerpDouble(a.numberGlow, b.numberGlow, t)!,
        ui.lerpDouble(a.cardGlow, b.cardGlow, t)!,
      );
}

enum _PlanSave { idle, saving, failed, saved }

/// Shows the dialog. [save] gets the break-day count (7 - workout days) and is
/// called from inside the dialog; the result is that count, only after [save]
/// succeeded. The scrim is drawn by the dialog (it follows the tier), so the
/// route's own barrier is transparent and the route's safe area is off: the
/// scrim must reach under the status bar and the nav bar. The card avoids
/// them itself.
@visibleForTesting
Future<int?> showWeeklyPlanDialog(
  BuildContext context, {
  required Future<void> Function(int breakDays) save,
  int initialWorkoutDays = kWeeklyPlanDefaultWorkoutDays,
}) =>
    showDialog<int>(
      context: context,
      barrierDismissible: false,
      barrierColor: Colors.transparent,
      useSafeArea: false,
      builder: (_) => WeeklyPlanDialog(initialWorkoutDays: initialWorkoutDays, save: save),
    );

/// The toast after a saved plan.
@visibleForTesting
SnackBar weeklyPlanSnackBar(int breakDays) => SnackBar(
      content: Text('Set $breakDays break day${breakDays == 1 ? '' : 's'} for this week.'),
      backgroundColor: Colors.green,
    );

/// Whether the plan dialog is due: true or false once the read answered, null
/// when it is unknown (offline or failed). Unknown shows no dialog and is not
/// remembered, so the next open asks again. An error that is not the network
/// is reported once as 'weekly_plan_check'.
@visibleForTesting
Future<bool?> weeklyPlanNeeded(
  Future<bool> Function() read, {
  void Function(Object, StackTrace?, String)? report,
}) async {
  try {
    return await orUnknown(read);
  } catch (e, st) {
    (report ?? reportNonFatal)(e, st, 'weekly_plan_check');
    return null;
  }
}

/// What to do with an answered plan check: nothing (a plan exists), open the
/// dialog, or leave it for later because the screen is busy. Later is not
/// remembered, so the next time Home is shown the check asks again.
enum WeeklyPlanStep { skip, show, later }

@visibleForTesting
WeeklyPlanStep weeklyPlanStep({required bool needsPlan, required bool screenFree}) =>
    !needsPlan ? WeeklyPlanStep.skip : (screenFree ? WeeklyPlanStep.show : WeeklyPlanStep.later);

/// Whether nothing else is on screen: Home is the current route (no pushed
/// page, bottom sheet or dialog above it) and the Dashboard is the shown tab.
/// The dialog cannot be left, so it must not land over anything else.
@visibleForTesting
bool weeklyPlanScreenIsFree(BuildContext context) =>
    ModalRoute.of(context)?.isCurrent == true && LiveEventToast.dashboardTabActive;

/// Waits, with no network call, for the screen to be free, then shows the plan
/// dialog once. Started when an answered check says the plan is needed but the
/// screen is busy (a pushed page, the notice dialog, another tab): nothing
/// else would ask again until a tab switch or a long resume.
@visibleForTesting
class WeeklyPlanWaiter {
  WeeklyPlanWaiter({
    required this.isMounted,
    required this.alreadyHandled,
    required this.screenFree,
    required this.show,
    this.every = const Duration(seconds: 2),
  });

  final bool Function() isMounted;
  final bool Function() alreadyHandled; // the "checked this session" flag
  final bool Function() screenFree;
  final void Function() show; // sets the flag, synchronously, and opens the dialog
  final Duration every;
  Timer? _timer;

  bool get waiting => _timer != null;

  /// One timer at most, however many checks come back "later".
  void start() => _timer ??= Timer.periodic(every, (_) => _tick());

  void cancel() {
    _timer?.cancel();
    _timer = null;
  }

  void _tick() {
    if (!isMounted() || alreadyHandled()) return cancel();
    if (!screenFree()) return;
    cancel();
    show();
  }
}

/// Applies an answered plan check. A plan that exists cancels a waiting
/// waiter, a free screen cancels it and shows the dialog now, a busy screen
/// starts (or keeps) the waiter.
@visibleForTesting
void applyWeeklyPlanStep(WeeklyPlanStep step, WeeklyPlanWaiter waiter) {
  switch (step) {
    case WeeklyPlanStep.skip:
      waiter.cancel();
    case WeeklyPlanStep.show:
      waiter.cancel();
      waiter.show();
    case WeeklyPlanStep.later:
      waiter.start();
  }
}

@visibleForTesting
class WeeklyPlanDialog extends StatefulWidget {
  const WeeklyPlanDialog({
    super.key,
    required this.save,
    this.initialWorkoutDays = kWeeklyPlanDefaultWorkoutDays,
  });

  final int initialWorkoutDays;
  final Future<void> Function(int breakDays) save;

  @override
  State<WeeklyPlanDialog> createState() => _WeeklyPlanDialogState();
}

class _WeeklyPlanDialogState extends State<WeeklyPlanDialog> with TickerProviderStateMixin {
  static const int _min = 4;
  static const int _max = 7;

  late int _workoutDays;
  _PlanSave _save = _PlanSave.idle;
  bool _reduce = false;

  // Blends the look between tiers (~300 ms).
  late final AnimationController _tierCtl;
  // One controller for the pop of the number, the ring, the chip and the card.
  late final AnimationController _pop;
  // The idle loop of tier 6 (throb) and tier 7 (jitter).
  late final AnimationController _idle;
  late _Look _from;
  late _Look _to;

  _Tier get _tier => _tiers[_workoutDays - _min];

  // Number: 0.5x and low, up to 1.3x, back to 0.93x, settles at 1x.
  static final _numScale = TweenSequence<double>([
    TweenSequenceItem(
        tween: Tween(begin: 0.5, end: 1.3).chain(CurveTween(curve: Curves.easeOutCubic)),
        weight: 40),
    TweenSequenceItem(
        tween: Tween(begin: 1.3, end: 0.93).chain(CurveTween(curve: Curves.easeInOut)),
        weight: 30),
    TweenSequenceItem(
        tween: Tween(begin: 0.93, end: 1.0).chain(CurveTween(curve: Curves.easeOut)), weight: 30),
  ]);
  static final _numDy = TweenSequence<double>([
    TweenSequenceItem(
        tween: Tween(begin: 18.0, end: -4.0).chain(CurveTween(curve: Curves.easeOutCubic)),
        weight: 40),
    TweenSequenceItem(
        tween: Tween(begin: -4.0, end: 0.0).chain(CurveTween(curve: Curves.easeOut)), weight: 60),
  ]);
  // Chip and card: the same shape, a little smaller.
  static final _chipScale = TweenSequence<double>([
    TweenSequenceItem(
        tween: Tween(begin: 0.8, end: 1.1).chain(CurveTween(curve: Curves.easeOutCubic)),
        weight: 50),
    TweenSequenceItem(
        tween: Tween(begin: 1.1, end: 1.0).chain(CurveTween(curve: Curves.easeOut)), weight: 50),
  ]);

  @override
  void initState() {
    super.initState();
    _workoutDays = widget.initialWorkoutDays.clamp(_min, _max);
    _to = _Look.of(_tier);
    _from = _to;
    _tierCtl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 300), value: 1);
    _pop = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 650), value: 1);
    _idle = AnimationController(vsync: this, duration: const Duration(milliseconds: 380));
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _reduce = MediaQuery.of(context).disableAnimations;
    _syncIdle();
  }

  @override
  void dispose() {
    _tierCtl.dispose();
    _pop.dispose();
    _idle.dispose();
    super.dispose();
  }

  void _syncIdle() {
    if (_reduce || _workoutDays < 6) {
      _idle.stop();
      _idle.value = 0;
    } else if (_workoutDays == 6) {
      _idle.duration = const Duration(milliseconds: 650); // 1.3 s there and back
      _idle.repeat(reverse: true);
    } else {
      _idle.duration = const Duration(milliseconds: 380);
      _idle.repeat();
    }
  }

  _Look _currentLook() =>
      _Look.lerp(_from, _to, Curves.easeOut.transform(_tierCtl.value));

  void _setDays(int next) {
    if (_save == _PlanSave.saving || _save == _PlanSave.saved) return; // locked
    next = next.clamp(_min, _max);
    if (next == _workoutDays) return;
    final from = _currentLook();
    setState(() {
      _workoutDays = next;
      if (_save == _PlanSave.failed) _save = _PlanSave.idle; // a new number clears the message
      _from = from;
      _to = _Look.of(_tier);
    });
    if (_reduce) {
      _tierCtl.value = 1;
      _pop.value = 1;
    } else {
      _tierCtl.forward(from: 0);
      _pop.forward(from: 0);
    }
    _syncIdle();
  }

  Future<void> _submit() async {
    // One save at a time, and none once it worked (a double tap).
    if (_save == _PlanSave.saving || _save == _PlanSave.saved) return;
    final breakDays = 7 - _workoutDays;
    setState(() => _save = _PlanSave.saving);
    try {
      await widget.save(breakDays);
    } catch (e, st) {
      reportNonFatal(e, st, 'weekly_plan_save');
      if (mounted) setState(() => _save = _PlanSave.failed);
      return;
    }
    if (!mounted) return;
    setState(() => _save = _PlanSave.saved);
    await Future.delayed(const Duration(milliseconds: 900)); // the check shows briefly
    if (!mounted) return;
    Navigator.of(context).pop(breakDays);
  }

  String _breakLabel(int breakDays) => breakDays == 0
      ? 'No break days'
      : breakDays == 1
          ? '1 break day'
          : '$breakDays break days';

  @override
  Widget build(BuildContext context) {
    // Back does nothing. The only way out is a successful save.
    return PopScope(
      canPop: false,
      child: AnimatedBuilder(
        animation: Listenable.merge([_tierCtl, _pop]),
        builder: (context, _) => _buildScrimAndCard(context),
      ),
    );
  }

  Widget _buildScrimAndCard(BuildContext context) {
    final appColors = AppColors.of(context);
    final cs = Theme.of(context).colorScheme;
    final look = _currentLook();
    final bars = MediaQuery.paddingOf(context); // status bar, nav bar: the scrim covers them, the card keeps off them
    final breakDays = 7 - _workoutDays;
    final chipPop = _chipScale.transform((_pop.value / (420 / 650)).clamp(0.0, 1.0));

    return Stack(
      fit: StackFit.expand,
      children: [
        // Scrim: a dark layer (about 60% black), then a soft glow in the tier
        // colour on top. They are two layers because a BoxDecoration with both
        // a color and a gradient paints only the gradient.
        Positioned.fill(
          child: IgnorePointer(
            child: ColoredBox(
              key: const ValueKey('weekly_plan_scrim'),
              color: Colors.black.withValues(alpha: 0.6),
            ),
          ),
        ),
        Positioned.fill(
          child: IgnorePointer(
            child: DecoratedBox(
              key: const ValueKey('weekly_plan_glow'),
              decoration: BoxDecoration(
                gradient: RadialGradient(
                  center: const Alignment(0, -0.1),
                  radius: 0.85,
                  colors: [
                    look.accent.withValues(alpha: 0.10 + 0.04 * (_workoutDays - _min)),
                    Colors.transparent,
                  ],
                ),
              ),
            ),
          ),
        ),
        Dialog(
          backgroundColor: Colors.transparent,
          elevation: 0,
          insetPadding: EdgeInsets.fromLTRB(24, 24 + bars.top, 24, 24 + bars.bottom),
          child: Container(
            key: const ValueKey('weekly_plan_card'),
            decoration: BoxDecoration(
              color: appColors.cardBackground,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: look.accent, width: 1.5),
              boxShadow: [
                BoxShadow(
                  color: look.accent.withValues(alpha: 0.28),
                  blurRadius: look.cardGlow,
                ),
              ],
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // ── Header ─────────────────────────────────────
                Container(
                  padding: const EdgeInsets.fromLTRB(20, 20, 20, 16),
                  decoration: BoxDecoration(
                    border: Border(bottom: BorderSide(color: appColors.cardBorder, width: 0.5)),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'THIS WEEK',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 12 * 0.12,
                          color: look.accent,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        'Plan your week',
                        style: TextStyle(
                            fontSize: 25, fontWeight: FontWeight.w900, color: cs.onSurface),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        'Choose how many days you will train. The rest are break days.',
                        style: TextStyle(fontSize: 14, color: appColors.subtleText, height: 1.35),
                      ),
                    ],
                  ),
                ),

                // ── Body ───────────────────────────────────────
                Flexible(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.fromLTRB(20, 18, 20, 20),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        // Tier chip
                        Center(
                          child: Transform.scale(
                            scale: chipPop,
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 8),
                              decoration: ShapeDecoration(
                                  color: look.accent, shape: const StadiumBorder()),
                              child: Text(
                                _tier.label.toUpperCase(),
                                key: const ValueKey('weekly_plan_tier'),
                                style: TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w900,
                                  letterSpacing: 0.8,
                                  color: look.onAccent,
                                ),
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(height: 14),

                        // Stepper row
                        FittedBox(
                          fit: BoxFit.scaleDown,
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              _PlanStepButton(
                                key: const ValueKey('weekly_plan_minus'),
                                icon: Icons.remove_rounded,
                                semanticLabel: 'Fewer workout days',
                                enabled: _workoutDays > _min && _canEdit,
                                atLimit: _workoutDays <= _min,
                                accent: look.accent,
                                reduce: _reduce,
                                onTap: () => _setDays(_workoutDays - 1),
                              ),
                              _numberBox(look, appColors),
                              _PlanStepButton(
                                key: const ValueKey('weekly_plan_plus'),
                                icon: Icons.add_rounded,
                                semanticLabel: 'More workout days',
                                enabled: _workoutDays < _max && _canEdit,
                                atLimit: _workoutDays >= _max,
                                accent: look.accent,
                                reduce: _reduce,
                                onTap: () => _setDays(_workoutDays + 1),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 12),

                        // Progress track: four tappable segments
                        Row(
                          children: [
                            for (var n = _min; n <= _max; n++)
                              Expanded(child: _segment(n, appColors, cs)),
                          ],
                        ),
                        const SizedBox(height: 14),

                        // Break-day card
                        Transform.scale(
                          scale: chipPop,
                          child: Container(
                            padding: const EdgeInsets.all(14),
                            decoration: BoxDecoration(
                              color: look.accent.withValues(alpha: 0.08),
                              borderRadius: BorderRadius.circular(14),
                              border: Border.all(color: look.accent, width: 1.5),
                            ),
                            child: Row(
                              children: [
                                Container(
                                  width: 44,
                                  height: 44,
                                  decoration:
                                      BoxDecoration(color: look.accent, shape: BoxShape.circle),
                                  child: Icon(Icons.nightlight_round,
                                      size: 24, color: look.onAccent),
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        _breakLabel(breakDays),
                                        key: const ValueKey('weekly_plan_break_days'),
                                        style: TextStyle(
                                            fontSize: 18,
                                            fontWeight: FontWeight.w900,
                                            color: cs.onSurface),
                                      ),
                                      const SizedBox(height: 2),
                                      Text(
                                        _tier.note,
                                        style: TextStyle(
                                            fontSize: 13,
                                            height: 1.3,
                                            color: appColors.subtleText),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),

                        // Save failed: stays open, says why, offers another go
                        AnimatedSwitcher(
                          duration: const Duration(milliseconds: 260),
                          transitionBuilder: (child, anim) => SizeTransition(
                            sizeFactor: anim,
                            child: FadeTransition(opacity: anim, child: child),
                          ),
                          child: _save == _PlanSave.failed
                              ? Padding(
                                  key: const ValueKey('weekly_plan_error'),
                                  padding: const EdgeInsets.only(top: 12),
                                  child: Semantics(
                                    liveRegion: true,
                                    container: true,
                                    child: Text(
                                      "Couldn't save your plan. Check your connection and try again.",
                                      style: TextStyle(
                                        fontSize: 14,
                                        fontWeight: FontWeight.w700,
                                        height: 1.3,
                                        color: appColors.warn,
                                      ),
                                    ),
                                  ),
                                )
                              : const SizedBox.shrink(key: ValueKey('weekly_plan_no_error')),
                        ),
                        const SizedBox(height: 16),

                        _submitButton(look),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  bool get _canEdit => _save != _PlanSave.saving && _save != _PlanSave.saved;

  /// The big number in a fixed 140x120 box, so nothing around it jumps.
  Widget _numberBox(_Look look, AppColors appColors) {
    final popT = (_pop.value / (520 / 650)).clamp(0.0, 1.0);
    final settle = Curves.easeOut.transform((popT / 0.4).clamp(0.0, 1.0));
    final popping = !_reduce && _pop.value < 1;
    final blur = popping ? 6 * (1 - settle) : 0.0;

    Widget number = Text(
      '$_workoutDays',
      key: const ValueKey('weekly_plan_number'),
      style: TextStyle(
        fontSize: look.numberSize,
        fontWeight: FontWeight.w900,
        height: 1,
        color: look.numberColor,
        shadows: look.numberGlow < 0.5
            ? null
            : [Shadow(color: look.accent.withValues(alpha: 0.75), blurRadius: look.numberGlow)],
      ),
    );
    if (blur > 0.05) {
      number = ImageFiltered(
          imageFilter: ui.ImageFilter.blur(sigmaX: blur, sigmaY: blur), child: number);
    }
    if (popping) {
      number = Opacity(
        opacity: 0.25 + 0.75 * settle,
        child: Transform.translate(
          offset: Offset(0, _numDy.transform(popT)),
          child: Transform.scale(scale: _numScale.transform(popT), child: number),
        ),
      );
    }
    // Idle: tier 6 throbs, tier 7 jitters. Tiers 4 and 5 stand still.
    number = AnimatedBuilder(
      animation: _idle,
      builder: (context, child) {
        if (_reduce || _workoutDays < 6) return child!;
        if (_workoutDays == 6) {
          return Transform.scale(
              scale: 1 + 0.06 * Curves.easeInOut.transform(_idle.value), child: child);
        }
        final a = _idle.value * 2 * math.pi;
        return Transform(
          alignment: Alignment.center,
          transform: Matrix4.identity()
            ..translateByDouble(2 * math.sin(a), 2 * math.cos(2 * a), 0, 1)
            ..rotateZ((math.pi / 180) * math.sin(3 * a)),
          child: child,
        );
      },
      child: number,
    );

    return SizedBox(
      width: 140,
      height: 120,
      child: Semantics(
        liveRegion: true,
        label: '$_workoutDays workout days',
        excludeSemantics: true,
        child: Stack(
          alignment: Alignment.center,
          clipBehavior: Clip.none,
          children: [
            // Ring expanding behind the number
            if (popping)
              IgnorePointer(
                child: Opacity(
                  opacity: (1 - _pop.value).clamp(0.0, 1.0),
                  child: Transform.scale(
                    scale: 0.45 + 1.45 * Curves.easeOut.transform(_pop.value),
                    child: Container(
                      width: 100,
                      height: 100,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        border: Border.all(color: look.accent, width: 3),
                      ),
                    ),
                  ),
                ),
              ),
            Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Flexible(child: FittedBox(fit: BoxFit.scaleDown, child: number)),
                Text(
                  'workout days',
                  style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color: appColors.subtleText),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  /// One segment of the heat bar. It fills with its own tier colour once the
  /// current value reaches it; a tap jumps to its value.
  Widget _segment(int n, AppColors appColors, ColorScheme cs) {
    final filled = n <= _workoutDays;
    return Semantics(
      label: '$n workout days',
      button: true,
      selected: n == _workoutDays,
      excludeSemantics: true,
      child: GestureDetector(
        key: ValueKey('weekly_plan_segment_$n'),
        behavior: HitTestBehavior.opaque,
        onTap: () => _setDays(n),
        child: SizedBox(
          height: 56,
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              AnimatedContainer(
                duration: _reduce ? Duration.zero : const Duration(milliseconds: 300),
                height: 8,
                margin: const EdgeInsets.symmetric(horizontal: 3),
                decoration: BoxDecoration(
                  color: filled ? _tiers[n - _min].accent : appColors.divider,
                  borderRadius: BorderRadius.circular(4),
                ),
              ),
              const SizedBox(height: 6),
              Text(
                '$n',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w800,
                  color: n == _workoutDays ? cs.onSurface : appColors.subtleText,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _submitButton(_Look look) {
    final saving = _save == _PlanSave.saving;
    final saved = _save == _PlanSave.saved;
    final label = _save == _PlanSave.failed ? 'Try again' : 'Set my plan';

    Widget content;
    if (saving) {
      content = Row(
        mainAxisAlignment: MainAxisAlignment.center,
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            width: 20,
            height: 20,
            child: CircularProgressIndicator(strokeWidth: 2.5, color: look.onAccent),
          ),
          const SizedBox(width: 10),
          Text('Saving...', style: _buttonText(look)),
        ],
      );
    } else if (saved) {
      content = Icon(Icons.check_rounded, size: 30, color: look.onAccent);
    } else {
      content = Text(label, style: _buttonText(look));
    }

    return _Pressable(
      reduce: _reduce,
      onTap: _canEdit ? _submit : null,
      child: Semantics(
        button: true,
        enabled: _canEdit,
        label: saving ? 'Saving' : saved ? 'Saved' : label,
        excludeSemantics: true,
        child: Container(
          key: const ValueKey('weekly_plan_submit'),
          height: 56,
          decoration: BoxDecoration(
            color: look.accent,
            borderRadius: BorderRadius.circular(15),
            boxShadow: [
              BoxShadow(
                  color: look.accent.withValues(alpha: 0.35),
                  blurRadius: 18,
                  offset: const Offset(0, 6)),
            ],
          ),
          alignment: Alignment.center,
          child: content,
        ),
      ),
    );
  }

  TextStyle _buttonText(_Look look) => TextStyle(
        fontSize: 17,
        fontWeight: FontWeight.w900,
        letterSpacing: 0.2,
        color: look.onAccent,
      );
}

/// Scales to about 0.92 while pressed.
class _Pressable extends StatefulWidget {
  const _Pressable({required this.child, required this.onTap, required this.reduce});
  final Widget child;
  final VoidCallback? onTap;
  final bool reduce;

  @override
  State<_Pressable> createState() => _PressableState();
}

class _PressableState extends State<_Pressable> {
  bool _down = false;

  void _set(bool v) {
    if (mounted && _down != v) setState(() => _down = v);
  }

  @override
  Widget build(BuildContext context) {
    final enabled = widget.onTap != null;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTapDown: enabled ? (_) => _set(true) : null,
      onTapUp: enabled ? (_) => _set(false) : null,
      onTapCancel: enabled ? () => _set(false) : null,
      onTap: widget.onTap,
      child: AnimatedScale(
        scale: _down && !widget.reduce ? 0.92 : 1.0,
        duration: widget.reduce ? Duration.zero : const Duration(milliseconds: 90),
        child: widget.child,
      ),
    );
  }
}

// ── Stepper button: round, 56 dp, accent border, 0.35 opacity at a limit ──
class _PlanStepButton extends StatelessWidget {
  const _PlanStepButton({
    super.key,
    required this.icon,
    required this.semanticLabel,
    required this.enabled,
    required this.atLimit,
    required this.accent,
    required this.reduce,
    required this.onTap,
  });

  final IconData icon;
  final String semanticLabel;
  final bool enabled;
  final bool atLimit; // dimmed only at the limit, not while saving
  final Color accent;
  final bool reduce;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final appColors = AppColors.of(context);
    return _Pressable(
      reduce: reduce,
      onTap: enabled ? onTap : null,
      child: Semantics(
        button: true,
        enabled: enabled,
        label: semanticLabel,
        excludeSemantics: true,
        child: AnimatedOpacity(
          opacity: atLimit ? 0.35 : 1.0,
          duration: reduce ? Duration.zero : const Duration(milliseconds: 200),
          child: Container(
            width: 56,
            height: 56,
            decoration: BoxDecoration(
              color: appColors.sectionBackground,
              shape: BoxShape.circle,
              border: Border.all(color: accent, width: 1.5),
            ),
            child: Icon(icon, size: 28, color: accent),
          ),
        ),
      ),
    );
  }
}
