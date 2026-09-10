import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../../data/avatar_catalog.dart';
import '../../theme/app_theme.dart';
import '../../widgets/avatar_picker_screen.dart' show AvatarBorderStyle;
import 'wardrobe_avatar_render.dart';
import 'wardrobe_selection_state.dart';

/// Binding-of-Isaac-style radial avatar picker: the equipped avatar sits in
/// the center at full size, the rest orbit around it. Tapping an unlocked
/// orbit tile swaps it into the center (same [WardrobeSelectionState.setAvatar]
/// the old grid used); tapping a locked one reveals its unlock condition in a
/// small callout instead of selecting it.
class WardrobeAvatarWheel extends StatefulWidget {
  const WardrobeAvatarWheel({super.key});

  @override
  State<WardrobeAvatarWheel> createState() => _WardrobeAvatarWheelState();
}

class _WardrobeAvatarWheelState extends State<WardrobeAvatarWheel> {
  static const double _wheelSize = 300;
  static const double _orbitRadius = 104;
  static const double _tileSize = 52;
  static const double _centerSize = 100;

  String? _calloutAvatarId;

  @override
  Widget build(BuildContext context) {
    final state = context.watch<WardrobeSelectionState>();
    final appColors = AppColors.of(context);
    final center = avatarCatalogById(state.avatarId);
    final orbit = avatarCatalog.where((a) => a.id != state.avatarId).toList();
    final angleStep = 2 * math.pi / orbit.length;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 28),
      decoration: BoxDecoration(
        color: appColors.claySurface,
        borderRadius: BorderRadius.circular(20),
        boxShadow: appColors.clayShadow(),
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          // The real safe margin around the wheel box — how far a callout can
          // extend before it'd hit the card's own edge — not a guessed
          // constant. Clamping to zero margin (the wheel box itself) instead
          // of this pulled off-center bubbles back on top of their own tile.
          final safeMargin =
              ((constraints.maxWidth - _wheelSize) / 2).clamp(0.0, double.infinity);

          return Center(
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () => setState(() => _calloutAvatarId = null),
              child: SizedBox(
                width: _wheelSize,
                height: _wheelSize,
                child: Stack(
                  clipBehavior: Clip.none,
                  children: [
                    Positioned.fill(
                      child: CustomPaint(
                        painter: _DashedCirclePainter(
                          radius: _orbitRadius,
                          color: appColors.inkMuted.withOpacity(0.25),
                        ),
                      ),
                    ),
                    for (int i = 0; i < orbit.length; i++)
                      _buildOrbitTile(orbit[i], i, angleStep, state, appColors),
                    Positioned.fill(
                      child: Center(
                        child: _buildCenter(center, state, appColors),
                      ),
                    ),
                    if (_calloutAvatarId != null)
                      _buildCalloutAtWheelLevel(
                          orbit, angleStep, appColors, safeMargin),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildCenter(
    AvatarCatalogEntry center,
    WardrobeSelectionState state,
    AppColors appColors,
  ) {
    final ringColor = state.ringItem?.colorHex != null
        ? hexToColor(state.ringItem!.colorHex!)
        : appColors.avatarRing;

    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 280),
      child: Column(
        key: ValueKey(center.id),
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: _centerSize + 24,
            height: _centerSize + 24,
            padding: const EdgeInsets.all(6),
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(color: ringColor, width: 6),
            ),
            child: WardrobeAvatarRender(
              emoji: center.emoji,
              borderStyle: state.border,
              borderColor: center.borderColor,
              bgColor: appColors.tint(center.color),
              size: _centerSize,
            ),
          ),
          const SizedBox(height: 10),
          Text(
            center.name,
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w700,
              color: appColors.readableForeground(appColors.claySurface),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildOrbitTile(
    AvatarCatalogEntry a,
    int index,
    double angleStep,
    WardrobeSelectionState state,
    AppColors appColors,
  ) {
    final angle = index * angleStep - math.pi / 2;
    final cx = _wheelSize / 2 + _orbitRadius * math.cos(angle);
    final cy = _wheelSize / 2 + _orbitRadius * math.sin(angle);
    final locked = !a.isStarter && !state.unlockedAvatarIds.contains(a.id);
    final calloutOpen = _calloutAvatarId == a.id;

    return Positioned(
      left: cx - _tileSize / 2,
      top: cy - _tileSize / 2,
      child: GestureDetector(
        onTap: () {
          HapticFeedback.selectionClick();
          if (locked) {
            setState(() => _calloutAvatarId = calloutOpen ? null : a.id);
          } else {
            setState(() => _calloutAvatarId = null);
            state.setAvatar(a.id);
          }
        },
        child: Container(
          width: _tileSize,
          height: _tileSize,
          padding: const EdgeInsets.all(2),
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            border: calloutOpen
                ? Border.all(color: appColors.streakOrange, width: 2.5)
                : null,
          ),
          child: Stack(
            alignment: Alignment.topRight,
            children: [
              Opacity(
                opacity: locked ? 0.5 : 1.0,
                child: WardrobeAvatarRender(
                  emoji: a.emoji,
                  borderStyle: AvatarBorderStyle.simple,
                  borderColor: a.borderColor,
                  bgColor: appColors.tint(a.color),
                  size: _tileSize - 4,
                ),
              ),
              if (locked)
                Container(
                  padding: const EdgeInsets.all(2),
                  decoration: BoxDecoration(
                    color: appColors.claySurface,
                    shape: BoxShape.circle,
                  ),
                  child: Icon(Icons.lock_rounded,
                      size: 11, color: appColors.inkMuted),
                ),
            ],
          ),
        ),
      ),
    );
  }

  /// Anchored above/below the tile (horizontally centered on it) rather than
  /// radially outward from the wheel center. Radial placement put the bubble
  /// on top of the tile itself for anything near the horizontal extremes —
  /// on this device the card's real available width leaves only ~18dp beyond
  /// the wheel box, far less than the ~56dp radial placement needed there, so
  /// clamping to the (correct) real margin still clamped into overlap. Every
  /// tile's cx sits within [wheelSize/2 - orbitRadius, wheelSize/2 +
  /// orbitRadius], which is always within the wheel box itself, so centering
  /// the bubble on tileCx keeps it inside the safe width by construction —
  /// no clamp needed for the dimension that was actually overflowing.
  Widget _buildCalloutAtWheelLevel(
    List<AvatarCatalogEntry> orbit,
    double angleStep,
    AppColors appColors,
    double safeMargin,
  ) {
    final index = orbit.indexWhere((a) => a.id == _calloutAvatarId);
    if (index == -1) return const SizedBox.shrink();
    final a = orbit[index];
    final angle = index * angleStep - math.pi / 2;
    final tileCx = _wheelSize / 2 + _orbitRadius * math.cos(angle);
    final tileCy = _wheelSize / 2 + _orbitRadius * math.sin(angle);

    const bubbleWidth = 116.0;
    const bubbleHeight = 36.0;
    const verticalGap = 8.0;
    final inTopHalf = tileCy <= _wheelSize / 2;
    final bubbleCy = inTopHalf
        ? tileCy - _tileSize / 2 - verticalGap - bubbleHeight / 2
        : tileCy + _tileSize / 2 + verticalGap + bubbleHeight / 2;

    final left = (tileCx - bubbleWidth / 2)
        .clamp(-safeMargin, _wheelSize - bubbleWidth + safeMargin);
    final top = (bubbleCy - bubbleHeight / 2)
        .clamp(-safeMargin, _wheelSize - bubbleHeight + safeMargin);

    return Positioned(
      left: left,
      top: top,
      child: SizedBox(
        width: bubbleWidth,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          decoration: BoxDecoration(
            color: appColors.claySurfaceLight,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: appColors.streakOrange, width: 1.5),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.lock_rounded, size: 13, color: appColors.streakOrange),
              const SizedBox(width: 6),
              Flexible(
                child: Text(
                  a.unlockReq ?? '',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: appColors.readableForeground(appColors.claySurfaceLight),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Purely decorative dashed guide circle behind the orbit tiles.
class _DashedCirclePainter extends CustomPainter {
  final double radius;
  final Color color;
  const _DashedCirclePainter({required this.radius, required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5;

    const dashLength = 6.0;
    const gapLength = 6.0;
    final circumference = 2 * math.pi * radius;
    final dashCount = (circumference / (dashLength + gapLength)).floor();
    final dashAngle = (dashLength / circumference) * 2 * math.pi;
    final angleStep = 2 * math.pi / dashCount;

    for (int i = 0; i < dashCount; i++) {
      canvas.drawArc(
        Rect.fromCircle(center: center, radius: radius),
        i * angleStep,
        dashAngle,
        false,
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _DashedCirclePainter old) =>
      old.radius != radius || old.color != color;
}
