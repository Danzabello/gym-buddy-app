import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

/// Streak count badge: a flame over the day count, tinted by tier.
///
/// Tiers (colours come from [AppColors] so they follow the accent skin):
///   0-6 days   Spark    streakOrange
///   7-29       Ember    warn (gold)
///   30-99      Blaze    success
///   100+       Inferno  info
///
/// Motion (all one-shot, nothing loops, so it costs nothing at rest):
///  * the number slides up when [streak] changes
///  * a pop on a normal check-in, a big pop + burst rings + confetti when
///    [celebrate] is true (milestone days)
///  * [broken] greys the badge, cracks it, shakes it once and tilts it
///  * [showBuddyDot] adds a small dot: grey "..." while the buddy is still to
///    check in, green tick once they have (the flame also dims while waiting)
///
/// To animate on first show (e.g. in a dialog) pass [tickFrom] (the previous
/// count) and/or [celebrate]; [startDelay] lets a dialog finish opening first.
///
/// Reduced motion: no animation, just the final state.
class StreakBadge extends StatefulWidget {
  final int streak;
  final double size;
  final int? tickFrom;
  final bool celebrate;
  final bool broken;
  final bool showBuddyDot;
  final bool buddyCheckedIn;
  final Duration startDelay;

  const StreakBadge({
    super.key,
    required this.streak,
    this.size = 56,
    this.tickFrom,
    this.celebrate = false,
    this.broken = false,
    this.showBuddyDot = false,
    this.buddyCheckedIn = false,
    this.startDelay = Duration.zero,
  });

  static const tierNames = ['Spark', 'Ember', 'Blaze', 'Inferno'];

  static int tierOf(int streak) =>
      streak >= 100 ? 3 : (streak >= 30 ? 2 : (streak >= 7 ? 1 : 0));

  @override
  State<StreakBadge> createState() => _StreakBadgeState();
}

enum _Fx { none, pop, big, shake }

