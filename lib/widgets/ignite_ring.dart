import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../theme/app_theme.dart';

/// Success mark: a thick ring sweeps closed, then a flame pops in and breathes
/// twice. Ring follows the accent skin (`avatarRing`); the flame stays the
/// fixed action orange (`streakOrange`, #EA580C on every palette).
/// Reduced motion → static lit ring + flame.
class IgniteRing extends StatefulWidget {
  final double size;

  /// Fires when the ring sweep closes (~70% of the main animation), not after
  /// the glow pulse, so callers can sequence against ring completion.
  final VoidCallback? onComplete;

  /// Wait before starting, so the sweep can line up with an external cue.
  final Duration delay;

  /// False → ring sweep + glow only, for halos around an existing icon.
  final bool showFlame;

  const IgniteRing({
    super.key,
    required this.size,
    this.onComplete,
    this.delay = Duration.zero,
    this.showFlame = true,
  });

  @override
  State<IgniteRing> createState() => _IgniteRingState();
}

class _IgniteRingState extends State<IgniteRing> with TickerProviderStateMixin {
  static const _ringEnd = 0.7;

  late final AnimationController _main = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 700),
  );
  // One forward pass = two breaths (see _breath).
  late final AnimationController _glow = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1500),
  );

  late final Animation<double> _ring = CurvedAnimation(
    parent: _main,
    curve: const Interval(0, _ringEnd, curve: Curves.easeOutCubic),
  );
  late final Animation<double> _flameScale = Tween(begin: 0.7, end: 1.0).animate(
    CurvedAnimation(parent: _main, curve: const Interval(_ringEnd, 1, curve: Curves.elasticOut)),
  );
  late final Animation<double> _flameOpacity = CurvedAnimation(
    parent: _main,
    curve: const Interval(_ringEnd, 0.85, curve: Curves.easeIn),
  );

  bool _started = false;
  bool _completed = false;

  @override
  void initState() {
    super.initState();
    _main.addListener(() {
      if (!_completed && _main.value >= _ringEnd) _fireComplete();
    });
    _main.addStatusListener((s) {
      if (s == AnimationStatus.completed) _glow.forward();
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_started) return;
    _started = true;
    if (MediaQuery.of(context).disableAnimations) {
      _main.value = 1;
      WidgetsBinding.instance.addPostFrameCallback((_) => _fireComplete());
      return;
    }
    Future.delayed(widget.delay, () {
      if (mounted) _main.forward();
    });
  }

  void _fireComplete() {
    if (_completed || !mounted) return;
    _completed = true;
    widget.onComplete?.call();
  }

  // 0 → 1 → 0 twice across the glow controller, ending at rest.
  double get _breath => 0.5 - 0.5 * math.cos(4 * math.pi * _glow.value);

  @override
  void dispose() {
    _main.dispose();
    _glow.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    return RepaintBoundary(
      child: AnimatedBuilder(
        animation: Listenable.merge([_main, _glow]),
        builder: (context, _) => CustomPaint(
          size: Size.square(widget.size),
          painter: _IgniteRingPainter(
            ringColor: c.avatarRing,
            flameColor: c.streakOrange,
            sweep: _ring.value,
            flameScale: _flameScale.value * (1 + 0.06 * _breath),
            flameOpacity: _flameOpacity.value,
            glow: _breath,
            showFlame: widget.showFlame,
          ),
        ),
      ),
    );
  }
}

class _IgniteRingPainter extends CustomPainter {
  final Color ringColor;
  final Color flameColor;
  final double sweep;
  final double flameScale;
  final double flameOpacity;
  final double glow;
  final bool showFlame;

  _IgniteRingPainter({
    required this.ringColor,
    required this.flameColor,
    required this.sweep,
    required this.flameScale,
    required this.flameOpacity,
    required this.glow,
    required this.showFlame,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final s = size.shortestSide;
    final center = size.center(Offset.zero);
    final stroke = s * 0.09;

    if (sweep > 0) {
      canvas.drawArc(
        Rect.fromCircle(center: center, radius: (s - stroke) / 2),
        -math.pi / 2,
        2 * math.pi * sweep,
        false,
        Paint()
          ..color = ringColor
          ..style = PaintingStyle.stroke
          ..strokeWidth = stroke
          ..strokeCap = StrokeCap.round,
      );
    }

    if (flameOpacity <= 0) return;

    // Rounded-teardrop flame: circular base, bezier sides meeting at a tip.
    final h = s * 0.46 * flameScale;
    final r = h * 0.36;
    final top = center.dy - h / 2;
    final baseY = center.dy + h / 2 - r;
    if (glow > 0) {
      canvas.drawCircle(
        Offset(center.dx, baseY - r * 0.2),
        r * 1.6,
        Paint()
          ..color = flameColor.withValues(alpha: 0.35 * glow * flameOpacity)
          ..maskFilter = MaskFilter.blur(BlurStyle.normal, r * 0.8),
      );
    }
    if (!showFlame) return;

    final flame = Path()
      ..moveTo(center.dx, top)
      ..cubicTo(center.dx + r * 0.3, top + h * 0.25, center.dx + r, baseY - r * 0.6,
          center.dx + r, baseY)
      ..arcToPoint(Offset(center.dx - r, baseY), radius: Radius.circular(r))
      ..cubicTo(center.dx - r, baseY - r * 0.6, center.dx - r * 0.3, top + h * 0.25,
          center.dx, top)
      ..close();
    canvas.drawPath(flame, Paint()..color = flameColor.withValues(alpha: flameOpacity));
  }

  @override
  bool shouldRepaint(_IgniteRingPainter old) =>
      old.sweep != sweep ||
      old.flameScale != flameScale ||
      old.flameOpacity != flameOpacity ||
      old.glow != glow ||
      old.showFlame != showFlame ||
      old.ringColor != ringColor ||
      old.flameColor != flameColor;
}
