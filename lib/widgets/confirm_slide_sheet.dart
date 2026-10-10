import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../services/handshake_service.dart';
import '../theme/app_theme.dart';
import 'workout_schedule_card.dart';

/// The words on the sheet for one destructive action.
typedef ConfirmCopy = ({String label, String title, String line, String slide});

/// [workout] is "Strength with Sam" (or just "Strength" with nobody else on it).
ConfirmCopy confirmCopyFor(CardAction a, {required String workout, String? other}) {
  final n = other ?? 'your buddy';
  switch (a) {
    case CardAction.leave:
      return (label: 'Leave workout', title: 'Leave $workout?', slide: 'Slide to leave',
          line: 'Your timer stops and this workout does not count for you. $n keeps going.');
    case CardAction.abandon:
      return (label: 'Abandon workout', title: 'Abandon this workout?', slide: 'Slide to leave',
          line: 'Your timer stops and this workout does not count.');
    case CardAction.cancel:
      return (label: 'Cancel workout', title: 'Cancel $workout?', slide: 'Slide to cancel',
          line: other == null ? 'Cancels this workout.' : 'Cancels it for you and $n. $n gets a notification.');
    default:
      return (label: "Can't make it", title: "Can't make it?", slide: 'Slide to confirm',
          line: 'Frees $n up. $n can still work out solo. No penalty.');
  }
}

/// Opens the sheet. [run] does the action and throws if the server refuses.
/// Returns true once it ran; false if the person kept the workout.
Future<bool> showConfirmSlideSheet(
  BuildContext context, {
  required CardAction action,
  required String workout,
  required Person me,
  Person? buddy,
  double? progress,
  required Future<void> Function() run,
}) async {
  final c = AppColors.of(context);
  final ok = await showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    showDragHandle: true,
    backgroundColor: c.cardBackground,
    shape: RoundedRectangleBorder(
      borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
      side: BorderSide(color: c.cardBorder),
    ),
    builder: (_) => ConfirmSlideSheet(
        action: action, workout: workout, me: me, buddy: buddy, progress: progress, run: run),
  );
  return ok == true;
}

class ConfirmSlideSheet extends StatefulWidget {
  final CardAction action;
  final String workout;
  final Person me;
  final Person? buddy;

  /// Real ring progress for Leave and Abandon; null draws an illustrative arc.
  final double? progress;
  final Future<void> Function() run;
  const ConfirmSlideSheet({
    super.key, required this.action, required this.workout, required this.me,
    this.buddy, this.progress, required this.run});

  @override
  State<ConfirmSlideSheet> createState() => _ConfirmSlideSheetState();
}

class _ConfirmSlideSheetState extends State<ConfirmSlideSheet> {
  bool _busy = false;
  int _failures = 0; // each one resets the slider
  String? _error;

  Future<void> _confirm() async {
    if (_busy) return;
    HapticFeedback.mediumImpact();
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await widget.run();
      if (mounted) Navigator.of(context).pop(true);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _failures++;
        _error = HandshakeError.from(e).message(name: widget.buddy?.name);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    final text = Theme.of(context).textTheme;
    final copy = confirmCopyFor(widget.action, workout: widget.workout, other: widget.buddy?.name);
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
      child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Text(copy.label.toUpperCase(), textAlign: TextAlign.center,
            style: text.labelMedium?.copyWith(color: c.subtleText, letterSpacing: 1.2)),
        const SizedBox(height: 6),
        Text(copy.title, textAlign: TextAlign.center,
            style: text.titleLarge?.copyWith(fontWeight: FontWeight.bold)),
        const SizedBox(height: 16),
        Center(child: FittedBox(fit: BoxFit.scaleDown, child: _NowAfter(
            action: widget.action, me: widget.me, buddy: widget.buddy, progress: widget.progress ?? 0.6))),
        const SizedBox(height: 16),
        Text(copy.line, textAlign: TextAlign.center, style: text.bodyMedium),
        const SizedBox(height: 20),
        Semantics(
          hint: 'Closes this without changes',
          child: FilledButton(
            style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(54)),
            onPressed: _busy ? null : () => Navigator.of(context).pop(false),
            child: const Text('Keep workout'),
          ),
        ),
        const SizedBox(height: 12),
        if (_error != null) ...[
          Semantics(
            liveRegion: true,
            child: Text(_error!, textAlign: TextAlign.center, style: TextStyle(color: c.danger)),
          ),
          const SizedBox(height: 8),
        ],
        _SlideToConfirm(label: copy.slide, me: widget.me, busy: _busy, failures: _failures, onConfirm: _confirm),
        if (MediaQuery.accessibleNavigationOf(context)) ...[
          const SizedBox(height: 8),
          Text('Using TalkBack? Double tap the slider to confirm.',
              textAlign: TextAlign.center, style: text.bodySmall?.copyWith(color: c.subtleText)),
        ],
      ]),
    );
  }
}

