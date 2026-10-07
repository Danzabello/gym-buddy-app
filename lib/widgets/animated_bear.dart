import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

/// Which face the bear is pulling.
enum BearMood {
  /// Breathing, blinking, glancing about, the odd ear twitch.
  idle,

  /// Hopping with closed happy eyes, open mouth, flapping ears.
  happy,

  /// Head tilted, soft worried brows. For a broken streak: sympathetic, not sad.
  worried,
}

/// The animated Bear avatar, drawn in code (no assets, no extra dependency).
///
/// Ported from the approved HTML prototype. Everything is drawn on a 240x240
/// canvas and scaled to [size], so it stays crisp at any size.
///
/// Motion is cheap (one painter, one ticker) but it does loop forever, so use
/// it where one or two avatars are on screen (profile hero, dialogs) — keep
/// static avatars in lists.
///
/// Reduced motion: no ticker runs; shows the static pose for [mood].
///
/// COLOURS: the fur/muzzle/eye colours below are illustration colours, like the
/// pixels of an image, so they are raw hex in this file only. They do not
/// follow the accent skin. This needs your sign-off against the "no raw hex"
/// rule, or the bear should move to an asset (Rive/SVG) later.
class AnimatedBear extends StatefulWidget {
  final double size;
  final BearMood mood;

  const AnimatedBear({
    super.key,
    this.size = 80,
    this.mood = BearMood.idle,
  });

  @override
  State<AnimatedBear> createState() => _AnimatedBearState();
}

