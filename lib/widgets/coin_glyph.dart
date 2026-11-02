import 'package:flutter/material.dart';
import 'package:gym_buddy_app/theme/app_theme.dart';

/// The app's coin: a gold disc with a flame, drawn from [AppColors.warn] so it
/// follows the theme. Decorative (no semantics). Sizes up to 20 use a simpler
/// face that stays readable when small.
class CoinGlyph extends StatelessWidget {
  const CoinGlyph({super.key, required this.size});

  final double size;

  @override
  Widget build(BuildContext context) {
    return ExcludeSemantics(
      child: CustomPaint(
        size: Size.square(size),
        painter: CoinGlyphPainter(
          warn: AppColors.of(context).warn,
          small: size <= 20,
        ),
      ),
    );
  }
}

/// Paints on a 48 by 48 design grid scaled to the canvas size.
class CoinGlyphPainter extends CustomPainter {
  const CoinGlyphPainter({required this.warn, required this.small});

  final Color warn;
  final bool small;

  /// The flame, in grid units.
  static Path flame() => Path()
    ..moveTo(24, 11.5)
    ..relativeCubicTo(1.1, 5.2, 7.3, 8.4, 7.3, 15.3)
    ..arcToPoint(
      const Offset(16.7, 26.8),
      radius: const Radius.circular(7.3),
      clockwise: true,
    )
    ..relativeCubicTo(0, -3.1, 1.5, -5.3, 3.6, -7.3)
    ..relativeCubicTo(0.3, 2.1, 1.3, 3.2, 2.3, 3.6)
    ..cubicTo(22.2, 18.2, 22.6, 14.8, 24, 11.5)
    ..close();

  @override
  void paint(Canvas canvas, Size size) {
    canvas.save();
    canvas.scale(size.width / 48, size.height / 48);

    final rim = Color.lerp(warn, Colors.black, 0.34)!;
    final shade = Color.lerp(warn, Colors.black, 0.16)!;
    final hi = Color.lerp(warn, Colors.white, 0.58)!;
    const centre = Offset(24, 24);

    canvas.drawCircle(centre, 23.5, Paint()..color = rim);

    final faceRadius = small ? 19.5 : 20.0;
    final faceBox = Rect.fromCircle(center: centre, radius: faceRadius);
    canvas.drawCircle(
      centre,
      faceRadius,
      Paint()
        ..shader = RadialGradient(
          center: const Alignment(2 * 0.34 - 1, 2 * 0.28 - 1),
          radius: 0.95,
          colors: [hi, warn, shade],
          stops: const [0, 0.5, 1],
        ).createShader(faceBox),
    );

    final path = flame();
    if (small) {
      canvas.save();
      canvas.translate(24, 25.5);
      canvas.scale(1.3);
      canvas.translate(-24, -24);
      canvas.drawPath(path, Paint()..color = rim.withValues(alpha: 0.85));
      canvas.restore();
      _arc(canvas, const Offset(10.5, 19), const Offset(21, 9.2), 15, 0.55, 3);
    } else {
      canvas.drawCircle(
        centre,
        16.2,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.3
          ..color = rim.withValues(alpha: 0.5),
      );
      canvas.save();
      canvas.translate(-0.7, -0.7);
      canvas.drawPath(path, Paint()..color = Colors.white.withValues(alpha: 0.45));
      canvas.restore();
      canvas.drawPath(path, Paint()..color = rim.withValues(alpha: 0.78));
      _arc(canvas, const Offset(9.6, 19.5), const Offset(20.6, 8.6), 15.6, 0.6, 2.4);
    }
    canvas.restore();
  }

  void _arc(Canvas c, Offset from, Offset to, double r, double alpha, double w) {
    c.drawPath(
      Path()
        ..moveTo(from.dx, from.dy)
        ..arcToPoint(to, radius: Radius.circular(r), clockwise: true),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = w
        ..strokeCap = StrokeCap.round
        ..color = Colors.white.withValues(alpha: alpha),
    );
  }

  @override
  bool shouldRepaint(CoinGlyphPainter old) =>
      old.warn != warn || old.small != small;
}