// ── slider ────────────────────────────────────────────────────────────────

const _trackH = 64.0, _thumb = 56.0, _pad = 4.0, _passAt = 0.85;

class _SlideToConfirm extends StatefulWidget {
  final String label;
  final Person me;
  final bool busy;
  final int failures;
  final VoidCallback onConfirm;
  const _SlideToConfirm({
    required this.label, required this.me, required this.busy, required this.failures, required this.onConfirm});

  @override
  State<_SlideToConfirm> createState() => _SlideToConfirmState();
}

class _SlideToConfirmState extends State<_SlideToConfirm> with SingleTickerProviderStateMixin {
  late final AnimationController _v = AnimationController(vsync: this); // 0..1 of the travel
  bool _fired = false;
  bool _live = false; // a drag that has not fired yet

  @override
  void didUpdateWidget(_SlideToConfirm old) {
    super.didUpdateWidget(old);
    if (old.failures != widget.failures) {
      _fired = false;
      _springBack();
    }
  }

  @override
  void dispose() {
    _v.dispose();
    super.dispose();
  }

  void _springBack() => _v.animateTo(0, duration: const Duration(milliseconds: 200), curve: Curves.easeOut);

  void _fire() {
    if (_fired) return;
    _fired = true;
    _live = false;
    widget.onConfirm();
  }

  void _drag(double dx, double travel) {
    if (!_live || _fired || widget.busy) return;
    _v.stop();
    _v.value = (_v.value + dx / travel).clamp(0.0, 1.0);
    if (_v.value >= 1) _fire();
  }

  void _release() {
    if (!_live || _fired || widget.busy) return;
    _live = false;
    _v.value >= _passAt ? _fire() : _springBack();
  }

  /// Screen readers: double tap confirms, thumb jumps to the end.
  void _tapConfirm() {
    if (_fired || widget.busy) return;
    _v.value = 1;
    _fire();
  }

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    final scheme = Theme.of(context).colorScheme;
    return Semantics(
      button: true,
      enabled: !widget.busy,
      label: '${widget.label}. Double tap to confirm',
      onTap: _tapConfirm,
      excludeSemantics: true,
      child: SizedBox(
        height: _trackH,
        child: LayoutBuilder(builder: (_, box) {
          final travel = math.max(1.0, box.maxWidth - _thumb - 2 * _pad);
          return GestureDetector(
            behavior: HitTestBehavior.opaque,
            onHorizontalDragStart: (_) => _live = !_fired && !widget.busy,
            onHorizontalDragUpdate: (d) => _drag(d.delta.dx, travel),
            onHorizontalDragEnd: (_) => _release(),
            onHorizontalDragCancel: _release,
            child: AnimatedBuilder(
              animation: _v,
              builder: (_, __) {
                final x = _pad + travel * _v.value;
                return Stack(children: [
                  Positioned.fill(
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(_trackH / 2),
                        border: Border.all(color: c.danger, width: 2)),
                    ),
                  ),
                  // red fill: from the left edge to inside the thumb, nothing showing at rest
                  Positioned(
                    left: 0, top: 0, bottom: 0, width: x + _thumb * _v.value,
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        color: c.danger, borderRadius: BorderRadius.circular(_trackH / 2)),
                    ),
                  ),
                  Positioned.fill(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: _thumb + 2 * _pad),
                      child: Center(
                        child: Opacity(
                          opacity: widget.busy ? 1 : (1 - _v.value * 2.5).clamp(0.0, 1.0),
                          child: FittedBox(
                            fit: BoxFit.scaleDown,
                            child: Text(widget.busy ? 'Done' : widget.label,
                                style: TextStyle(
                                    fontWeight: FontWeight.bold,
                                    color: widget.busy ? scheme.onError : scheme.onSurface)),
                          ),
                        ),
                      ),
                    ),
                  ),
                  Positioned(
                    left: x, top: _pad,
                    child: RingAvatar(person: widget.me, size: _thumb),
                  ),
                ]);
              },
            ),
          );
        }),
      ),
    );
  }
}

// ── Now -> After ──────────────────────────────────────────────────────────

