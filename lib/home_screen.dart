import 'dart:async';
import 'package:gym_buddy_app/login_screen.dart';
import 'dart:math' as math;
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'services/friend_service.dart';
import 'services/workout_service.dart';
import 'services/team_streak_service.dart';
import 'widgets/skeleton_box.dart';
import 'widgets/ai_disclosure_tag.dart';
import 'package:confetti/confetti.dart';
import 'package:flutter/services.dart';
import 'widgets/user_avatar.dart';
import 'widgets/press_scale.dart';
import 'services/team_sync_service.dart';
import 'package:flutter/foundation.dart';
import 'services/break_day_service.dart';
import 'widgets/friends_page_modern.dart';
import 'pages/schedule_page.dart';
import 'pages/workout_page.dart';
import 'services/handshake_service.dart';
import 'widgets/checkin_ignite_video.dart';
import 'widgets/streak_badge.dart';
import 'widgets/custom_streak_selector.dart';
import 'widgets/buddy_profile_sheet.dart';
import 'services/nickname_service.dart';
import 'services/nudge_service.dart';
import 'widgets/schedule_workout_sheet.dart';
import 'widgets/workout_checkin_sheet.dart';
import 'services/workout_history_service.dart';
import 'widgets/workout_selection_modal.dart';
import 'pages/notification_settings_page.dart';
import 'pages/shop_page.dart';
import 'pages/coin_history_page.dart';
import 'pages/notice_screens.dart';
import 'pages/workout_history_page.dart';
import 'pages/account_page.dart';
import 'pages/wardrobe/wardrobe_page.dart';
import 'pages/help_support_page.dart';
import 'services/coin_service.dart';
import 'widgets/menu_card.dart';
import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import 'services/level_service.dart';
import 'services/economy_sync.dart';
import 'widgets/header_motion.dart';
import 'package:flutter/semantics.dart';
import 'pages/achievements_page.dart' as achievements_page;
import 'widgets/achievement_toast.dart';
import 'services/achievement_service.dart';
import 'package:provider/provider.dart';
import 'package:timezone/data/latest.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;
import 'theme/app_theme.dart';
import 'theme/accent_theme_provider.dart';
import 'data/coach_tips.dart';
import 'services/auth_service.dart';
import 'services/notification_service.dart';
import 'pages/notifications_page.dart';
import 'widgets/live_event_toast.dart';
import 'widgets/coin_glyph.dart';
import 'widgets/workout_celebration.dart';
import 'package:gym_buddy_app/utils/debug_logger.dart';
import 'package:gym_buddy_app/utils/hex_color.dart';
import 'package:gym_buddy_app/utils/app_dates.dart';
import 'package:gym_buddy_app/utils/run_once.dart';

part 'home/all_streaks_dialog.dart';
part 'home/capped_count.dart';
part 'home/checkin_ring.dart';
part 'home/dashboard_page.dart';
part 'home/home_shell.dart';
part 'home/profile_page.dart';


/// Second line of the buddy check-in banner. Only when the viewer is already
/// in does the buddy's check-in complete the pair; otherwise it is their turn.
@visibleForTesting
String checkInBannerSubtitle({required bool viewerCheckedIn}) => viewerCheckedIn
    ? 'Your streak is safe today'
    : 'Your turn to check in';

// Pure profile helpers, top-level so test/profile_helpers_test.dart can pin them.
@visibleForTesting
String formatYear(String? dateStr) {
  if (dateStr == null) return '2025';
  try { return '${DateTime.parse(dateStr).year}'; } catch (_) { return '2025'; }
}

@visibleForTesting
List<Color> levelGradient(int level) {
  if (level >= 91) return [const Color(0xFF7F77DD), const Color(0xFF534AB7)];
  if (level >= 76) return [const Color(0xFFD85A30), const Color(0xFF993C1D)];
  if (level >= 56) return [const Color(0xFFD4537E), const Color(0xFF993556)];
  if (level >= 46) return [const Color(0xFFEF9F27), const Color(0xFFBA7517)];
  if (level >= 26) return [const Color(0xFF1D9E75), const Color(0xFF0F6E56)];
  if (level >= 11) return [const Color(0xFF378ADD), const Color(0xFF185FA5)];
  return [const Color(0xFFFFB300), const Color(0xFFFF8F00)];
}

