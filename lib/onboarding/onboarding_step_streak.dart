import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../theme/app_theme.dart';
import '../widgets/user_avatar.dart';
import 'onboarding_host.dart';
import 'onboarding_max.dart';
import 'onboarding_theme.dart';

/// Step 6: two rings, one streak. Max hops from his slot into the empty chip,
/// the orange half fills, the flame lights.
class StreakStep extends StatefulWidget {
  const StreakStep({super.key});

  @override
  State<StreakStep> createState() => _StreakStepState();
}

class _StreakStepState extends State<StreakStep> with TickerProviderStateMixin {
  // Ring is r 84 on a 220 viewbox drawn at 240; chips are centred on that line
  // at the left and right middle.
  static const _chipInset = 120 - 84 * 240 / 220 - 22;
  static const _chipTop = 98.0;

  late final AnimationController _green = AnimationController(
      vsync: this, duration: const Duration(seconds: 1));
  late final AnimationController _orange = AnimationController(
      vsync: this, duration: const Duration(seconds: 1));
  late final AnimationController _pulse = AnimationController(
      vsync: this, duration: const Duration(milliseconds: 1600));

  bool _lit = false;
  bool _line2 = false;
  bool _cards = false;
  bool _warning = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _run());
  }

  @override
  void dispose() {
    _green.dispose();
    _orange.dispose();
    _pulse.dispose();
    super.dispose();
  }

  Future<bool> _wait(int ms) async {
    await Future<void>.delayed(Duration(milliseconds: ms));
    return mounted;
  }

  Future<void> _run() async {
    if (!mounted) return;
    final host = OnbScope.read(context);
    final layer = host.layerKey.currentState;
    if (MediaQuery.disableAnimationsOf(context)) {
      _green.value = 1;
      _orange.value = 1;
      layer?.placeAt(MaxSpot.streakChip);
      layer?.setOrange(true);
      setState(() {
        _lit = true;
        _line2 = true;
        _cards = true;
        _warning = true;
      });
      return;
    }

    // The green half starts 0.5 s after the page has slid in.
    unawaited(_wait(1100).then((ok) {
      if (ok) _green.forward();
    }));

    while (!host.bubbleVisible.value) {
      if (!await _wait(50)) return;
    }
    if (!await _wait(1300)) return;

    final landed = Completer<void>();
    layer?.flyTo(MaxSpot.streakChip,
        duration: const Duration(milliseconds: 1050),
        onLanded: landed.complete);
    await landed.future;
    if (!mounted) return;
    layer?.setOrange(true);
    _orange.forward();

    if (!await _wait(900)) return;
    setState(() {
      _lit = true;
      _line2 = true;
    });
    _pulse.repeat(reverse: true);
    if (!await _wait(400)) return;
    setState(() => _cards = true);
    if (!await _wait(500)) return;
    setState(() => _warning = true);
  }

  @override
  Widget build(BuildContext context) {
    final host = OnbScope.of(context);
    final draft = host.draft;
    final c = AppColors.of(context);
    final cs = Theme.of(context).colorScheme;
    final reduce = MediaQuery.disableAnimationsOf(context);
    final fade = reduce ? Duration.zero : const Duration(milliseconds: 400);

    return OnbStepFrame(
      footer: ObPrimaryButton(label: 'Got it', onTap: () => host.go(6)),
      child: Column(
        children: [
          MaxStrip(
            anchor: host.anchors[MaxSpot.streakSlot]!,
            spot: MaxSpot.streakSlot,
            text: _line2
                ? "I'll take the orange half. You fill yours, I fill mine."
                : 'Watch this.',
            bubbleVisible: host.bubbleVisible,
            decorateBox: (box) => CustomPaint(
              foregroundPainter: _DashedCircle(c.info, 2),
              child: box,
            ),
          ),
          const SizedBox(height: 20),
          Semantics(
            header: true,
            child: Text('Two rings.\nOne streak.',
                textAlign: TextAlign.center,
                style: TextStyle(
                    fontSize: 30,
                    fontWeight: FontWeight.w800,
                    height: 1.15,
                    color: cs.onSurface)),
          ),
          const SizedBox(height: 18),
          Semantics(
            container: true,
            label: 'Streak ring, day 1',
            excludeSemantics: true,
            child: SizedBox(
              width: 240,
              height: 240,
              child: Stack(
                children: [
                  Positioned.fill(
                    child: AnimatedBuilder(
                      animation: Listenable.merge([_green, _orange]),
                      builder: (_, __) => CustomPaint(
                        painter: _TwoHalves(
                          track: c.claySurface,
                          green: cs.primary,
                          orange: c.streakOrange,
                          greenT: Curves.easeInOut.transform(_green.value),
                          orangeT: Curves.easeInOut.transform(_orange.value),
                        ),
                      ),
                    ),
                  ),
                  Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        AnimatedBuilder(
                          animation: _pulse,
                          builder: (_, child) => Transform.scale(
                              scale: 1 + 0.06 * _pulse.value, child: child),
                          child: _Flame(lit: _lit),
                        ),
                        const SizedBox(height: 4),
                        Text('DAY 1',
                            textScaler: TextScaler.noScaling,
                            style: TextStyle(
                                fontSize: 15,
                                fontWeight: FontWeight.w800,
                                letterSpacing: 2,
                                color: cs.onSurface)),
                      ],
                    ),
                  ),
                  Positioned(
                    left: _chipInset,
                    top: _chipTop,
                    child: Container(
                      width: 44,
                      height: 44,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: c.inputFill,
                        border: Border.all(color: cs.primary, width: 3),
                      ),
                      child: Center(
                          child: UserAvatar(
                              avatarId: draft.avatarId,
                              size: 32,
                              bare: true,
                              semanticLabel: 'You')),
                    ),
                  ),
                  Positioned(
                    right: _chipInset,
                    top: _chipTop,
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                          shape: BoxShape.circle, color: c.inputFill),
                      child: CustomPaint(
                        foregroundPainter: _DashedCircle(c.streakOrange, 2),
                        child: host.anchors[MaxSpot.streakChip]!.box(44),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
          AnimatedOpacity(
            opacity: _cards ? 1 : 0,
            duration: fade,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                    child: _InfoCard(
                        title: 'You',
                        caption: 'Checked in',
                        captionColor: cs.primary)),
                const SizedBox(width: 12),
                Expanded(
                    child: _InfoCard(
                        title: 'Coach Max',
                        caption: 'AI buddy, waiting',
                        captionColor: c.subtleText)),
              ],
            ),
          ),
          const SizedBox(height: 14),
          AnimatedOpacity(
            opacity: _warning ? 1 : 0,
            duration: fade,
            child: Text('Miss a day and the streak resets.',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 14, color: c.subtleText)),
          ),
        ],
      ),
    );
  }
}

