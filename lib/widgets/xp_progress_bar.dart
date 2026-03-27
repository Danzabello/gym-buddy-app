import 'package:flutter/material.dart';
import '../services/level_service.dart';



/// Standalone XP progress bar — drop anywhere in the profile page.
/// Fetches its own data via LevelService so no plumbing needed at the call site.
class XpProgressBar extends StatefulWidget {
  /// Pass a pre-loaded [LevelInfo] to avoid an extra fetch (e.g. when the
  /// parent already has it). Leave null to let the widget fetch itself.
  final LevelInfo? levelInfo;

  const XpProgressBar({super.key, this.levelInfo});

  @override
  State<XpProgressBar> createState() => _XpProgressBarState();
}

class _XpProgressBarState extends State<XpProgressBar>
    with SingleTickerProviderStateMixin {
  LevelInfo? _info;
  bool _loading = true;

  late final AnimationController _barController;
  late final Animation<double> _barAnim;

  @override
  void initState() {
    super.initState();
    _barController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    );
    _barAnim = CurvedAnimation(
      parent: _barController,
      curve: Curves.easeOutCubic,
    );

    if (widget.levelInfo != null) {
      _info = widget.levelInfo;
      _loading = false;
      _barController.animateTo(widget.levelInfo!.progressPercent);
    } else {
      _loadInfo();
    }
  }

  Future<void> _loadInfo() async {
    final info = await LevelService().getLevelInfo();
    if (mounted) {
      setState(() {
        _info = info;
        _loading = false;
      });
      if (info != null) {
        _barController.animateTo(info.progressPercent);
      }
    }
  }

  @override
  void dispose() {
    _barController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return _buildSkeleton();
    }
    if (_info == null) return const SizedBox.shrink();

    final info = _info!;
    final isMaxLevel = info.level >= 99;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.grey.shade100),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.04),
            blurRadius: 12,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── Level badge + title row ─────────────────────────────
          Row(
            children: [
              _LevelBadge(level: info.level),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      info.title,
                      style: const TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.w700,
                        color: Color(0xFF1A1A2E),
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      isMaxLevel
                          ? 'Max level reached 🏆'
                          : '${info.xpNeededForNext} XP to level ${info.level + 1}',
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.grey[500],
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ),
              // Total XP chip
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                decoration: BoxDecoration(
                  color: const Color(0xFFEEEDFE),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  '${info.currentXp} XP',
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: Color(0xFF534AB7),
                  ),
                ),
              ),
            ],
          ),

          const SizedBox(height: 14),

          // ── Animated progress bar ───────────────────────────────
          ClipRRect(
            borderRadius: BorderRadius.circular(100),
            child: AnimatedBuilder(
              animation: _barAnim,
              builder: (_, __) => LinearProgressIndicator(
                value: isMaxLevel
                    ? 1.0
                    : _barAnim.value * info.progressPercent,
                minHeight: 10,
                backgroundColor: Colors.grey.shade100,
                valueColor: AlwaysStoppedAnimation<Color>(
                  _barColor(info.level),
                ),
              ),
            ),
          ),

          const SizedBox(height: 8),

          // ── XP sub-label ────────────────────────────────────────
          if (!isMaxLevel)
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  '${info.xpIntoCurrentLevel} / ${info.xpForNextLevel - info.xpForThisLevel} XP',
                  style: TextStyle(fontSize: 11, color: Colors.grey[400]),
                ),
                Text(
                  '${(info.progressPercent * 100).toStringAsFixed(0)}%',
                  style: TextStyle(fontSize: 11, color: Colors.grey[400]),
                ),
              ],
            ),
        ],
      ),
    );
  }

  /// Bar colour ramps through the level tiers.
  Color _barColor(int level) {
    if (level >= 91) return const Color(0xFF7F77DD); // purple — Gym Pro
    if (level >= 76) return const Color(0xFFD85A30); // coral — Champion
    if (level >= 56) return const Color(0xFFD4537E); // pink — Legend/Elite
    if (level >= 46) return const Color(0xFFBA7517); // amber — Beast
    if (level >= 26) return const Color(0xFF1D9E75); // teal — Warrior/Iron
    if (level >= 11) return const Color(0xFF378ADD); // blue — Rookie/Athlete
    return const Color(0xFF888780);                  // gray — Newcomer/Beginner
  }

  Widget _buildSkeleton() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.grey.shade100),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: Colors.grey.shade100,
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                        height: 14,
                        width: 100,
                        decoration: BoxDecoration(
                          color: Colors.grey.shade100,
                          borderRadius: BorderRadius.circular(6),
                        )),
                    const SizedBox(height: 6),
                    Container(
                        height: 10,
                        width: 140,
                        decoration: BoxDecoration(
                          color: Colors.grey.shade100,
                          borderRadius: BorderRadius.circular(6),
                        )),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Container(
            height: 10,
            decoration: BoxDecoration(
              color: Colors.grey.shade100,
              borderRadius: BorderRadius.circular(100),
            ),
          ),
        ],
      ),
    );
  }
}

// ── Level badge circle ──────────────────────────────────────────────────────
class _LevelBadge extends StatelessWidget {
  final int level;
  const _LevelBadge({required this.level});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 44,
      height: 44,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: LinearGradient(
          colors: _gradientColors(level),
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        boxShadow: [
          BoxShadow(
            color: _gradientColors(level).last.withOpacity(0.35),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Center(
        child: Text(
          '$level',
          style: const TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w800,
            color: Colors.white,
          ),
        ),
      ),
    );
  }

  List<Color> _gradientColors(int level) {
    if (level >= 91) return [const Color(0xFF7F77DD), const Color(0xFF534AB7)];
    if (level >= 76) return [const Color(0xFFD85A30), const Color(0xFF993C1D)];
    if (level >= 56) return [const Color(0xFFD4537E), const Color(0xFF993556)];
    if (level >= 46) return [const Color(0xFFEF9F27), const Color(0xFFBA7517)];
    if (level >= 26) return [const Color(0xFF1D9E75), const Color(0xFF0F6E56)];
    if (level >= 11) return [const Color(0xFF378ADD), const Color(0xFF185FA5)];
    return [const Color(0xFF888780), const Color(0xFF5F5E5A)];
  }
}