@visibleForTesting
String titleIcon(String title) {
  const map = {
    'Newcomer': '🌱', 'Beginner': '⚡', 'Rookie': '🔥',
    'Athlete': '💪', 'Warrior': '⚔️', 'Iron': '🛡️',
    'Beast': '🦁', 'Legend': '👑', 'Elite': '💎',
    'Champion': '🏆', 'Gym Pro': '🌟',
  };
  return map[title] ?? '⭐';
}

enum StreakSortMode {
  highestCurrent,    // ⚡ Highest active streak (default)
  mostWorkouts,      // 💪 Most workouts together
  bestAllTime,       // 🏆 Longest streak ever
  mostRecent,        // 🕐 Most recent workout
  favorites,         // ⭐ User favorites (future)
  custom,  // ✅ NEW!
  mostUrgent,        // ⚠️ At-risk streaks first
  alphabetical,      // 🔤 By team/buddy name
}

/// Order the sort grid renders in — deliberately NOT the enum's declaration
/// order. `custom` is a manual-reorder mode rather than an automatic sort, so
/// it sits last. The enum order itself is load-bearing (persisted by `.name`,
/// switch statements) and must not be changed to achieve this.
///
/// Every StreakSortMode must appear here or it silently vanishes from the UI;
/// the assert in _showSortBottomSheet catches that in debug.
const List<StreakSortMode> _sortModeDisplayOrder = [
  StreakSortMode.highestCurrent,
  StreakSortMode.mostWorkouts,
  StreakSortMode.bestAllTime,
  StreakSortMode.mostRecent,
  StreakSortMode.favorites,
  StreakSortMode.mostUrgent,
  StreakSortMode.alphabetical,
  StreakSortMode.custom,
];

// ✅ ADD EXTENSION HERE - OUTSIDE THE CLASS!
extension StreakSortModeExtension on StreakSortMode {
  String get displayName {
    switch (this) {
      case StreakSortMode.highestCurrent:
        return 'Highest Streak';
      case StreakSortMode.mostWorkouts:
        return 'Most Workouts';
      case StreakSortMode.bestAllTime:
        return 'Best All-Time';
      case StreakSortMode.mostRecent:
        return 'Most Recent';
      case StreakSortMode.favorites:
        return 'Favorites';
      case StreakSortMode.custom: 
        return 'Custom';  // ✅ NEW!
      case StreakSortMode.mostUrgent:
        return 'At Risk First';
      case StreakSortMode.alphabetical:
        return 'A to Z';
    }
  }
  
  String get emoji {
    switch (this) {
      case StreakSortMode.highestCurrent:
        return '⚡';
      case StreakSortMode.mostWorkouts:
        return '💪';
      case StreakSortMode.bestAllTime:
        return '🏆';
      case StreakSortMode.mostRecent:
        return '🕐';
      case StreakSortMode.favorites:
        return '⭐';
      case StreakSortMode.custom: 
        return '👤';  // ✅ NEW!
      case StreakSortMode.mostUrgent:
        return '⚠️';
      case StreakSortMode.alphabetical:
        return '🔤';
    }
  }
  
  String get description {
    switch (this) {
      case StreakSortMode.highestCurrent: return 'View by current streak';
      case StreakSortMode.mostWorkouts: return 'Most active teammates';
      case StreakSortMode.bestAllTime: return 'All-time champions';
      case StreakSortMode.mostRecent: return 'Recently active';
      case StreakSortMode.favorites: return 'Your favorites';
      case StreakSortMode.custom: return 'Manual selection';  // ✅ NEW!
      case StreakSortMode.mostUrgent: return 'Nobody checked in yet';
      case StreakSortMode.alphabetical: return 'By name, A to Z';
    }
  }
}

