import 'dart:async';

import 'package:flutter/material.dart';

import '../theme/app_theme.dart';
import 'onboarding_draft.dart';
import 'onboarding_max.dart';
import 'onboarding_max_layer.dart';
import 'onboarding_step_allset.dart';
import 'onboarding_step_avatar.dart';
import 'onboarding_step_buddy.dart';
import 'onboarding_step_identity.dart';
import 'onboarding_step_notify.dart';
import 'onboarding_step_signup.dart';
import 'onboarding_step_streak.dart';
import 'onboarding_theme.dart';
import 'splash_screen.dart';

/// The six-step onboarding flow: one host owns the step index and a single
/// Coach Max layer above every step. Steps are plain widgets inside it.
class OnboardingHost extends StatefulWidget {
  /// True when an auth user already exists but onboarding never finished:
  /// the flow resumes at step 2.
  final bool resume;

  const OnboardingHost({
    super.key,
    this.resume = false,
  });

  @override
  State<OnboardingHost> createState() => OnboardingHostState();
}

class OnbScope extends InheritedWidget {
  final OnboardingHostState host;
  const OnbScope({super.key, required this.host, required super.child});

  static OnboardingHostState of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<OnbScope>()!.host;

  /// For initState, where a dependency cannot be registered.
  static OnboardingHostState read(BuildContext context) =>
      context.getInheritedWidgetOfExactType<OnbScope>()!.host;

  @override
  bool updateShouldNotify(OnbScope old) => false;
}

