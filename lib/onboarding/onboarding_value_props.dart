import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'onboarding_theme.dart';
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

  void _goToSignUp() {
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(
        builder: (_) =>
            SignUpScreen(pendingInvites: List.from(_pendingInvites)),
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
          ),
          _Slide2(onNext: _next, onSkip: _skip),
          _Slide3(onNext: _goToSignUp, onSkip: _goToSignUp),
        ],
      ),
    );
  }
}

// ── Fixed-height gradient band used on all value prop screens ─────────────

class _GradBand extends StatelessWidget {
  final Widget illustration;
  final Widget? topRow;
  final Widget? bottomRow;

  const _GradBand({
    required this.illustration,
    this.topRow,
    this.bottomRow,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(gradient: kGradientDiag),
      child: SafeArea(
        bottom: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (topRow != null) topRow!,
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 20),
              child: illustration,
            ),
            if (bottomRow != null)
              Padding(
                padding: const EdgeInsets.only(bottom: 16),
                child: bottomRow!,
              ),
          ],
        ),
      ),
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

  const _Slide1({
    required this.pendingInvites,
    required this.onInvite,
    required this.onRemove,
    required this.onNext,
    required this.onSkip,
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
      final res = await Supabase.instance.client
          .from('user_profiles')
          .select('id, username, display_name, avatar_id')
          .ilike('username', '%$clean%')
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
    return Column(
      children: [
        // Gradient band — SafeArea + intrinsic height
        Container(
          decoration: const BoxDecoration(gradient: kGradientDiag),
          child: SafeArea(
            bottom: false,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Top row: back (when searching) + skip
                Padding(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 8, vertical: 4),
                  child: Row(
                    children: [
                      if (_searching)
                        GestureDetector(
                          onTap: () => setState(() {
                            _searching = false;
                            _results = [];
                            _searchCtrl.clear();
                          }),
                          child: Container(
                            width: 32,
                            height: 32,
                            decoration: BoxDecoration(
                              color: Colors.white.withOpacity(0.2),
                              shape: BoxShape.circle,
                            ),
                            child: const Icon(Icons.arrow_back,
                                color: Colors.white, size: 16),
                          ),
                        )
                      else
                        const SizedBox(width: 32),
                      const Spacer(),
                      TextButton(
                        onPressed: widget.onSkip,
                        child: const Text('Skip',
                            style: TextStyle(
                                color: Colors.white70,
                                fontSize: 14,
                                fontWeight: FontWeight.w500)),
                      ),
                    ],
                  ),
                ),
                // Search field or illustration
                _searching
                    ? Padding(
                        padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
                        child: Container(
                          height: 40,
                          decoration: BoxDecoration(
                            color: Colors.white.withOpacity(0.95),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: TextField(
                            controller: _searchCtrl,
                            autofocus: true,
                            style: const TextStyle(
                                fontSize: 14,
                                color: Color(0xFF1E293B)),
                            decoration: InputDecoration(
                              hintText: 'Search by username...',
                              hintStyle: TextStyle(
                                  color: Colors.grey[400], fontSize: 14),
                              prefixIcon: const Icon(Icons.search,
                                  color: Colors.grey, size: 18),
                              border: InputBorder.none,
                              contentPadding:
                                  const EdgeInsets.symmetric(vertical: 10),
                              suffixIcon: _isSearching
                                  ? const Padding(
                                      padding: EdgeInsets.all(10),
                                      child: SizedBox(
                                          width: 18,
                                          height: 18,
                                          child: CircularProgressIndicator(
                                              strokeWidth: 2,
                                              color: kObBlue)))
                                  : null,
                            ),
                            onChanged: (v) {
                              Future.delayed(
                                  const Duration(milliseconds: 400), () {
                                if (_searchCtrl.text == v && mounted) {
                                  _search(v);
                                }
                              });
                            },
                          ),
                        ),
                      )
                    : Padding(
                        padding: const EdgeInsets.only(bottom: 20),
                        child: Column(
                          children: [
                            Container(
                              width: 72,
                              height: 72,
                              decoration: BoxDecoration(
                                color: Colors.white.withOpacity(0.2),
                                shape: BoxShape.circle,
                              ),
                              child: const Center(
                                child: Icon(Icons.people_outline,
                                    color: Colors.white, size: 38),
                              ),
                            ),
                            const SizedBox(height: 12),
                            ObProgressDots(count: 3, active: 0),
                          ],
                        ),
                      ),
              ],
            ),
          ),
        ),

        // Body
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(24, 20, 24, 24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Find your buddy',
                    style: TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.w700,
                        color: Color(0xFF1E293B))),
                const SizedBox(height: 8),
                Text(
                  'Connect with friends already on Gym Buddy and start building streaks from day one.',
                  style: TextStyle(
                      fontSize: 14,
                      color: Colors.grey[600],
                      height: 1.5),
                ),
                const SizedBox(height: 20),

                if (!_searching) ...[
                  ObGradientButton(
                    label: 'Find my friends',
                    icon: Icons.search,
                    onTap: () =>
                        setState(() => _searching = true),
                  ),
                  const SizedBox(height: 10),
                  ObGhostButton(
                      label: 'Skip for now',
                      onTap: widget.onSkip),
                ] else ...[
                  if (_results.isNotEmpty) ...[
                    Text('Results',
                        style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: Colors.grey[500])),
                    const SizedBox(height: 8),
                    ..._results
                        .map((u) => _UserResultTile(
                              user: u,
                              isInvited: widget.pendingInvites
                                  .any((p) => p['id'] == u['id']),
                              onInvite: () =>
                                  widget.onInvite(u),
                              onRemove: () => widget
                                  .onRemove(u['id']),
                            ))
                        .toList(),
                  ] else if (_searchCtrl.text.isNotEmpty &&
                      !_isSearching)
                    Center(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                            vertical: 20),
                        child: Text('No users found',
                            style: TextStyle(
                                color: Colors.grey[400],
                                fontSize: 14)),
                      ),
                    ),

                  if (widget.pendingInvites.isNotEmpty) ...[
                    const SizedBox(height: 16),
                    Text(
                        'Invited (${widget.pendingInvites.length})',
                        style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: Colors.grey[500])),
                    const SizedBox(height: 8),
                    ...widget.pendingInvites
                        .map((u) => _InvitedTile(
                              user: u,
                              onRemove: () => widget
                                  .onRemove(u['id']),
                            ))
                        .toList(),
                    const SizedBox(height: 8),
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: const Color(0xFFEFF6FF),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                            color: const Color(0xFFBFDBFE)),
                      ),
                      child: const Row(
                        children: [
                          Icon(Icons.info_outline,
                              color: kObBlue, size: 16),
                          SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              'Invites send automatically once you finish setup.',
                              style: TextStyle(
                                  fontSize: 12,
                                  color: Color(0xFF1D4ED8),
                                  height: 1.4),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],

                  const SizedBox(height: 20),
                  ObGradientButton(
                    label: widget.pendingInvites.isEmpty
                        ? 'Next'
                        : 'Next — continue setup',
                    onTap: widget.onNext,
                  ),
                ],
              ],
            ),
          ),
        ),
      ],
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
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding:
          const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      child: Row(
        children: [
          Container(
            width: 38,
            height: 38,
            decoration: const BoxDecoration(
                color: Color(0xFFEFF6FF), shape: BoxShape.circle),
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
                    style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: Color(0xFF1E293B))),
                Text('@${user['username'] ?? ''}',
                    style: TextStyle(
                        fontSize: 12, color: Colors.grey[500])),
              ],
            ),
          ),
          GestureDetector(
            onTap: isInvited ? onRemove : onInvite,
            child: Container(
              padding: const EdgeInsets.symmetric(
                  horizontal: 14, vertical: 6),
              decoration: BoxDecoration(
                gradient: isInvited ? null : kGradient,
                color: isInvited
                    ? const Color(0xFFDCFCE7)
                    : null,
                borderRadius: BorderRadius.circular(8),
                border: isInvited
                    ? Border.all(color: const Color(0xFF86EFAC))
                    : null,
              ),
              child: Text(
                isInvited ? 'Invited' : 'Invite',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: isInvited
                      ? const Color(0xFF166534)
                      : Colors.white,
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
    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      padding:
          const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: const Color(0xFFF0FDF4),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: const Color(0xFF86EFAC)),
      ),
      child: Row(
        children: [
          const Icon(Icons.check_circle,
              color: Color(0xFF10B981), size: 16),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              '${user['display_name']} · @${user['username']}',
              style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w500,
                  color: Color(0xFF065F46)),
            ),
          ),
          GestureDetector(
            onTap: onRemove,
            child: Icon(Icons.close, size: 16, color: Colors.grey[400]),
          ),
        ],
      ),
    );
  }
}