/// Friends-only, ordered by [mode]. Coach Max is always excluded — it is an
/// AI buddy, not a rankable streak. Top-level so both the dashboard and the
/// profile page order the streak list identically.
/// Time left before the streak-breaking deadline — the end of [now]'s day in
/// [now]'s own zone — or null while it's still before [cutoffHour] there.
/// Cutoff and deadline are both local to that zone, never UTC: the buddy's own
/// local midnight is the boundary reconcile_stale_streaks judges them against,
/// so a UTC frame quoted anyone far from UTC a deadline hours off their real
/// one. Absolute-time arithmetic, so a night that springs forward is 23h.
Duration? dangerRemainingAt(tz.TZDateTime now, {int cutoffHour = 18}) {
  if (now.hour < cutoffHour) return null;
  return tz.TZDateTime(now.location, now.year, now.month, now.day + 1)
      .difference(now);
}

/// Which variant Card 1's single slot shows.
enum StatusSlot { danger, secured, feed }

/// The danger window owns the slot: inside it the card reports where the
/// team's streak stands, outside it the feed has the slot to itself.
/// "Secured" is the resolved half of the countdown, not an all-day badge —
/// gating it the same way as [StatusSlot.danger] is what keeps the feed
/// reachable on a day the buddy checked in early. No buddy (Coach Max, solo
/// team) means there's no check-in to wait on, so those always get the feed.
StatusSlot resolveStatusSlot({
  required bool hasBuddy,
  required bool buddyCheckedIn,
  required bool inDangerWindow,
}) {
  if (!hasBuddy || !inDangerWindow) return StatusSlot.feed;
  return buddyCheckedIn ? StatusSlot.secured : StatusSlot.danger;
}

/// Streak milestones and their celebration names. One source for both the
/// milestone dialog's trigger list and the "next milestone" card, so the two
/// can't drift apart.
const kStreakMilestones = <int, String>{
  1: 'First Check-in',
  3: 'Building Momentum',
  7: 'On Fire',
  14: 'Two Weeks',
  30: 'Diamond Status',
  50: 'Unstoppable',
  100: 'Legend',
  365: 'Immortal',
};

/// The milestone [current] is working toward, and how far along it is —
/// [progress] is 0.0 at the previous milestone and 1.0 at the next. Null once
/// every milestone is behind it.
({int target, String name, double progress, int toGo})? getNextMilestone(
    int current) {
  final target =
      kStreakMilestones.keys.firstWhere((m) => m > current, orElse: () => -1);
  if (target < 0) return null;
  final previous =
      kStreakMilestones.keys.lastWhere((m) => m <= current, orElse: () => 0);
  return (
    target: target,
    name: kStreakMilestones[target]!,
    progress: ((current - previous) / (target - previous)).clamp(0.0, 1.0),
    toGo: target - current,
  );
}