class _StreakBadgeState extends State<StreakBadge>
    with SingleTickerProviderStateMixin {
  static const _brokenTilt = 0.17; // ~10 degrees
  static const _brokenDrop = 0.09; // of size

  static final _popScale = TweenSequence<double>([
    TweenSequenceItem(
        tween: Tween(begin: 1.0, end: 1.28)
            .chain(CurveTween(curve: Curves.easeOut)),
        weight: 30),
    TweenSequenceItem(tween: Tween(begin: 1.28, end: 0.96), weight: 30),
    TweenSequenceItem(tween: Tween(begin: 0.96, end: 1.0), weight: 40),
  ]);
  static final _bigScale = TweenSequence<double>([
    TweenSequenceItem(
        tween: Tween(begin: 1.0, end: 1.6)
            .chain(CurveTween(curve: Curves.easeOut)),
        weight: 22),
    TweenSequenceItem(tween: Tween(begin: 1.6, end: 1.1), weight: 20),
    TweenSequenceItem(tween: Tween(begin: 1.1, end: 1.28), weight: 24),
    TweenSequenceItem(tween: Tween(begin: 1.28, end: 1.0), weight: 34),
  ]);
  static final _shakeRot = TweenSequence<double>([
    TweenSequenceItem(tween: Tween(begin: 0.0, end: -0.14), weight: 15),
    TweenSequenceItem(tween: Tween(begin: -0.14, end: 0.14), weight: 15),
    TweenSequenceItem(tween: Tween(begin: 0.14, end: -0.10), weight: 15),
    TweenSequenceItem(tween: Tween(begin: -0.10, end: 0.09), weight: 15),
    TweenSequenceItem(tween: Tween(begin: 0.09, end: _brokenTilt), weight: 40),
  ]);
  static final _shakeDx = TweenSequence<double>([
    TweenSequenceItem(tween: Tween(begin: 0.0, end: -0.09), weight: 15),
    TweenSequenceItem(tween: Tween(begin: -0.09, end: 0.09), weight: 15),
    TweenSequenceItem(tween: Tween(begin: 0.09, end: -0.07), weight: 15),
    TweenSequenceItem(tween: Tween(begin: -0.07, end: 0.05), weight: 15),
    TweenSequenceItem(tween: Tween(begin: 0.05, end: 0.0), weight: 40),
  ]);
  static final _shakeDy = TweenSequence<double>([
    TweenSequenceItem(tween: ConstantTween(0.0), weight: 60),
    TweenSequenceItem(tween: Tween(begin: 0.0, end: _brokenDrop), weight: 40),
  ]);

  late final AnimationController _c = AnimationController(vsync: this)
    ..addStatusListener((s) {
      if (s == AnimationStatus.completed && mounted) {
        setState(() => _fx = _Fx.none);
      }
    });

  late int _shown;
  _Fx _fx = _Fx.none;
  bool _reduce = false;
  Timer? _startTimer;

  @override
  void initState() {
    super.initState();
    _shown = widget.tickFrom ?? widget.streak;
    if (widget.tickFrom != null || widget.celebrate) {
      _startTimer = Timer(widget.startDelay, () {
        if (!mounted) return;
        setState(() => _shown = widget.streak);
        _play(widget.celebrate ? _Fx.big : _Fx.pop);
      });
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _reduce = MediaQuery.of(context).disableAnimations;
  }

  @override
  void didUpdateWidget(StreakBadge old) {
    super.didUpdateWidget(old);
    if (widget.streak != old.streak) {
      _shown = widget.streak;
      if (widget.streak > old.streak) {
        _play(widget.celebrate ? _Fx.big : _Fx.pop);
      }
    }
    if (widget.broken && !old.broken) _play(_Fx.shake);
  }

  @override
  void dispose() {
    _startTimer?.cancel();
    _c.dispose();
    super.dispose();
  }

  void _play(_Fx fx) {
    if (_reduce) return;
    _fx = fx;
    _c.duration = switch (fx) {
      _Fx.big => const Duration(milliseconds: 1400),
      _Fx.shake => const Duration(milliseconds: 900),
      _ => const Duration(milliseconds: 700),
    };
    _c.forward(from: 0);
  }

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    final s = widget.size;
    final tier = StreakBadge.tierOf(widget.streak);

    final Color base = widget.broken
        ? c.subtleText
        : switch (tier) {
            0 => c.streakOrange,
            1 => c.warn,
            2 => c.success,
            _ => c.info,
          };
    final top = Color.lerp(base, Colors.white, 0.22)!;
    final bottom = Color.lerp(base, Colors.black, 0.22)!;
    final onBadge =
        ThemeData.estimateBrightnessForColor(base) == Brightness.light
            ? Colors.black87
            : Colors.white;
    final glow = widget.broken ? 0.0 : const [0.0, 5.0, 7.0, 9.0][tier];
    final flameAlpha = widget.broken
        ? 0.35
        : (widget.showBuddyDot && !widget.buddyCheckedIn ? 0.5 : 0.95);
    final digits = '$_shown'.length;
    final numberSize = s * (digits <= 2 ? 0.38 : (digits == 3 ? 0.30 : 0.24));

    final face = Container(
      width: s,
      height: s,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [top, bottom],
        ),
        border: Border.all(color: Colors.white, width: s * 0.07),
        boxShadow: glow == 0
            ? null
            : [
                BoxShadow(
                  color: base.withValues(alpha: 0.7),
                  blurRadius: glow * (s / 56) * 1.6,
                ),
              ],
      ),
      child: Stack(
        alignment: Alignment.center,
        clipBehavior: Clip.none,
        children: [
          Positioned(
            top: s * 0.10,
            child: CustomPaint(
              size: Size(s * 0.28, s * 0.35),
              painter: _FlamePainter(onBadge.withValues(alpha: flameAlpha)),
            ),
          ),
          Align(
            alignment: const Alignment(0, 0.42),
            child: AnimatedSwitcher(
              duration:
                  _reduce ? Duration.zero : const Duration(milliseconds: 320),
              transitionBuilder: (child, anim) {
                final incoming = child.key == ValueKey<int>(_shown);
                final slide = Tween<Offset>(
                  begin: Offset(0, incoming ? 0.6 : -0.6),
                  end: Offset.zero,
                ).animate(anim);
                return SlideTransition(
                  position: slide,
                  child: FadeTransition(opacity: anim, child: child),
                );
              },
              child: Text(
                '$_shown',
                key: ValueKey<int>(_shown),
                style: TextStyle(
                  fontSize: numberSize,
                  fontWeight: FontWeight.w800,
                  height: 1,
                  color: onBadge,
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
            ),
          ),
          if (widget.broken)
            Positioned.fill(child: CustomPaint(painter: _CrackPainter())),
          if (widget.showBuddyDot)
            Positioned(
              left: -s * 0.06,
              bottom: -s * 0.06,
              child: _BuddyDot(
                size: s * 0.36,
                isIn: widget.buddyCheckedIn,
                instant: _reduce,
                inColor: c.successGreen,
                waitColor: c.subtleText,
              ),
            ),
        ],
      ),
    );

    return Semantics(
      label: widget.broken ? 'Streak ended' : '${widget.streak} day streak',
      child: ExcludeSemantics(
        child: SizedBox(
          width: s,
          height: s,
          child: AnimatedBuilder(
            animation: _c,
            builder: (context, _) {
              final t = _c.value;
              var scale = 1.0;
              var rot = widget.broken ? _brokenTilt : 0.0;
              var dx = 0.0;
              var dy = widget.broken ? s * _brokenDrop : 0.0;
              switch (_fx) {
                case _Fx.pop:
                  scale = _popScale.transform(t);
                case _Fx.big:
                  scale = _bigScale.transform(t);
                case _Fx.shake:
                  rot = _shakeRot.transform(t);
                  dx = _shakeDx.transform(t) * s;
                  dy = _shakeDy.transform(t) * s;
                case _Fx.none:
                  break;
              }
              return Stack(
                alignment: Alignment.center,
                clipBehavior: Clip.none,
                children: [
                  if (_fx == _Fx.big)
                    Positioned.fill(
                      child: IgnorePointer(
                        child: CustomPaint(
                          painter: _BurstPainter(t, base, [
                            c.streakOrange,
                            c.warn,
                            c.success,
                            c.info,
                            c.danger,
                          ]),
                        ),
                      ),
                    ),
                  Transform.translate(
                    offset: Offset(dx, dy),
                    child: Transform.rotate(
                      angle: rot,
                      child: Transform.scale(scale: scale, child: face),
                    ),
                  ),
                ],
              );
            },
          ),
        ),
      ),
    );
  }
}