class _NowAfter extends StatelessWidget {
  final CardAction action;
  final Person me;
  final Person? buddy;
  final double progress;
  const _NowAfter({required this.action, required this.me, required this.buddy, required this.progress});

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    final lavender = c.secondaryAccent;
    final them = buddy == null ? null : Person(name: buddy!.name, avatarId: buddy!.avatarId, ring: buddy!.ring ?? lavender);
    final running = action == CardAction.leave || action == CardAction.abandon;
    final solo = them == null;
    // Where avatars sit, from the card's own avatarSpots.
    final spots = avatarSpots(running ? 'running' : 'time_to_start', solo: solo);
    final reduce = MediaQuery.disableAnimationsOf(context);

    Widget column(String caption, Widget ring) => Column(mainAxisSize: MainAxisSize.min, children: [
          Text(caption, style: TextStyle(fontSize: 12, color: c.subtleText)),
          const SizedBox(height: 6),
          SizedBox.square(dimension: 150, child: FittedBox(child: SizedBox.square(dimension: 220, child: ring))),
        ]);

    return ExcludeSemantics(
      child: Row(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.end, children: [
        column('Now', _MiniRing(action: action, me: me, them: them, spots: spots, p: 0, running: running, progress: progress)),
        Padding(
          padding: const EdgeInsets.only(bottom: 62),
          child: Icon(Icons.arrow_forward, color: c.subtleText),
        ),
        reduce
            ? column('After', _MiniRing(action: action, me: me, them: them, spots: spots, p: 1, running: running, progress: progress))
            : _LoopingAfter(builder: (p) => column('After',
                _MiniRing(action: action, me: me, them: them, spots: spots, p: p, running: running, progress: progress))),
      ]),
    );
  }
}

/// 6 s loop: rest, avatar leaves, rest, reset. Only this widget ticks.
class _LoopingAfter extends StatefulWidget {
  final Widget Function(double p) builder;
  const _LoopingAfter({required this.builder});

  @override
  State<_LoopingAfter> createState() => _LoopingAfterState();
}

class _LoopingAfterState extends State<_LoopingAfter> with SingleTickerProviderStateMixin {
  late final AnimationController _ctl =
      AnimationController(vsync: this, duration: const Duration(seconds: 6))..repeat();

  @override
  void dispose() {
    _ctl.dispose();
    super.dispose();
  }

  /// 0 = Now state, 1 = After state.
  static double _phase(double t) {
    if (t < 0.25) return 0;
    if (t < 0.42) return Curves.easeInOut.transform((t - 0.25) / 0.17);
    if (t < 0.92) return 1;
    return 1 - (t - 0.92) / 0.08;
  }

  @override
  Widget build(BuildContext context) =>
      AnimatedBuilder(animation: _ctl, builder: (_, __) => widget.builder(_phase(_ctl.value)));
}

/// One 220 dp ring (the card's own look), drawn at [p] between Now (0) and After (1).
class _MiniRing extends StatelessWidget {
  final CardAction action;
  final Person me;
  final Person? them;
  final AvatarSpots spots;
  final double p;
  final bool running;
  final double progress;
  const _MiniRing({
    required this.action, required this.me, required this.them, required this.spots,
    required this.p, required this.running, required this.progress});

  Widget _at(double deg, Widget child, {double out = 0}) {
    final a = deg * math.pi / 180;
    return Transform.translate(
        offset: Offset(math.sin(a) * (98 + out), -math.cos(a) * (98 + out)), child: child);
  }

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    final scheme = Theme.of(context).colorScheme;
    final cancel = action == CardAction.cancel;
    final leave = action == CardAction.leave;
    final cant = action == CardAction.cantMakeIt;
    final dimRing = action == CardAction.abandon || cancel;
    final waiting = !running;
    return Stack(alignment: Alignment.center, children: [
      Opacity(
        opacity: dimRing ? 1 - 0.65 * p : 1,
        child: CustomPaint(
          size: const Size.square(220),
          painter: RingPainter(
              progress: running ? progress : 0, dashed: waiting, track: c.divider, fill: scheme.primary),
        ),
      ),
      if (them != null)
        _at(spots.them!, Opacity(
            opacity: cancel ? 1 - p : 1,
            child: RingAvatar(person: them!, size: 44, dashed: !spots.themIn))),
      if (leave || cant) // the dashed ghost where I was
        _at(spots.me, Opacity(opacity: 0.5 * p, child: RingAvatar(person: me, size: 44, dashed: true))),
      _at(spots.me, Opacity(
          opacity: 1 - p,
          child: RingAvatar(person: me, size: 44, dashed: !spots.meIn)), out: 34 * p),
    ]);
  }
}
