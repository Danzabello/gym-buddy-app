// lib/pages/achievements_page.dart
import 'package:flutter/material.dart';
import '../services/achievement_service.dart';
import '../services/level_service.dart';
import '../theme/app_theme.dart';

class AchievementsPage extends StatefulWidget {
  const AchievementsPage({super.key});

  @override
  State<AchievementsPage> createState() => _AchievementsPageState();
}

class _AchievementsPageState extends State<AchievementsPage>
    with SingleTickerProviderStateMixin {
  final AchievementService _achievementService = AchievementService();
  final LevelService _levelService = LevelService();

  List<Achievement> _all = [];
  LevelInfo? _levelInfo;
  bool _isLoading = true;

  late AnimationController _fadeController;
  late Animation<double> _fadeAnimation;

  static const _categoryMeta = {
    'streak':    ('🔥', 'Streak'),
    'workout':   ('💪', 'Workout'),
    'coop':      ('🤝', 'Co-op'),
    'social':    ('👥', 'Social'),
    'milestone': ('🏅', 'Milestone'),
    'prestige':  ('💎', 'Prestige'),
    'loyalty':   ('🛡️', 'Loyalty'),
    'fun':       ('🎲', 'Fun'),
  };

  @override
  void initState() {
    super.initState();
    _fadeController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 450),
    );
    _fadeAnimation = CurvedAnimation(
      parent: _fadeController,
      curve: Curves.easeOut,
    );
    _load();
  }

  @override
  void dispose() {
    _fadeController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() => _isLoading = true);
    final results = await Future.wait([
      _achievementService.getAll(),
      _levelService.getLevelInfo(),
    ]);
    if (!mounted) return;
    setState(() {
      _all = results[0] as List<Achievement>;
      _levelInfo = results[1] as LevelInfo?;
      _isLoading = false;
    });
    _fadeController.forward(from: 0);
  }

  // ── Buckets ────────────────────────────────────────────────
  List<Achievement> get _inProgress =>
      _all.where((a) => !a.isUnlocked && a.hasProgress).toList()
        ..sort((a, b) => b.progressPercent.compareTo(a.progressPercent));

  List<Achievement> get _locked =>
      _all.where((a) => !a.isUnlocked && !a.hasProgress).toList();

  List<Achievement> get _completed =>
      _all.where((a) => a.isUnlocked).toList()
        ..sort((a, b) => (b.unlockedAt ?? DateTime(0))
            .compareTo(a.unlockedAt ?? DateTime(0)));

  int get _totalUnlocked => _completed.length;
  int get _totalXpEarned =>
      _completed.fold(0, (s, a) => s + a.xpReward);
  int get _totalCoinsEarned =>
      _completed.fold(0, (s, a) => s + a.coinReward);
  double get _overallPct =>
      _all.isEmpty ? 0.0 : _totalUnlocked / _all.length;

  // ── Colours ────────────────────────────────────────────────
  Color _rarityColor(String rarity) {
    switch (rarity) {
      case 'uncommon':  return const Color(0xFF10B981);
      case 'rare':      return const Color(0xFF3B82F6);
      case 'epic':      return const Color(0xFF7C3AED);
      case 'legendary': return const Color(0xFFD97706);
      default:          return const Color(0xFF6B7280);
    }
  }

  Color _rarityBg(String rarity) =>
      _rarityColor(rarity).withOpacity(0.13);

  Color _categoryAccent(String category) {
    switch (category) {
      case 'streak':    return const Color(0xFFF97316);
      case 'workout':   return const Color(0xFF3B82F6);
      case 'coop':      return const Color(0xFF10B981);
      case 'social':    return const Color(0xFFA855F7);
      case 'milestone': return const Color(0xFF14B8A6);
      case 'prestige':  return const Color(0xFFEC4899);
      case 'loyalty':   return const Color(0xFFEF4444);
      case 'fun':       return const Color(0xFFEAB308);
      default:          return const Color(0xFF6B7280);
    }
  }

  Map<String, int> get _categoryUnlockCounts {
    final counts = <String, int>{};
    for (final a in _completed) {
      counts[a.category] = (counts[a.category] ?? 0) + 1;
    }
    return counts;
  }

  // ══════════════════════════════════════════════════════════════
  // TAP SHEETS
  // ══════════════════════════════════════════════════════════════

  void _showOverallSheet(BuildContext context) {
    final appColors = AppColors.of(context);
    final cs = Theme.of(context).colorScheme;
    final pct = _overallPct;
    final remaining = _all.length - _totalUnlocked;
    final inProgressCount = _inProgress.length;
    final lockedCount = _locked.length;

    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (_) => _Sheet(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _SheetHeader(
              icon: '📊',
              title: 'Overall progress',
              subtitle: '$_totalUnlocked of ${_all.length} achievements',
              appColors: appColors,
              cs: cs,
            ),
            const SizedBox(height: 20),
            // Big progress ring (linear here, clean)
            ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: LinearProgressIndicator(
                value: pct,
                minHeight: 10,
                backgroundColor: appColors.divider,
                valueColor: const AlwaysStoppedAnimation(Color(0xFF3B82F6)),
              ),
            ),
            const SizedBox(height: 8),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text('0', style: TextStyle(fontSize: 10, color: appColors.subtleText)),
                Text('${(pct * 100).round()}% complete',
                    style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.w700,
                        color: cs.onSurface)),
                Text('${_all.length}',
                    style: TextStyle(fontSize: 10, color: appColors.subtleText)),
              ],
            ),
            const SizedBox(height: 24),
            // Breakdown rows
            _SheetStatRow(label: 'Completed', value: '$_totalUnlocked',
                color: const Color(0xFF10B981), appColors: appColors, cs: cs),
            const SizedBox(height: 10),
            _SheetStatRow(label: 'In progress', value: '$inProgressCount',
                color: const Color(0xFFF97316), appColors: appColors, cs: cs),
            const SizedBox(height: 10),
            _SheetStatRow(label: 'Locked', value: '$lockedCount',
                color: appColors.subtleText, appColors: appColors, cs: cs),
            const SizedBox(height: 10),
            _SheetStatRow(label: 'Still to unlock', value: '$remaining',
                color: const Color(0xFF3B82F6), appColors: appColors, cs: cs),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  void _showStreakSheet(BuildContext context) {
    final appColors = AppColors.of(context);
    final cs = Theme.of(context).colorScheme;
    final streakAchs = _all
        .where((a) => a.category == 'streak')
        .toList()
      ..sort((a, b) => a.targetValue.compareTo(b.targetValue));
    final bestCompleted = _completed
        .where((a) => a.category == 'streak')
        .toList()
      ..sort((a, b) => b.targetValue.compareTo(a.targetValue));
    final bestDays =
        bestCompleted.isNotEmpty ? bestCompleted.first.targetValue : 0;

    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (_) => _Sheet(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _SheetHeader(
              icon: '🔥',
              title: 'Streak milestones',
              subtitle: 'Best: $bestDays days in a row',
              appColors: appColors,
              cs: cs,
            ),
            const SizedBox(height: 16),
            Text('Streak achievements',
                style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    color: appColors.subtleText,
                    letterSpacing: 0.5)),
            const SizedBox(height: 10),
            ...streakAchs.map((a) {
              final done = a.isUnlocked;
              final inProg = !done && a.hasProgress;
              return Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Row(
                  children: [
                    Container(
                      width: 28,
                      height: 28,
                      decoration: BoxDecoration(
                        color: done
                            ? const Color(0xFFF97316).withOpacity(0.15)
                            : appColors.sectionBackground,
                        shape: BoxShape.circle,
                      ),
                      child: Icon(
                        done ? Icons.check : Icons.lock_outline,
                        size: 13,
                        color: done
                            ? const Color(0xFFF97316)
                            : appColors.subtleText,
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(a.name,
                              style: TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600,
                                  color: done
                                      ? cs.onSurface
                                      : appColors.subtleText)),
                          if (inProg) ...[
                            const SizedBox(height: 3),
                            ClipRRect(
                              borderRadius: BorderRadius.circular(2),
                              child: LinearProgressIndicator(
                                value: a.progressPercent,
                                minHeight: 3,
                                backgroundColor: appColors.divider,
                                valueColor: const AlwaysStoppedAnimation(
                                    Color(0xFFF97316)),
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      '${a.targetValue}d',
                      style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          color: done
                              ? const Color(0xFFF97316)
                              : appColors.subtleText),
                    ),
                  ],
                ),
              );
            }),
            const SizedBox(height: 4),
          ],
        ),
      ),
    );
  }

  void _showXpSheet(BuildContext context) {
    final appColors = AppColors.of(context);
    final cs = Theme.of(context).colorScheme;
    final li = _levelInfo;

    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (_) => _Sheet(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _SheetHeader(
              icon: '⚡',
              title: 'XP & level',
              subtitle: li != null ? '${li.title}' : 'Keep going!',
              appColors: appColors,
              cs: cs,
            ),
            const SizedBox(height: 20),
            if (li != null) ...[
              // Level progress bar
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: const Color(0xFF7C3AED),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text('Lv ${li.level}',
                        style: const TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w800,
                            color: Colors.white)),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(4),
                      child: LinearProgressIndicator(
                        value: li.progressPercent,
                        minHeight: 8,
                        backgroundColor: appColors.divider,
                        valueColor: const AlwaysStoppedAnimation(
                            Color(0xFF7C3AED)),
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: appColors.sectionBackground,
                      borderRadius: BorderRadius.circular(6),
                      border: Border.all(
                          color: appColors.cardBorder, width: 0.5),
                    ),
                    child: Text('Lv ${li.level + 1}',
                        style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w800,
                            color: appColors.subtleText)),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Center(
                child: Text(
                  '${li.xpIntoCurrentLevel} / ${li.xpForNextLevel - li.xpForThisLevel} XP  ·  ${li.xpNeededForNext} to next level',
                  style: TextStyle(
                      fontSize: 11, color: appColors.subtleText),
                ),
              ),
              const SizedBox(height: 24),
            ],
            Text('How to earn XP',
                style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    color: appColors.subtleText,
                    letterSpacing: 0.5)),
            const SizedBox(height: 10),
            _SheetStatRow(
                label: 'Daily check-in',
                value: '+10 XP',
                color: const Color(0xFF10B981),
                appColors: appColors,
                cs: cs),
            const SizedBox(height: 8),
            _SheetStatRow(
                label: 'Partner also checked in',
                value: '+5 XP',
                color: const Color(0xFF10B981),
                appColors: appColors,
                cs: cs),
            const SizedBox(height: 8),
            _SheetStatRow(
                label: 'Workout logged',
                value: '+15 XP',
                color: const Color(0xFF3B82F6),
                appColors: appColors,
                cs: cs),
            const SizedBox(height: 8),
            _SheetStatRow(
                label: '7-day streak milestone',
                value: '+50 XP',
                color: const Color(0xFFF97316),
                appColors: appColors,
                cs: cs),
            const SizedBox(height: 8),
            _SheetStatRow(
                label: '30-day streak milestone',
                value: '+50 XP',
                color: const Color(0xFFF97316),
                appColors: appColors,
                cs: cs),
            const SizedBox(height: 8),
            _SheetStatRow(
                label: 'Achievement unlocked',
                value: 'varies',
                color: const Color(0xFF7C3AED),
                appColors: appColors,
                cs: cs),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  void _showCoinsSheet(BuildContext context) {
    final appColors = AppColors.of(context);
    final cs = Theme.of(context).colorScheme;
    final topEarners = [..._completed]
      ..sort((a, b) => b.coinReward.compareTo(a.coinReward));
    final top5 = topEarners.take(5).toList();

    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (_) => _Sheet(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _SheetHeader(
              icon: '🪙',
              title: 'Coins',
              subtitle: '$_totalCoinsEarned earned from achievements',
              appColors: appColors,
              cs: cs,
            ),
            const SizedBox(height: 20),
            _SheetMiniCard(
              label: 'Earned from achievements',
              value: '$_totalCoinsEarned',
              color: const Color(0xFFFBBF24),
              appColors: appColors,
              cs: cs,
            ),
            if (top5.isNotEmpty) ...[
              const SizedBox(height: 24),
              Text('Top coin earners you\'ve unlocked',
                  style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      color: appColors.subtleText,
                      letterSpacing: 0.5)),
              const SizedBox(height: 10),
              ...top5.map((a) => Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Row(
                      children: [
                        Text(a.icon,
                            style: const TextStyle(fontSize: 20)),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(a.name,
                              style: TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600,
                                  color: cs.onSurface)),
                        ),
                        Text('+${a.coinReward} 🪙',
                            style: const TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w800,
                                color: Color(0xFFFBBF24))),
                      ],
                    ),
                  )),
            ] else ...[
              const SizedBox(height: 20),
              Center(
                child: Text('Unlock achievements to earn coins!',
                    style: TextStyle(
                        fontSize: 13, color: appColors.subtleText)),
              ),
            ],
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  // ══════════════════════════════════════════════════════════════
  // MAIN BUILD
  // ══════════════════════════════════════════════════════════════
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      body: SafeArea(
        child: _isLoading
            ? _buildSkeleton(context)
            : FadeTransition(
                opacity: _fadeAnimation,
                child: RefreshIndicator(
                  onRefresh: _load,
                  color: Theme.of(context).colorScheme.primary,
                  child: CustomScrollView(
                    slivers: [
                      _buildHeroHeader(context),
                      _buildBentoGrid(context),
                      if (_inProgress.isNotEmpty) ...[
                        _buildSectionHeader(context,
                            label: 'In progress',
                            count: _inProgress.length,
                            color: const Color(0xFFF97316)),
                        _buildList(_inProgress, context,
                            showProgress: true, dimmed: false),
                      ],
                      if (_locked.isNotEmpty) ...[
                        _buildSectionHeader(context,
                            label: 'Locked',
                            count: _locked.length,
                            color: AppColors.of(context).subtleText),
                        _buildList(_locked, context,
                            showProgress: false, dimmed: true),
                      ],
                      if (_completed.isNotEmpty) ...[
                        _buildSectionHeader(context,
                            label: 'Completed',
                            count: _completed.length,
                            color: const Color(0xFF10B981)),
                        _buildList(_completed, context,
                            showProgress: false,
                            dimmed: false,
                            showRewards: true,
                            ranked: true),
                      ],
                      const SliverToBoxAdapter(
                          child: SizedBox(height: 40)),
                    ],
                  ),
                ),
              ),
      ),
    );
  }

  // ══════════════════════════════════════════════════════════════
  // HERO HEADER
  // ══════════════════════════════════════════════════════════════
  Widget _buildHeroHeader(BuildContext context) {
    final appColors = AppColors.of(context);
    final cs = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final level = _levelInfo?.level ?? 1;
    final pctDisplay = '${(_overallPct * 100).round()}%';

    return SliverToBoxAdapter(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                GestureDetector(
                  onTap: () => Navigator.pop(context),
                  child: Container(
                    width: 32,
                    height: 32,
                    decoration: BoxDecoration(
                      color: appColors.cardBackground,
                      shape: BoxShape.circle,
                      border: Border.all(
                          color: appColors.cardBorder, width: 0.5),
                    ),
                    child: Icon(Icons.arrow_back_ios_new,
                        size: 14, color: cs.onSurface),
                  ),
                ),
                const SizedBox(width: 10),
                const Text('GYM BUDDY',
                    style: TextStyle(
                        fontSize: 9,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 1.2,
                        color: Color(0xFFF97316))),
                const SizedBox(width: 8),
                Expanded(
                  child: Container(
                      height: 0.5,
                      color: const Color(0xFFF97316).withOpacity(0.25)),
                ),
              ],
            ),
            const SizedBox(height: 12),
            RichText(
              text: TextSpan(
                style: TextStyle(
                  fontSize: 38,
                  fontWeight: FontWeight.w900,
                  letterSpacing: -2,
                  height: 0.88,
                  color: cs.onSurface,
                ),
                children: [
                  const TextSpan(text: 'ACHIEVE\n'),
                  TextSpan(
                    text: 'MENTS',
                    style: TextStyle(
                        color: isDark
                            ? const Color(0xFF7C3AED)
                            : const Color(0xFF6D28D9)),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                // Level badge — tappable, opens XP sheet
                GestureDetector(
                  onTap: () => _showXpSheet(context),
                  child: _heroBadge('Lv $level',
                      bg: const Color(0xFF7C3AED), fg: Colors.white),
                ),
                const SizedBox(width: 8),
                Expanded(
                    child: Container(
                        height: 0.5, color: appColors.divider)),
                const SizedBox(width: 8),
                _heroBadge('$pctDisplay complete',
                    bg: const Color(0xFFF97316).withOpacity(0.14),
                    fg: const Color(0xFFF97316),
                    border: const Color(0xFFF97316).withOpacity(0.3)),
              ],
            ),
            const SizedBox(height: 14),
          ],
        ),
      ),
    );
  }

  Widget _heroBadge(String label,
      {required Color bg, required Color fg, Color? border}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(6),
        border:
            border != null ? Border.all(color: border, width: 0.5) : null,
      ),
      child: Text(label.toUpperCase(),
          style: TextStyle(
              fontSize: 9,
              fontWeight: FontWeight.w800,
              letterSpacing: 0.5,
              color: fg)),
    );
  }

  // ══════════════════════════════════════════════════════════════
  // BENTO GRID
  // ══════════════════════════════════════════════════════════════
  Widget _buildBentoGrid(BuildContext context) {
    return SliverToBoxAdapter(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 0, 12, 4),
        child: Column(
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(child: _bentoProgress(context)),
                const SizedBox(width: 6),
                Expanded(child: _bentoStreak(context)),
              ],
            ),
            const SizedBox(height: 6),
            Row(
              children: [
                Expanded(
                    child: _bentoStat(context,
                        icon: '⚡',
                        value: _totalXpEarned.toString(),
                        label: 'XP Earned',
                        color: const Color(0xFF10B981),
                        onTap: () => _showXpSheet(context))),
                const SizedBox(width: 6),
                Expanded(
                    child: _bentoStat(context,
                        icon: '🪙',
                        value: _totalCoinsEarned.toString(),
                        label: 'Coins',
                        color: const Color(0xFFFBBF24),
                        onTap: () => _showCoinsSheet(context))),
              ],
            ),
            const SizedBox(height: 6),
            _bentoCategoryTile(context),
          ],
        ),
      ),
    );
  }

  Widget _bentoTile(BuildContext context, Widget child,
      {VoidCallback? onTap}) {
    final appColors = AppColors.of(context);
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: double.infinity,
        decoration: BoxDecoration(
          color: appColors.cardBackground,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: appColors.cardBorder, width: 0.5),
        ),
        child: child,
      ),
    );
  }

  Widget _bentoProgress(BuildContext context) {
    final appColors = AppColors.of(context);
    final cs = Theme.of(context).colorScheme;
    final pct = _overallPct;
    return _bentoTile(
      context,
      onTap: () => _showOverallSheet(context),
      Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Text('OVERALL',
                    style: TextStyle(
                        fontSize: 8,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 0.7,
                        color: appColors.subtleText)),
                const Spacer(),
                Icon(Icons.chevron_right,
                    size: 14, color: appColors.subtleText),
              ],
            ),
            const SizedBox(height: 6),
            Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text('${(pct * 100).round()}',
                    style: TextStyle(
                        fontSize: 30,
                        fontWeight: FontWeight.w900,
                        letterSpacing: -1.5,
                        height: 1,
                        color: cs.onSurface)),
                Padding(
                  padding: const EdgeInsets.only(bottom: 4),
                  child: Text('%',
                      style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w500,
                          color: appColors.subtleText)),
                ),
              ],
            ),
            const SizedBox(height: 3),
            Text('$_totalUnlocked of ${_all.length} unlocked',
                style:
                    TextStyle(fontSize: 9, color: appColors.subtleText)),
            const SizedBox(height: 8),
            ClipRRect(
              borderRadius: BorderRadius.circular(2),
              child: LinearProgressIndicator(
                value: pct,
                minHeight: 3,
                backgroundColor: appColors.divider,
                valueColor: const AlwaysStoppedAnimation(
                    Color(0xFF3B82F6)),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _bentoStreak(BuildContext context) {
    final appColors = AppColors.of(context);
    final cs = Theme.of(context).colorScheme;
    final streakAch = _completed
        .where((a) => a.category == 'streak')
        .toList()
      ..sort((a, b) => b.targetValue.compareTo(a.targetValue));
    final bestDays =
        streakAch.isNotEmpty ? streakAch.first.targetValue : 0;
    final dotsOn = bestDays > 0
        ? (bestDays >= 30 ? 7 : (bestDays ~/ 5).clamp(1, 7))
        : 0;

    return _bentoTile(
      context,
      onTap: () => _showStreakSheet(context),
      Stack(
        children: [
          Positioned(
            right: 2,
            bottom: 2,
            child: Text('🔥',
                style: TextStyle(
                    fontSize: 48,
                    color: cs.onSurface.withOpacity(0.06))),
          ),
          Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Text('BEST STREAK',
                        style: TextStyle(
                            fontSize: 8,
                            fontWeight: FontWeight.w700,
                            letterSpacing: 0.7,
                            color: Color(0xFFF97316))),
                    const Spacer(),
                    Icon(Icons.chevron_right,
                        size: 14, color: appColors.subtleText),
                  ],
                ),
                const SizedBox(height: 6),
                Text('$bestDays',
                    style: TextStyle(
                        fontSize: 30,
                        fontWeight: FontWeight.w900,
                        letterSpacing: -1.5,
                        height: 1,
                        color: cs.onSurface)),
                const SizedBox(height: 3),
                Text('days in a row',
                    style: TextStyle(
                        fontSize: 9, color: appColors.subtleText)),
                const SizedBox(height: 8),
                Row(
                  children: List.generate(7, (i) {
                    return Container(
                      width: 6,
                      height: 6,
                      margin: const EdgeInsets.only(right: 3),
                      decoration: BoxDecoration(
                        color: i < dotsOn
                            ? const Color(0xFFF97316)
                            : appColors.divider,
                        shape: BoxShape.circle,
                      ),
                    );
                  }),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _bentoStat(BuildContext context,
      {required String icon,
      required String value,
      required String label,
      required Color color,
      VoidCallback? onTap}) {
    final appColors = AppColors.of(context);
    return _bentoTile(
      context,
      onTap: onTap,
      Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Text(icon,
                    style: const TextStyle(fontSize: 16, height: 1)),
                const Spacer(),
                if (onTap != null)
                  Icon(Icons.chevron_right,
                      size: 14, color: appColors.subtleText),
              ],
            ),
            const SizedBox(height: 6),
            Text(value,
                style: TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.w900,
                    letterSpacing: -0.8,
                    height: 1,
                    color: color)),
            const SizedBox(height: 3),
            Text(label.toUpperCase(),
                style: TextStyle(
                    fontSize: 8,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.7,
                    color: appColors.subtleText)),
          ],
        ),
      ),
    );
  }

  Widget _bentoCategoryTile(BuildContext context) {
    final appColors = AppColors.of(context);
    final counts = _categoryUnlockCounts;
    return _bentoTile(
      context,
      Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Text('BY CATEGORY',
                    style: TextStyle(
                        fontSize: 8,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 0.7,
                        color: appColors.subtleText)),
                const SizedBox(width: 8),
                Expanded(
                    child: Container(
                        height: 0.5, color: appColors.divider)),
              ],
            ),
            const SizedBox(height: 10),
            Row(
              children: _categoryMeta.entries.map((e) {
                final cat = e.key;
                final emoji = e.value.$1;
                final shortName = e.value.$2;
                final n = counts[cat] ?? 0;
                final accent = _categoryAccent(cat);
                return Expanded(
                  child: Column(
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(
                            vertical: 5, horizontal: 2),
                        decoration: BoxDecoration(
                          color: appColors.sectionBackground,
                          borderRadius: BorderRadius.circular(7),
                          border: Border.all(
                              color: appColors.cardBorder, width: 0.5),
                        ),
                        child: Column(
                          children: [
                            Text(emoji,
                                style: const TextStyle(fontSize: 14)),
                            const SizedBox(height: 2),
                            Text('$n',
                                style: TextStyle(
                                    fontSize: 9,
                                    fontWeight: FontWeight.w700,
                                    color: n > 0
                                        ? accent
                                        : appColors.subtleText)),
                          ],
                        ),
                      ),
                      const SizedBox(height: 3),
                      Text(shortName,
                          style: TextStyle(
                              fontSize: 7, color: appColors.subtleText),
                          overflow: TextOverflow.ellipsis,
                          textAlign: TextAlign.center),
                    ],
                  ),
                );
              }).toList(),
            ),
          ],
        ),
      ),
    );
  }

  // ══════════════════════════════════════════════════════════════
  // SECTION HEADER
  // ══════════════════════════════════════════════════════════════
  Widget _buildSectionHeader(BuildContext context,
      {required String label,
      required int count,
      required Color color}) {
    final appColors = AppColors.of(context);
    return SliverToBoxAdapter(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
        child: Row(
          children: [
            Expanded(
                child:
                    Container(height: 0.5, color: appColors.divider)),
            const SizedBox(width: 10),
            Text(label.toUpperCase(),
                style: TextStyle(
                    fontSize: 8,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 0.8,
                    color: color)),
            const SizedBox(width: 8),
            Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
              decoration: BoxDecoration(
                color: appColors.sectionBackground,
                borderRadius: BorderRadius.circular(5),
              ),
              child: Text('$count',
                  style: TextStyle(
                      fontSize: 9,
                      fontWeight: FontWeight.w700,
                      color: appColors.subtleText)),
            ),
            const SizedBox(width: 10),
            Expanded(
                child:
                    Container(height: 0.5, color: appColors.divider)),
          ],
        ),
      ),
    );
  }

  // ══════════════════════════════════════════════════════════════
  // ACHIEVEMENT LIST
  // ══════════════════════════════════════════════════════════════
  Widget _buildList(List<Achievement> items, BuildContext context,
      {required bool showProgress,
      required bool dimmed,
      bool showRewards = false,
      bool ranked = false}) {
    return SliverPadding(
      padding: const EdgeInsets.symmetric(horizontal: 12),
      sliver: SliverList(
        delegate: SliverChildBuilderDelegate(
          (ctx, i) => _buildRow(ctx, items[i],
              showProgress: showProgress,
              dimmed: dimmed,
              showRewards: showRewards,
              rank: ranked ? i + 1 : null),
          childCount: items.length,
        ),
      ),
    );
  }

  Widget _buildRow(BuildContext context, Achievement a,
      {required bool showProgress,
      required bool dimmed,
      required bool showRewards,
      int? rank}) {
    final appColors = AppColors.of(context);
    final cs = Theme.of(context).colorScheme;
    final accent = _categoryAccent(a.category);
    final rColor = _rarityColor(a.rarity);
    final rBg = _rarityBg(a.rarity);

    return Opacity(
      opacity: dimmed ? 0.4 : 1.0,
      child: Container(
        margin: const EdgeInsets.only(bottom: 5),
        decoration: BoxDecoration(
          color: appColors.cardBackground,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: appColors.cardBorder, width: 0.5),
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(9.5),
          child: IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Container(
                  width: 3,
                  color: dimmed ? Colors.transparent : accent,
                ),
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(8, 9, 9, 9),
                    child: Row(
                      children: [
                        SizedBox(
                          width: 16,
                          child: Text(
                            rank != null ? '$rank' : '—',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                                fontSize: 10,
                                fontWeight: FontWeight.w800,
                                color: appColors.subtleText),
                          ),
                        ),
                        const SizedBox(width: 7),
                        Text(dimmed ? '🔒' : a.icon,
                            style: const TextStyle(fontSize: 20)),
                        const SizedBox(width: 9),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Text(a.name,
                                  style: TextStyle(
                                      fontSize: 11,
                                      fontWeight: FontWeight.w700,
                                      color: dimmed
                                          ? appColors.subtleText
                                          : cs.onSurface)),
                              const SizedBox(height: 1),
                              Text(a.description,
                                  style: TextStyle(
                                      fontSize: 9,
                                      color: appColors.subtleText),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis),
                              if (showProgress) ...[
                                const SizedBox(height: 6),
                                Row(
                                  children: [
                                    Expanded(
                                      child: ClipRRect(
                                        borderRadius:
                                            BorderRadius.circular(2),
                                        child: LinearProgressIndicator(
                                          value: a.progressPercent,
                                          minHeight: 3,
                                          backgroundColor: appColors.divider,
                                          valueColor:
                                              AlwaysStoppedAnimation(accent),
                                        ),
                                      ),
                                    ),
                                    const SizedBox(width: 6),
                                    Text(
                                        '${(a.progressPercent * 100).round()}%',
                                        style: TextStyle(
                                            fontSize: 9,
                                            fontWeight: FontWeight.w700,
                                            color: accent)),
                                  ],
                                ),
                                const SizedBox(height: 2),
                                Text('${a.progress ?? 0} / ${a.targetValue}',
                                    style: TextStyle(
                                        fontSize: 8,
                                        color: appColors.subtleText)),
                              ],
                            ],
                          ),
                        ),
                        const SizedBox(width: 8),
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.end,
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            if (showRewards) ...[
                              Text('+${a.xpReward} XP',
                                  style: TextStyle(
                                      fontSize: 9,
                                      fontWeight: FontWeight.w800,
                                      color: rColor)),
                              Text('+${a.coinReward} 🪙',
                                  style: TextStyle(
                                      fontSize: 8,
                                      color: appColors.subtleText)),
                              const SizedBox(height: 4),
                            ] else if (!showProgress && !dimmed) ...[
                              Text('+${a.xpReward} XP',
                                  style: TextStyle(
                                      fontSize: 9,
                                      fontWeight: FontWeight.w800,
                                      color: appColors.subtleText)),
                              const SizedBox(height: 4),
                            ],
                            Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 6, vertical: 2),
                              decoration: BoxDecoration(
                                color: dimmed
                                    ? appColors.sectionBackground
                                    : rBg,
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: Text(
                                a.rarity[0].toUpperCase() +
                                    a.rarity.substring(1),
                                style: TextStyle(
                                    fontSize: 8,
                                    fontWeight: FontWeight.w700,
                                    color: dimmed
                                        ? appColors.subtleText
                                        : rColor),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // ══════════════════════════════════════════════════════════════
  // SKELETON
  // ══════════════════════════════════════════════════════════════
  Widget _buildSkeleton(BuildContext context) {
    final c = AppColors.of(context).cardBorder;
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _skBox(c, double.infinity, 120, 12),
          const SizedBox(height: 10),
          Row(children: [
            Expanded(child: _skBox(c, double.infinity, 90, 12)),
            const SizedBox(width: 6),
            Expanded(child: _skBox(c, double.infinity, 90, 12)),
          ]),
          const SizedBox(height: 6),
          Row(children: [
            Expanded(child: _skBox(c, double.infinity, 70, 12)),
            const SizedBox(width: 6),
            Expanded(child: _skBox(c, double.infinity, 70, 12)),
          ]),
          const SizedBox(height: 6),
          _skBox(c, double.infinity, 80, 12),
          const SizedBox(height: 20),
          ...List.generate(
              5,
              (_) => Padding(
                    padding: const EdgeInsets.only(bottom: 6),
                    child: _skBox(c, double.infinity, 62, 10),
                  )),
        ],
      ),
    );
  }

  Widget _skBox(Color color, double w, double h, double r) =>
      Container(
        width: w,
        height: h,
        decoration: BoxDecoration(
            color: color, borderRadius: BorderRadius.circular(r)),
      );
}

