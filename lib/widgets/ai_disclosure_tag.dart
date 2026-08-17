// lib/widgets/ai_disclosure_tag.dart
//
// AI-disclosure tags for Coach Max. Coach Max is a bot, not a person, and he
// appears in the same lists, wheels and cards as real buddies — these two tags
// are the one thing that tells them apart.
//
// Two renderings, same visual language:
//   AiCornerBadge — overlay tag for the bottom-right of an avatar circle.
//                   Carries a border in the surrounding surface colour so it
//                   reads as cut into the avatar rather than floating on it.
//                   Wrap in a Stack/Positioned at the call site.
//   AiInlinePill  — borderless pill that sits next to a name label.

import 'package:flutter/material.dart';
import '../theme/app_theme.dart';

/// Shared ink for both tags.
const Color _kAiTagBackground = Color(0xFF2C2C34);

const TextStyle _kAiTagTextStyle = TextStyle(
  color: Colors.white,
  fontSize: 9,
  fontWeight: FontWeight.bold,
  letterSpacing: 0.4,
  height: 1.0,
);

/// Small "AI" tag meant to overlay the bottom-right of an avatar circle.
///
/// [scale] shrinks the whole tag for smaller avatars — stay at or above 0.85,
/// below that the two letters stop being legible on a phone.
/// [borderColor] should match whatever surface sits behind the avatar; it
/// defaults to the card background, which is right for every list/card use.
/// Pass it explicitly on gradient backdrops (e.g. onboarding).
class AiCornerBadge extends StatelessWidget {
  final double scale;
  final Color? borderColor;

  const AiCornerBadge({
    super.key,
    this.scale = 1.0,
    this.borderColor,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final surface = borderColor ??
        theme.extension<AppColors>()?.cardBackground ??
        theme.scaffoldBackgroundColor;

    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: 6 * scale,
        vertical: 2 * scale,
      ),
      decoration: BoxDecoration(
        color: _kAiTagBackground,
        borderRadius: BorderRadius.circular(8 * scale),
        border: Border.all(color: surface, width: 1.5 * scale),
      ),
      child: Text(
        'AI',
        style: _kAiTagTextStyle.copyWith(fontSize: 9 * scale),
      ),
    );
  }
}

/// Small "AI" pill meant to sit inline next to a name label.
///
/// Borderless — it sits on the surface, not on top of an avatar.
class AiInlinePill extends StatelessWidget {
  final double scale;

  const AiInlinePill({
    super.key,
    this.scale = 1.0,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: 6 * scale,
        vertical: 2 * scale,
      ),
      decoration: BoxDecoration(
        color: _kAiTagBackground,
        borderRadius: BorderRadius.circular(8 * scale),
      ),
      child: Text(
        'AI',
        style: _kAiTagTextStyle.copyWith(fontSize: 9 * scale),
      ),
    );
  }
}
