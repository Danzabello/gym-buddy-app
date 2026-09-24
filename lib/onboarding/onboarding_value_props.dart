import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
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
  final List<Map<String, dynamic>> _pendingInvites = [];

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

  void _skip() {
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
        page: SignUpScreen(pendingInvites: List.from(_pendingInvites)),
      ),
    );
  }

  void _addPendingInvite(Map<String, dynamic> user) {
    if (_pendingInvites.any((u) => u['id'] == user['id'])) return;
    setState(() => _pendingInvites.add(user));
    HapticFeedback.selectionClick();
  }

  void _removePendingInvite(String userId) {
    setState(
        () => _pendingInvites.removeWhere((u) => u['id'] == userId));
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
            pendingInvites: _pendingInvites,
            onInvite: _addPendingInvite,
            onRemove: _removePendingInvite,
            onNext: _next,
            onSkip: _skip,
            active: _currentPage == 0,
            onDotTap: _goToPage,
          ),
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
  final IconData? icon;
  final VoidCallback onTap;
  const _ActionButton({required this.label, required this.onTap, this.icon});

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
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (widget.icon != null) ...[
                  Icon(widget.icon, size: 18),
                  const SizedBox(width: 8),
                ],
                Text(widget.label,
                    style: const TextStyle(
                        fontSize: 16, fontWeight: FontWeight.w700)),
              ],
            ),
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
class _Slide1 extends StatefulWidget {
  final List<Map<String, dynamic>> pendingInvites;
  final void Function(Map<String, dynamic>) onInvite;
  final void Function(String) onRemove;
  final VoidCallback onNext;
  final VoidCallback onSkip;
  final bool active;
  final ValueChanged<int> onDotTap;

  const _Slide1({
    required this.pendingInvites,
    required this.onInvite,
    required this.onRemove,
    required this.onNext,
    required this.onSkip,
    required this.active,
    required this.onDotTap,
  });

  @override
  State<_Slide1> createState() => _Slide1State();
}

class _Slide1State extends State<_Slide1> {
  bool _searching = false;
  final _searchCtrl = TextEditingController();
  List<Map<String, dynamic>> _results = [];
  bool _isSearching = false;

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  Future<void> _search(String query) async {
    if (query.isEmpty) {
      setState(() => _results = []);
      return;
    }
    setState(() => _isSearching = true);
    try {
      final clean =
          query.startsWith('@') ? query.substring(1) : query;
      // Escape % and _ so they're treated as literal characters, not
      // SQL LIKE wildcards (S10 audit fix).
      final escapedClean = clean
          .replaceAll('\\', '\\\\')
          .replaceAll('%', '\\%')
          .replaceAll('_', '\\_');
      final res = await Supabase.instance.client
          .from('user_profiles')
          .select('id, username, display_name, avatar_id')
          .ilike('username', '%$escapedClean%')
          .not('username', 'is', null)
          .limit(10);
      if (mounted) {
        setState(() {
          _results = List<Map<String, dynamic>>.from(res);
          _isSearching = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _isSearching = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    final scheme = Theme.of(context).colorScheme;
    return SafeArea(
      child: Column(
        children: [
          // Back button, shown only while searching
          if (_searching)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              child: GestureDetector(
                onTap: () => setState(() {
                  _searching = false;
                  _results = [];
                  _searchCtrl.clear();
                }),
                child: Container(
                  width: 32,
                  height: 32,
                  decoration: BoxDecoration(
                    color: colors.clayBg,
                    shape: BoxShape.circle,
                  ),
                  child: Icon(Icons.arrow_back,
                      color: scheme.onSurface, size: 16),
                ),
              ),
            ),
          // Search field or illustration
          _searching
              ? Padding(
                  padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
                  child: Container(
                    height: 40,
                    decoration: BoxDecoration(
                      color: colors.clayBg,
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: colors.divider),
                    ),
                    child: TextField(
                      controller: _searchCtrl,
                      autofocus: true,
                      cursorColor: scheme.primary,
                      style: TextStyle(fontSize: 14, color: scheme.onSurface),
                      decoration: InputDecoration(
                        hintText: 'Search by username...',
                        hintStyle:
                            TextStyle(color: colors.inkMuted, fontSize: 14),
                        prefixIcon: Icon(Icons.search,
                            color: colors.inkMuted, size: 18),
                        border: InputBorder.none,
                        enabledBorder: InputBorder.none,
                        focusedBorder: InputBorder.none,
                        filled: false,
                        contentPadding:
                            const EdgeInsets.symmetric(vertical: 10),
                        suffixIcon: _isSearching
                            ? Padding(
                                padding: const EdgeInsets.all(10),
                                child: SizedBox(
                                    width: 18,
                                    height: 18,
                                    child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                        color: scheme.primary)))
                            : null,
                      ),
                      onChanged: (v) {
                        Future.delayed(const Duration(milliseconds: 400), () {
                          if (_searchCtrl.text == v && mounted) {
                            _search(v);
                          }
                        });
                      },
                    ),
                  ),
                )
              : const Padding(
                  padding: EdgeInsets.only(top: 24, bottom: 8),
                  child: _IconCard(Icons.local_fire_department),
                ),

          // Body
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(24, 20, 24, 24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _StaggerIn(
                    active: widget.active,
                    delayMs: 0,
                    child: SizedBox(
                      width: double.infinity,
                      child: Text('Find your buddy',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                              fontSize: 24,
                              fontWeight: FontWeight.w700,
                              color: scheme.onSurface)),
                    ),
                  ),
                  const SizedBox(height: 8),
                  _StaggerIn(
                    active: widget.active,
                    delayMs: 60,
                    child: Center(
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 300),
                        child: Text(
                          'Connect with friends already on Gym Buddy and start building streaks from day one.',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                              fontSize: 15,
                              color: colors.inkMuted,
                              height: 1.5),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 20),

                  if (!_searching) ...[
                    SizedBox(
                      width: double.infinity,
                      height: 52,
                      child: OutlinedButton(
                        onPressed: widget.onSkip,
                        style: OutlinedButton.styleFrom(
                          side: BorderSide(color: colors.divider, width: 1.5),
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(16)),
                        ),
                        child: Text('Skip for now',
                            style: TextStyle(
                                color: scheme.onSurface,
                                fontSize: 15,
                                fontWeight: FontWeight.w500)),
                      ),
                    ),
                  ] else ...[
                    if (_results.isNotEmpty) ...[
                      Text('Results',
                          style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              color: colors.inkMuted)),
                      const SizedBox(height: 8),
                      ..._results
                          .map((u) => _UserResultTile(
                                user: u,
                                isInvited: widget.pendingInvites
                                    .any((p) => p['id'] == u['id']),
                                onInvite: () => widget.onInvite(u),
                                onRemove: () => widget.onRemove(u['id']),
                              ))
                          .toList(),
                    ] else if (_searchCtrl.text.isNotEmpty && !_isSearching)
                      Center(
                        child: Padding(
                          padding: const EdgeInsets.symmetric(vertical: 20),
                          child: Text('No users found',
                              style: TextStyle(
                                  color: colors.inkMuted, fontSize: 14)),
                        ),
                      ),

                    if (widget.pendingInvites.isNotEmpty) ...[
                      const SizedBox(height: 16),
                      Text('Invited (${widget.pendingInvites.length})',
                          style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              color: colors.inkMuted)),
                      const SizedBox(height: 8),
                      ...widget.pendingInvites
                          .map((u) => _InvitedTile(
                                user: u,
                                onRemove: () => widget.onRemove(u['id']),
                              ))
                          .toList(),
                      const SizedBox(height: 8),
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: colors.tint(colors.info, surface: colors.clayBg),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: colors.info),
                        ),
                        child: Row(
                          children: [
                            Icon(Icons.info_outline,
                                color: colors.info, size: 16),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                'Invites send automatically once you finish setup.',
                                style: TextStyle(
                                    fontSize: 12,
                                    color: scheme.onSurface,
                                    height: 1.4),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ],
                ],
              ),
            ),
          ),
          _Footer(
            dot: 0,
            active: widget.active,
            onDotTap: widget.onDotTap,
            cta: _searching
                ? _ActionButton(
                    label: widget.pendingInvites.isEmpty
                        ? 'Next'
                        : 'Next — continue setup',
                    onTap: widget.onNext,
                  )
                : _ActionButton(
                    label: 'Find my friends',
                    icon: Icons.search,
                    onTap: () => setState(() => _searching = true),
                  ),
          ),
        ],
      ),
    );
  }
}

