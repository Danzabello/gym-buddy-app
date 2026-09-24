import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';

import '../../theme/app_theme.dart';

/// Splash backdrop: two drifting glow blobs, ten rising motes, and the looping
/// brand-mark video. [builder] lays out the foreground and receives the 132px
/// circular logo to place in it, so the video sits in the foreground's own
/// layout while blobs and motes paint behind everything.
///
/// Reduced motion: blobs rest, motes are skipped, and the video is never
/// initialised — the static lit frame shows instead.
class OnboardingSplashBackground extends StatefulWidget {
  static const videoAsset = 'assets/animations/branding/streak_flame_loop.mp4';
  static const fallbackAsset =
      'assets/animations/branding/streak_flame_static_fallback.png';

  final Widget Function(BuildContext context, Widget logo) builder;

  const OnboardingSplashBackground({super.key, required this.builder});

  @override
  State<OnboardingSplashBackground> createState() =>
      _OnboardingSplashBackgroundState();
}

class _OnboardingSplashBackgroundState extends State<OnboardingSplashBackground>
    with SingleTickerProviderStateMixin, WidgetsBindingObserver {
  // One clock drives blobs and motes. 720s is the LCM of every loop period
  // used below (12/15/16/18/20s), so the wrap back to 0 is seamless.
  static const _clockSeconds = 720.0;
  late final AnimationController _clock = AnimationController(
    vsync: this,
    duration: Duration(seconds: _clockSeconds.toInt()),
  );
  VideoPlayerController? _video;
  bool _reduceMotion = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _reduceMotion = MediaQuery.disableAnimationsOf(context);
    if (_reduceMotion) {
      _clock.reset(); // stop at the resting position
      _video?.pause();
      return;
    }
    if (!_clock.isAnimating) _clock.repeat();
    if (_video == null) {
      _video = VideoPlayerController.asset(
        OnboardingSplashBackground.videoAsset,
      );
      _startVideo(_video!);
    } else {
      _video!.play();
    }
  }

  Future<void> _startVideo(VideoPlayerController video) async {
    try {
      await video.initialize();
    } catch (_) {
      return; // a broken asset must never block the splash — circle stays empty
    }
    if (!mounted) return;
    await video.setLooping(true);
    await video.setVolume(0);
    if (!_reduceMotion) await video.play();
    if (mounted) setState(() {});
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final video = _video;
    if (video == null || !video.value.isInitialized) return;
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.inactive) {
      video.pause();
    } else if (state == AppLifecycleState.resumed &&
        mounted &&
        !_reduceMotion) {
      video.play();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _clock.dispose();
    _video?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    final emerald = Theme.of(context).colorScheme.primary;
    final orange = colors.streakOrange;
    final video = _video;

    final Widget mark;
    if (_reduceMotion) {
      mark = Image.asset(
        OnboardingSplashBackground.fallbackAsset,
        fit: BoxFit.cover,
      );
    } else if (video != null && video.value.isInitialized) {
      mark = FittedBox(
        fit: BoxFit.cover,
        child: SizedBox.fromSize(
          size: video.value.size,
          child: VideoPlayer(video),
        ),
      );
    } else {
      mark = const SizedBox.shrink(); // empty circle until the first frame
    }

    final logo = Container(
      width: 132,
      height: 132,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: colors.clayBg,
        boxShadow: colors.clayShadow(),
      ),
      child: ClipOval(child: mark),
    );

    return Stack(
      fit: StackFit.expand,
      children: [
        CustomPaint(painter: _BlobPainter(_clock, emerald, orange)),
        if (!_reduceMotion)
          CustomPaint(painter: _MotePainter(_clock, emerald, orange)),
        widget.builder(context, logo),
      ],
    );
  }
}

/// 0→1→0 over [period] seconds, eased like CSS `ease-in-out alternate`.
double _pingPong(double seconds, double period) =>
    0.5 - 0.5 * math.cos(2 * math.pi * (seconds % period) / period);

class _BlobPainter extends CustomPainter {
  final Animation<double> clock;
  final Color emerald;
  final Color orange;