class _BuddyDot extends StatelessWidget {
  const _BuddyDot({
    required this.size,
    required this.isIn,
    required this.instant,
    required this.inColor,
    required this.waitColor,
  });

  final double size;
  final bool isIn;
  final bool instant;
  final Color inColor;
  final Color waitColor;

  @override
  Widget build(BuildContext context) {
    final dot = size * 0.1;
    return AnimatedSwitcher(
      duration: instant ? Duration.zero : const Duration(milliseconds: 350),
      transitionBuilder: (child, anim) => ScaleTransition(
        scale: CurvedAnimation(parent: anim, curve: Curves.elasticOut),
        child: child,
      ),
      child: Container(
        key: ValueKey<bool>(isIn),
        width: size,
        height: size,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: isIn ? inColor : waitColor,
          border: Border.all(color: Colors.white, width: size * 0.15),
        ),
        child: Center(
          child: isIn
              ? Icon(Icons.check_rounded, size: size * 0.6, color: Colors.white)
              : Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    for (var i = 0; i < 3; i++)
                      Container(
                        width: dot,
                        height: dot,
                        margin: EdgeInsets.symmetric(horizontal: dot * 0.35),
                        decoration: const BoxDecoration(
                          shape: BoxShape.circle,
                          color: Colors.white,
                        ),
                      ),
                  ],
                ),
        ),
      ),
    );
  }
}

/// The flame glyph, drawn in a 30x38 box and scaled to fit.
class _FlamePainter extends CustomPainter {
  _FlamePainter(this.color);
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.scale(size.width / 30, size.height / 38);
    final path = Path()
      ..moveTo(15, 0)
      ..cubicTo(22, 10, 30, 15, 30, 26)
      ..cubicTo(30, 33, 24, 38, 15, 38)
      ..cubicTo(6, 38, 0, 33, 0, 26)
      ..cubicTo(0, 15, 8, 10, 15, 0)
      ..close();
    canvas.drawPath(path, Paint()..color = color);
  }

  @override
  bool shouldRepaint(_FlamePainter old) => old.color != color;
}

/// A jagged crack down the right side of the badge (kept clear of the number).
class _CrackPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final k = size.width / 56;
    final path = Path()
      ..moveTo(43 * k, 3 * k)
      ..lineTo(38 * k, 14 * k)
      ..lineTo(46 * k, 22 * k)
      ..lineTo(39 * k, 31 * k)
      ..lineTo(43 * k, 43 * k);
    canvas.drawPath(
      path,
      Paint()
        ..color = Colors.black54
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.2 * k
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round,
    );
  }

  @override
  bool shouldRepaint(_CrackPainter old) => false;
}

/// Two expanding rings plus eight pieces of confetti, for milestone days.
class _BurstPainter extends CustomPainter {
  _BurstPainter(this.t, this.color, this.confetti);

  final double t;
  final Color color;
  final List<Color> confetti;

  @override
  void paint(Canvas canvas, Size size) {
    final center = size.center(Offset.zero);
    final r = size.width / 2;

    for (final delay in const [0.0, 0.16]) {
      final p = ((t - delay) / (1 - delay)).clamp(0.0, 1.0).toDouble();
      if (p <= 0 || p >= 1) continue;
      final radius = r * (1 + 2.4 * Curves.easeOut.transform(p));
      canvas.drawCircle(
        center,
        radius,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = delay == 0 ? r * 0.14 : r * 0.10
          ..color = color.withValues(alpha: (1 - p) * 0.85),
      );
    }

    const n = 8;
    for (var i = 0; i < n; i++) {
      final p = ((t - (i % 4) * 0.04) / 0.88).clamp(0.0, 1.0).toDouble();
      if (p <= 0 || p >= 1) continue;
      final angle = i * (2 * math.pi / n) + 0.4;
      final dist = r * (1.6 + (i % 3) * 0.9) * Curves.easeOut.transform(p);
      final alpha = (p < 0.15 ? p / 0.15 : 1 - (p - 0.15) / 0.85)
          .clamp(0.0, 1.0)
          .toDouble();
      final paint = Paint()
        ..color = confetti[i % confetti.length].withValues(alpha: alpha);
      final pos = center + Offset(math.cos(angle), math.sin(angle)) * dist;
      if (i.isEven) {
        canvas.drawCircle(pos, r * 0.14, paint);
      } else {
        canvas.drawRRect(
          RRect.fromRectAndRadius(
            Rect.fromCenter(center: pos, width: r * 0.28, height: r * 0.28),
            Radius.circular(r * 0.05),
          ),
          paint,
        );
      }
    }
  }

  @override
  bool shouldRepaint(_BurstPainter old) => old.t != t || old.color != color;
}
