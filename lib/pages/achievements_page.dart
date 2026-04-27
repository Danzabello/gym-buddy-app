import 'package:flutter/material.dart';
import '../services/achievement_service.dart';

class AchievementsPage extends StatefulWidget {
  const AchievementsPage({super.key});

  @override
  State<AchievementsPage> createState() => _AchievementsPageState();
}

class _AchievementsPageState extends State<AchievementsPage>
    with SingleTickerProviderStateMixin {
  final AchievementService _service = AchievementService();

  List<Achievement> _all = [];
  String _selectedCategory = 'all';
  bool _isLoading = true;

  late AnimationController _fadeController;
  late Animation<double> _fadeAnimation;

  static const _categories = [
    ('all',       'All'),
    ('streak',    '🔥 Streak'),
    ('workout',   '💪 Workout'),
    ('coop',      '🤝 Co-op'),
    ('social',    '👥 Social'),
    ('milestone', '🏅 Milestone'),
    ('prestige',  '💎 Prestige'),
    ('loyalty',   '🛡️ Loyalty'),
    ('fun',       '🎲 Fun'),
  ];

  static const _rarityOrder = [
    'common', 'uncommon', 'rare', 'epic', 'legendary'
  ];

  @override
  void initState() {
    super.initState();
    _fadeController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 400),
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
    final achievements = await _service.getAll();
    if (!mounted) return;
    setState(() {
      _all = achievements;
      _isLoading = false;
    });
    _fadeController.forward(from: 0);
  }

  List<Achievement> get _filtered {
    if (_selectedCategory == 'all') return _all;
    return _all.where((a) => a.category == _selectedCategory).toList();
  }

  List<Achievement> get _unlocked =>
      _filtered.where((a) => a.isUnlocked).toList();

  List<Achievement> get _inProgress =>
      _filtered.where((a) => !a.isUnlocked && a.hasProgress).toList();

  List<Achievement> get _locked =>
      _filtered.where((a) => !a.isUnlocked && !a.hasProgress).toList();

  int get _totalUnlocked => _all.where((a) => a.isUnlocked).length;
  int get _totalXpEarned => _all
      .where((a) => a.isUnlocked)
      .fold(0, (sum, a) => sum + a.xpReward);
  int get _totalCoinsEarned => _all
      .where((a) => a.isUnlocked)
      .fold(0, (sum, a) => sum + a.coinReward);

  Color _rarityColor(String rarity) {
    switch (rarity) {
      case 'uncommon':  return const Color(0xFF16A34A);
      case 'rare':      return const Color(0xFF1D4ED8);
      case 'epic':      return const Color(0xFF7C3AED);
      case 'legendary': return const Color(0xFFB45309);
      default:          return const Color(0xFF64748B);
    }
  }

  Color _rarityBg(String rarity) {
    switch (rarity) {
      case 'uncommon':  return const Color(0xFFDCFCE7);
      case 'rare':      return const Color(0xFFDBEAFE);
      case 'epic':      return const Color(0xFFEDE9FE);
      case 'legendary': return const Color(0xFFFEF3C7);
      default:          return const Color(0xFFF1F5F9);
    }
  }

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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF0F2F7),
      body: SafeArea(
        child: _isLoading ? _buildSkeleton() : FadeTransition(
          opacity: _fadeAnimation,
          child: RefreshIndicator(
            onRefresh: _load,
            child: CustomScrollView(
              slivers: [
                _buildHeader(),
                _buildStatsRow(),
                _buildFilterChips(),
                if (_unlocked.isNotEmpty) ...[
                  _buildSectionLabel('Unlocked  ✓', const Color(0xFF16A34A)),
                  _buildGrid(_unlocked),
                ],
                if (_inProgress.isNotEmpty) ...[
                  _buildSectionLabel('In Progress', const Color(0xFFF97316)),
                  _buildGrid(_inProgress),
                ],
                if (_locked.isNotEmpty) ...[
                  _buildSectionLabel('Locked', const Color(0xFF94A3B8)),
                  _buildGrid(_locked),
                ],
                const SliverToBoxAdapter(child: SizedBox(height: 32)),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // ── HEADER ────────────────────────────────────────────────────
  Widget _buildHeader() {
    return SliverToBoxAdapter(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
        child: Row(
          children: [
            GestureDetector(
              onTap: () => Navigator.pop(context),
              child: Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: Colors.white,
                  shape: BoxShape.circle,
                  border: Border.all(color: Colors.grey.shade200),
                ),
                child: const Icon(Icons.arrow_back_ios_new,
                    size: 16, color: Color(0xFF1E293B)),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Achievements',
                      style: TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.w700,
                          color: Color(0xFF1E293B))),
                  Text(
                    '$_totalUnlocked of ${_all.length} unlocked',
                    style: const TextStyle(
                        fontSize: 12, color: Color(0xFF64748B)),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ── STATS ROW ─────────────────────────────────────────────────
  Widget _buildStatsRow() {
    final pct = _all.isEmpty ? 0.0 : _totalUnlocked / _all.length;
    return SliverToBoxAdapter(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
        child: Column(
          children: [
            // Progress bar
            Row(
              children: [
                const Text('Overall progress',
                    style: TextStyle(fontSize: 11, color: Color(0xFF64748B))),
                const Spacer(),
                Text('${(pct * 100).round()}%',
                    style: const TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        color: Color(0xFF1E293B))),
              ],
            ),
            const SizedBox(height: 6),
            ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: LinearProgressIndicator(
                value: pct,
                minHeight: 6,
                backgroundColor: Colors.grey.shade200,
                valueColor: const AlwaysStoppedAnimation(Color(0xFFF97316)),
              ),
            ),
            const SizedBox(height: 12),
            // 3 stat cards
            Row(
              children: [
                _statCard('$_totalUnlocked', 'Unlocked',
                    const Color(0xFFFFF7ED), const Color(0xFFF97316)),
                const SizedBox(width: 8),
                _statCard('$_totalXpEarned', 'XP Earned',
                    const Color(0xFFF0FDF4), const Color(0xFF16A34A)),
                const SizedBox(width: 8),
                _statCard('$_totalCoinsEarned', 'Coins',
                    const Color(0xFFEFF6FF), const Color(0xFF1D4ED8)),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _statCard(String value, String label, Color bg, Color fg) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 12),
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(
          children: [
            Text(value,
                style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w700,
                    color: fg)),
            const SizedBox(height: 2),
            Text(label,
                style: const TextStyle(
                    fontSize: 10, color: Color(0xFF64748B))),
          ],
        ),
      ),
    );
  }

  // ── FILTER CHIPS ──────────────────────────────────────────────
  Widget _buildFilterChips() {
    return SliverToBoxAdapter(
      child: SizedBox(
        height: 44,
        child: ListView(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
          children: _categories.map((cat) {
            final isActive = _selectedCategory == cat.$1;
            return GestureDetector(
              onTap: () => setState(() => _selectedCategory = cat.$1),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 180),
                margin: const EdgeInsets.only(right: 8),
                padding: const EdgeInsets.symmetric(
                    horizontal: 14, vertical: 5),
                decoration: BoxDecoration(
                  color: isActive
                      ? const Color(0xFFF97316)
                      : Colors.white,
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(
                    color: isActive
                        ? const Color(0xFFF97316)
                        : Colors.grey.shade200,
                  ),
                ),
                child: Text(
                  cat.$2,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                    color: isActive
                        ? Colors.white
                        : const Color(0xFF64748B),
                  ),
                ),
              ),
            );
          }).toList(),
        ),
      ),
    );
  }

  // ── SECTION LABEL ─────────────────────────────────────────────
  Widget _buildSectionLabel(String label, Color color) {
    return SliverToBoxAdapter(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 20, 16, 10),
        child: Row(
          children: [
            Container(
                width: 3,
                height: 14,
                decoration: BoxDecoration(
                    color: color,
                    borderRadius: BorderRadius.circular(2))),
            const SizedBox(width: 8),
            Text(label.toUpperCase(),
                style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: color,
                    letterSpacing: 0.6)),
          ],
        ),
      ),
    );
  }

  // ── ACHIEVEMENT GRID ──────────────────────────────────────────
  Widget _buildGrid(List<Achievement> items) {
    return SliverPadding(
      padding: const EdgeInsets.symmetric(horizontal: 12),
      sliver: SliverList(
        delegate: SliverChildBuilderDelegate(
          (context, index) => _buildCard(items[index]),
          childCount: items.length,
        ),
      ),
    );
  }

  // ── ACHIEVEMENT CARD ──────────────────────────────────────────
  Widget _buildCard(Achievement a) {
    final accent = _categoryAccent(a.category);
    final isLocked = !a.isUnlocked && !a.hasProgress;

    return Opacity(
      opacity: isLocked ? 0.45 : 1.0,
      child: Container(
        margin: const EdgeInsets.only(bottom: 8, left: 4, right: 4),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(14),
          border: Border(
            left: BorderSide(
              color: a.isUnlocked ? accent : Colors.transparent,
              width: 3,
            ),
          ),
          boxShadow: a.isUnlocked
              ? [
                  BoxShadow(
                    color: accent.withOpacity(0.08),
                    blurRadius: 8,
                    offset: const Offset(0, 2),
                  )
                ]
              : null,
        ),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            children: [
              // Icon
              Container(
                width: 46,
                height: 46,
                decoration: BoxDecoration(
                  color: isLocked
                      ? Colors.grey.shade100
                      : accent.withOpacity(0.12),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Center(
                  child: isLocked
                      ? Icon(Icons.lock_outline,
                          size: 20, color: Colors.grey.shade400)
                      : Text(a.icon,
                          style: const TextStyle(fontSize: 24)),
                ),
              ),
              const SizedBox(width: 12),
              // Info
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child: Text(
                            a.name,
                            style: const TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w600,
                                color: Color(0xFF1E293B)),
                          ),
                        ),
                        const SizedBox(width: 6),
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 7, vertical: 2),
                          decoration: BoxDecoration(
                            color: _rarityBg(a.rarity),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Text(
                            a.rarity[0].toUpperCase() +
                                a.rarity.substring(1),
                            style: TextStyle(
                                fontSize: 9,
                                fontWeight: FontWeight.w600,
                                color: _rarityColor(a.rarity)),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 2),
                    Text(
                      a.description,
                      style: const TextStyle(
                          fontSize: 11, color: Color(0xFF64748B)),
                    ),
                    if (a.isUnlocked) ...[
                      const SizedBox(height: 4),
                      Text(
                        '+${a.xpReward} XP  ·  +${a.coinReward} coins',
                        style: TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.w600,
                            color: accent),
                      ),
                    ] else if (a.hasProgress) ...[
                      const SizedBox(height: 6),
                      Row(
                        children: [
                          Expanded(
                            child: ClipRRect(
                              borderRadius: BorderRadius.circular(3),
                              child: LinearProgressIndicator(
                                value: a.progressPercent,
                                minHeight: 4,
                                backgroundColor: Colors.grey.shade200,
                                valueColor:
                                    AlwaysStoppedAnimation(accent),
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Text(
                            '${a.progress} / ${a.targetValue}',
                            style: const TextStyle(
                                fontSize: 10,
                                color: Color(0xFF64748B)),
                          ),
                        ],
                      ),
                    ],
                  ],
                ),
              ),
              // Check / lock
              const SizedBox(width: 8),
              if (a.isUnlocked)
                Container(
                  width: 22,
                  height: 22,
                  decoration: BoxDecoration(
                      color: accent, shape: BoxShape.circle),
                  child: const Icon(Icons.check,
                      size: 13, color: Colors.white),
                )
              else
                const SizedBox(width: 22),
            ],
          ),
        ),
      ),
    );
  }

  // ── SKELETON ──────────────────────────────────────────────────
  Widget _buildSkeleton() {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        children: List.generate(
          6,
          (_) => Container(
            margin: const EdgeInsets.only(bottom: 10),
            height: 72,
            decoration: BoxDecoration(
              color: Colors.grey.shade200,
              borderRadius: BorderRadius.circular(14),
            ),
          ),
        ),
      ),
    );
  }
}