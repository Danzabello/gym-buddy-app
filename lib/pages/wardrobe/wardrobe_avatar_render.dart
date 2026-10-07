import 'package:flutter/material.dart';
import '../../widgets/avatars/animated_bear.dart';
import '../../widgets/avatar_picker_screen.dart' show AvatarBorderStyle;

/// Public rewrite of AvatarPickerScreen's private `_AvatarWithBorder` /
/// `_BorderPainter` so Wardrobe screens can render the same avatar+border
/// combination without depending on that file's private classes. Reuses its
/// public `AvatarBorderStyle` enum so the two stay in sync.
class WardrobeAvatarRender extends StatelessWidget {
  final String emoji;
  final AvatarBorderStyle borderStyle;
  final Color borderColor;
  final Color bgColor;
  final double size;

  /// Show the animated bear instead of the emoji. Only the big preview should
  /// set this; the grid tiles stay static so many bears aren't looping at once.
  final bool animatedBear;

  const WardrobeAvatarRender({
    super.key,
    required this.emoji,
    required this.borderStyle,
    required this.borderColor,
    required this.bgColor,
    required this.size,
    this.animatedBear = false,
  });

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      size: Size(size, size),
      foregroundPainter: _WardrobeBorderPainter(borderStyle, borderColor),
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(shape: BoxShape.circle, color: bgColor),
        child: Center(
          child: animatedBear
              ? AnimatedBear(size: size * 0.86)
              : Text(emoji, style: TextStyle(fontSize: size * 0.48)),
        ),
      ),
    );
  }
}

class _WardrobeBorderPainter extends CustomPainter {
  final AvatarBorderStyle style;
  final Color color;
  _WardrobeBorderPainter(this.style, this.color);

  @override
  void paint(Canvas canvas, Size size) {
    final c = Offset(size.width / 2, size.height / 2);
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;

    switch (style) {
      case AvatarBorderStyle.simple:
        paint.strokeWidth = size.width * 0.06;
        final r = size.width / 2 - paint.strokeWidth / 2 - 1;
        canvas.drawCircle(c, r, paint);
        break;
      case AvatarBorderStyle.bold:
        paint.strokeWidth = size.width * 0.13;
        final r = size.width / 2 - paint.strokeWidth / 2 - 1;
        canvas.drawCircle(c, r, paint);
        paint
          ..strokeWidth = size.width * 0.03
          ..color = color.withValues(alpha: 0.4);
        canvas.drawCircle(c, r - size.width * 0.10, paint);
        break;
      case AvatarBorderStyle.arc:
        paint.strokeWidth = size.width * 0.07;
        final r = size.width / 2 - paint.strokeWidth / 2 - 1;
        final rect = Rect.fromCircle(center: c, radius: r);
        canvas.drawArc(rect, -2.36, 4.71, false, paint);
        paint
          ..style = PaintingStyle.fill
          ..color = color.withValues(alpha: 0.5);
        final capR = paint.strokeWidth * 0.5;
        canvas.drawCircle(
            Offset(c.dx - r * 0.71, c.dy + r * 0.71), capR, paint);
        canvas.drawCircle(
            Offset(c.dx + r * 0.71, c.dy + r * 0.71), capR, paint);
        break;
    }
  }

  @override
  bool shouldRepaint(_WardrobeBorderPainter old) =>
      old.style != style || old.color != color;
}

String borderStyleLabel(AvatarBorderStyle style) =>
    style.name[0].toUpperCase() + style.name.substring(1);

Color hexToColor(String hex) =>
    Color(int.parse('FF${hex.replaceFirst('#', '')}', radix: 16));
