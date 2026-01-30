import 'package:flutter/material.dart';

/// Displays a user's avatar with emoji-based profile pictures
/// 
/// Usage:
/// ```dart
/// UserAvatar(
///   avatarId: 'lion',
///   size: 48,
/// )
/// ```
class UserAvatar extends StatelessWidget {
  final String? avatarId;
  final double size;
  
  const UserAvatar({
    super.key,
    this.avatarId,
    this.size = 40,
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
    
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: Colors.blue[50],
        shape: BoxShape.circle,
        border: Border.all(color: Colors.blue[200]!, width: 2),
      ),
      child: Center(
        child: Text(
          emoji,
          style: TextStyle(fontSize: size * 0.6),
        ),
      ),
    );
  }
}
