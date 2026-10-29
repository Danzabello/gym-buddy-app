import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../theme/app_theme.dart';
import '../signup_screen.dart';

class OnboardingValueProps extends StatefulWidget {
  const OnboardingValueProps({super.key});

  @override
  State<OnboardingValueProps> createState() =>
      _OnboardingValuePropsState();
}

class _OnboardingValuePropsState extends State<OnboardingValueProps> {
  final PageController _pageController = PageController();
  int _currentPage = 0;

  void _next() {
    HapticFeedback.selectionClick();
    if (_currentPage < 2) {
      _pageController.nextPage(
          duration: const Duration(milliseconds: 350),
          curve: Curves.easeInOut);
    } else {
      _goToSignUp();
    }
  }

  void _goToPage(int i) {
    HapticFeedback.selectionClick();
    _pageController.animateToPage(i,
        duration: const Duration(milliseconds: 350), curve: Curves.easeInOut);
  }

  void _goToSignUp() {
    Navigator.of(context).pushReplacement(
      FadeSlideRoute(
        page: const SignUpScreen(),
      ),
    );
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: PageView(
        controller: _pageController,
        onPageChanged: (i) => setState(() => _currentPage = i),
        children: [
          _Slide1(
              onNext: _next,
              active: _currentPage == 0,
              onDotTap: _goToPage),
          _Slide2(
              onNext: _next,
              active: _currentPage == 1,
              onDotTap: _goToPage),
          _Slide3(
              onNext: _goToSignUp,
              active: _currentPage == 2,
              onDotTap: _goToPage),
        ],
      ),
    );
  }
}

// ── Shared Emerald Ink pieces ──────────────────────────────────────────────

/// Floating 200×200 clay card holding the slide's emerald icon.
class _IconCard extends StatelessWidget {
  final IconData icon;
  const _IconCard(this.icon);

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    return _FloatingWidget(
      duration: const Duration(milliseconds: 1600), // 3.2s up-and-back
      offset: 8,
      child: Container(
        width: 200,
        height: 200,
        decoration: BoxDecoration(
          color: colors.clayBg,
          borderRadius: BorderRadius.circular(32),
          boxShadow: colors.clayShadow(),
        ),
        child: Icon(icon, size: 84, color: Theme.of(context).colorScheme.primary),
      ),
    );
  }
}

/// Tappable page dots: 8×8 dim, 20×8 emerald when active.
class _Dots extends StatelessWidget {
  final int active;
  final ValueChanged<int> onTap;
  const _Dots({required this.active, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    final primary = Theme.of(context).colorScheme.primary;
    final reduceMotion = MediaQuery.disableAnimationsOf(context);
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: List.generate(3, (i) {
        final isActive = i == active;
        return GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () => onTap(i),
          child: Padding(
            padding: const EdgeInsets.all(8), // 24px+ tap target
            child: AnimatedContainer(
              duration: reduceMotion
                  ? Duration.zero
                  : const Duration(milliseconds: 250),
              width: isActive ? 20 : 8,
              height: 8,
              decoration: BoxDecoration(
                color: isActive ? primary : colors.divider,
                borderRadius: BorderRadius.circular(4),
              ),
            ),
          ),
        );
      }),
    );
  }
}

/// Full-width orange action button, 52 tall, presses down to 0.97.
class _ActionButton extends StatefulWidget {
  final String label;
  final VoidCallback onTap;
  const _ActionButton({required this.label, required this.onTap});

  @override
  State<_ActionButton> createState() => _ActionButtonState();
}

class _ActionButtonState extends State<_ActionButton> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    final fg = colors.readableForeground(colors.streakOrange);
    return Listener(
      onPointerDown: (_) => setState(() => _pressed = true),
      onPointerUp: (_) => setState(() => _pressed = false),
      onPointerCancel: (_) => setState(() => _pressed = false),
      child: AnimatedScale(
        scale: _pressed ? 0.97 : 1.0,
        duration: MediaQuery.disableAnimationsOf(context)
            ? Duration.zero
            : const Duration(milliseconds: 100),
        child: SizedBox(
          width: double.infinity,
          height: 52,
          child: ElevatedButton(
            onPressed: widget.onTap,
            style: ElevatedButton.styleFrom(
              backgroundColor: colors.streakOrange,
              foregroundColor: fg,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16)),
              elevation: 0,
            ),
            child: Text(widget.label,
                style: const TextStyle(
                    fontSize: 16, fontWeight: FontWeight.w700)),
          ),
        ),
      ),
    );
  }
}