class _Flame extends StatelessWidget {
  final bool lit;
  const _Flame({required this.lit});

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    final cs = Theme.of(context).colorScheme;
    return SizedBox(
      width: 64,
      height: 64,
      child: Stack(
        alignment: Alignment.center,
        children: [
          TweenAnimationBuilder<Color?>(
            tween: ColorTween(end: lit ? c.streakOrange : c.claySurfaceLight),
            duration: const Duration(milliseconds: 400),
            builder: (_, color, __) => Icon(
                Icons.local_fire_department_rounded,
                size: 64,
                color: color),
          ),
          Padding(
            padding: const EdgeInsets.only(top: 18),
            child: AnimatedOpacity(
              opacity: lit ? 1 : 0,
              duration: const Duration(milliseconds: 400),
              child: Icon(Icons.local_fire_department_rounded,
                  size: 28, color: cs.onSurface),
            ),
          ),
        ],
      ),
    );
  }
}

class _InfoCard extends StatelessWidget {
  final String title;
  final String caption;
  final Color captionColor;
  const _InfoCard(
      {required this.title, required this.caption, required this.captionColor});

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    final cs = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: c.claySurface,
        borderRadius: BorderRadius.circular(16),
        boxShadow: c.clayShadow(),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title,
              style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                  color: cs.onSurface)),
          const SizedBox(height: 2),
          Text(caption,
              style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: captionColor)),
        ],
      ),
    );
  }
}

/// Ring drawn on a 220 viewbox (r 84, stroke 14), scaled to the widget.
/// The user's green half is the left one, Max's orange half the right one;
/// both fill from the top.
class _TwoHalves extends CustomPainter {
  final Color track, green, orange;
  final double greenT, orangeT;
  const _TwoHalves({
    required this.track,
    required this.green,
    required this.orange,
    required this.greenT,
    required this.orangeT,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final k = size.width / 220;
    final rect = Rect.fromCircle(center: size.center(Offset.zero), radius: 84 * k);
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 14 * k
      ..strokeCap = StrokeCap.round;
    canvas.drawArc(rect, 0, 2 * math.pi, false, paint..color = track);
    if (greenT > 0) {
      canvas.drawArc(rect, -math.pi / 2, -math.pi * greenT, false, paint..color = green);
    }
    if (orangeT > 0) {
      canvas.drawArc(rect, -math.pi / 2, math.pi * orangeT, false, paint..color = orange);
    }
  }

  @override
  bool shouldRepaint(_TwoHalves old) =>
      old.greenT != greenT ||
      old.orangeT != orangeT ||
      old.track != track ||
      old.green != green ||
      old.orange != orange;
}

class _DashedCircle extends CustomPainter {
  final Color color;
  final double width;
  const _DashedCircle(this.color, this.width);

  @override
  void paint(Canvas canvas, Size size) {
    final r = size.shortestSide / 2 - width / 2;
    final center = size.center(Offset.zero);
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = width
      ..strokeCap = StrokeCap.round;
    const dashes = 18;
    const step = 2 * math.pi / dashes;
    for (var i = 0; i < dashes; i++) {
      canvas.drawArc(Rect.fromCircle(center: center, radius: r), i * step,
          step * 0.55, false, paint);
    }
  }

  @override
  bool shouldRepaint(_DashedCircle old) =>
      old.color != color || old.width != width;
}