  _BlobPainter(this.clock, this.emerald, this.orange) : super(repaint: clock);

  // Drift is a fraction of the screen size; scale multiplies the diameter.
  static final _emeraldDrift = Tween<Offset>(
    begin: Offset.zero,
    end: const Offset(0.08, 0.06),
  );
  static final _orangeDrift = Tween<Offset>(
    begin: Offset.zero,
    end: const Offset(-0.10, -0.07),
  );
  static final _emeraldScale = Tween<double>(begin: 1.0, end: 1.12);
  static final _orangeScale = Tween<double>(begin: 1.0, end: 1.10);

  @override
  void paint(Canvas canvas, Size size) {
    final s = clock.value * _OnboardingSplashBackgroundState._clockSeconds;
    _blob(
      canvas,
      size,
      const Offset(0.2, 0.22),
      1.3,
      emerald,
      0.16,
      _emeraldDrift,
      _emeraldScale,
      _pingPong(s, 16),
    );
    _blob(
      canvas,
      size,
      const Offset(0.85, 0.82),
      1.1,
      orange,
      0.10,
      _orangeDrift,
      _orangeScale,
      _pingPong(s, 20),
    );
  }

  void _blob(
    Canvas canvas,
    Size size,
    Offset rest,
    double diameter,
    Color color,
    double opacity,
    Tween<Offset> drift,
    Tween<double> scale,
    double t,
  ) {
    final d = drift.transform(t);
    final centre = Offset(
      (rest.dx + d.dx) * size.width,
      (rest.dy + d.dy) * size.height,
    );
    final radius = diameter * size.width / 2 * scale.transform(t);
    // A radial gradient fading to transparent is the soft-edged "blurred
    // blob" — no ImageFilter blur pass needed.
    final paint = Paint()
      ..shader = RadialGradient(
        colors: [
          color.withValues(alpha: opacity),
          color.withValues(alpha: 0),
        ],
      ).createShader(Rect.fromCircle(center: centre, radius: radius));
    canvas.drawCircle(centre, radius, paint);
  }

  @override
  bool shouldRepaint(_BlobPainter old) =>
      old.emerald != emerald || old.orange != orange;
}

class _MotePainter extends CustomPainter {
  final Animation<double> clock;
  final Color emerald;
  final Color orange;

  _MotePainter(this.clock, this.emerald, this.orange) : super(repaint: clock);

  // Per mote: x (fraction of width), loop seconds, start delay seconds.
  static const _x = [0.08, 0.18, 0.3, 0.42, 0.52, 0.63, 0.72, 0.82, 0.9, 0.36];
  static const _period = [12.0, 15.0, 16.0, 18.0];
  static const _delay = [0.0, 4.0, 8.0, 2.0, 11.0, 6.0, 1.0, 9.0, 3.0, 7.0];

  @override
  void paint(Canvas canvas, Size size) {
    final s = clock.value * _OnboardingSplashBackgroundState._clockSeconds;
    for (var i = 0; i < 10; i++) {
      final local = s - _delay[i];
      // Not started yet, like CSS animation-delay. ponytail: this also re-hides
      // delayed motes for ≤11s each time the 720s clock wraps — invisible on a
      // splash seen for seconds; track real elapsed time if that ever matters.
      if (local < 0) continue;
      final period = _period[i % 4];
      final p = (local % period) / period;
      // Fade in over the first 15%, out over the last 15%.
      final fade = math.min(1.0, math.min(p, 1 - p) / 0.15);
      final maxOpacity = 0.25 + 0.25 * (i % 4) / 3;
      final paint = Paint()
        ..color = (i.isEven ? emerald : orange).withValues(
          alpha: maxOpacity * fade,
        );
      canvas.drawCircle(
        Offset(_x[i] * size.width, size.height * (1.05 - 1.15 * p)),
        (3 + i % 3) / 2, // 3–5px diameter
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(_MotePainter old) =>
      old.emerald != emerald || old.orange != orange;
}