/// Bottom-anchored dots + primary CTA. Identical height on every slide, so the
/// dots and CTA sit at the same y whichever slide is showing.
class _Footer extends StatelessWidget {
  final int dot;
  final bool active;
  final ValueChanged<int> onDotTap;
  final Widget cta;
  const _Footer(
      {required this.dot,
      required this.active,
      required this.onDotTap,
      required this.cta});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 0, 24, 32),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          _Dots(active: dot, onTap: onDotTap),
          const SizedBox(height: 16),
          _StaggerIn(active: active, delayMs: 120, child: cta),
        ],
      ),
    );
  }
}

/// Fades + slides [child] up 12px over 300ms, [delayMs] after [active] turns
/// true — i.e. each time its slide becomes the current page. Reduced motion:
/// always rendered in its final state.
class _StaggerIn extends StatefulWidget {
  final bool active;
  final int delayMs;
  final Widget child;
  const _StaggerIn(
      {required this.active, required this.delayMs, required this.child});

  @override
  State<_StaggerIn> createState() => _StaggerInState();
}

class _StaggerInState extends State<_StaggerIn>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl = AnimationController(
      vsync: this, duration: Duration(milliseconds: widget.delayMs + 300));
  late final Animation<double> _t = CurvedAnimation(
      parent: _ctrl,
      curve: Interval(widget.delayMs / (widget.delayMs + 300), 1,
          curve: Curves.easeOut));

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (MediaQuery.disableAnimationsOf(context)) {
      _ctrl.value = 1;
    } else if (widget.active && _ctrl.isDismissed) {
      _ctrl.forward();
    }
  }

  @override
  void didUpdateWidget(_StaggerIn old) {
    super.didUpdateWidget(old);
    if (MediaQuery.disableAnimationsOf(context)) return;
    if (widget.active && !old.active) {
      _ctrl.forward(from: 0);
    } else if (!widget.active) {
      _ctrl.value = 0; // ready to play again when swiped back to
    }
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _t,
      builder: (_, child) => Opacity(
        opacity: _t.value,
        child: Transform.translate(
            offset: Offset(0, 12 * (1 - _t.value)), child: child),
      ),
      child: widget.child,
    );
  }
}

// ── Slide 1 — Find your buddy ──────────────────────────────────────────────
class _Slide1 extends StatelessWidget {
  final VoidCallback onNext;
  final bool active;
  final ValueChanged<int> onDotTap;
  const _Slide1(
      {required this.onNext, required this.active, required this.onDotTap});

  @override
  Widget build(BuildContext context) {
    return _ValuePropLayout(
      dot: 0,
      active: active,
      onDotTap: onDotTap,
      icon: Icons.local_fire_department,
      title: 'Find your buddy',
      body:
          'Pair up with a friend and build a streak together, one workout at a time.',
      onNext: onNext,
    );
  }
}

// ── Floating animation wrapper ─────────────────────────────────────────────
class _FloatingWidget extends StatefulWidget {
  final Widget child;
  final Duration duration;
  final double offset;

  const _FloatingWidget({
    required this.child,
    this.duration = const Duration(milliseconds: 2000),
    this.offset = 10.0,
  });

  @override
  State<_FloatingWidget> createState() => _FloatingWidgetState();
}

class _FloatingWidgetState extends State<_FloatingWidget>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  late final Animation<double> _anim;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(vsync: this, duration: widget.duration);
    _anim = Tween<double>(begin: 0, end: widget.offset).animate(
      CurvedAnimation(parent: _ctrl, curve: Curves.easeInOut),
    );
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Reduced motion: hold still at the resting position.
    if (MediaQuery.disableAnimationsOf(context)) {
      _ctrl.reset();
    } else if (!_ctrl.isAnimating) {
      _ctrl.repeat(reverse: true);
    }
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _anim,
      builder: (_, child) => Transform.translate(
        offset: Offset(0, -_anim.value),
        child: child,
      ),
      child: widget.child,
    );
  }
}

