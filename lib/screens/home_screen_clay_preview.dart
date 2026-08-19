// lib/screens/home_screen_clay_preview.dart
//
// TEMPORARY visual preview — 100% claymorphism, static dummy data.
// No Supabase, no streak logic, no services. Nothing here is wired.
//
// To strip: delete this file + the "CLAY PREVIEW" block in lib/home_screen.dart.

import 'package:flutter/material.dart';
import '../theme/app_theme.dart';

/// Brand gradient. Fixed per CLAUDE.md and deliberately NOT an AppColors
/// token — it is already hardcoded the same way in custom_streak_selector,
/// profile_view_dialog, workout_card and home_screen. Coach Max's identity
/// depends on it, so the preview matches the rest of the app.
const _brandGradient = [Color(0xFF1D4ED8), Color(0xFF7C3AED)];

enum _BuddyKind { coach, star, done }

class _Buddy {
  final String name;
  final String glyph;
  final _BuddyKind kind;
  const _Buddy(this.name, this.glyph, this.kind);
}

// Friends only — none of these is the current user. No "YOU" anywhere.
const _buddies = <_Buddy>[
  _Buddy('Coach Max', '🤖', _BuddyKind.coach),
  _Buddy('Sofia', 'S', _BuddyKind.star),
  _Buddy('Marcus', 'M', _BuddyKind.done),
];

class HomeScreenClayPreview extends StatefulWidget {
  const HomeScreenClayPreview({super.key});

  @override
  State<HomeScreenClayPreview> createState() => _HomeScreenClayPreviewState();
}

class _HomeScreenClayPreviewState extends State<HomeScreenClayPreview> {
  final _wheel = PageController(viewportFraction: 0.6, initialPage: 1);
  bool _starred = false;

  @override
  void dispose() {
    _wheel.dispose();
    super.dispose();
  }

  /// 0.0 = centered/focused, 1.0 = fully peeked at the edge.
  double _distance(int i) {
    var page = _wheel.initialPage.toDouble();
    if (_wheel.hasClients && _wheel.position.haveDimensions) {
      page = _wheel.page ?? page;
    }
    return (page - i).abs().clamp(0.0, 1.0);
  }

