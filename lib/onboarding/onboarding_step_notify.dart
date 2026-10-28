import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../services/notification_service.dart';
import '../theme/app_theme.dart';
import 'onboarding_host.dart';
import 'onboarding_max.dart';
import 'onboarding_notifications.dart' show markNotificationRationaleSeen;
import 'onboarding_theme.dart';

/// Step 7: the one place onboarding asks for notification permission, and
/// only from the button. "Not now" never asks.
class NotifyStep extends StatefulWidget {
  const NotifyStep({super.key});

  @override
  State<NotifyStep> createState() => _NotifyStepState();
}

class _NotifyStepState extends State<NotifyStep>
    with TickerProviderStateMixin {
  static const _loopMs = 3400;
  late final AnimationController _bell = AnimationController(
      vsync: this, duration: const Duration(milliseconds: _loopMs));
  late final AnimationController _rows = AnimationController(
      vsync: this, duration: const Duration(milliseconds: 1000));
  bool _busy = false;
  bool _started = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final host = OnbScope.of(context);
    if (_started) return;
    _started = true;
    if (MediaQuery.disableAnimationsOf(context)) {
      _rows.value = 1;
      return;
    }
    void arm() {
      if (!host.bubbleVisible.value) return;
      host.bubbleVisible.removeListener(arm);
      if (!mounted) return;
      _rows.forward();
      Future<void>.delayed(const Duration(milliseconds: 500), () {
        if (mounted) _bell.repeat();
      });
    }

    host.bubbleVisible.addListener(arm);
    arm();
  }

  @override
  void dispose() {
    _bell.dispose();
    _rows.dispose();
    super.dispose();
  }

  Future<void> _finish({required bool ask}) async {
    if (_busy) return;
    final host = OnbScope.of(context);
    setState(() => _busy = true);
    if (ask) await NotificationService().requestPermissionFromUser();
    await markNotificationRationaleSeen();
    if (mounted) host.go(7);
  }

  static const _items = [
    ('Buddy check-ins', 'Know when your buddy has trained today.'),
    ('Streak at risk', 'A heads-up before the day resets.'),
    ('Workout reminders', 'Reminders for sessions you plan with your buddy.'),
  ];

  @override
  Widget build(BuildContext context) {
    final host = OnbScope.of(context);
    final c = AppColors.of(context);
    final cs = Theme.of(context).colorScheme;
    final reduce = MediaQuery.disableAnimationsOf(context);
    return OnbStepFrame(
      footer: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ObPrimaryButton(
            label: 'Turn on notifications',
            isLoading: _busy,
            onTap: () => _finish(ask: true),
          ),
          SizedBox(
            width: double.infinity,
            child: TextButton(
              onPressed: _busy ? null : () => _finish(ask: false),
              style: TextButton.styleFrom(
                  minimumSize: const Size.fromHeight(48),
                  foregroundColor: c.subtleText),
              child: const Text('Not now',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
            ),
          ),
          Text('You can change this any time in Settings.',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 12, color: c.subtleText)),
        ],
      ),
      child: Column(
        children: [
          MaxStrip(
            anchor: host.anchors[MaxSpot.notify]!,
            spot: MaxSpot.notify,
            text: 'Want a nudge before your streak slips?',
            bubbleVisible: host.bubbleVisible,
          ),
          const SizedBox(height: 22),
          ExcludeSemantics(
            child: AnimatedBuilder(
              animation: _bell,
              builder: (_, __) {
                final ms = reduce ? null : _bell.value * _loopMs;
                final glow = ms == null
                    ? 0.0
                    : 0.45 * math.sin(math.pi * (ms / 700).clamp(0.0, 1.0));
                return Container(
                  width: 96,
                  height: 96,
                  decoration: BoxDecoration(
                    color: c.claySurface,
                    borderRadius: BorderRadius.circular(30),
                    boxShadow: [
                      ...c.clayShadow(),
                      if (glow > 0)
                        BoxShadow(
                            color: c.warn.withValues(alpha: glow),
                            blurRadius: 28,
                            spreadRadius: 2),
                    ],
                  ),
                  child: CustomPaint(
                    painter: _BellPainter(
                      ms: ms,
                      gold: c.warn,
                      badge: c.streakOrange,
                      badgeText: c.readableForeground(c.streakOrange),
                    ),
                  ),
                );
              },
            ),
          ),
          const SizedBox(height: 22),
          Semantics(
            header: true,
            child: Text('Keep your streak alive',
                textAlign: TextAlign.center,
                style: TextStyle(
                    fontSize: 28, fontWeight: FontWeight.w800, color: cs.onSurface)),
          ),
          const SizedBox(height: 10),
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 320),
            child: Text(
              'Turn on notifications so Gym Buddy can reach you at the right moments. You pick which kinds in Settings.',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 15, height: 1.4, color: c.subtleText),
            ),
          ),
          const SizedBox(height: 22),
          for (var i = 0; i < _items.length; i++) ...[
            if (i > 0) const SizedBox(height: 12),
            _Row(
              title: _items[i].$1,
              caption: _items[i].$2,
              progress: CurvedAnimation(
                parent: _rows,
                curve: Interval(i * 0.2, i * 0.2 + 0.6, curve: Curves.easeOutCubic),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _Row extends StatelessWidget {
  final String title;
  final String caption;
  final Animation<double> progress;
  const _Row(
      {required this.title, required this.caption, required this.progress});

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    final cs = Theme.of(context).colorScheme;
    return FadeTransition(
      opacity: progress,
      child: SlideTransition(
        position: Tween<Offset>(begin: const Offset(-0.25, 0), end: Offset.zero)
            .animate(progress),
        child: Semantics(
          container: true,
          label: '$title. $caption',
          excludeSemantics: true,
          child: Container(
            width: double.infinity,
            decoration: BoxDecoration(
              color: c.claySurface,
              borderRadius: BorderRadius.circular(16),
              boxShadow: c.clayShadow(),
            ),
            clipBehavior: Clip.antiAlias,
            child: IntrinsicHeight(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Container(width: 5, color: cs.primary),
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(title,
                              style: TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.w700,
                                  color: cs.onSurface)),
                          const SizedBox(height: 2),
                          Text(caption,
                              style:
                                  TextStyle(fontSize: 14, color: c.subtleText)),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Gold bell on a 96 tile, pivoting at the top. [ms] is the time into the 3.4 s
/// loop; null paints the resting bell with its badge (reduced motion).
class _BellPainter extends CustomPainter {
  final double? ms;
  final Color gold;
  final Color badge;
  final Color badgeText;
  const _BellPainter({
    required this.ms,
    required this.gold,
    required this.badge,
    required this.badgeText,
  });

  static const List<double> _extremes = [0, 16, -14, 11, -8, 5, -2, 0];
  static const _swingMs = 1500.0;

  /// Degrees at [t] ms: decaying swings through the extremes above.
  static double _swing(double t) {
    if (t <= 0 || t >= _swingMs) return 0;
    final seg = _swingMs / (_extremes.length - 1);
    final i = (t / seg).floor();
    final u = Curves.easeInOut.transform((t - i * seg) / seg);
    return _extremes[i] + (_extremes[i + 1] - _extremes[i]) * u;
  }

  @override
  void paint(Canvas canvas, Size size) {
    final t = ms;
    final pale = Color.lerp(gold, Colors.white, 0.55)!;
    final hsl = HSLColor.fromColor(gold);
    final dark = hsl.withLightness((hsl.lightness * 0.6).clamp(0.0, 1.0)).toColor();
    final cx = size.width / 2;

    // Ring waves, two arcs per side, drifting 8dp outward while fading.
    if (t != null && t < 1400) {
      for (var k = 0; k < 2; k++) {
        final p = ((t - k * 220) / 800).clamp(0.0, 1.0);
        if (t < k * 220) continue;
        final paint = Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2.5
          ..strokeCap = StrokeCap.round
          ..color = gold.withValues(alpha: 0.8 * (1 - p));
        final rect = Rect.fromCircle(
            center: Offset(cx, 40), radius: 33 + k * 7 + 8 * p);
        canvas.drawArc(rect, math.pi - 0.55, 1.1, false, paint);
        canvas.drawArc(rect, -0.55, 1.1, false, paint);
      }
    }

    // Bell body, swinging from its pivot.
    canvas.save();
    canvas.translate(cx, 18);
    canvas.rotate((t == null ? 0 : _swing(t)) * math.pi / 180);
    final body = Path()
      ..moveTo(-6, 2)
      ..quadraticBezierTo(-20, 5, -20, 26)
      ..lineTo(-25, 32)
      ..lineTo(25, 32)
      ..lineTo(20, 26)
      ..quadraticBezierTo(20, 5, 6, 2)
      ..close();
    canvas.drawPath(body, Paint()..color = gold);
    canvas.drawRRect(
        RRect.fromRectAndRadius(
            const Rect.fromLTWH(-27, 31, 54, 5), const Radius.circular(2.5)),
        Paint()..color = gold);
    canvas.drawCircle(const Offset(0, 2), 3.5, Paint()..color = gold);
    canvas.drawPath(
        Path()
          ..moveTo(-13, 10)
          ..quadraticBezierTo(-16, 16, -15.5, 24),
        Paint()
          ..color = pale
          ..style = PaintingStyle.stroke
          ..strokeWidth = 3
          ..strokeCap = StrokeCap.round);
    final knock = t == null ? 0.0 : -_swing(t - 70) / 16 * 5;
    canvas.drawCircle(Offset(knock, 40), 4.5, Paint()..color = dark);
    canvas.restore();

    // Badge: pops 0 to 1.3 to 1, fades near the end of the loop.
    double scale = 1;
    double alpha = 1;
    if (t != null) {
      final u = ((t - 120) / 320).clamp(0.0, 1.0);
      scale = u < 0.6 ? 1.3 * u / 0.6 : 1.3 - 0.3 * (u - 0.6) / 0.4;
      alpha = 1 - ((t - 2800) / 400).clamp(0.0, 1.0);
    }
    if (scale > 0 && alpha > 0) {
      canvas.save();
      canvas.translate(cx + 20, 22);
      canvas.scale(scale);
      canvas.drawCircle(Offset.zero, 11, Paint()..color = badge.withValues(alpha: alpha));
      final tp = TextPainter(
        text: TextSpan(
            text: '1',
            style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w800,
                color: badgeText.withValues(alpha: alpha))),
        textDirection: TextDirection.ltr,
      )..layout();
      tp.paint(canvas, Offset(-tp.width / 2, -tp.height / 2));
      canvas.restore();
    }
  }

  @override
  bool shouldRepaint(_BellPainter old) =>
      old.ms != ms || old.gold != gold || old.badge != badge;
}