// ── Fade+slide page route ──────────────────────────────────────────────────
class FadeSlideRoute<T> extends PageRouteBuilder<T> {
  final Widget page;
  FadeSlideRoute({required this.page})
      : super(
          pageBuilder: (_, __, ___) => page,
          transitionDuration: const Duration(milliseconds: 400),
          reverseTransitionDuration: const Duration(milliseconds: 300),
          transitionsBuilder: (_, animation, secondaryAnimation, child) {
            final fade = CurvedAnimation(
                parent: animation, curve: Curves.easeOut);
            final slide = Tween<Offset>(
              begin: const Offset(0.04, 0),
              end: Offset.zero,
            ).animate(CurvedAnimation(
                parent: animation, curve: Curves.easeOutCubic));
            final fadeOut = Tween<double>(begin: 1.0, end: 0.0)
                .animate(CurvedAnimation(
                    parent: secondaryAnimation,
                    curve: Curves.easeIn));
            return FadeTransition(
              opacity: fadeOut,
              child: SlideTransition(
                position: slide,
                child: FadeTransition(opacity: fade, child: child),
              ),
            );
          },
        );
}

// ── Slide 2 — Earn cosmetics ───────────────────────────────────────────────
class _Slide2 extends StatelessWidget {
  final VoidCallback onNext;
  final bool active;
  final ValueChanged<int> onDotTap;
  const _Slide2(
      {required this.onNext, required this.active, required this.onDotTap});

  @override
  Widget build(BuildContext context) {
    return _ValuePropLayout(
      dot: 1,
      active: active,
      onDotTap: onDotTap,
      icon: Icons.palette,
      title: 'Earn cosmetics, not paywalls',
      body:
          'No premium tiers. Every ring, border and skin is unlocked by playing, not paying.',
      onNext: onNext,
    );
  }
}

// ── Slide 3 — Never train alone ────────────────────────────────────────────
class _Slide3 extends StatelessWidget {
  final VoidCallback onNext;
  final bool active;
  final ValueChanged<int> onDotTap;
  const _Slide3(
      {required this.onNext, required this.active, required this.onDotTap});

  @override
  Widget build(BuildContext context) {
    return _ValuePropLayout(
      dot: 2,
      active: active,
      onDotTap: onDotTap,
      icon: Icons.handshake,
      title: 'Never train alone',
      body:
          'Pick a real buddy or team up with Coach Max while you wait — either way, someone is checking in with you.',
      ctaLabel: 'Get started',
      onNext: onNext,
    );
  }
}

// ── Shared value prop layout ───────────────────────────────────────────────
class _ValuePropLayout extends StatelessWidget {
  final int dot;
  final bool active;
  final ValueChanged<int> onDotTap;
  final IconData icon;
  final String title;
  final String body;
  final String? ctaLabel;
  final VoidCallback onNext;

  const _ValuePropLayout({
    required this.dot,
    required this.active,
    required this.onDotTap,
    required this.icon,
    required this.title,
    required this.body,
    this.ctaLabel,
    required this.onNext,
  });

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    return SafeArea(
      child: Column(
        children: [
          Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: Column(
                children: [
                  const Spacer(flex: 2),
                  _IconCard(icon),
                  const SizedBox(height: 40),
                  _StaggerIn(
                    active: active,
                    delayMs: 0,
                    child: Text(title,
                        textAlign: TextAlign.center,
                        style: TextStyle(
                            fontSize: 24,
                            fontWeight: FontWeight.w700,
                            color: Theme.of(context).colorScheme.onSurface)),
                  ),
                  const SizedBox(height: 12),
                  _StaggerIn(
                    active: active,
                    delayMs: 60,
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 300),
                      child: Text(body,
                          textAlign: TextAlign.center,
                          style: TextStyle(
                              fontSize: 15,
                              color: colors.inkMuted,
                              height: 1.5)),
                    ),
                  ),
                  const Spacer(flex: 3),
                ],
              ),
            ),
          ),
          _Footer(
            dot: dot,
            active: active,
            onDotTap: onDotTap,
            cta: _ActionButton(label: ctaLabel ?? 'Continue', onTap: onNext),
          ),
        ],
      ),
    );
  }
}