// ── Slide 2 — Build your streak ────────────────────────────────────────────
class _Slide2 extends StatelessWidget {
  final VoidCallback onNext;
  final VoidCallback onSkip;
  const _Slide2({required this.onNext, required this.onSkip});

  @override
  Widget build(BuildContext context) {
    return _ValuePropLayout(
      dot: 1,
      onSkip: onSkip,
      illustration: Container(
        width: 72,
        height: 72,
        decoration: BoxDecoration(
          color: Colors.white.withOpacity(0.2),
          shape: BoxShape.circle,
        ),
        child: const Center(
          child: Icon(Icons.local_fire_department,
              color: Colors.white, size: 38),
        ),
      ),
      title: 'Build your streak',
      body:
          'Your streak only counts when you and your partner both check in. Real accountability — not just a number.',
      onNext: onNext,
    );
  }
}

// ── Slide 3 — Meet Coach Max ───────────────────────────────────────────────
class _Slide3 extends StatelessWidget {
  final VoidCallback onNext;
  final VoidCallback onSkip;
  const _Slide3({required this.onNext, required this.onSkip});

  @override
  Widget build(BuildContext context) {
    return _ValuePropLayout(
      dot: 2,
      onSkip: onSkip,
      illustration: Container(
        width: 72,
        height: 72,
        decoration: BoxDecoration(
          color: Colors.white.withOpacity(0.2),
          shape: BoxShape.circle,
        ),
        child: const Center(
          child: Text('🤖', style: TextStyle(fontSize: 38)),
        ),
      ),
      title: 'Meet Coach Max',
      body:
          'No buddy? No problem. Coach Max keeps your streak alive, checks in automatically, and never lets you down.',
      ctaLabel: "Let's go",
      onNext: onNext,
    );
  }
}