  /// Mirrors AppColors.actionGradient's formula for the non-orange tokens,
  /// so every clay gradient is derived, never a second hardcoded colour.
  List<Color> _grad(Color base) => [Color.lerp(base, Colors.white, 0.15)!, base];

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);

    return Scaffold(
      backgroundColor: c.clayBg,
      body: SafeArea(
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // 1 ── header ────────────────────────────────────────────
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 14, 20, 16),
                child: Row(
                  children: [
                    Icon(Icons.nightlight_round, color: c.inkMuted, size: 22),
                    const SizedBox(width: 10),
                    Text(
                      'Good Night',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 22,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const Spacer(),
                    _clayCircleButton(
                      c,
                      size: 46,
                      child: Icon(Icons.notifications_none_rounded,
                          color: Colors.white, size: 22),
                    ),
                  ],
                ),
              ),

              // 2 ── hairline divider ──────────────────────────────────
              Container(height: 1, color: c.clayShadowLight),

              // 3 ── warn chip, right-aligned under the bell ───────────
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 14, 20, 0),
                child: Align(
                  alignment: Alignment.centerRight,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 15, vertical: 8),
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: _grad(c.warn),
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                      borderRadius: BorderRadius.circular(999),
                      boxShadow: c.clayShadow(),
                    ),
                    child: Text(
                      '⚠ 0/2',
                      style: TextStyle(
                        color: c.clayBg,
                        fontSize: 13,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                ),
              ),

              // 4 ── section label ─────────────────────────────────────
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 20, 20, 16),
                child: Text(
                  'INVITE A BUDDY TO WORKOUT',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: c.inkMuted,
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 1.5,
                  ),
                ),
              ),

              // 5 ── buddy wheel: centre focus, sides peek ─────────────
              SizedBox(
                height: 182,
                child: PageView.builder(
                  controller: _wheel,
                  itemCount: _buddies.length,
                  itemBuilder: (context, i) => AnimatedBuilder(
                    animation: _wheel,
                    builder: (context, _) =>
                        Center(child: _avatar(c, _buddies[i], _distance(i))),
                  ),
                ),
              ),

              // 6 ── swipe hint ────────────────────────────────────────
              Opacity(
                opacity: 0.6,
                child: Padding(
                  padding: const EdgeInsets.only(top: 10, bottom: 26),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.chevron_left_rounded,
                          size: 18, color: c.inkMuted),
                      const SizedBox(width: 6),
                      Text(
                        'swipe to pick a buddy',
                        style: TextStyle(color: c.inkMuted, fontSize: 12),
                      ),
                      const SizedBox(width: 6),
                      Icon(Icons.chevron_right_rounded,
                          size: 18, color: c.inkMuted),
                    ],
                  ),
                ),
              ),

              // 7 ── check-in card ─────────────────────────────────────
              _checkInCard(c),

              const SizedBox(height: 18),

              // 8 ── Coach Max tip card ────────────────────────────────
              _coachTipCard(c),

              // 9 ── stats row intentionally cut (lives in profile).
              // 10 ── "Active Streaks" entry point intentionally absent.
              const SizedBox(height: 32),
            ],
          ),
        ),
      ),
    );
  }

  // ── pieces ────────────────────────────────────────────────────────

  Widget _clayCircleButton(AppColors c, {required double size, required Widget child}) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: LinearGradient(
          colors: [c.claySurfaceLight, c.claySurface],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        boxShadow: c.clayShadow(),
      ),
      child: Center(child: child),
    );
  }

  Widget _avatar(AppColors c, _Buddy b, double d) {
    final size = 108.0 - 32.0 * d;      // 108 focused → 76 peeked
    final focused = d < 0.5;

    return Opacity(
      opacity: 1.0 - 0.4 * d,            // 1.0 focused → 0.6 peeked
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            width: size + 18,
            height: size + 18,
            child: Stack(
              clipBehavior: Clip.none,
              alignment: Alignment.center,
              children: [
                Container(
                  width: size,
                  height: size,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: LinearGradient(
                      colors: b.kind == _BuddyKind.coach
                          ? _brandGradient
                          : [c.claySurfaceLight, c.claySurface],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                    // Focus ring only — not a structural border.
                    border: focused
                        ? Border.all(color: c.info, width: 3 * (1 - d * 2))
                        : null,
                    boxShadow: c.clayShadow(),
                  ),
                  child: Center(
                    child: Text(
                      b.glyph,
                      style: TextStyle(
                        fontSize: size * 0.33,
                        fontWeight: FontWeight.w800,
                        color: Colors.white,
                      ),
                    ),
                  ),
                ),
                if (b.kind == _BuddyKind.coach)
                  Positioned(bottom: 0, child: _aiTag(c)),
                if (b.kind == _BuddyKind.star)
                  Positioned(top: 0, right: 0, child: _starBadge(c)),
                if (b.kind == _BuddyKind.done)
                  Positioned(top: 0, right: 0, child: _doneBadge(c)),
              ],
            ),
          ),
          const SizedBox(height: 10),
          Text(
            b.name,
            style: TextStyle(
              color: Colors.white,
              fontSize: 14,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }

  Widget _aiTag(AppColors c) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: _brandGradient,
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          borderRadius: BorderRadius.circular(999),
          boxShadow: c.clayShadow(),
        ),
        child: Text(
          'AI',
          style: TextStyle(
            color: Colors.white,
            fontSize: 10,
            fontWeight: FontWeight.w800,
            letterSpacing: 0.8,
          ),
        ),
      );

  Widget _starBadge(AppColors c) => GestureDetector(
        onTap: () => setState(() => _starred = !_starred),
        child: Container(
          width: 32,
          height: 32,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            gradient: LinearGradient(
              colors: _starred
                  ? _grad(c.warn)
                  : [c.claySurfaceLight, c.claySurface],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            boxShadow: c.clayShadow(inset: _starred),
          ),
          child: Icon(
            _starred ? Icons.star_rounded : Icons.star_border_rounded,
            size: 18,
            color: _starred ? c.clayBg : c.inkMuted,
          ),
        ),
      );

  Widget _doneBadge(AppColors c) => Container(
        width: 30,
        height: 30,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          gradient: LinearGradient(
            colors: _grad(c.success),
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          boxShadow: c.clayShadow(),
        ),
        child: Icon(Icons.check_rounded, size: 17, color: c.clayBg),
      );

  Widget _checkInCard(AppColors c) => Container(
        margin: const EdgeInsets.symmetric(horizontal: 20),
        padding: const EdgeInsets.fromLTRB(22, 24, 22, 20),
        decoration: BoxDecoration(
          color: c.claySurface,
          borderRadius: BorderRadius.circular(26),
          boxShadow: c.clayShadow(),
        ),
        child: Column(
          children: [
            Text(
              'CARLOS',
              style: TextStyle(
                color: c.inkMuted,
                fontSize: 12,
                fontWeight: FontWeight.w700,
                letterSpacing: 1.6,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              '0 DAY STREAK',
              style: TextStyle(
                color: Colors.white,
                fontSize: 30,
                fontWeight: FontWeight.w800,
                letterSpacing: 0.5,
              ),
            ),
            const SizedBox(height: 10),
            Text(
              '🔥 Sofia already checked in — keep pace',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: c.streakOrange, // actionGradient's base stop
                fontSize: 12.5,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 20),
            Container(
              width: double.infinity,
              height: 58,
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: c.actionGradient,
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius: BorderRadius.circular(19),
                boxShadow: c.clayShadow(),
              ),
              child: Center(
                child: Text(
                  '🔥 Check In',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 17,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 16),
            Text(
              '🌙 Take a break day',
              style: TextStyle(
                color: c.inkMuted,
                fontSize: 13,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      );

  Widget _coachTipCard(AppColors c) => Container(
        margin: const EdgeInsets.symmetric(horizontal: 20),
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: c.claySurface,
          borderRadius: BorderRadius.circular(26),
          boxShadow: c.clayShadow(),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 46,
                  height: 46,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: LinearGradient(
                      colors: _brandGradient,
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                    boxShadow: c.clayShadow(),
                  ),
                  child: Center(
                    child: Text('🤖', style: TextStyle(fontSize: 20)),
                  ),
                ),
                const SizedBox(width: 14),
                Text(
                  'Coach Max',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(width: 10),
                Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 12, vertical: 5),
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: _grad(c.info),
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                    borderRadius: BorderRadius.circular(999),
                    boxShadow: c.clayShadow(),
                  ),
                  child: Text(
                    'Mindset',
                    style: TextStyle(
                      color: c.clayBg,
                      fontSize: 11,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Text(
              'Streaks are built one honest day at a time. You do not need a '
              'perfect week — you need to show up tomorrow.',
              style: TextStyle(
                color: c.inkMuted,
                fontSize: 13.5,
                height: 1.55,
              ),
            ),
          ],
        ),
      );
}
