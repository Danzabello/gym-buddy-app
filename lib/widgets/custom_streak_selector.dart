// lib/widgets/custom_streak_selector.dart
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../services/team_streak_service.dart';
import '../theme/app_theme.dart';
import 'user_avatar.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class CustomStreakSelector extends StatefulWidget {
  final List<TeamStreak> availableStreaks;
  final List<TeamStreak>? currentSelection;

  const CustomStreakSelector({
    super.key,
    required this.availableStreaks,
    this.currentSelection,
  });

  @override
  State<CustomStreakSelector> createState() =>
      _CustomStreakSelectorState();
}

class _CustomStreakSelectorState extends State<CustomStreakSelector>
    with SingleTickerProviderStateMixin {
  late List<TeamStreak> _available;

  // ✅ 4 ordered wheel slots — Coach Max rides along automatically as #5
  final List<TeamStreak?> _slots = List<TeamStreak?>.filled(4, null);
  static const List<String> _ordinals = ['1st', '2nd', '3rd', '4th'];

  String _searchQuery = '';

  late AnimationController _animController;
  late Animation<Offset> _slideAnim;

  @override
  void initState() {
    super.initState();
    // Coach Max is never pickable — he always gets the last wheel slot
    _available = widget.availableStreaks
        .where((s) => !s.isCoachMaxTeam)
        .toList();

    _animController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 300),
    );
    _slideAnim = Tween<Offset>(
      begin: const Offset(0, 1),
      end: Offset.zero,
    ).animate(CurvedAnimation(
        parent: _animController, curve: Curves.easeOutCubic));
    _animController.forward();

    // ✅ Restore any previous selection (1–4 picks, old 3-pick saves included)
    final restore = widget.currentSelection;
    if (restore != null && restore.isNotEmpty) {
      final picks = restore
          .where((s) => !s.isCoachMaxTeam)
          .take(4)
          .toList();
      for (var i = 0; i < picks.length; i++) {
        _slots[i] = picks[i];
      }
      _available.removeWhere(
          (s) => picks.any((p) => p.teamId == s.teamId));
    }
  }

  @override
  void dispose() {
    _animController.dispose();
    super.dispose();
  }

  // ── Helpers ────────────────────────────────────────────
  String _friendName(TeamStreak s) {
    final me = Supabase.instance.client.auth.currentUser?.id;
    final buddy = s.members.firstWhere(
        (m) => m.userId != me,
        orElse: () => s.members.first);
    return buddy.displayName;
  }

  String _friendAvatar(TeamStreak s) {
    final me = Supabase.instance.client.auth.currentUser?.id;
    final buddy = s.members.firstWhere(
        (m) => m.userId != me,
        orElse: () => s.members.first);
    return buddy.avatarId ?? 'avatar_1';
  }

  List<TeamStreak> get _filtered => _searchQuery.isEmpty
      ? _available
      : _available
          .where((s) => _friendName(s)
              .toLowerCase()
              .contains(_searchQuery.toLowerCase()))
          .toList();

  bool get _allSlotsFilled => _slots.every((s) => s != null);

  List<TeamStreak> get _assigned =>
      _slots.whereType<TeamStreak>().toList();

  // ✅ Save when all 4 filled OR every available buddy is assigned
  bool get _canSave =>
      _assigned.isNotEmpty && (_allSlotsFilled || _available.isEmpty);

  String? _slotLabel(TeamStreak streak) {
    final i =
        _slots.indexWhere((s) => s?.teamId == streak.teamId);
    return i == -1 ? null : _ordinals[i];
  }

  // ── Next slot name for hint text ──────────────────────
  String get _nextSlotHint {
    final i = _slots.indexWhere((s) => s == null);
    return i == -1 ? '' : _ordinals[i];
  }

  // ── Tap to assign: fills next empty slot ──────────────
  void _assign(TeamStreak streak) {
    HapticFeedback.selectionClick();
    setState(() {
      final i = _slots.indexWhere((s) => s == null);
      if (i == -1) return; // all full
      _slots[i] = streak;
      _available.remove(streak);
    });
  }

  void _unassign(TeamStreak streak) {
    HapticFeedback.selectionClick();
    setState(() {
      final i =
          _slots.indexWhere((s) => s?.teamId == streak.teamId);
      if (i != -1) {
        _slots[i] = null;
        _available.add(streak);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final appColors = AppColors.of(context);
    final cs = Theme.of(context).colorScheme;

    return SlideTransition(
      position: _slideAnim,
      child: Scaffold(
        backgroundColor: Theme.of(context).scaffoldBackgroundColor,
        appBar: AppBar(
          elevation: 0,
          backgroundColor: Colors.transparent,
          flexibleSpace: Container(
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                colors: [Color(0xFF1D4ED8), Color(0xFF7C3AED)],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
            ),
          ),
          leading: IconButton(
            icon: const Icon(Icons.arrow_back_ios,
                color: Colors.white, size: 18),
            onPressed: () => Navigator.pop(context),
          ),
          title: const Text('Pick your top 4',
              style: TextStyle(
                  color: Colors.white,
                  fontSize: 18,
                  fontWeight: FontWeight.w800)),
          actions: [
            if (_canSave)
              Padding(
                padding: const EdgeInsets.only(right: 12),
                child: GestureDetector(
                  onTap: () => Navigator.pop(context, _assigned),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 14, vertical: 6),
                    decoration: BoxDecoration(
                      color: const Color(0xFFF97316),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Text('Save',
                        style: TextStyle(
                            color: Colors.white,
                            fontSize: 13,
                            fontWeight: FontWeight.w700)),
                  ),
                ),
              ),
          ],
        ),
        body: Column(
          children: [
            // ── Carousel preview ───────────────────────
            Container(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
              decoration: BoxDecoration(
                color: appColors.cardBackground,
                border: Border(
                  bottom: BorderSide(
                      color: appColors.cardBorder, width: 0.5),
                ),
              ),
              child: Column(
                children: [
                  Text('CAROUSEL PREVIEW',
                      style: TextStyle(
                          fontSize: 9,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 0.8,
                          color: appColors.subtleText)),
                  const SizedBox(height: 12),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      for (var i = 0; i < 4; i++) ...[
                        _previewSlot(_ordinals[i], _slots[i],
                            size: 46,
                            isPrimary: i == 0,
                            appColors: appColors,
                            cs: cs),
                        const SizedBox(width: 10),
                      ],
                      _coachMaxPreview(appColors),
                    ],
                  ),
                  const SizedBox(height: 6),
                  if (!_allSlotsFilled && _available.isNotEmpty)
                    Text(
                      'Tap a buddy below → fills $_nextSlotHint slot',
                      style: TextStyle(
                          fontSize: 10, color: appColors.subtleText),
                    )
                  else
                    Text(
                      '🤖 Coach Max joins automatically',
                      style: TextStyle(
                          fontSize: 10, color: appColors.subtleText),
                    ),
                ],
              ),
            ),

            // ── Search ─────────────────────────────────
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 10, 12, 4),
              child: Container(
                decoration: BoxDecoration(
                  color: appColors.cardBackground,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(
                      color: appColors.cardBorder, width: 0.5),
                ),
                child: TextField(
                  style:
                      TextStyle(color: cs.onSurface, fontSize: 14),
                  decoration: InputDecoration(
                    hintText: 'Search buddies...',
                    hintStyle: TextStyle(
                        color: appColors.subtleText, fontSize: 13),
                    prefixIcon: Icon(Icons.search,
                        color: appColors.subtleText, size: 18),
                    border: InputBorder.none,
                    contentPadding: const EdgeInsets.symmetric(
                        horizontal: 12, vertical: 12),
                  ),
                  onChanged: (v) =>
                      setState(() => _searchQuery = v),
                ),
              ),
            ),

            Expanded(
              child: ListView(
                padding: const EdgeInsets.symmetric(
                    horizontal: 12, vertical: 4),
                children: [
                  // ── Available buddies ──────────────
                  if (_filtered.isNotEmpty) ...[
                    _sectionHeader('Available',
                        _filtered.length, appColors,
                        countColor: const Color(0xFF3B82F6)),
                    ..._filtered.map(
                        (s) => _buddyRow(s, appColors, cs,
                            assigned: false)),
                  ] else if (_searchQuery.isNotEmpty) ...[
                    const SizedBox(height: 24),
                    Center(
                      child: Text('No matches',
                          style: TextStyle(
                              color: appColors.subtleText)),
                    ),
                  ],

                  // ── Assigned buddies ───────────────
                  if (_assigned.isNotEmpty) ...[
                    const SizedBox(height: 8),
                    _sectionHeader('Assigned',
                        _assigned.length, appColors,
                        countColor: const Color(0xFFF97316)),
                    ..._assigned.map(
                        (s) => _buddyRow(s, appColors, cs,
                            assigned: true)),
                  ],

                  // ── All filled empty state ─────────
                  if (_filtered.isEmpty && _searchQuery.isEmpty) ...[
                    const SizedBox(height: 24),
                    Center(
                      child: Column(children: [
                        const Text('✅',
                            style: TextStyle(fontSize: 32)),
                        const SizedBox(height: 8),
                        Text('All buddies assigned!',
                            style: TextStyle(
                                color: appColors.subtleText,
                                fontWeight: FontWeight.w600)),
                      ]),
                    ),
                  ],
                  const SizedBox(height: 20),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _previewSlot(String label, TeamStreak? streak,
      {required double size,
      bool isPrimary = false,
      required AppColors appColors,
      required ColorScheme cs}) {
    final filled = streak != null;
    return Column(
      children: [
        Container(
          width: size,
          height: size,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: filled
                ? (isPrimary
                    ? const Color(0xFF7C3AED).withOpacity(0.12)
                    : const Color(0xFF3B82F6).withOpacity(0.10))
                : appColors.sectionBackground,
            border: Border.all(
              color: filled
                  ? (isPrimary
                      ? const Color(0xFF7C3AED)
                      : const Color(0xFF3B82F6))
                  : appColors.cardBorder,
              width: filled ? 2 : 1.5,
            ),
          ),
          child: filled
              ? ClipOval(
                  child: UserAvatar(
                      avatarId: _friendAvatar(streak),
                      size: size))
              : Icon(Icons.add,
                  size: size * 0.35, color: appColors.subtleText),
        ),
        const SizedBox(height: 4),
        Text(label,
            style: TextStyle(
                fontSize: 9,
                fontWeight: FontWeight.w600,
                color: isPrimary && filled
                    ? const Color(0xFF7C3AED)
                    : appColors.subtleText)),
      ],
    );
  }

  // ✅ Locked 5th circle — Coach Max is always in the wheel
  Widget _coachMaxPreview(AppColors appColors) {
    return Column(
      children: [
        Container(
          width: 46,
          height: 46,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            gradient: const LinearGradient(
              colors: [Color(0xFF1D4ED8), Color(0xFF7C3AED)],
            ),
            border: Border.all(
              color: appColors.cardBorder,
              width: 1.5,
            ),
          ),
          child: const Center(
              child: Text('🤖', style: TextStyle(fontSize: 20))),
        ),
        const SizedBox(height: 4),
        Text('Max',
            style: TextStyle(
                fontSize: 9,
                fontWeight: FontWeight.w600,
                color: appColors.subtleText)),
      ],
    );
  }

  Widget _sectionHeader(String label, int count,
      AppColors appColors,
      {required Color countColor}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6, top: 4),
      child: Row(children: [
        Text(label.toUpperCase(),
            style: TextStyle(
                fontSize: 9,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.7,
                color: appColors.subtleText)),
        const SizedBox(width: 8),
        Container(
          padding:
              const EdgeInsets.symmetric(horizontal: 7, vertical: 1),
          decoration: BoxDecoration(
            color: countColor.withOpacity(0.12),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Text('$count',
              style: TextStyle(
                  fontSize: 9,
                  fontWeight: FontWeight.w700,
                  color: countColor)),
        ),
      ]),
    );
  }

  Widget _buddyRow(TeamStreak streak, AppColors appColors,
      ColorScheme cs, {required bool assigned}) {
    final name = streak.isCoachMaxTeam
        ? 'Coach Max'
        : _friendName(streak);
    final slotLbl = _slotLabel(streak);
    final canAssign = !assigned && !_allSlotsFilled;
    final isPrimaryLbl = slotLbl == '1st';

    return Opacity(
      opacity: assigned ? 0.6 : 1.0,
      child: Container(
        margin: const EdgeInsets.only(bottom: 6),
        decoration: BoxDecoration(
          color: appColors.cardBackground,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: appColors.cardBorder, width: 0.5),
        ),
        child: Padding(
          padding: const EdgeInsets.all(9),
          child: Row(children: [
            // Avatar
            Container(
              width: 38,
              height: 38,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: LinearGradient(
                  colors: streak.isCoachMaxTeam
                      ? [
                          const Color(0xFF1D4ED8),
                          const Color(0xFF7C3AED)
                        ]
                      : [
                          const Color(0xFF374151),
                          const Color(0xFF4B5563)
                        ],
                ),
              ),
              child: streak.isCoachMaxTeam
                  ? const Center(
                      child: Text('🤖',
                          style: TextStyle(fontSize: 18)))
                  : ClipOval(
                      child: UserAvatar(
                          avatarId: _friendAvatar(streak),
                          size: 38)),
            ),
            const SizedBox(width: 10),
            // Info
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(children: [
                    Text(name,
                        style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                            color: cs.onSurface)),
                    if (slotLbl != null) ...[
                      const SizedBox(width: 6),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 5, vertical: 1),
                        decoration: BoxDecoration(
                          color: isPrimaryLbl
                              ? const Color(0xFF7C3AED)
                                  .withOpacity(0.12)
                              : const Color(0xFF3B82F6)
                                  .withOpacity(0.12),
                          borderRadius: BorderRadius.circular(5),
                        ),
                        child: Text(slotLbl,
                            style: TextStyle(
                                fontSize: 8,
                                fontWeight: FontWeight.w700,
                                color: isPrimaryLbl
                                    ? const Color(0xFF7C3AED)
                                    : const Color(0xFF3B82F6))),
                      ),
                    ],
                  ]),
                  Text(
                    streak.isCoachMaxTeam
                        ? 'Always active'
                        : '🔥 ${streak.currentStreak} day streak',
                    style: TextStyle(
                        fontSize: 9, color: appColors.subtleText),
                  ),
                ],
              ),
            ),
            // Add / remove button
            GestureDetector(
              onTap: assigned
                  ? () => _unassign(streak)
                  : canAssign
                      ? () => _assign(streak)
                      : null,
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 150),
                width: 30,
                height: 30,
                decoration: BoxDecoration(
                  color: assigned
                      ? const Color(0xFFEF4444).withOpacity(0.10)
                      : canAssign
                          ? const Color(0xFF3B82F6).withOpacity(0.10)
                          : appColors.sectionBackground,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: assigned
                        ? const Color(0xFFEF4444).withOpacity(0.25)
                        : canAssign
                            ? const Color(0xFF3B82F6)
                                .withOpacity(0.25)
                            : appColors.cardBorder,
                    width: 0.5,
                  ),
                ),
                child: Icon(
                  assigned ? Icons.close : Icons.add,
                  size: 16,
                  color: assigned
                      ? const Color(0xFFEF4444)
                      : canAssign
                          ? const Color(0xFF3B82F6)
                          : appColors.subtleText,
                ),
              ),
            ),
          ]),
        ),
      ),
    );
  }
}