// ── Shared value prop layout ───────────────────────────────────────────────
class _ValuePropLayout extends StatelessWidget {
  final int dot;
  final VoidCallback onSkip;
  final Widget illustration;
  final String title;
  final String body;
  final String? ctaLabel;
  final VoidCallback onNext;

  const _ValuePropLayout({
    required this.dot,
    required this.onSkip,
    required this.illustration,
    required this.title,
    required this.body,
    this.ctaLabel,
    required this.onNext,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        _GradBand(
          illustration: illustration,
          topRow: Padding(
            padding:
                const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            child: Align(
              alignment: Alignment.centerRight,
              child: TextButton(
                onPressed: onSkip,
                child: const Text('Skip',
                    style: TextStyle(
                        color: Colors.white70,
                        fontSize: 14,
                        fontWeight: FontWeight.w500)),
              ),
            ),
          ),
          bottomRow: ObProgressDots(count: 3, active: dot),
        ),
        Expanded(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(24, 24, 24, 32),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title,
                    style: const TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.w700,
                        color: Color(0xFF1E293B))),
                const SizedBox(height: 10),
                Text(body,
                    style: TextStyle(
                        fontSize: 14,
                        color: Colors.grey[600],
                        height: 1.6)),
                const Spacer(),
                ObGradientButton(
                  label: ctaLabel ?? 'Next',
                  onTap: onNext,
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}