import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

/// Which face Coach Max is pulling.
enum CoachMaxMood {
  /// Breathing, blinking, glancing about, antenna sway, the odd ear-plate flick.
  idle,

  /// Hopping with closed happy eyes, open mouth, flapping ear plates, wagging
  /// antenna.
  happy,

  /// Head tilted, slanted brows, drooping antenna with a dimmed flame, flat
  /// mouth. For a broken streak: sympathetic, not sad.
  worried,
}

/// The animated Coach Max avatar (the AI bot buddy), drawn in code (no assets,
/// no extra dependency).
///
/// Shaped like [AnimatedBear]: everything is drawn on a 240x240 canvas and
/// scaled to [size], so it stays crisp at any size.
///
/// Motion is cheap (one painter, one ticker) but it does loop forever, so use
/// it where one or two avatars are on screen (dashboard carousel focus,
/// dialogs) — keep still avatars in lists.
///
/// [animate] false paints a single still frame and never creates an
/// AnimationController, so list rows can show Coach Max for free.
///
/// Reduced motion: no ticker runs; shows the static pose for [mood].
///
/// This paints the robot only. The blue to purple AI-disclosure gradient and
/// the AI tag belong to the avatar container and are not drawn or changed here.
///
/// COLOURS: the shell/visor/LED colours below are illustration colours, like
/// the pixels of an image, so they are raw hex under `lib/widgets/avatars/`
/// only (the second permitted raw hex in CLAUDE.md). They do not follow the
/// accent skin.
class AnimatedCoachMax extends StatefulWidget {
  final double size;
  final CoachMaxMood mood;
  final bool animate;

  const AnimatedCoachMax({
    super.key,
    this.size = 80,
    this.mood = CoachMaxMood.idle,
    this.animate = true,
  });

  @override
  State<AnimatedCoachMax> createState() => _AnimatedCoachMaxState();
}