// ══════════════════════════════════════════════════════════════
// SHARED SHEET WIDGETS
// ══════════════════════════════════════════════════════════════

class _Sheet extends StatelessWidget {
  final Widget child;
  const _Sheet({required this.child});

  @override
  Widget build(BuildContext context) {
    final appColors = AppColors.of(context);
    return Container(
      decoration: BoxDecoration(
        color: appColors.cardBackground,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
        border: Border.all(color: appColors.cardBorder, width: 0.5),
      ),
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 32),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Handle
          Center(
            child: Container(
              width: 36,
              height: 4,
              margin: const EdgeInsets.only(bottom: 16),
              decoration: BoxDecoration(
                color: AppColors.of(context).divider,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          child,
        ],
      ),
    );
  }
}

class _SheetHeader extends StatelessWidget {
  final String icon;
  final String title;
  final String subtitle;
  final AppColors appColors;
  final ColorScheme cs;

  const _SheetHeader({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.appColors,
    required this.cs,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Text(icon, style: const TextStyle(fontSize: 26)),
        const SizedBox(width: 12),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title,
                style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w800,
                    color: cs.onSurface)),
            Text(subtitle,
                style: TextStyle(
                    fontSize: 11, color: appColors.subtleText)),
          ],
        ),
      ],
    );
  }
}

class _SheetStatRow extends StatelessWidget {
  final String label;
  final String value;
  final Color color;
  final AppColors appColors;
  final ColorScheme cs;

  const _SheetStatRow({
    required this.label,
    required this.value,
    required this.color,
    required this.appColors,
    required this.cs,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          width: 3,
          height: 14,
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.circular(2),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Text(label,
              style: TextStyle(
                  fontSize: 13, color: cs.onSurface)),
        ),
        Text(value,
            style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w800,
                color: color)),
      ],
    );
  }
}

class _SheetMiniCard extends StatelessWidget {
  final String label;
  final String value;
  final Color color;
  final AppColors appColors;
  final ColorScheme cs;

  const _SheetMiniCard({
    required this.label,
    required this.value,
    required this.color,
    required this.appColors,
    required this.cs,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color.withOpacity(0.10),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: color.withOpacity(0.2), width: 0.5),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(value,
              style: TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.w900,
                  letterSpacing: -0.8,
                  color: color)),
          const SizedBox(height: 2),
          Text(label,
              style: TextStyle(
                  fontSize: 10, color: appColors.subtleText)),
        ],
      ),
    );
  }
}