List<TeamStreak> sortStreaks(List<TeamStreak> streaks, StreakSortMode mode) {
  debugLog('🔄 SORT: Mode = ${mode.displayName}');
  debugLog('🔄 SORT: Input streaks count = ${streaks.length}');
  
  // Filter out Coach Max
  final friendStreaks = streaks.where((s) => !s.isCoachMaxTeam).toList();
  debugLog('🔄 SORT: After filtering Coach Max = ${friendStreaks.length}');
  
  // Sort based on mode
  switch (mode) {
    case StreakSortMode.highestCurrent:
      friendStreaks.sort((a, b) => b.currentStreak.compareTo(a.currentStreak));
      debugLog('⚡ SORT: Highest Current - Order: ${friendStreaks.map((s) => '${s.teamName}(${s.currentStreak})').join(', ')}');
      break;
      
    case StreakSortMode.mostWorkouts:
      friendStreaks.sort((a, b) => b.totalWorkouts.compareTo(a.totalWorkouts)); 
      debugLog('💪 SORT: Most Workouts - Order: ${friendStreaks.map((s) => '${s.teamName}(${s.totalWorkouts})').join(', ')}');
      break;
      
    case StreakSortMode.bestAllTime:
      friendStreaks.sort((a, b) => b.bestStreak.compareTo(a.bestStreak));  // ✅ Use real data!
      debugLog('🏆 SORT: Best All-Time - Order: ${friendStreaks.map((s) => '${s.teamName}(${s.bestStreak})').join(', ')}');
      break;
      
    case StreakSortMode.mostRecent:
      friendStreaks.sort((a, b) {
        if (a.lastInteractionAt == null) return 1;  // ✅ Use real timestamps!
        if (b.lastInteractionAt == null) return -1;
        return b.lastInteractionAt!.compareTo(a.lastInteractionAt!);  // Most recent first
      });
      debugLog('🕐 SORT: Most Recent - Order: ${friendStreaks.map((s) => '${s.teamName}(${s.lastInteractionAt})').join(', ')}');
      break;
      
    case StreakSortMode.favorites:
      // ✨ Filter to only favorites
      final favorites = friendStreaks.where((s) => s.isFavorite).toList();
      favorites.sort((a, b) => b.currentStreak.compareTo(a.currentStreak));
      debugLog('⭐ SORT: Favorites - Found ${favorites.length} favorite(s)');
      return favorites; // ✅ Return empty list if no favorites
      
    case StreakSortMode.mostUrgent:
      // At-risk first (nobody checked in today), longest streak as tiebreaker
      // so the most valuable streak at risk sits at the top.
      friendStreaks.sort((a, b) {
        if (a.isAtRisk != b.isAtRisk) return a.isAtRisk ? -1 : 1;
        return b.currentStreak.compareTo(a.currentStreak);
      });
      debugLog('⚠️ SORT: At Risk First - Order: ${friendStreaks.map((s) => '${s.teamName}(risk:${s.isAtRisk},${s.currentStreak})').join(', ')}');
      break;

    case StreakSortMode.alphabetical:
      friendStreaks.sort((a, b) =>
          a.teamName.toLowerCase().compareTo(b.teamName.toLowerCase()));
      debugLog('🔤 SORT: A to Z - Order: ${friendStreaks.map((s) => s.teamName).join(', ')}');
      break;

    case StreakSortMode.custom:
      // Don't need any code here for now
      break;
  }
  
  debugLog('✅ SORT: Returning ${friendStreaks.length} sorted streaks');
  return friendStreaks;
}


/// Brand gradient, fixed per CLAUDE.md. Coach Max's identity depends on it, so
/// it is deliberately NOT an accent token — it must not shift with the skin.
const _kBrandGradient = [Color(0xFF1D4ED8), Color(0xFF7C3AED)];


// ═══════════════════════════════════════════════════════════════
// WEEKLY PLAN DIALOG — Editorial stepper redesign
// Returns breakDays (int) on confirm, null on cancel.
// ═══════════════════════════════════════════════════════════════
class _WeeklyPlanDialog extends StatefulWidget {
  final int initialWorkoutDays;
  const _WeeklyPlanDialog({required this.initialWorkoutDays});

  @override
  State<_WeeklyPlanDialog> createState() => _WeeklyPlanDialogState();
}