class OnboardingHostState extends State<OnboardingHost>
    with SingleTickerProviderStateMixin {
  static const _slide = Cubic(.3, .7, .2, 1);

  final anchors = {for (final s in MaxSpot.values) s: MaxAnchor()};
  final layerKey = GlobalKey<CoachMaxLayerState>();
  final bubbleVisible = ValueNotifier<bool>(false);
  final draft = OnboardingDraft();

  late final AnimationController _t;
  late int index = widget.resume ? 1 : 0;
  int? _prev;
  int _dir = 1;
  double _width = 360;
  Timer? _bubbleTimer;

  bool get _reduce => MediaQuery.disableAnimationsOf(context);

  @override
  void initState() {
    super.initState();
    _t = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 600), value: 1);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      layerKey.currentState?.flyTo(
        kStepSpots[index],
        entrance: true,
        duration: const Duration(milliseconds: 1000),
        onLanded: _landed,
      );
    });
  }

  @override
  void dispose() {
    _bubbleTimer?.cancel();
    _t.dispose();
    bubbleVisible.dispose();
    draft.dispose();
    super.dispose();
  }

  void _landed() {
    _bubbleTimer?.cancel();
    if (!mounted) return;
    if (_reduce) {
      bubbleVisible.value = true;
    } else {
      _bubbleTimer = Timer(const Duration(milliseconds: 350), () {
        if (mounted) bubbleVisible.value = true;
      });
    }
  }

  /// Slides to page [to]; Max hops to that page's anchor. The page slides in
  /// from the side Max is leaving.
  void go(int to) {
    if (to == index || to < 0 || to > kAllSetIndex || _t.isAnimating) return;
    final reduce = _reduce;
    _bubbleTimer?.cancel();
    bubbleVisible.value = false;
    setState(() {
      _prev = index;
      _dir = maxTravel(index, to);
      index = to;
    });
    _t.duration = Duration(milliseconds: reduce ? 150 : 600);
    _t.forward(from: 0).whenComplete(() {
      if (mounted) setState(() => _prev = null);
    });
    layerKey.currentState?.flyTo(
      kStepSpots[to],
      destShift: () =>
          Offset(-_dir * _width * (1 - _slide.transform(_t.value)), 0),
      onLanded: _landed,
    );
  }

  /// Slides to the next page.
  void next() => go(index + 1);

  /// Back is offered on identity and buddy only: avatar follows the sign-up
  /// that created the account, and the pages after buddy follow the profile
  /// write.
  bool get canGoBack =>
      kStepSpots[index] == MaxSpot.identity || kStepSpots[index] == MaxSpot.buddy;

  void back() {
    if (_t.isAnimating) return;
    if (index == 0) {
      final nav = Navigator.of(context);
      if (nav.canPop()) {
        nav.pop();
      } else {
        nav.pushReplacement(FadeSlideRoute(page: const SplashScreen()));
      }
    } else if (canGoBack) {
      go(index - 1);
    }
  }

  Widget _page(int i) => RepaintBoundary(child: _buildStep(i));

  Widget _steps(BuildContext context, Widget? _) {
    final t = _t.value;
    final c = _slide.transform(t);
    final reduce = _reduce;
    final prev = _prev;
    final w = _width;
    return Stack(
      fit: StackFit.expand,
      children: [
        if (prev != null)
          KeyedSubtree(
            key: ValueKey(prev),
            child: Opacity(
              opacity: reduce ? 1 - t : 1 - (t * 600 / 400).clamp(0.0, 1.0),
              child: Transform.translate(
                offset: reduce ? Offset.zero : Offset(_dir * w * 0.35 * c, 0),
                child: _page(prev),
              ),
            ),
          ),
        KeyedSubtree(
          key: ValueKey(index),
          child: Opacity(
            opacity: reduce ? t : 1,
            child: Transform.translate(
              offset: reduce ? Offset.zero : Offset(-_dir * w * (1 - c), 0),
              child: _page(index),
            ),
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final allSet = index == kAllSetIndex;
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) back();
      },
      child: OnbScope(
        host: this,
        child: Scaffold(
          body: Stack(
            children: [
              Column(
                children: [
                  ExcludeSemantics(
                    excluding: allSet,
                    child: IgnorePointer(
                      ignoring: allSet,
                      child: AnimatedOpacity(
                        opacity: allSet ? 0 : 1,
                        duration: _reduce
                            ? Duration.zero
                            : const Duration(milliseconds: 300),
                        child: _Chrome(
                          step: (index + 1).clamp(1, kNumberedSteps),
                          onBack: canGoBack ? back : null,
                        ),
                      ),
                    ),
                  ),
                  Expanded(
                    child: LayoutBuilder(builder: (context, cons) {
                      _width = cons.maxWidth;
                      return AnimatedBuilder(
                          animation: _t, builder: _steps);
                    }),
                  ),
                ],
              ),
              Positioned.fill(
                  child: CoachMaxLayer(key: layerKey, anchors: anchors)),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildStep(int i) => switch (i) {
        0 => const SignUpStep(),
        1 => const AvatarStep(),
        2 => const IdentityStep(),
        3 => const BuddyStep(),
        4 => const StreakStep(),
        5 => const NotifyStep(),
        _ => const AllSetStep(),
      };
}

// ── Chrome ──────────────────────────────────────────────────────────────────

class _Chrome extends StatelessWidget {
  final int step;
  final VoidCallback? onBack;
  const _Chrome({required this.step, required this.onBack});

  @override
  Widget build(BuildContext context) {
    final reduce = MediaQuery.disableAnimationsOf(context);
    final back = onBack == null
        ? const SizedBox(height: 48)
        : Row(children: [
            ObBackButton(onTap: onBack!),
            const SizedBox(width: 12),
          ]);
    return SafeArea(
      bottom: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(24, 16, 24, 8),
        child: Row(
          children: [
            if (reduce)
              back
            else
              AnimatedSize(
                duration: const Duration(milliseconds: 200),
                alignment: Alignment.centerLeft,
                child: back,
              ),
            Expanded(child: ObSegmentBar(step: step)),
          ],
        ),
      ),
    );
  }
}

/// Seven segments: 6dp high, 4dp apart, filled up to [step].
class ObSegmentBar extends StatelessWidget {
  final int step;
  final int total;
  const ObSegmentBar({super.key, required this.step, this.total = kNumberedSteps});

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    final fill = Theme.of(context).colorScheme.primary;
    final reduce = MediaQuery.disableAnimationsOf(context);
    return Semantics(
      label: 'Step $step of $total',
      excludeSemantics: true,
      child: Row(
        children: [
          for (var i = 1; i <= total; i++) ...[
            if (i > 1) const SizedBox(width: 4),
            Expanded(
              child: AnimatedContainer(
                key: ValueKey('segment$i'),
                duration:
                    reduce ? Duration.zero : const Duration(milliseconds: 300),
                height: 6,
                decoration: BoxDecoration(
                  color: i <= step ? fill : c.claySurface,
                  borderRadius: BorderRadius.circular(3),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// Common frame for a step: scrolling body (so nothing clips at large text
/// sizes) and a pinned footer.
class OnbStepFrame extends StatelessWidget {
  final Widget child;
  final Widget? footer;
  final bool centered;
  const OnbStepFrame({
    super.key,
    required this.child,
    this.footer,
    this.centered = false,
  });

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      top: false,
      child: Column(
        children: [
          Expanded(
            child: LayoutBuilder(
              builder: (context, cons) => SingleChildScrollView(
                keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
                padding: const EdgeInsets.fromLTRB(24, 12, 24, 16),
                child: ConstrainedBox(
                  constraints: BoxConstraints(
                      minHeight: centered ? cons.maxHeight - 28 : 0),
                  child: centered ? Center(child: child) : child,
                ),
              ),
            ),
          ),
          if (footer != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 4, 24, 16),
              child: footer,
            ),
        ],
      ),
    );
  }
}
