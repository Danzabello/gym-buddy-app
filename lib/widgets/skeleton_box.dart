import 'package:flutter/material.dart';
import '../theme/app_theme.dart';

/// Shared skeleton placeholder with a looping left-to-right shimmer sweep.
/// Falls back to a static box when the OS has reduced motion enabled.
class SkeletonBox extends StatefulWidget {
  final double width;
  final double height;
  final double radius;
  final BoxShape shape;

  const SkeletonBox({
    super.key,
    required this.width,
    required this.height,
    this.radius = 8,
  }) : shape = BoxShape.rectangle;

  const SkeletonBox.circle({super.key, required double size})
      : width = size,
        height = size,
        radius = 0,
        shape = BoxShape.circle;

  @override
  State<SkeletonBox> createState() => _SkeletonBoxState();
}

class _SkeletonBoxState extends State<SkeletonBox>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 2000),
  );

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (MediaQuery.of(context).disableAnimations) {
      _controller.stop();
    } else if (!_controller.isAnimating) {
      _controller.repeat();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    final box = Container(
      width: widget.width,
      height: widget.height,
      decoration: BoxDecoration(
        color: colors.claySurface,
        shape: widget.shape,
        borderRadius: widget.shape == BoxShape.circle
            ? null
            : BorderRadius.circular(widget.radius),
      ),
    );

    if (MediaQuery.of(context).disableAnimations) return box;

    return AnimatedBuilder(
      animation: _controller,
      child: box,
      builder: (context, child) => ShaderMask(
        blendMode: BlendMode.srcATop,
        shaderCallback: (bounds) => LinearGradient(
          begin: Alignment.centerLeft,
          end: Alignment.centerRight,
          stops: const [0.0, 0.5, 1.0],
          colors: [colors.claySurface, colors.claySurfaceLight, colors.claySurface],
          transform: _SlidingGradientTransform(_controller.value),
        ).createShader(bounds),
        child: child,
      ),
    );
  }
}

class _SlidingGradientTransform extends GradientTransform {
  const _SlidingGradientTransform(this.slidePercent);
  final double slidePercent;

  @override
  Matrix4? transform(Rect bounds, {TextDirection? textDirection}) {
    return Matrix4.translationValues(bounds.width * (2 * slidePercent - 1), 0.0, 0.0);
  }
}
