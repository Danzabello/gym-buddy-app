import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../theme/app_theme.dart';
import '../widgets/avatars/animated_coach_max.dart';

enum MaxSide { left, right, centre }

/// Every place Coach Max can rest during onboarding.
enum MaxSpot {
  signUp,
  avatar,
  border,
  identity,
  buddy,
  streakSlot,
  streakChip,
  notify,
  allSet,
}

class MaxStop {
  final MaxSide side;
  final double size;
  const MaxStop(this.side, this.size);
}

/// Side and size (dp) of each resting place.
const Map<MaxSpot, MaxStop> kMaxStops = {
  MaxSpot.signUp: MaxStop(MaxSide.left, 92),
  MaxSpot.avatar: MaxStop(MaxSide.right, 64),
  MaxSpot.border: MaxStop(MaxSide.left, 64),
  MaxSpot.identity: MaxStop(MaxSide.right, 64),
  MaxSpot.buddy: MaxStop(MaxSide.left, 64),
  MaxSpot.streakSlot: MaxStop(MaxSide.right, 64),
  MaxSpot.streakChip: MaxStop(MaxSide.right, 44),
  MaxSpot.notify: MaxStop(MaxSide.left, 64),
  MaxSpot.allSet: MaxStop(MaxSide.centre, 156),
};

/// Where Max first rests on each page: seven numbered steps, then All set.
const List<MaxSpot> kStepSpots = [
  MaxSpot.signUp,
  MaxSpot.avatar,
  MaxSpot.border,
  MaxSpot.identity,
  MaxSpot.buddy,
  MaxSpot.streakSlot,
  MaxSpot.notify,
  MaxSpot.allSet,
];

const int kNumberedSteps = 7;
const int kAllSetIndex = 7;

int _sideOrder(MaxSide s) => switch (s) {
      MaxSide.left => -1,
      MaxSide.centre => 0,
      MaxSide.right => 1,
    };

/// +1 when Max moves right between two pages, -1 when he moves left.
int maxTravel(int fromIndex, int toIndex) {
  final d = _sideOrder(kMaxStops[kStepSpots[toIndex]]!.side) -
      _sideOrder(kMaxStops[kStepSpots[fromIndex]]!.side);
  return d == 0 ? 1 : d.sign;
}

/// A box a step reserves for Max. The layer reads [key] for geometry and
/// follows [link] while he rests there.
class MaxAnchor {
  final GlobalKey key = GlobalKey();
  final LayerLink link = LayerLink();

  Widget box(double size) => CompositedTransformTarget(
        link: link,
        child: SizedBox.square(key: key, dimension: size),
      );
}

// ── Max ─────────────────────────────────────────────────────────────────────

/// Coach Max in his circle: clay fill, aqua ring (orange inside the streak
/// chip) and an "AI" chip once there is room for it. Fills its constraints.
class CoachMaxBadge extends StatelessWidget {
  final CoachMaxMood mood;
  final bool orange;
  const CoachMaxBadge({
    super.key,
    this.mood = CoachMaxMood.idle,
    this.orange = false,
  });

  static const double aiChipMinSize = 52;

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    final ink = Theme.of(context).scaffoldBackgroundColor;
    return Semantics(
      container: true,
      label: 'Coach Max, AI coach',
      excludeSemantics: true,
      child: LayoutBuilder(builder: (context, cons) {
        final size = cons.biggest.shortestSide;
        final ring = size >= 92 ? 3.0 : 2.0;
        return Stack(
          clipBehavior: Clip.none,
          children: [
            Positioned.fill(
              child: TweenAnimationBuilder<Color?>(
                tween: ColorTween(end: orange ? c.streakOrange : c.aqua),
                duration: const Duration(milliseconds: 250),
                builder: (_, color, child) => DecoratedBox(
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: c.claySurface,
                    border: Border.all(color: color ?? c.aqua, width: ring),
                  ),
                  child: child,
                ),
                child: ClipOval(
                  child: Center(
                    child: AnimatedCoachMax(
                      size: math.max(0, size - ring * 2),
                      mood: mood,
                    ),
                  ),
                ),
              ),
            ),
            if (size >= aiChipMinSize)
              Positioned(
                right: -size * 0.04,
                bottom: -size * 0.02,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 5, vertical: 1.5),
                  decoration: BoxDecoration(
                    color: c.aqua,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: ink, width: 2),
                  ),
                  child: Text(
                    'AI',
                    textScaler: TextScaler.noScaling,
                    style: TextStyle(
                      fontSize: size >= 92 ? 11 : 10,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 0.8,
                      height: 1.1,
                      color: ink,
                    ),
                  ),
                ),
              ),
          ],
        );
      }),
    );
  }
}

/// Speech bubble: "Coach Max · AI coach" over one line of real text, with a
/// diamond tail pointing at Max, who stands on [side].
class MaxBubble extends StatelessWidget {
  final String text;
  final MaxSide side;
  const MaxBubble({super.key, required this.text, required this.side});

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    final cs = Theme.of(context).colorScheme;
    final tailOnLeft = side == MaxSide.left;
    return Stack(
      clipBehavior: Clip.none,
      children: [
        Positioned(
          top: 16,
          left: tailOnLeft ? -6 : null,
          right: tailOnLeft ? null : -6,
          child: Transform.rotate(
            angle: math.pi / 4,
            child: Container(
              width: 12,
              height: 12,
              decoration: BoxDecoration(
                color: c.claySurface,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
        ),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          decoration: BoxDecoration(
            color: c.claySurface,
            borderRadius: BorderRadius.circular(16),
            boxShadow: c.clayShadow(),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Coach Max · AI coach',
                  style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 0.3,
                      color: c.subtleText)),
              const SizedBox(height: 2),
              AnimatedSwitcher(
                duration: const Duration(milliseconds: 200),
                child: Text(text,
                    key: ValueKey(text),
                    style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                        height: 1.3,
                        color: cs.onSurface)),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

/// Max's anchor box beside his bubble. The bubble stays hidden until
/// [bubbleVisible] turns true (350 ms after Max lands), then fades in and
/// rises 8dp.
class MaxStrip extends StatelessWidget {
  final MaxAnchor anchor;
  final MaxSpot spot;
  final String text;
  final ValueListenable<bool> bubbleVisible;
  const MaxStrip({
    super.key,
    required this.anchor,
    required this.spot,
    required this.text,
    required this.bubbleVisible,
  });

  @override
  Widget build(BuildContext context) {
    final stop = kMaxStops[spot]!;
    final reduce = MediaQuery.disableAnimationsOf(context);
    final bubble = Expanded(
      child: ValueListenableBuilder<bool>(
        valueListenable: bubbleVisible,
        builder: (_, visible, child) => TweenAnimationBuilder<double>(
          tween: Tween(end: visible ? 1.0 : 0.0),
          duration: reduce ? Duration.zero : const Duration(milliseconds: 300),
          curve: Curves.easeOut,
          builder: (_, v, child) => Opacity(
            opacity: v,
            child: Transform.translate(
                offset: Offset(0, 8 * (1 - v)), child: child),
          ),
          child: child,
        ),
        child: MaxBubble(text: text, side: stop.side),
      ),
    );
    final box = anchor.box(stop.size);
    const gap = SizedBox(width: 14);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: stop.side == MaxSide.left
          ? [box, gap, bubble]
          : [bubble, gap, box],
    );
  }
}