class _AnimatedCoachMaxState extends State<AnimatedCoachMax>
    with SingleTickerProviderStateMixin {
  // One long looping ticker; every motion is derived from elapsed seconds.
  static const _periodSeconds = 3600;
  // Created on first need, so a still Coach Max never owns a controller.
  AnimationController? _c;
  bool _reduce = false;

  bool get _running => widget.animate && !_reduce;

  void _syncTicker() {
    if (_running) {
      final c = _c ??= AnimationController(
        vsync: this,
        duration: const Duration(seconds: _periodSeconds),
      );
      if (!c.isAnimating) c.repeat();
    } else {
      _c?.stop();
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _reduce = MediaQuery.of(context).disableAnimations;
    _syncTicker();
  }

  @override
  void didUpdateWidget(AnimatedCoachMax old) {
    super.didUpdateWidget(old);
    if (old.animate != widget.animate) _syncTicker();
  }

  @override
  void dispose() {
    _c?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: 'Coach Max, AI coach avatar',
      child: ExcludeSemantics(
        child: SizedBox.square(
          dimension: widget.size,
          child: RepaintBoundary(
            child: AnimatedBuilder(
              animation: _c ?? const AlwaysStoppedAnimation<double>(0),
              builder: (context, _) => CustomPaint(
                painter: _CoachMaxPainter(
                  t: _running ? _c!.value * _periodSeconds : 0,
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

/// Illustration palette (see the note on [AnimatedCoachMax]).
class _Ink {
  static const shellLight = Color(0xFFF6F8FD);
  static const shell = Color(0xFFBCC8DE);
  static const outline = Color(0xFF5E6E99);
  static const visorTop = Color(0xFF17235A);
  static const visorBottom = Color(0xFF0A1230);
  static const visorEdge = Color(0xFF2A3A78);
  static const ledLight = Color(0xFFA5F3FC);
  static const led = Color(0xFF67E8F9);
  static const orangeLight = Color(0xFFFB923C);
  static const orange = Color(0xFFF97316);
  static const orangeDeep = Color(0xFFEA580C);
  static const orangeEdge = Color(0xFF9A3412);
  static const blush = Color(0xFFFDA4AF);
  static const stalk = Color(0xFF7C8DB5);
  static const flameLight = Color(0xFFFDBA74);
  static const flameCore = Color(0xFFFDE68A);
  static const flameGlow = Color.fromRGBO(251, 146, 60, 0.38);
  static const flameGlowOff = Color.fromRGBO(251, 146, 60, 0);
}

class _CoachMaxPainter extends CustomPainter {
  _CoachMaxPainter({required this.t, required this.mood});

  final double t; // seconds
  final CoachMaxMood mood;

  static const _deg = math.pi / 180;

  /// The streak-badge flame, drawn in a 30x38 box.
  static final Path _flame = Path()
    ..moveTo(15, 0)
    ..cubicTo(22, 10, 30, 15, 30, 26)
    ..cubicTo(30, 33, 24, 38, 15, 38)
    ..cubicTo(6, 38, 0, 33, 0, 26)
    ..cubicTo(0, 15, 8, 10, 15, 0)
    ..close();

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

  static double _mod(double x, double m) => ((x % m) + m) % m;

  /// 0 → 1 → 0 smoothly, once per [period] seconds, at time [x].
  static double _waveAt(double x, double period) =>
      0.5 - 0.5 * math.cos(2 * math.pi * (_mod(x, period) / period));

  double _wave(double period) => _waveAt(t, period);

  static Paint _fill(Color c) => Paint()..color = c;

  static Paint _stroke(Color c, double w) => Paint()
    ..color = c
    ..style = PaintingStyle.stroke
    ..strokeWidth = w
    ..strokeCap = StrokeCap.round
    ..strokeJoin = StrokeJoin.round;

  static Paint _radialPaint(Offset center, double radius, Color a, Color b) =>
      Paint()..shader = ui.Gradient.radial(center, radius, [a, b]);

  static Paint _linearPaint(Offset from, Offset to, Color a, Color b) =>
      Paint()..shader = ui.Gradient.linear(from, to, [a, b]);

  static RRect _rr(double x, double y, double w, double h, double r) =>
      RRect.fromRectAndRadius(Rect.fromLTWH(x, y, w, h), Radius.circular(r));

  @override
  void paint(Canvas canvas, Size size) {
    canvas.save();
    canvas.scale(size.width / 240, size.height / 240);

    var dx = 0.0, dy = 0.0, sx = 1.0, sy = 1.0, rot = 0.0;
    var origin = const Offset(120, 200);
    switch (mood) {
      case CoachMaxMood.idle:
        final breathe = _wave(3.6);
        dy = -2 * breathe;
        sx = 1 + 0.012 * breathe;
        sy = 1 + 0.018 * breathe;
      case CoachMaxMood.happy:
        final p = _mod(t, 0.9) / 0.9;
        origin = const Offset(120, 210);
        dy = _kf(p, const [
          [0, 0],
          [0.3, -14],
          [0.6, 0],
          [1, 0],
        ]);
        sx = _kf(p, const [
          [0, 1.04],
          [0.3, 0.96],
          [0.6, 1.05],
          [1, 1],
        ]);
        sy = _kf(p, const [
          [0, 0.94],
          [0.3, 1.05],
          [0.6, 0.94],
          [1, 1],
        ]);
        rot =
            _kf(p, const [
              [0, 0],
              [0.3, -3],
              [0.6, 3],
              [1, 0],
            ]) *
            _deg;
      case CoachMaxMood.worried:
        final sway = _wave(4);
        dx = -3;
        dy = -sway;
        rot = (-7 + 2 * sway) * _deg;
    }

    canvas.translate(origin.dx + dx, origin.dy + dy);
    canvas.rotate(rot);
    canvas.scale(sx, sy);
    canvas.translate(-origin.dx, -origin.dy);
    _drawBot(canvas);

    canvas.restore();
  }

  void _drawBot(Canvas canvas) {
    final happy = mood == CoachMaxMood.happy;
    final worried = mood == CoachMaxMood.worried;

    // ---- antenna + flame (behind the head) ----
    _antenna(canvas);

    // ---- ear plates ----
    var leftEar = 0.0, rightEar = 0.0, ledL = 1.0, ledR = 1.0;
    if (happy) {
      final k = _wave(0.45);
      leftEar = -12 * k;
      rightEar = 12 * k;
    } else if (worried) {
      ledL = ledR = 0.35;
    } else {
      leftEar = _kf(_mod(t, 6) / 6, const [
        [0, 0],
        [0.86, 0],
        [0.90, -9],
        [0.94, 3],
        [1, 0],
      ]);
      rightEar = _kf(_mod(t - 2.4, 6) / 6, const [
        [0, 0],
        [0.86, 0],
        [0.90, 9],
        [0.94, -3],
        [1, 0],
      ]);
      ledL = 0.65 + 0.35 * _wave(2.4);
      ledR = 0.65 + 0.35 * _waveAt(t + 1.2, 2.4);
    }
    _plate(canvas, 31, 152, 42, 128, leftEar, ledL);
    _plate(canvas, 209, 152, 198, 128, rightEar, ledR);

    // ---- head shell ----
    final head = _rr(38, 84, 164, 132, 50);
    canvas.drawRRect(
      head,
      _radialPaint(const Offset(120, 112), 130, _Ink.shellLight, _Ink.shell),
    );

    // ---- sweatband (clipped to the head) ----
    canvas.save();
    canvas.clipRRect(head);
    canvas.drawRect(
      Rect.fromLTWH(30, 94, 180, 16),
      _linearPaint(
        const Offset(0, 94),
        const Offset(0, 110),
        _Ink.orangeLight,
        _Ink.orangeDeep,
      ),
    );
    final bandEdge = _stroke(_Ink.orangeEdge, 2.5);
    canvas.drawLine(const Offset(30, 94), const Offset(210, 94), bandEdge);
    canvas.drawLine(const Offset(30, 110), const Offset(210, 110), bandEdge);
    canvas.drawRect(
      Rect.fromLTWH(30, 100, 180, 4),
      _fill(Colors.white.withValues(alpha: 0.85)),
    );
    canvas.restore();

    // head outline over the band edge
    canvas.drawRRect(head, _stroke(_Ink.outline, 4));

    // soft highlight
    canvas.save();
    canvas.translate(90, 100);
    canvas.rotate(-20 * _deg);
    canvas.drawOval(
      Rect.fromCenter(center: Offset.zero, width: 56, height: 14),
      _fill(Colors.white.withValues(alpha: 0.5)),
    );
    canvas.restore();

    // ---- visor ----
    final visor = _rr(52, 116, 136, 84, 32);
    canvas.drawRRect(
      visor,
      _linearPaint(
        const Offset(0, 116),
        const Offset(0, 200),
        _Ink.visorTop,
        _Ink.visorBottom,
      ),
    );
    canvas.drawRRect(visor, _stroke(_Ink.visorEdge, 3));

    // visor sheen: a still highlight, plus a slow sweep when idle
    canvas.save();
    canvas.clipRRect(visor);
    canvas.save();
    canvas.translate(86, 130);
    canvas.rotate(-20 * _deg);
    canvas.drawOval(
      Rect.fromCenter(center: Offset.zero, width: 50, height: 14),
      _fill(Colors.white.withValues(alpha: 0.1)),
    );
    canvas.restore();
    if (mood == CoachMaxMood.idle) {
      final s = _mod(t, 8) / 8;
      if (s < 0.16) {
        final p = s / 0.16;
        final x = -30 + p * 230;
        canvas.drawPath(
          Path()
            ..moveTo(x, 116)
            ..lineTo(x + 18, 116)
            ..lineTo(x + 6, 200)
            ..lineTo(x - 12, 200)
            ..close(),
          _fill(Colors.white.withValues(alpha: 0.14 * math.sin(math.pi * p))),
        );
      }
    }
    canvas.restore();

    // ---- mouth ----
    if (happy) {
      _openMouth(canvas);
    } else {
      _closedMouth(canvas, flat: worried);
    }

    // ---- cheeks (happy only) ----
    if (happy) {
      final cheek = _fill(_Ink.blush.withValues(alpha: 0.7));
      canvas.drawOval(
        Rect.fromCenter(center: const Offset(66, 176), width: 20, height: 12),
        cheek,
      );
      canvas.drawOval(
        Rect.fromCenter(center: const Offset(174, 176), width: 20, height: 12),
        cheek,
      );
    }

    // ---- eyes ----
    if (happy) {
      final arc = _stroke(_Ink.led, 6);
      canvas.drawPath(
        Path()
          ..moveTo(79, 156)
          ..cubicTo(83, 142, 99, 142, 103, 156),
        arc,
      );
      canvas.drawPath(
        Path()
          ..moveTo(137, 156)
          ..cubicTo(141, 142, 157, 142, 161, 156),
        arc,
      );
    } else {
      final blink = _kf(_mod(t, 4.8) / 4.8, const [
        [0, 1],
        [0.92, 1],
        [0.95, 0.08],
        [1, 1],
      ]);
      final look = _mod(t, 7) / 7;
      final px = _kf(look, const [
        [0, 0],
        [0.4, 0],
        [0.5, 3],
        [0.64, 3],
        [0.72, -3],
        [0.88, -3],
        [1, 0],
      ]);
      final py = _kf(look, const [
        [0, 0],
        [0.4, 0],
        [0.5, 1],
        [0.64, 1],
        [0.72, 0],
        [1, 0],
      ]);
      _eye(canvas, 91, 150, blink, px, py);
      _eye(canvas, 149, 150, blink, px, py);
    }

    // ---- brows (LED strokes) ----
    final brow = _stroke(_Ink.led.withValues(alpha: 0.85), 4);
    if (worried) {
      canvas.drawLine(const Offset(78, 132), const Offset(103, 123), brow);
      canvas.drawLine(const Offset(162, 132), const Offset(137, 123), brow);
    } else {
      canvas.drawPath(
        Path()
          ..moveTo(80, 129)
          ..cubicTo(86, 125, 96, 124, 104, 127),
        brow,
      );
      canvas.drawPath(
        Path()
          ..moveTo(136, 127)
          ..cubicTo(144, 124, 154, 125, 160, 129),
        brow,
      );
    }
  }

  /// Stalk and flame. Sways when idle, wags on the hop, droops and dims when
  /// worried.
  void _antenna(Canvas canvas) {
    var rot = 0.0;
    var flameScale = 1.0, amp = 1.0, a = 1.0;
    switch (mood) {
      case CoachMaxMood.idle:
        rot =
            3 * math.sin(2 * math.pi * t / 4.2) +
            _kf(_mod(t, 9) / 9, const [
              [0, 0],
              [0.88, 0],
              [0.91, -7],
              [0.95, 3],
              [1, 0],
            ]);
      case CoachMaxMood.happy:
        rot = 10 * math.sin(2 * math.pi * (t / 0.9) - 1.0);
        flameScale = 1.15;
        amp = 1.6;
      case CoachMaxMood.worried:
        rot = -26 + 1.5 * math.sin(2 * math.pi * t / 4);
        flameScale = 0.7;
        amp = 0.5;
        a = 0.6;
    }

    canvas.save();
    canvas.translate(120, 88);
    canvas.rotate(rot * _deg);
    canvas.translate(-120, -88);

    // stalk + joint
    canvas.drawLine(
      const Offset(120, 92),
      const Offset(120, 60),
      _stroke(_Ink.stalk, 5),
    );
    final joint = Rect.fromCenter(
      center: const Offset(120, 60),
      width: 11,
      height: 11,
    );
    canvas.drawOval(joint, _fill(_Ink.stalk));
    canvas.drawOval(joint, _stroke(_Ink.outline, 2));

    // glow
    canvas.drawCircle(
      const Offset(120, 44),
      22,
      _radialPaint(
        const Offset(120, 44),
        22,
        _Ink.flameGlow.withValues(alpha: _Ink.flameGlow.a * a),
        _Ink.flameGlowOff,
      ),
    );

    // flicker
    final f1 = math.sin(2 * math.pi * t / 0.5);
    final f2 = math.sin(2 * math.pi * t / 0.37 + 1);
    final k = 0.75 * flameScale;
    final fsy = 1 + 0.08 * amp * f1;
    final fsx = 1 - 0.05 * amp * f1;
    final tilt = 3 * amp * f2;

    canvas.save();
    canvas.translate(120, 58);
    canvas.rotate(tilt * _deg);
    canvas.scale(k * fsx, k * fsy);
    canvas.translate(-15, -38);
    canvas.drawPath(
      _flame,
      _linearPaint(
        Offset.zero,
        const Offset(0, 38),
        _Ink.flameLight.withValues(alpha: a),
        _Ink.orange.withValues(alpha: a),
      ),
    );
    canvas.restore();

    canvas.save();
    canvas.translate(120, 57);
    canvas.rotate(tilt * _deg);
    canvas.scale(k * fsx * 0.55, k * fsy * 0.55);
    canvas.translate(-15, -38);
    canvas.drawPath(_flame, _fill(_Ink.flameCore.withValues(alpha: a)));
    canvas.restore();

    canvas.restore();
  }

  void _plate(
    Canvas canvas,
    double cx,
    double cy,
    double ox,
    double oy,
    double deg,
    double led,
  ) {
    canvas.save();
    canvas.translate(ox, oy);
    canvas.rotate(deg * _deg);
    canvas.translate(-ox, -oy);
    final r = _rr(cx - 12, cy - 25, 24, 50, 11);
    canvas.drawRRect(
      r,
      _linearPaint(
        Offset(0, cy - 25),
        Offset(0, cy + 25),
        _Ink.orangeLight,
        _Ink.orangeDeep,
      ),
    );
    canvas.drawRRect(r, _stroke(_Ink.orangeEdge, 3));
    canvas.drawOval(
      Rect.fromCenter(center: Offset(cx, cy + 9), width: 13, height: 13),
      _fill(_Ink.orangeEdge),
    );
    canvas.drawOval(
      Rect.fromCenter(center: Offset(cx, cy + 9), width: 8, height: 8),
      _fill(_Ink.led.withValues(alpha: led)),
    );
    canvas.restore();
  }

  void _eye(
    Canvas canvas,
    double cx,
    double cy,
    double blink,
    double px,
    double py,
  ) {
    canvas.save();
    canvas.translate(cx, cy);
    canvas.scale(1, blink);
    canvas.translate(-cx, -cy);
    canvas.drawRRect(
      _rr(cx - 17 + px, cy - 20 + py, 34, 40, 13),
      _fill(_Ink.led.withValues(alpha: 0.22)),
    );
    canvas.drawRRect(
      _rr(cx - 12 + px, cy - 15 + py, 24, 30, 10),
      _linearPaint(
        Offset(0, cy - 15),
        Offset(0, cy + 15),
        _Ink.ledLight,
        _Ink.led,
      ),
    );
    canvas.drawOval(
      Rect.fromCenter(
        center: Offset(cx + 4 + px * 1.6, cy - 6 + py * 1.6),
        width: 8.8,
        height: 8.8,
      ),
      _fill(Colors.white),
    );
    canvas.drawOval(
      Rect.fromCenter(
        center: Offset(cx - 4 + px * 1.6, cy + 7 + py * 1.6),
        width: 4.4,
        height: 4.4,
      ),
      _fill(Colors.white.withValues(alpha: 0.7)),
    );
    canvas.restore();
  }

  void _closedMouth(Canvas canvas, {required bool flat}) {
    final line = _stroke(_Ink.led, 4.5);
    if (flat) {
      canvas.drawLine(const Offset(108, 181), const Offset(132, 181), line);
    } else {
      canvas.drawPath(
        Path()
          ..moveTo(106, 177)
          ..quadraticBezierTo(120, 187, 134, 177),
        line,
      );
    }
  }

  void _openMouth(Canvas canvas) {
    // chatter: the mouth squashes slightly, ~2x a second
    final sy = 1 - 0.3 * _wave(0.45);
    canvas.save();
    canvas.translate(120, 172);
    canvas.scale(1, sy);
    canvas.translate(-120, -172);
    canvas.drawPath(
      Path()
        ..moveTo(104, 172)
        ..cubicTo(106, 194, 134, 194, 136, 172)
        ..close(),
      _fill(_Ink.led),
    );
    // speaker grille
    final grille = _stroke(_Ink.visorBottom.withValues(alpha: 0.35), 2.5);
    canvas.drawLine(const Offset(120, 173), const Offset(120, 184), grille);
    canvas.drawLine(const Offset(112, 173), const Offset(112, 180), grille);
    canvas.drawLine(const Offset(128, 173), const Offset(128, 180), grille);
    canvas.restore();
  }

  @override
  bool shouldRepaint(_CoachMaxPainter old) => old.t != t || old.mood != mood;
}
