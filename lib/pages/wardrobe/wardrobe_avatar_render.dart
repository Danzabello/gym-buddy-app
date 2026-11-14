import 'package:flutter/material.dart';
import '../../widgets/avatars/avatar_art.dart';
import '../../widgets/avatar_picker_screen.dart' show AvatarBorderPainter, AvatarBorderStyle;

/// Public rewrite of AvatarPickerScreen's private `_AvatarWithBorder` so
/// Wardrobe screens can render the same avatar+border combination without
/// depending on that file's private classes. Reuses its public
/// `AvatarBorderStyle` enum and `AvatarBorderPainter` so the two stay in sync.
class WardrobeAvatarRender extends StatelessWidget {
  final String emoji;
  final AvatarBorderStyle borderStyle;
  final Color borderColor;
  final Color bgColor;
  final double size;

  /// Species with illustration art (see [avatarArt]) draw it instead of
  /// [emoji]; null keeps the emoji.
  final String? avatarId;

  /// Loop the art. Only the big preview should set this; wheel and grid tiles
  /// stay still so many avatars aren't animating at once.
  final bool animated;

  /// Replaces the art's own label; '' when a parent already announces it.
  final String? semanticLabel;

  const WardrobeAvatarRender({
    super.key,
    required this.emoji,
    required this.borderStyle,
    required this.borderColor,
    required this.bgColor,
    required this.size,
    this.avatarId,
    this.animated = false,
    this.semanticLabel,
  });

  @override
  Widget build(BuildContext context) {
    Widget? art = avatarArt(avatarId, size: size, animate: animated);
    if (art != null && semanticLabel != null) {
      art = Semantics(
        label: semanticLabel,
        image: true,
        excludeSemantics: true,
        child: art,
      );
    }
    return CustomPaint(
      size: Size(size, size),
      foregroundPainter: AvatarBorderPainter(borderStyle, borderColor),
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(shape: BoxShape.circle, color: bgColor),
        child: Center(
          child: art ?? Text(emoji, style: TextStyle(fontSize: size * 0.48)),
        ),
      ),
    );
  }
}

String borderStyleLabel(AvatarBorderStyle style) =>
    style.name[0].toUpperCase() + style.name.substring(1);
