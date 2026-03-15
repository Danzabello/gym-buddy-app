import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'onboarding_theme.dart';
import 'onboarding_value_props.dart';
import '../signup_screen.dart';

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  late final Animation<double> _fade;
  late final Animation<Offset> _slide;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 900));
    _fade = CurvedAnimation(parent: _ctrl, curve: Curves.easeOut);
    _slide = Tween<Offset>(
            begin: const Offset(0, 0.12), end: Offset.zero)
        .animate(CurvedAnimation(parent: _ctrl, curve: Curves.easeOut));
    _ctrl.forward();
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  void _getStarted() {
    HapticFeedback.mediumImpact();
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(builder: (_) => const OnboardingValueProps()),
    );
  }

  void _signIn() {
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const SignUpScreen()),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(gradient: kGradientDiag),
        child: SafeArea(
          child: FadeTransition(
            opacity: _fade,
            child: SlideTransition(
              position: _slide,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 32),
                child: Column(
                  children: [
                    const Spacer(flex: 3),

                    // Logo
                    Container(
                      width: 88,
                      height: 88,
                      decoration: BoxDecoration(
                        color: Colors.white.withOpacity(0.2),
                        borderRadius: BorderRadius.circular(24),
                      ),
                      child: const Center(
                        child: _DumbbellIcon(size: 48, color: Colors.white),
                      ),
                    ),

                    const SizedBox(height: 24),

                    const Text(
                      'Gym Buddy',
                      style: TextStyle(
                        fontSize: 34,
                        fontWeight: FontWeight.w700,
                        color: Colors.white,
                        letterSpacing: -0.5,
                      ),
                    ),

                    const SizedBox(height: 10),

                    Text(
                      'Train together. Streak together.',
                      style: TextStyle(
                        fontSize: 16,
                        color: Colors.white.withOpacity(0.8),
                        height: 1.4,
                      ),
                      textAlign: TextAlign.center,
                    ),

                    const Spacer(flex: 3),

                    // CTA
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton(
                        onPressed: _getStarted,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.white,
                          foregroundColor: kObBlue,
                          padding:
                              const EdgeInsets.symmetric(vertical: 16),
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(14)),
                          elevation: 0,
                        ),
                        child: const Text(
                          'Get started',
                          style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w700),
                        ),
                      ),
                    ),

                    const SizedBox(height: 16),

                    GestureDetector(
                      onTap: _signIn,
                      child: RichText(
                        text: TextSpan(
                          style: TextStyle(
                              fontSize: 14,
                              color: Colors.white.withOpacity(0.7)),
                          children: const [
                            TextSpan(text: 'Already have an account? '),
                            TextSpan(
                              text: 'Sign in',
                              style: TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.w600),
                            ),
                          ],
                        ),
                      ),
                    ),

                    const SizedBox(height: 32),
                  ],
                ),
              ),
            ),
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