class _WeeklyPlanDialogState extends State<_WeeklyPlanDialog>
    with SingleTickerProviderStateMixin {
  late int _workoutDays;
  late AnimationController _numAnim;
  late Animation<double> _scaleAnim;

  static const int _min = 4;
  static const int _max = 7;

  @override
  void initState() {
    super.initState();
    _workoutDays = widget.initialWorkoutDays.clamp(_min, _max);
    _numAnim = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 120),
    );
    _scaleAnim = Tween<double>(begin: 1.0, end: 1.18).animate(
      CurvedAnimation(parent: _numAnim, curve: Curves.easeOut),
    );
  }

  @override
  void dispose() {
    _numAnim.dispose();
    super.dispose();
  }

  void _step(int delta) {
    final next = (_workoutDays + delta).clamp(_min, _max);
    if (next == _workoutDays) return;
    setState(() => _workoutDays = next);
    _numAnim.forward(from: 0).then((_) => _numAnim.reverse());
  }

  double get _trackProgress =>
      (_workoutDays - _min) / (_max - _min);

  @override
  Widget build(BuildContext context) {
    final appColors = AppColors.of(context);
    final cs = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final breakDays = 7 - _workoutDays;

    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 40),
      child: Container(
        decoration: BoxDecoration(
          color: appColors.cardBackground,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: appColors.cardBorder, width: 0.5),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // ── Header ──────────────────────────────────────────
            Container(
              padding: const EdgeInsets.fromLTRB(20, 20, 20, 16),
              decoration: BoxDecoration(
                border: Border(
                  bottom: BorderSide(
                      color: appColors.cardBorder, width: 0.5),
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'THIS WEEK',
                    style: TextStyle(
                      fontSize: 9,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 1.2,
                      color: const Color(0xFFF97316),
                    ),
                  ),
                  const SizedBox(height: 4),
                  RichText(
                    text: TextSpan(
                      style: TextStyle(
                        fontSize: 28,
                        fontWeight: FontWeight.w900,
                        letterSpacing: -1.5,
                        height: 0.9,
                        color: cs.onSurface,
                      ),
                      children: [
                        const TextSpan(text: 'WORKOUT\n'),
                        TextSpan(
                          text: 'PLAN',
                          style: TextStyle(
                            color: isDark
                                ? const Color(0xFF7C3AED)
                                : const Color(0xFF6D28D9),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),

            // ── Body ─────────────────────────────────────────────
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 20, 20, 0),
              child: Column(
                children: [
                  // Big animated number
                  ScaleTransition(
                    scale: _scaleAnim,
                    child: Column(
                      children: [
                        Text(
                          '$_workoutDays',
                          style: const TextStyle(
                            fontSize: 72,
                            fontWeight: FontWeight.w900,
                            letterSpacing: -4,
                            height: 1,
                            color: Color(0xFFF97316),
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          'workout day${_workoutDays == 1 ? '' : 's'}',
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w700,
                            letterSpacing: 0.3,
                            color: appColors.subtleText,
                          ),
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(height: 20),

                  // Stepper row: − track +
                  Row(
                    children: [
                      _StepButton(
                        label: '−',
                        enabled: _workoutDays > _min,
                        onTap: () => _step(-1),
                        appColors: appColors,
                        cs: cs,
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          children: [
                            // Gradient track
                            ClipRRect(
                              borderRadius: BorderRadius.circular(3),
                              child: SizedBox(
                                height: 5,
                                child: Stack(
                                  children: [
                                    Container(
                                        color: appColors.divider),
                                    FractionallySizedBox(
                                      widthFactor: _trackProgress,
                                      child: Container(
                                        decoration: const BoxDecoration(
                                          gradient: LinearGradient(
                                            colors: [
                                              Color(0xFFF97316),
                                              Color(0xFF7C3AED),
                                            ],
                                          ),
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                            const SizedBox(height: 6),
                            Row(
                              mainAxisAlignment:
                                  MainAxisAlignment.spaceBetween,
                              children: [
                                Text('4 days',
                                    style: TextStyle(
                                        fontSize: 10,
                                        color: appColors.subtleText)),
                                Text('7 days',
                                    style: TextStyle(
                                        fontSize: 10,
                                        color: appColors.subtleText)),
                              ],
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 12),
                      _StepButton(
                        label: '+',
                        enabled: _workoutDays < _max,
                        onTap: () => _step(1),
                        appColors: appColors,
                        cs: cs,
                        accent: true,
                      ),
                    ],
                  ),

                  const SizedBox(height: 20),

                  // Break days info row
                  AnimatedContainer(
                    duration: const Duration(milliseconds: 200),
                    padding: const EdgeInsets.symmetric(
                        horizontal: 16, vertical: 12),
                    decoration: BoxDecoration(
                      color: const Color(0xFF3B82F6).withValues(alpha: 0.08),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                          color:
                              const Color(0xFF3B82F6).withValues(alpha: 0.2),
                          width: 0.5),
                    ),
                    child: Row(
                      children: [
                        const Text('🌙',
                            style: TextStyle(fontSize: 18)),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            '$breakDays break day${breakDays == 1 ? '' : 's'}',
                            style: const TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.w700,
                              color: Color(0xFF3B82F6),
                            ),
                          ),
                        ),
                        Text(
                          '$breakDays',
                          style: TextStyle(
                            fontSize: 28,
                            fontWeight: FontWeight.w900,
                            letterSpacing: -1,
                            color: const Color(0xFF3B82F6)
                                .withValues(alpha: 0.35),
                          ),
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(height: 12),

                  Text(
                    'Your streak stays safe on break days.',
                    style: TextStyle(
                      fontSize: 11,
                      color: appColors.subtleText,
                      height: 1.4,
                    ),
                    textAlign: TextAlign.center,
                  ),

                  const SizedBox(height: 20),
                ],
              ),
            ),

            // ── Actions ──────────────────────────────────────────
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
              child: Row(
                children: [
                  Expanded(
                    child: GestureDetector(
                      onTap: () => Navigator.pop(context),
                      child: Container(
                        padding:
                            const EdgeInsets.symmetric(vertical: 14),
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                              color: appColors.cardBorder, width: 0.5),
                        ),
                        child: Center(
                          child: Text(
                            'Cancel',
                            style: TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w600,
                              color: appColors.subtleText,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    flex: 2,
                    child: GestureDetector(
                      onTap: () => Navigator.pop(context, breakDays),
                      child: Container(
                        padding:
                            const EdgeInsets.symmetric(vertical: 14),
                        decoration: BoxDecoration(
                          color: const Color(0xFFF97316),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: const Center(
                          child: Text(
                            'Set Plan',
                            style: TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w800,
                              color: Colors.white,
                              letterSpacing: 0.2,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Stepper button ──────────────────────────────────────────────
class _StepButton extends StatelessWidget {
  final String label;
  final bool enabled;
  final bool accent;
  final VoidCallback onTap;
  final AppColors appColors;
  final ColorScheme cs;

  const _StepButton({
    required this.label,
    required this.enabled,
    required this.onTap,
    required this.appColors,
    required this.cs,
    this.accent = false,
  });

  @override
  Widget build(BuildContext context) {
      final active = enabled && accent;
      return GestureDetector(
        onTap: enabled ? onTap : null,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          width: 44,
          height: 44,
          decoration: BoxDecoration(
            color: active
                ? const Color(0xFFF97316)
                : appColors.sectionBackground,
            shape: BoxShape.circle,
            border: Border.all(
              color: active
                  ? const Color(0xFFF97316)
                  : appColors.cardBorder,
              width: 0.5,
            ),
          ),
          child: Center(
            child: Text(
              label,
              style: TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.w700,
                height: 1,
                color: !enabled
                    ? appColors.subtleText.withValues(alpha: 0.4)
                    : active
                        ? Colors.white
                        : cs.onSurface,
              ),
            ),
          ),
        ),
      );
    }
}

  // ── Custom nav bar ─────────────────────────────────────────────────────────

class _GymBuddyNavBar extends StatelessWidget {
    final int selectedIndex;
    final ValueChanged<int> onTabSelected;

    const _GymBuddyNavBar({
      required this.selectedIndex,
      required this.onTabSelected,
    });

    @override
    Widget build(BuildContext context) {
      final c = AppColors.of(context);
      // Same clay language as the cards above it: raised slab, dual shadow,
      // rounded top so the bar reads as part of one surface system.
      final inactiveColor = c.inkMuted;
      final activeColor = c.readableForeground(c.claySurface);

      return Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [c.claySurfaceLight, c.claySurface],
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
          ),
          borderRadius: const BorderRadius.vertical(top: Radius.circular(26)),
          boxShadow: c.clayShadow(),
        ),
        child: SafeArea(
          top: false,
          child: SizedBox(
            height: 62,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              // Schedule (logical 0)
              _NavIcon(
                icon: Icons.calendar_today_outlined,
                activeIcon: Icons.calendar_today,
                isActive: selectedIndex == 0,
                color: selectedIndex == 0 ? activeColor : inactiveColor,
                semanticLabel: 'Schedule',
                onTap: () {
                  HapticFeedback.selectionClick();
                  onTabSelected(0);
                },
              ),
              // Buddies (logical 1)
              _NavIcon(
                icon: Icons.people_outline,
                activeIcon: Icons.people,
                isActive: selectedIndex == 1,
                color: selectedIndex == 1 ? activeColor : inactiveColor,
                semanticLabel: 'Buddies',
                onTap: () {
                  HapticFeedback.selectionClick();
                  onTabSelected(1);
                },
              ),
              // 🔥 Streaks — centre hero (logical 2)
              _FireNavButton(
                isActive: selectedIndex == 2,
                onTap: () {
                  HapticFeedback.mediumImpact();
                  onTabSelected(2);
                },
              ),
              // Shop (logical 3)
              _NavIcon(
                icon: Icons.shopping_bag_outlined,
                activeIcon: Icons.shopping_bag,
                isActive: selectedIndex == 3,
                color: selectedIndex == 3 ? activeColor : inactiveColor,
                semanticLabel: 'Shop',
                onTap: () {
                  HapticFeedback.selectionClick();
                  onTabSelected(3);
                },
              ),
              // Profile (logical 4)
              _NavIcon(
                icon: Icons.person_outline,
                activeIcon: Icons.person,
                isActive: selectedIndex == 4,
                color: selectedIndex == 4 ? activeColor : inactiveColor,
                semanticLabel: 'Profile',
                onTap: () {
                  HapticFeedback.selectionClick();
                  onTabSelected(4);
                },
              ),
              ],
            ),
          ),
        ),
      );
    }
  }

class _NavIcon extends StatelessWidget {

    final IconData icon;
    final IconData activeIcon;
    final bool isActive;
    final Color color;
    final String semanticLabel;
    final VoidCallback onTap;

    const _NavIcon({
      required this.icon,
      required this.activeIcon,
      required this.isActive,
      required this.color,
      required this.semanticLabel,
      required this.onTap,
    });

    @override
    Widget build(BuildContext context) {
      return Semantics(
        label: semanticLabel,
        button: true,
        child: GestureDetector(
          onTap: onTap,
          behavior: HitTestBehavior.opaque,
          child: SizedBox(
            width: 48,
            height: 48,
            child: Center(
              child: Icon(
                isActive ? activeIcon : icon,
                color: color,
                size: 26,
              ),
            ),
          ),
        ),
      );
    }
  }

class _FireNavButton extends StatelessWidget {

    final bool isActive;
    final VoidCallback onTap;

    const _FireNavButton({required this.isActive, required this.onTap});

    @override
    Widget build(BuildContext context) {
      final c = AppColors.of(context);
      return Semantics(
        label: 'Streaks',
        button: true,
        child: GestureDetector(
          onTap: onTap,
          child: Transform.translate(
            offset: const Offset(0, -10),
            child: Container(
              width: 54,
              height: 54,
              decoration: BoxDecoration(
                // Same action gradient as the Check In CTA, so the hero button
                // and the hero action read as one thing.
                gradient: LinearGradient(
                  colors: c.actionGradient,
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius: BorderRadius.circular(18),
                boxShadow: c.clayShadow(inset: isActive),
              ),
              child: Center(
                child: Icon(Icons.local_fire_department,
                    color: c.readableForeground(c.streakOrange), size: 32),
              ),
            ),
          ),
        ),
      );
    }
  }

/// The Log Out control. A repeat tap while a log out is running is ignored.
class LogoutButton extends StatefulWidget {
  final Future<void> Function() onLogout;
  const LogoutButton({super.key, required this.onLogout});

  @override
  State<LogoutButton> createState() => _LogoutButtonState();
}

class _LogoutButtonState extends State<LogoutButton> {
  final _once = RunOnce();

  @override
  void dispose() {
    _once.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => _once.run(widget.onLogout),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(vertical: 10),
        decoration: BoxDecoration(
          color: const Color(0xFFE53935).withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: const Color(0xFFE53935).withValues(alpha: 0.3), width: 1.5),
        ),
        child: const Center(
          child: Text(
            'Log Out',
            style: TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w600,
              color: Color(0xFFE53935),
            ),
          ),
        ),
      ),
    );
  }
}
