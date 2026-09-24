import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../theme/app_theme.dart';
import 'onboarding_value_props.dart';
import '../signup_screen.dart';
import '../login_screen.dart';
import '../main.dart';

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen>
    with SingleTickerProviderStateMixin {
  // Entrance timeline: tile scales in over 0–450ms, then wordmark, tagline,
  // CTA and sign-in link fade+slide up, 60ms apart from 380ms, 400ms each.
  static const _totalMs = 960.0;
  late final AnimationController _ctrl;
  late final Animation<double> _tileScale;
  bool _ctaPressed = false;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
        vsync: this, duration: Duration(milliseconds: _totalMs.toInt()));
    _tileScale = Tween<double>(begin: 0.8, end: 1.0).animate(CurvedAnimation(
        parent: _ctrl,
        curve: const Interval(0, 450 / _totalMs, curve: Curves.easeOutBack)));
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Reduced motion: jump straight to the final frame.
    if (MediaQuery.disableAnimationsOf(context)) {
      _ctrl.value = 1;
    } else if (_ctrl.isDismissed) {
      _ctrl.forward();
    }
  }

  Widget _stagger(int startMs, Widget child) {
    final curved = CurvedAnimation(
        parent: _ctrl,
        curve: Interval(startMs / _totalMs, (startMs + 400) / _totalMs,
            curve: Curves.easeOut));
    return FadeTransition(
      opacity: curved,
      child: SlideTransition(
        position: Tween<Offset>(begin: const Offset(0, 0.3), end: Offset.zero)
            .animate(curved),
        child: child,
      ),
    );
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  void _getStarted() {
    HapticFeedback.mediumImpact();
    Navigator.of(context).pushReplacement(
      PageRouteBuilder(
        pageBuilder: (_, __, ___) => const OnboardingValueProps(),
        transitionDuration: const Duration(milliseconds: 500),
        transitionsBuilder: (_, animation, __, child) {
          return FadeTransition(
            opacity: CurvedAnimation(parent: animation, curve: Curves.easeOut),
            child: child,
          );
        },
      ),
    );
  }

  void _signIn() {
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => LoginScreen()),
    );
  }

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    final scheme = Theme.of(context).colorScheme;
    final reduceMotion = MediaQuery.disableAnimationsOf(context);
    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 32),
          child: Column(
            children: [
              const Spacer(flex: 3),

              // Logo
              ScaleTransition(
                scale: _tileScale,
                child: Container(
                  width: 96,
                  height: 96,
                  decoration: BoxDecoration(
                    color: colors.clayBg,
                    borderRadius: BorderRadius.circular(26),
                    boxShadow: colors.clayShadow(),
                  ),
                  child: Center(
                    child: _DumbbellIcon(size: 44, color: scheme.primary),
                  ),
                ),
              ),

              const SizedBox(height: 24),

              _stagger(
                380,
                Text(
                  'Gym Buddy',
                  style: TextStyle(
                    fontSize: 28,
                    fontWeight: FontWeight.w700,
                    color: scheme.onSurface,
                    letterSpacing: -0.5,
                  ),
                ),
              ),

              const SizedBox(height: 10),

              _stagger(
                440,
                ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 260),
                  child: Text(
                    'Streaks are better with a buddy. Check in together, every day.',
                    style: TextStyle(
                      fontSize: 15,
                      color: colors.inkMuted,
                      height: 1.4,
                    ),
                    textAlign: TextAlign.center,
                  ),
                ),
              ),

              const Spacer(flex: 3),

              // CTA
              _stagger(
                500,
                ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 326),
                  child: Listener(
                    onPointerDown: (_) => setState(() => _ctaPressed = true),
                    onPointerUp: (_) => setState(() => _ctaPressed = false),
                    onPointerCancel: (_) =>
                        setState(() => _ctaPressed = false),
                    child: AnimatedScale(
                      scale: _ctaPressed ? 0.97 : 1.0,
                      duration: reduceMotion
                          ? Duration.zero
                          : const Duration(milliseconds: 100),
                      child: SizedBox(
                        width: double.infinity,
                        height: 52,
                        child: ElevatedButton(
                          onPressed: _getStarted,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: colors.streakOrange,
                            foregroundColor:
                                colors.readableForeground(colors.streakOrange),
                            shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(16)),
                            elevation: 0,
                          ),
                          child: const Text(
                            'Get started',
                            style: TextStyle(
                                fontSize: 16, fontWeight: FontWeight.w700),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),

              const SizedBox(height: 16),

              _stagger(
                560,
                GestureDetector(
                  onTap: _signIn,
                  child: RichText(
                    text: TextSpan(
                      style: TextStyle(fontSize: 14, color: colors.inkMuted),
                      children: [
                        const TextSpan(text: 'Already have an account? '),
                        TextSpan(
                          text: 'Sign in',
                          style: TextStyle(
                              color: scheme.primary,
                              fontWeight: FontWeight.w600),
                        ),
                      ],
                    ),
                  ),
                ),
              ),

              const SizedBox(height: 32),
            ],
          ),
        ),
      ),
    );
  }
}

class _DumbbellIcon extends StatelessWidget {
  final double size;
  final Color color;
  const _DumbbellIcon({required this.size, required this.color});

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      size: Size(size, size),
      painter: _DumbbellPainter(color),
    );
  }
}

class _DumbbellPainter extends CustomPainter {
  final Color color;
  _DumbbellPainter(this.color);

  @override
  void paint(Canvas canvas, Size size) {
    final p = Paint()
      ..color = color
      ..style = PaintingStyle.fill;
    final w = size.width;
    final h = size.height;
    final barH = h * 0.18;
    final barY = (h - barH) / 2;
    canvas.drawRRect(
        RRect.fromLTRBR(w * 0.12, barY, w * 0.88, barY + barH,
            Radius.circular(barH / 2)),
        p);
    for (final x in [w * 0.04, w * 0.72]) {
      canvas.drawRRect(
          RRect.fromLTRBR(x, h * 0.22, x + w * 0.18, h * 0.78,
              Radius.circular(4)),
          p);
    }
  }

  @override
  bool shouldRepaint(_) => false;
}