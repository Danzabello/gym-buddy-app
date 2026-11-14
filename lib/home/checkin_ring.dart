part of '../home_screen.dart';

/// Splits a ring into one arc per team member: solid in that member's colour
/// once they have checked in today, a faint track if not. Recon confirmed teams
/// are pairs (42 two-member, 2 one-member, never more), but this draws N arcs so
/// a larger team degrades gracefully rather than silently mis-rendering.
///
/// [fillProgress] is 0.0 (track) → 1.0 (fully checked in) per segment, so
/// _AnimatedCheckInRing can tween a segment in rather than popping it — the
/// endpoints are pixel-identical to the old boolean on/off draw.
class _CheckInRingPainter extends CustomPainter {
  final List<Color> segmentColors;
  final List<double> fillProgress;
  final Color track;

  static const stroke = 5.0;

  const _CheckInRingPainter({
    required this.segmentColors,
    required this.fillProgress,
    required this.track,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final n = segmentColors.length;
    if (n == 0) return;

    final rect = Rect.fromLTWH(
        stroke / 2, stroke / 2, size.width - stroke, size.height - stroke);
    // A single-member team has no seam to show, so it draws as one closed ring.
    final gap = n == 1 ? 0.0 : 0.14;
    final sweep = (2 * math.pi / n) - gap;

    for (var i = 0; i < n; i++) {
      final start = -math.pi / 2 + i * (2 * math.pi / n) + gap / 2;
      final t = fillProgress[i].clamp(0.0, 1.0);
      canvas.drawArc(
        rect,
        start,
        sweep,
        false,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeCap = StrokeCap.round
          ..strokeWidth = ui.lerpDouble(stroke * 0.6, stroke, t)!
          ..color = Color.lerp(track, segmentColors[i], t)!,
      );
    }
  }

  @override
  bool shouldRepaint(_CheckInRingPainter old) =>
      old.fillProgress.toString() != fillProgress.toString() ||
      old.segmentColors.toString() != segmentColors.toString() ||
      old.track != track;
}

/// Tweens _CheckInRingPainter's fill from whatever it last was to the new
/// checked-in state — reused for both the user's own check-in and a buddy's
/// realtime one, so the ring never pops, only fills in.
class _AnimatedCheckInRing extends StatefulWidget {
  final List<Color> segmentColors;
  final List<bool> checkedIn;
  final Color track;
  final double size;

  const _AnimatedCheckInRing({
    super.key,
    required this.segmentColors,
    required this.checkedIn,
    required this.track,
    required this.size,
  });

  @override
  State<_AnimatedCheckInRing> createState() => _AnimatedCheckInRingState();
}

class _AnimatedCheckInRingState extends State<_AnimatedCheckInRing>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _anim;
  late List<double> _fromFill;
  late List<double> _toFill;

  static List<double> _fillFor(List<bool> checkedIn) =>
      [for (final c in checkedIn) c ? 1.0 : 0.0];

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    );
    _anim = CurvedAnimation(parent: _controller, curve: Curves.easeOutCubic);
    _toFill = _fillFor(widget.checkedIn);
    _fromFill = _toFill;
    _controller.value = 1.0; // no transition on first mount
  }

  @override
  void didUpdateWidget(covariant _AnimatedCheckInRing old) {
    super.didUpdateWidget(old);
    final newTarget = _fillFor(widget.checkedIn);
    if (newTarget.length != _toFill.length) {
      // Team roster changed shape (rare) — snap rather than lerp mismatched
      // segment counts.
      _toFill = newTarget;
      _fromFill = newTarget;
      _controller.value = 1.0;
      return;
    }
    if (newTarget.toString() != _toFill.toString()) {
      _fromFill = _currentFill();
      _toFill = newTarget;
      _controller
        ..value = 0.0
        ..forward();
    }
  }

  List<double> _currentFill() => [
        for (var i = 0; i < _toFill.length; i++)
          ui.lerpDouble(_fromFill[i], _toFill[i], _anim.value)!,
      ];

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _anim,
      builder: (_, __) => CustomPaint(
        size: Size(widget.size, widget.size),
        painter: _CheckInRingPainter(
          segmentColors: widget.segmentColors,
          fillProgress: _currentFill(),
          track: widget.track,
        ),
      ),
    );
  }
}