class _AnimatedBearState extends State<AnimatedBear>
    with SingleTickerProviderStateMixin {
  // One long looping ticker; every motion is derived from elapsed seconds.
  static const _periodSeconds = 3600;
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(seconds: _periodSeconds),
  );
  bool _reduce = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _reduce = MediaQuery.of(context).disableAnimations;
    if (_reduce) {
      _c.stop();
    } else if (!_c.isAnimating) {
      _c.repeat();
    }
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: 'Bear avatar',
      child: ExcludeSemantics(
        child: SizedBox.square(
          dimension: widget.size,
          child: RepaintBoundary(
            child: AnimatedBuilder(
              animation: _c,
              builder: (context, _) => CustomPaint(
                painter: _BearPainter(
                  t: _reduce ? 0 : _c.value * _periodSeconds,
                  mood: widget.mood,
                ),
                size: Size.square(widget.size),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Illustration palette (see the note on [AnimatedBear]).
class _Ink {
  static const furLight = Color(0xFFC48D50);
  static const fur = Color(0xFFA9733A);
  static const outline = Color(0xFF8B5E10);
  static const innerEar = Color(0xFFE9B58A);
  static const muzzle = Color(0xFFF1D9B5);
  static const muzzleEdge = Color(0xFFD2B084);
  static const dark = Color(0xFF2A1A12);
  static const cheek = Color(0xFFF28B82);
  static const mouthInside = Color(0xFF7A2A2A);
  static const tongue = Color(0xFFE8727A);
}

class _BearPainter extends CustomPainter {
  _BearPainter({required this.t, required this.mood});

  final double t; // seconds
  final BearMood mood;

  static const _deg = math.pi / 180;

  /// Piecewise-linear keyframes: [[progress, value], ...] with progress 0..1.
  static double _kf(double p, List<List<double>> s) {
    if (p <= s.first[0]) return s.first[1];
    for (var i = 1; i < s.length; i++) {
      if (p <= s[i][0]) {
        final a = s[i - 1];
        final b = s[i];
        final u = (p - a[0]) / (b[0] - a[0]);
        return a[1] + (b[1] - a[1]) * u;
      }
    }
    return s.last[1];
  }

  /// 0 → 1 → 0 smoothly, once per [period] seconds.
  double _wave(double period) =>
      0.5 - 0.5 * math.cos(2 * math.pi * ((t % period) / period));

  static Paint _fill(Color c) => Paint()..color = c;

  static Paint _stroke(Color c, double w) => Paint()
    ..color = c
    ..style = PaintingStyle.stroke
    ..strokeWidth = w
    ..strokeCap = StrokeCap.round
    ..strokeJoin = StrokeJoin.round;

  static Paint _furPaint(Offset center, double radius) => Paint()
    ..shader = ui.Gradient.radial(
      center,
      radius,
      const [_Ink.furLight, _Ink.fur],
    );

  @override
  void paint(Canvas canvas, Size size) {
    canvas.save();
    canvas.scale(size.width / 240, size.height / 240);

    var dx = 0.0, dy = 0.0, sx = 1.0, sy = 1.0, rot = 0.0;
    var origin = const Offset(120, 190);
    switch (mood) {
      case BearMood.idle:
        final breathe = _wave(3.6);
        dy = -2 * breathe;
        sx = 1 + 0.012 * breathe;
        sy = 1 + 0.018 * breathe;
      case BearMood.happy:
        final p = (t % 0.9) / 0.9;
        origin = const Offset(120, 204);
        dy = _kf(p, const [[0, 0], [0.3, -14], [0.6, 0], [1, 0]]);
        sx = _kf(p, const [[0, 1.04], [0.3, 0.96], [0.6, 1.05], [1, 1]]);
        sy = _kf(p, const [[0, 0.94], [0.3, 1.05], [0.6, 0.94], [1, 1]]);
        rot = _kf(p, const [[0, 0], [0.3, -3], [0.6, 3], [1, 0]]) * _deg;
      case BearMood.worried:
        final sway = _wave(4);
        dx = -3;
        dy = -sway;
        rot = (-7 + 2 * sway) * _deg;
    }

    canvas.translate(origin.dx + dx, origin.dy + dy);
    canvas.rotate(rot);
    canvas.scale(sx, sy);
    canvas.translate(-origin.dx, -origin.dy);
    _drawBear(canvas);

    canvas.restore();
  }

  void _drawBear(Canvas canvas) {
    final happy = mood == BearMood.happy;

    // ---- ears ----
    double leftEar = 0, rightEar = 0;
    if (happy) {
      final k = _wave(0.45);
      leftEar = -12 * k;
      rightEar = 12 * k;
    } else if (mood == BearMood.idle) {
      leftEar = _kf((t % 6) / 6,
          const [[0, 0], [0.86, 0], [0.90, -9], [0.94, 3], [1, 0]]);
      rightEar = _kf(((t - 2.4) % 6 + 6) % 6 / 6,
          const [[0, 0], [0.86, 0], [0.90, 9], [0.94, -3], [1, 0]]);
    }
    _ear(canvas, const Offset(64, 64), const Offset(66, 66),
        const Offset(79.6, 82.2), leftEar);
    _ear(canvas, const Offset(176, 64), const Offset(174, 66),
        const Offset(160.4, 82.2), rightEar);

    // ---- head ----
    canvas.drawOval(
      Rect.fromCenter(center: const Offset(120, 128), width: 164, height: 152),
      _furPaint(const Offset(120, 109.8), 114.8),
    );
    canvas.drawOval(
      Rect.fromCenter(center: const Offset(120, 128), width: 164, height: 152),
      _stroke(_Ink.outline, 4),
    );
    // soft highlight
    canvas.save();
    canvas.translate(96, 86);
    canvas.rotate(-20 * _deg);
    canvas.drawOval(
      Rect.fromCenter(center: Offset.zero, width: 60, height: 28),
      _fill(Colors.white.withValues(alpha: 0.18)),
    );
    canvas.restore();

    // ---- muzzle + nose ----
    final muzzle =
        Rect.fromCenter(center: const Offset(120, 154), width: 76, height: 60);
    canvas.drawOval(muzzle, _fill(_Ink.muzzle));
    canvas.drawOval(muzzle, _stroke(_Ink.muzzleEdge, 2));
    canvas.drawOval(
      Rect.fromCenter(center: const Offset(120, 140), width: 24, height: 16),
      _fill(_Ink.dark),
    );
    canvas.drawOval(
      Rect.fromCenter(center: const Offset(116, 137), width: 8, height: 4.8),
      _fill(Colors.white.withValues(alpha: 0.55)),
    );

    // ---- mouth ----
    if (happy) {
      _openMouth(canvas);
    } else {
      _closedMouth(canvas);
    }

    // ---- cheeks (happy only) ----
    if (happy) {
      final cheek = _fill(_Ink.cheek.withValues(alpha: 0.55));
      canvas.drawOval(
          Rect.fromCenter(center: const Offset(68, 146), width: 26, height: 18),
          cheek);
      canvas.drawOval(
          Rect.fromCenter(center: const Offset(172, 146), width: 26, height: 18),
          cheek);
    }

    // ---- eyes ----
    if (happy) {
      final arc = _stroke(_Ink.dark, 5);
      canvas.drawPath(
        Path()
          ..moveTo(78, 122)
          ..cubicTo(82, 110, 98, 110, 102, 122),
        arc,
      );
      canvas.drawPath(
        Path()
          ..moveTo(138, 122)
          ..cubicTo(142, 110, 158, 110, 162, 122),
        arc,
      );
    } else {
      final blink =
          _kf((t % 4.8) / 4.8, const [[0, 1], [0.92, 1], [0.95, 0.08], [1, 1]]);
      final look = (t % 7) / 7;
      final px = _kf(look,
          const [[0, 0], [0.4, 0], [0.5, 3], [0.64, 3], [0.72, -3], [0.88, -3], [1, 0]]);
      final py =
          _kf(look, const [[0, 0], [0.4, 0], [0.5, 1], [0.64, 1], [0.72, 0], [1, 0]]);
      _eye(canvas, const Offset(90, 118), blink, px, py,
          const Offset(94, 113), const Offset(87, 123));
      _eye(canvas, const Offset(150, 118), blink, px, py,
          const Offset(154, 113), const Offset(147, 123));
    }

    // ---- brows ----
    final brow = _stroke(_Ink.outline, 4);
    if (mood == BearMood.worried) {
      canvas.drawLine(const Offset(76, 104), const Offset(102, 94), brow);
      canvas.drawLine(const Offset(164, 104), const Offset(138, 94), brow);
    } else {
      canvas.drawPath(
        Path()
          ..moveTo(78, 98)
          ..cubicTo(84, 93, 92, 92, 100, 95),
        brow,
      );
      canvas.drawPath(
        Path()
          ..moveTo(140, 95)
          ..cubicTo(148, 92, 156, 93, 162, 98),
        brow,
      );
    }
  }

  void _ear(Canvas canvas, Offset c, Offset inner, Offset origin, double deg) {
    canvas.save();
    canvas.translate(origin.dx, origin.dy);
    canvas.rotate(deg * _deg);
    canvas.translate(-origin.dx, -origin.dy);
    canvas.drawCircle(
        c, 26, _furPaint(Offset(c.dx, c.dy - 26 + 0.38 * 52), 36.4));
    canvas.drawCircle(c, 26, _stroke(_Ink.outline, 3));
    canvas.drawCircle(inner, 13, _fill(_Ink.innerEar));
    canvas.restore();
  }

  void _eye(Canvas canvas, Offset c, double blink, double px, double py,
      Offset glint, Offset glint2) {
    canvas.save();
    canvas.translate(c.dx, c.dy);
    canvas.scale(1, blink);
    canvas.translate(-c.dx, -c.dy);
    canvas.drawOval(
        Rect.fromCenter(center: c, width: 24, height: 28), _fill(_Ink.dark));
    canvas.drawCircle(glint.translate(px, py), 4.6, _fill(Colors.white));
    canvas.drawCircle(glint2.translate(px, py), 2.2,
        _fill(Colors.white.withValues(alpha: 0.7)));
    canvas.restore();
  }

  void _closedMouth(Canvas canvas) {
    final line = _stroke(_Ink.dark, 3);
    canvas.drawLine(const Offset(120, 148), const Offset(120, 156), line);
    canvas.drawPath(
      Path()
        ..moveTo(104, 158)
        ..cubicTo(109, 165, 115, 166, 120, 162)
        ..cubicTo(125, 166, 131, 165, 136, 158),
      line,
    );
  }

  void _openMouth(Canvas canvas) {
    // chatter: the mouth squashes slightly, ~2x a second
    final sy = 1 - 0.3 * _wave(0.45);
    canvas.save();
    canvas.translate(120, 165);
    canvas.scale(1, sy);
    canvas.translate(-120, -165);
    final mouth = Path()
      ..moveTo(104, 156)
      ..cubicTo(108, 174, 132, 174, 136, 156)
      ..close();
    canvas.drawPath(mouth, _fill(_Ink.mouthInside));
    canvas.drawPath(mouth, _stroke(_Ink.dark, 3));
    canvas.drawPath(
      Path()
        ..moveTo(110, 168)
        ..cubicTo(115, 163, 125, 163, 130, 168)
        ..cubicTo(125, 173, 115, 173, 110, 168)
        ..close(),
      _fill(_Ink.tongue),
    );
    canvas.restore();
  }

  @override
  bool shouldRepaint(_BearPainter old) => old.t != t || old.mood != mood;
}
