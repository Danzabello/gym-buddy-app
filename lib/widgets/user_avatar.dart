import 'package:flutter/material.dart';

import 'avatars/avatar_art.dart';

/// Displays a user's avatar with emoji-based profile pictures
/// 
/// Usage:
/// ```dart
/// UserAvatar(
///   avatarId: 'lion',
///   size: 48,
/// )
/// ```
///
/// Species with illustration art (see [avatarArt]) show it instead of the
/// emoji, as a still frame by default. Pass `animated: true` for a hero spot
/// (profile, focused carousel slot) so only a few bears loop at once.
///
/// `bare` skips the circle and border, for spots that draw their own frame.
///
/// `semanticLabel` replaces the art's own label; pass '' when a parent
/// already announces who this is, so it isn't read twice.
class UserAvatar extends StatelessWidget {
  final String? avatarId;
  final double size;
  final bool animated;
  final bool bare;
  final String? semanticLabel;

  const UserAvatar({
    super.key,
    this.avatarId,
    this.size = 40,
    this.animated = false,
    this.bare = false,
    this.semanticLabel,
  });
  
  // Available avatar emojis
  static const Map<String, String> avatars = {
    'lion': '🦁',
    'bear': '🐻',
    'eagle': '🦅',
    'shark': '🦈',
    'wolf': '🐺',
    'gorilla': '🦍',
    'tiger': '🐯',
    'buffalo': '🦬',
    'robot': '🤖',
    'flexed': '💪',
    'weightlifter': '🏋️',
    'runner': '🏃',
  };
  
  @override
  Widget build(BuildContext context) {
    // Get emoji for the avatar ID, default to lion if not found
    final emoji = avatars[avatarId] ?? '🦁';

    Widget face = avatarArt(avatarId, size: size, animate: animated) ??
        Text(emoji, style: TextStyle(fontSize: size * (bare ? 0.54 : 0.6)));
    if (semanticLabel != null) {
      face = Semantics(
        label: semanticLabel,
        image: true,
        excludeSemantics: true,
        child: face,
      );
    }

    if (bare) return SizedBox.square(dimension: size, child: Center(child: face));

    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: Colors.blue[50],
        shape: BoxShape.circle,
        border: Border.all(color: Colors.blue[200]!, width: 2),
      ),
      child: Center(child: face),
    );
  }
}
