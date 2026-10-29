import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../home_screen.dart';
import '../services/coach_max_service.dart';
import '../theme/app_theme.dart';
import 'onboarding_host.dart';
import 'onboarding_max.dart';
import 'onboarding_theme.dart';
import '../utils/run_once.dart';

/// Last page: Max lands in the centre, a halo rings out once, the headline,
/// body and button rise in. No bar and no back.
class AllSetStep extends StatefulWidget {
  const AllSetStep({super.key});

  @override
  State<AllSetStep> createState() => _AllSetStepState();
}

class _AllSetStepState extends State<AllSetStep> with TickerProviderStateMixin {
  final _once = RunOnce();
  late final AnimationController _halo = AnimationController(
      vsync: this, duration: const Duration(milliseconds: 1200));
  late final AnimationController _rise = AnimationController(
      vsync: this, duration: const Duration(milliseconds: 1100));
  bool _started = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_started) return;
    _started = true;
    final host = OnbScope.of(context);
    if (MediaQuery.disableAnimationsOf(context)) {
      _rise.value = 1;
      return;
    }
    void arm() {
      if (!host.bubbleVisible.value) return;
      host.bubbleVisible.removeListener(arm);
      if (!mounted) return;
      _halo.forward();
      _rise.forward();
      host.layerKey.currentState?.cheer(const Duration(milliseconds: 2200));
    }

    host.bubbleVisible.addListener(arm);
    arm();
  }

  @override
  void dispose() {
    _once.dispose();
    _halo.dispose();
    _rise.dispose();
    super.dispose();
  }

  Future<void> _toHome() {
    final user = Supabase.instance.client.auth.currentUser;
    final msg = user != null
        ? CoachMaxService()
            .getMotivationalMessage(currentStreak: 0, hasCheckedInToday: false)
        : "Let's go! Coach Max is ready for you.";

    // Captured before navigating: ScaffoldMessenger sits above the Navigator,
    // so the snackbar outlives this route and shows on HomeScreen.
    final messenger = ScaffoldMessenger.of(context);
    final successColor = AppColors.of(context).success;

    final pushed = Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => const HomeScreen()),
      (r) => false,
    );

    Future.delayed(const Duration(milliseconds: 400), () {
      messenger.showSnackBar(
        SnackBar(
          content: Text(msg),
          backgroundColor: successColor,
          duration: const Duration(seconds: 4),
          behavior: SnackBarBehavior.floating,
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        ),
      );
    });
    return pushed;
  }

  Widget _rising(double start, Widget child) {
    final a = CurvedAnimation(
      parent: _rise,
      curve: Interval(start, start + 500 / 1100, curve: Curves.easeOutCubic),
    );
    return FadeTransition(
      opacity: a,
      child: SlideTransition(
        position: Tween<Offset>(begin: const Offset(0, 0.25), end: Offset.zero)
            .animate(a),
        child: child,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final host = OnbScope.of(context);
    final c = AppColors.of(context);
    final cs = Theme.of(context).colorScheme;
    const size = 156.0;
    return OnbStepFrame(
      centered: true,
      footer: _rising(
        300 / 1100,
        ObPrimaryButton(label: "Let's train", onTap: () => _once.run(_toHome)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            width: size * 1.6,
            height: size * 1.6,
            child: Stack(
              alignment: Alignment.center,
              children: [
                ExcludeSemantics(
                  child: AnimatedBuilder(
                    animation: _halo,
                    builder: (_, __) {
                      final t = Curves.easeOut.transform(_halo.value);
                      return Opacity(
                        opacity: _halo.isAnimating ? 1 - t : 0,
                        child: Container(
                          width: size * (1 + 0.5 * t),
                          height: size * (1 + 0.5 * t),
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            border: Border.all(color: c.aqua, width: 3),
                          ),
                        ),
                      );
                    },
                  ),
                ),
                host.anchors[MaxSpot.allSet]!.box(size),
              ],
            ),
          ),
          const SizedBox(height: 12),
          _rising(
            0,
            Semantics(
              header: true,
              child: Text("You're all set!",
                  textAlign: TextAlign.center,
                  style: TextStyle(
                      fontSize: 30, fontWeight: FontWeight.w800, color: cs.onSurface)),
            ),
          ),
          const SizedBox(height: 12),
          _rising(
            150 / 1100,
            Text(
              'Your profile is ready. Coach Max is waiting. Time to build some streaks.',
              style: TextStyle(fontSize: 16, color: c.subtleText, height: 1.5),
              textAlign: TextAlign.center,
            ),
          ),
        ],
      ),
    );
  }
}
