import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../widgets/avatars/animated_coach_max.dart';
import 'onboarding_max.dart';

/// The one Coach Max of the onboarding flow, drawn above every step.
///
/// At rest he follows his anchor's [LayerLink], so he stays glued to it through
/// scrolling, the keyboard and page slides. [flyTo] reads the destination
/// anchor's box and hops him there along an arc.
class CoachMaxLayer extends StatefulWidget {
  final Map<MaxSpot, MaxAnchor> anchors;
  const CoachMaxLayer({super.key, required this.anchors});

  @override
  State<CoachMaxLayer> createState() => CoachMaxLayerState();
}

class CoachMaxLayerState extends State<CoachMaxLayer>
    with TickerProviderStateMixin {
  static const _flightMs = 950;
  static const _happyTail = Duration(milliseconds: 700);

  final _badgeKey = GlobalKey();
  late final AnimationController _flight = AnimationController(vsync: this);
  late final AnimationController _squash = AnimationController(
      vsync: this, duration: const Duration(milliseconds: 420));

  MaxSpot? _spot;
  MaxSpot? _dest;
  Rect _from = Rect.zero;
  Rect _lastRect = Rect.zero;
  bool _entrance = false;
  Offset Function() _destShift = () => Offset.zero;
  int _token = 0;

  bool _orange = false;
  bool _happy = false;
  Timer? _happyTimer;

  bool get _flying => _dest != null;
  MaxSpot? get restingSpot => _spot;

  @override
  void dispose() {
    _happyTimer?.cancel();
    _flight.dispose();
    _squash.dispose();
    super.dispose();
  }

  /// Puts Max at [spot] with no movement (reduced motion, resume).
  void placeAt(MaxSpot spot) {
    _token++;
    _flight.stop();
    setState(() {
      _spot = spot;
      _dest = null;
    });
  }

  void setOrange(bool v) {
    if (_orange != v) setState(() => _orange = v);
  }

  /// Happy face for [d] (All set).
  void cheer(Duration d) {
    _happyTimer?.cancel();
    setState(() => _happy = true);
    _happyTimer = Timer(d, () {
      if (mounted) setState(() => _happy = false);
    });
  }

  Rect? _anchorRect(MaxSpot s) {
    final ro = widget.anchors[s]!.key.currentContext?.findRenderObject();
    final me = context.findRenderObject();
    if (ro is! RenderBox || !ro.attached || !ro.hasSize) return null;
    if (me is! RenderBox || !me.attached) return null;
    return me.globalToLocal(ro.localToGlobal(Offset.zero)) & ro.size;
  }

  /// Hops Max to [to]. [destShift] is how far the destination's page is still
  /// offset by its slide-in, so the flight aims at where the anchor will rest.
  /// [onLanded] fires when he touches down.
  Future<void> flyTo(
    MaxSpot to, {
    Duration? duration,
    bool entrance = false,
    Offset Function()? destShift,
    VoidCallback? onLanded,
  }) async {
    if (MediaQuery.disableAnimationsOf(context)) {
      placeAt(to);
      onLanded?.call();
      return;
    }
    final token = ++_token;
    final start = _flying ? _lastRect : (_spot == null ? null : _anchorRect(_spot!));
    _destShift = destShift ?? () => Offset.zero;

    for (var i = 0; i < 12 && mounted && _anchorRect(to) == null; i++) {
      await WidgetsBinding.instance.endOfFrame;
    }
    if (!mounted || token != _token) return;
    final end = _anchorRect(to);
    if (end == null) {
      placeAt(to);
      onLanded?.call();
      return;
    }

    _entrance = entrance || start == null;
    _from = _entrance
        ? Rect.fromCenter(
            center: Offset(end.center.dx, -end.height),
            width: end.width,
            height: end.height)
        : start!;
    _flight.duration = duration ?? const Duration(milliseconds: _flightMs);
    setState(() {
      _spot = null;
      _dest = to;
      _happy = true;
    });
    _happyTimer?.cancel();
    try {
      await _flight.forward(from: 0);
    } on TickerCanceled {
      return;
    }
    if (!mounted || token != _token) return;
    setState(() {
      _spot = to;
      _dest = null;
    });
    _squash.forward(from: 0);
    _happyTimer = Timer(_happyTail, () {
      if (mounted) setState(() => _happy = false);
    });
    onLanded?.call();
  }

  Rect _frameRect() {
    final to = _anchorRect(_dest!);
    final shift = _destShift();
    final end = to == null ? _lastRect : to.shift(-shift);
    final t = _flight.value;
    final a = _from.center;
    final b = end.center;
    final x = a.dx + (b.dx - a.dx) * Curves.easeInOutCubic.transform(t);
    double y;
    if (_entrance) {
      y = a.dy + (b.dy - a.dy) * Curves.easeInQuad.transform(t);
    } else {
      final apex = math.min(a.dy, b.dy) - (70 + 0.15 * (b.dy - a.dy).abs());
      y = t < 0.5
          ? a.dy + (apex - a.dy) * Curves.easeOutCubic.transform(t / 0.5)
          : apex + (b.dy - apex) * Curves.easeInCubic.transform((t - 0.5) / 0.5);
    }
    final w = (_from.width + (end.width - _from.width) * t) *
        (_entrance ? 1 : 1 + 0.06 * math.sin(math.pi * t));
    return _lastRect = Rect.fromCenter(center: Offset(x, y), width: w, height: w);
  }

  Widget _badge() => KeyedSubtree(
        key: _badgeKey,
        child: AnimatedBuilder(
          animation: _squash,
          builder: (_, child) {
            final t = _squash.isAnimating ? _squash.value : 1.0;
            final sx = t < 0.5 ? 1.14 + (0.95 - 1.14) * t * 2 : 0.95 + 0.05 * (t - 0.5) * 2;
            final sy = t < 0.5 ? 0.86 + (1.06 - 0.86) * t * 2 : 1.06 - 0.06 * (t - 0.5) * 2;
            return Transform(
              alignment: Alignment.bottomCenter,
              transform: Matrix4.diagonal3Values(sx, sy, 1),
              child: child,
            );
          },
          child: CoachMaxBadge(
            mood: _happy ? CoachMaxMood.happy : CoachMaxMood.idle,
            orange: _orange,
          ),
        ),
      );

  @override
  Widget build(BuildContext context) {
    final Widget content;
    if (_flying) {
      content = Positioned.fill(
        child: AnimatedBuilder(
          animation: _flight,
          builder: (_, __) => Stack(
            clipBehavior: Clip.none,
            children: [Positioned.fromRect(rect: _frameRect(), child: _badge())],
          ),
        ),
      );
    } else if (_spot != null) {
      content = CompositedTransformFollower(
        link: widget.anchors[_spot]!.link,
        showWhenUnlinked: false,
        child: SizedBox.square(
            dimension: kMaxStops[_spot]!.size, child: _badge()),
      );
    } else {
      content = const SizedBox.shrink();
    }
    return IgnorePointer(
      child: Stack(clipBehavior: Clip.none, children: [content]),
    );
  }
}