class _UserResultTile extends StatelessWidget {
  final Map<String, dynamic> user;
  final bool isInvited;
  final VoidCallback onInvite;
  final VoidCallback onRemove;

  const _UserResultTile({
    required this.user,
    required this.isInvited,
    required this.onInvite,
    required this.onRemove,
  });

  static const _avatarEmojis = {
    'lion': '🦁', 'bear': '🐻', 'eagle': '🦅',
    'shark': '🦈', 'wolf': '🐺', 'gorilla': '🦍',
    'tiger': '🐯', 'buffalo': '🦬', 'robot': '🤖',
    'flexed': '💪', 'weightlifter': '🏋️', 'runner': '🏃',
  };

  @override
  Widget build(BuildContext context) {
    final emoji = _avatarEmojis[user['avatar_id']] ?? '🦁';
    final colors = AppColors.of(context);
    final scheme = Theme.of(context).colorScheme;
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding:
          const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: colors.clayBg,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: colors.divider),
      ),
      child: Row(
        children: [
          Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(
                color: colors.tint(scheme.primary, surface: colors.clayBg),
                shape: BoxShape.circle),
            child: Center(
                child:
                    Text(emoji, style: const TextStyle(fontSize: 20))),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(user['display_name'] ?? '',
                    style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: scheme.onSurface)),
                Text('@${user['username'] ?? ''}',
                    style: TextStyle(fontSize: 12, color: colors.inkMuted)),
              ],
            ),
          ),
          GestureDetector(
            onTap: isInvited ? onRemove : onInvite,
            child: Container(
              padding: const EdgeInsets.symmetric(
                  horizontal: 14, vertical: 6),
              decoration: BoxDecoration(
                color: isInvited
                    ? colors.tint(colors.success, surface: colors.clayBg)
                    : colors.streakOrange,
                borderRadius: BorderRadius.circular(8),
                border: isInvited ? Border.all(color: colors.success) : null,
              ),
              child: Text(
                isInvited ? 'Invited' : 'Invite',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: isInvited
                      ? colors.success
                      : colors.readableForeground(colors.streakOrange),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _InvitedTile extends StatelessWidget {
  final Map<String, dynamic> user;
  final VoidCallback onRemove;

  const _InvitedTile({required this.user, required this.onRemove});

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      padding:
          const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: colors.tint(colors.success, surface: colors.clayBg),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: colors.success),
      ),
      child: Row(
        children: [
          Icon(Icons.check_circle, color: colors.success, size: 16),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              '${user['display_name']} · @${user['username']}',
              style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w500,
                  color: Theme.of(context).colorScheme.onSurface),
            ),
          ),
          GestureDetector(
            onTap: onRemove,
            child: Icon(Icons.close, size: 16, color: colors.inkMuted),
          ),
        ],
      ),
    );
  }
}

// ── Slide 2 — Build your streak ────────────────────────────────────────────
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
