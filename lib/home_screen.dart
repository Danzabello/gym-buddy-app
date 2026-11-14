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

part 'home/checkin_ring.dart';
part 'home/dashboard_page.dart';
part 'home/home_shell.dart';


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

class _AllStreaksDialog extends StatefulWidget {
  final List<TeamStreak> streaks;
  const _AllStreaksDialog({required this.streaks});

  @override
  State<_AllStreaksDialog> createState() => _AllStreaksDialogState();
}

class _AllStreaksDialogState extends State<_AllStreaksDialog> {
  late List<TeamStreak> _streaks;
  final _once = RunOnce();

  @override
  void initState() {
    super.initState();
    _streaks = List.from(widget.streaks);
  }

  @override
  void dispose() {
    _once.dispose();
    super.dispose();
  }

  // ── Rename ──────────────────────────────────────────────
  Future<void> _showRenameDialog(TeamStreak streak) async {
    final appColors = AppColors.of(context);
    final cs = Theme.of(context).colorScheme;
    var input = streak.teamName;

    final newName = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: appColors.cardBackground,
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16)),
        title: Row(children: [
          Icon(Icons.edit_outlined,
              color: const Color(0xFF3B82F6), size: 20),
          const SizedBox(width: 10),
          Text('Rename team',
              style: TextStyle(
                  color: cs.onSurface,
                  fontSize: 16,
                  fontWeight: FontWeight.w700)),
        ]),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Give your partnership a custom name',
                style: TextStyle(
                    fontSize: 13, color: appColors.subtleText)),
            const SizedBox(height: 14),
            TextFormField(
              initialValue: input,
              onChanged: (v) => input = v,
              autofocus: true,
              textCapitalization: TextCapitalization.words,
              style: TextStyle(color: cs.onSurface),
              decoration: InputDecoration(
                labelText: 'Team name',
                hintText: 'e.g. Morning Crew',
                border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10)),
                prefixIcon: const Icon(Icons.group_outlined),
              ),
              onFieldSubmitted: (v) => Navigator.pop(context, v),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text('Cancel',
                style:
                    TextStyle(color: appColors.subtleText)),
          ),
          GestureDetector(
            onTap: () =>
                Navigator.pop(context, input),
            child: Container(
              padding: const EdgeInsets.symmetric(
                  horizontal: 16, vertical: 8),
              decoration: BoxDecoration(
                color: const Color(0xFF3B82F6),
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Text('Save',
                  style: TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w700)),
            ),
          ),
        ],
      ),
    );

    if (newName != null &&
        newName.trim().isNotEmpty &&
        newName != streak.teamName) {
      await _updateTeamName(streak, newName.trim());
    }
  }

  Future<void> _updateTeamName(
      TeamStreak streak, String newName) async {
    try {
      await Supabase.instance.client
          .from('buddy_teams')
          .update({'team_name': newName})
          .eq('id', streak.teamId);

      // Update local list immediately without waiting for a full reload
      if (mounted) {
        setState(() {
          final idx = _streaks.indexWhere((s) => s.teamId == streak.teamId);
          if (idx != -1) {
            final updated = List<TeamStreak>.from(_streaks);
            updated[idx] = TeamStreak(
              id: streak.id,
              teamId: streak.teamId,
              teamName: newName,
              teamEmoji: streak.teamEmoji,
              currentStreak: streak.currentStreak,
              longestStreak: streak.longestStreak,
              totalWorkouts: streak.totalWorkouts,
              bestStreak: streak.bestStreak,
              lastWorkoutDate: streak.lastWorkoutDate,
              lastInteractionAt: streak.lastInteractionAt,
              isCoachMaxTeam: streak.isCoachMaxTeam,
              members: streak.members,
              todayCheckIns: streak.todayCheckIns,
              isFavorite: streak.isFavorite,
            );
            _streaks = updated;
          }
        });
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('Renamed to "$newName"'),
          backgroundColor: AppColors.of(context).success,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(8)),
        ));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Failed to rename')));
      }
    }
  }

  // ── Buddy helpers ────────────────────────────────────────
  String _buddyName(TeamStreak streak) {
    if (streak.isCoachMaxTeam) return 'Coach Max';
    final me =
        Supabase.instance.client.auth.currentUser?.id;
    final buddy = streak.members.firstWhere(
        (m) => m.userId != me,
        orElse: () => streak.members.first);
    return buddy.displayName;
  }

  String _buddyAvatar(TeamStreak streak) {
    if (streak.isCoachMaxTeam) return 'coach_max';
    final me =
        Supabase.instance.client.auth.currentUser?.id;
    final buddy = streak.members.firstWhere(
        (m) => m.userId != me,
        orElse: () => streak.members.first);
    return buddy.avatarId ?? 'avatar_1';
  }

  @override
  Widget build(BuildContext context) {
    final appColors = AppColors.of(context);
    final cs = Theme.of(context).colorScheme;

    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding:
          const EdgeInsets.symmetric(horizontal: 24, vertical: 40),
      child: Container(
            constraints: const BoxConstraints(
            maxWidth: 400),
        decoration: BoxDecoration(
          color: appColors.cardBackground,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
              color: appColors.cardBorder, width: 0.5),
        ),
        child: SingleChildScrollView(
          child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // ── Header ──────────────────────────────────
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [
                    Color(0xFFF97316),
                    AppColors.of(context).streakOrange
                  ],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius: BorderRadius.vertical(
                    top: Radius.circular(20)),
              ),
              child: Row(children: [
                const Text('🔥',
                    style: TextStyle(fontSize: 20)),
                const SizedBox(width: 10),
                const Expanded(
                  child: Text('All Your Streaks',
                      style: TextStyle(
                          fontSize: 17,
                          fontWeight: FontWeight.w800,
                          color: Colors.white,
                          letterSpacing: -0.3)),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 10, vertical: 3),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.2),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Text('${_streaks.length}',
                      style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w700,
                          fontSize: 13)),
                ),
              ]),
            ),

            // ── Tip ──────────────────────────────────────
            Container(
              padding: const EdgeInsets.symmetric(
                  horizontal: 14, vertical: 9),
              decoration: BoxDecoration(
                border: Border(
                  bottom: BorderSide(
                      color: appColors.divider, width: 0.5),
                ),
              ),
              child: Row(children: [
                const Text('✏️',
                    style: TextStyle(fontSize: 12)),
                const SizedBox(width: 7),
                Text('Tap the edit icon to rename any team',
                    style: TextStyle(
                        fontSize: 10,
                        color: appColors.subtleText)),
              ]),
            ),

            // ── List ──────────────────────────────────────
            Flexible(
              child: _streaks.isEmpty
                  ? Center(
                      child: Padding(
                        padding: const EdgeInsets.all(32),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.sentiment_neutral,
                                size: 48,
                                color: appColors.subtleText),
                            const SizedBox(height: 12),
                            Text('No active streaks yet!',
                                style: TextStyle(
                                    color: appColors.subtleText)),
                          ],
                        ),
                      ),
                    )
                  : ListView.builder(
                      padding: const EdgeInsets.fromLTRB(
                          12, 8, 12, 4),
                      shrinkWrap: true,
                      itemCount: _streaks.length,
                      itemBuilder: (context, i) =>
                          _streakRow(_streaks[i],
                              appColors, cs),
                    ),
            ),

            // ── Close ─────────────────────────────────────
            Padding(
              padding: const EdgeInsets.all(12),
              child: GestureDetector(
                onTap: () => Navigator.pop(context),
                child: Container(
                  width: double.infinity,
                  padding:
                      const EdgeInsets.symmetric(vertical: 13),
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                      colors: [
                        Color(0xFF1D4ED8),
                        Color(0xFF7C3AED)
                      ],
                    ),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Center(
                    child: Text('Close',
                        style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w700,
                            color: Colors.white)),
                  ),
                ),
              ),
            ),
          ],
        ),
        ), // SingleChildScrollView
      ),
    );
  }

  Widget _streakRow(TeamStreak streak,
      AppColors appColors, ColorScheme cs) {
    final isCoach = streak.isCoachMaxTeam;
    final isComplete = streak.isCompleteToday;
    final buddyName = _buddyName(streak);

    return Container(
      margin: const EdgeInsets.only(bottom: 7),
      decoration: BoxDecoration(
        color: isCoach
            ? const Color(0xFFF97316).withValues(alpha: 0.06)
            : appColors.sectionBackground,
        borderRadius: BorderRadius.circular(11),
        border: Border.all(
          color: isCoach
              ? const Color(0xFFF97316).withValues(alpha: 0.2)
              : appColors.cardBorder,
          width: 0.5,
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(9),
        child: Row(children: [
          // Avatar
          Stack(
            clipBehavior: Clip.none,
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: LinearGradient(
                    colors: isCoach
                        ? [
                            const Color(0xFF1D4ED8),
                            const Color(0xFF7C3AED)
                          ]
                        : [
                            const Color(0xFFF97316),
                            AppColors.of(context).streakOrange
                          ],
                  ),
                ),
                child: isCoach
                    ? const Center(
                        child: Text('🤖',
                            style: TextStyle(fontSize: 20)))
                    : ClipOval(
                        child: UserAvatar(
                            avatarId: _buddyAvatar(streak),
                            size: 40)),
              ),
              // 🤖 AI disclosure — this row sits in the same list as real buddies.
              if (isCoach)
                Positioned(
                  bottom: -2,
                  right: -6,
                  child: AiCornerBadge(scale: 0.85),
                ),
            ],
          ),
          const SizedBox(width: 10),
          // Name + buddy
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  isCoach ? 'Coach Max' : streak.teamName,
                  style: TextStyle(
                      fontSize: streak.teamName.length > 20
                          ? 10
                          : 12,
                      fontWeight: FontWeight.w700,
                      color: cs.onSurface),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                Text(
                  isCoach
                      ? 'always here'
                      : 'with $buddyName',
                  style: TextStyle(
                      fontSize: 9,
                      color: appColors.subtleText),
                ),
              ],
            ),
          ),
          // Streak count
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                '${streak.currentStreak}',
                style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w900,
                    letterSpacing: -0.5,
                    color: isComplete
                        ? appColors.success
                        : const Color(0xFFF97316)),
              ),
              Text('day streak',
                  style: TextStyle(
                      fontSize: 8,
                      color: appColors.subtleText)),
            ],
          ),
          const SizedBox(width: 6),
          // Status + edit
          if (!isCoach)
            GestureDetector(
              onTap: () => _once.run(() => _showRenameDialog(streak)),
              child: Container(
                width: 28,
                height: 28,
                decoration: BoxDecoration(
                  color: appColors.cardBackground,
                  borderRadius: BorderRadius.circular(7),
                  border: Border.all(
                      color: appColors.cardBorder, width: 0.5),
                ),
                child: Icon(Icons.edit_outlined,
                    size: 14,
                    color: appColors.subtleText),
              ),
            )
          else
            Container(
              width: 28,
              height: 28,
              decoration: BoxDecoration(
                color: isComplete
                    ? appColors.success.withValues(alpha: 0.12)
                    : appColors.sectionBackground,
                shape: BoxShape.circle,
              ),
              child: Icon(
                isComplete ? Icons.check : Icons.access_time,
                size: 15,
                color: isComplete
                    ? appColors.success
                    : appColors.subtleText,
              ),
            ),
        ]),
      ),
    );
  }
}

// Profile Page
class ProfilePage extends StatefulWidget {
  const ProfilePage({super.key});

  @override
  State<ProfilePage> createState() => _ProfilePageState();
}
 
class _ProfilePageState extends State<ProfilePage>
    with TickerProviderStateMixin {
  Map<String, dynamic>? _profile;
  List<TeamStreak> _allStreaks = [];
  StreakSortMode _streakSortMode = StreakSortMode.highestCurrent;
  /// Mirrors the dashboard's list so both entry points agree.
  List<TeamStreak> get _listStreaks => sortStreaks(_allStreaks, _streakSortMode);
  /// Total sortable streaks (friends only), independent of sort/filter mode.
  int get _streakCount => _allStreaks.where((s) => !s.isCoachMaxTeam).length;
  LevelInfo? _levelInfo;
  int _totalWorkouts = 0;
  int _buddyCount = 0;
  /// Top 3 workout_category values for the CURRENT CALENDAR MONTH in the
  /// user's own local timezone, from get_favourite_categories (the RPC does
  /// the month + tz resolution server-side). Each row:
  /// {workout_category, category_count}. Empty is a normal state — the card
  /// is hidden rather than showing a zero.
  List<Map<String, dynamic>> _favouriteCategories = [];
  bool _isLoading = true;
  final _once = RunOnce();

  late AnimationController _fadeController;
  late Animation<double> _xpAnimation;
  late Animation<double> _ringAnimation;
 
  @override
  void initState() {
    super.initState();
    _fadeController = AnimationController(
      duration: const Duration(milliseconds: 500),
      vsync: this,
    );
    _fadeController = AnimationController(
      duration: const Duration(milliseconds: 500),
      vsync: this,
    );
    _xpAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _fadeController, curve: const Interval(0.3, 1.0, curve: Curves.easeOut)),
    );
    _ringAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _fadeController, curve: const Interval(0.2, 1.0, curve: Curves.easeOut)),
    );
    _loadAll();
  }

  @override
  void dispose() {
    _once.dispose();
    _fadeController.dispose();
    super.dispose();
  }
 
  // ── data loading ──────────────────────────────────────────────
  Future<void> _loadAll() async {
    try {
      final uid = Supabase.instance.client.auth.currentUser?.id;
      if (uid == null) return;

      final profileFuture = Supabase.instance.client
          .rpc('get_my_profile')
          .select('avatar_id, display_name, created_at, xp, level, preferred_streak_sort')
          .single();

      final streaksFuture = TeamStreakService().getAllUserStreaks();
      final levelFuture = LevelService().getLevelInfo();
      final workoutsFuture = Supabase.instance.client
          .from('workouts')
          .select('id')
          .or('user_id.eq.$uid,buddy_id.eq.$uid')
          .eq('status', 'completed');
      final friendsFuture = FriendService().getFriends();
      final favouriteCategoriesFuture = Supabase.instance.client
          .rpc('get_favourite_categories', params: {'p_user_id': uid});

      final profile  = await profileFuture;
      final streaks  = await streaksFuture;
      final level    = await levelFuture;
      final workouts = await workoutsFuture;
      final friends  = await friendsFuture;
      final favouriteCategories = await favouriteCategoriesFuture;

      if (!mounted) return;

      setState(() {
        _profile       = profile;
        _allStreaks     = streaks;
        _streakSortMode = StreakSortMode.values.firstWhere(
          (e) => e.name == profile['preferred_streak_sort'],
          orElse: () => StreakSortMode.highestCurrent,
        );
        _levelInfo     = level;
        _totalWorkouts = (workouts as List).length;
        _buddyCount    = friends.length;
        _favouriteCategories = (favouriteCategories as List).cast<Map<String, dynamic>>();
        _isLoading     = false;
      });

      await Future.delayed(const Duration(milliseconds: 50));
      if (mounted) _fadeController.forward();
    } catch (e) {
      if (kDebugMode) debugLog('❌ ProfilePage._loadAll: $e');
      if (mounted) setState(() => _isLoading = false);
    }
  }

  int get _bestStreak => _allStreaks.isEmpty
      ? 0
      : _allStreaks.map((s) => s.bestStreak).reduce((a, b) => a > b ? a : b);

 
  // ══════════════════════════════════════════════════════════════
  // BUILD
  // ══════════════════════════════════════════════════════════════
  @override
  Widget build(BuildContext context) {
    if (_isLoading) return _buildSkeleton();

    final appColors = AppColors.of(context);
    final profile  = _profile ?? {};
    final level    = _levelInfo?.level ?? 1;
    final title    = _levelInfo?.title ?? 'Newcomer';
    final avatarId = profile['avatar_id'] as String? ?? 'lion';
    final name     = profile['display_name'] as String? ?? 'User';
    final year     = formatYear(profile['created_at'] as String?);

    return Scaffold(
      backgroundColor: appColors.sectionBackground,
      body: RefreshIndicator(
        onRefresh: () async {
          _fadeController.reset();
          await _loadAll();
        },
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          // The nav bar floats over the body (extendBody), so
          // reserve its height or the last card hides under it.
          padding: EdgeInsets.only(
            bottom: 62 + MediaQuery.paddingOf(context).bottom,
          ),
          children: [
            _buildHero(
              name: name, year: year, avatarId: avatarId,
              level: level, title: title,
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 5, 16, 32),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                      _buildXpCard(),
                      const SizedBox(height: 14),
                      _buildLifetimeStatsCard(),
                      // Hidden entirely when the user has logged nothing this
                      // month (e.g. the first days of a new month).
                      if (_favouriteCategories.isNotEmpty) ...[
                        const SizedBox(height: 14),
                        _buildTopCategoriesCard(),
                      ],
                      const SizedBox(height: 22),
                      _sectionLabel('Activity'),
                      const SizedBox(height: 10),
                      buildMenuCard(context, [
                        MenuItem(
                          emoji: '🔥',
                          color: appColors.sectionBackground,
                          label: 'All Streaks',
                          sub: '$_streakCount active streaks',
                          onTap: () => showDialog(
                            context: context,
                            builder: (_) => _AllStreaksDialog(streaks: _listStreaks),
                          ),
                        ),
                        MenuItem(
                          emoji: '🏆',
                          color: appColors.sectionBackground,
                          label: 'Achievements',
                          sub: 'View all achievements',
                          onTap: () => Navigator.push(
                            context,
                            MaterialPageRoute(builder: (_) => achievements_page.AchievementsPage()),
                          ),
                        ),
                        MenuItem(
                          emoji: '📊',
                          color: appColors.sectionBackground,
                          label: 'Progress',
                          sub: 'View your history',
                          onTap: () => Navigator.push(
                            context,
                            MaterialPageRoute(
                                builder: (_) => const WorkoutHistoryPage()),
                          ),
                        ),
                      ]),
                      const SizedBox(height: 22),
                      _sectionLabel('Settings'),
                      const SizedBox(height: 10),
                      buildMenuCard(context, [
                        MenuItem(
                          emoji: '🔔',
                          color: appColors.sectionBackground,
                          label: 'Notifications',
                          sub: 'Manage alerts',
                          onTap: () => Navigator.push(
                            context,
                            MaterialPageRoute(builder: (_) => const NotificationSettingsPage()),
                          ),
                        ),
                        MenuItem(
                          emoji: '🌈',
                          color: appColors.sectionBackground,
                          label: 'Accent Theme',
                          sub: _accentThemeLabel(context),
                          onTap: () => _showAccentThemePicker(context),
                        ),
                        MenuItem(
                          emoji: '❓',
                          color: appColors.sectionBackground,
                          label: 'Help & Support',
                          sub: 'FAQs & contact',
                          onTap: () => Navigator.push(
                            context,
                            MaterialPageRoute(builder: (_) => const HelpSupportPage()),
                          ),
                        ),
                        MenuItem(
                          icon: Icons.person_outline,
                          iconColor: appColors.subtleText,
                          color: appColors.sectionBackground,
                          label: 'Account',
                          sub: 'Email, username, delete',
                          onTap: () => Navigator.push(
                            context,
                            MaterialPageRoute(builder: (_) => const AccountPage()),
                          ),
                        ),
                      ]),
                      const SizedBox(height: 22),
                  _buildLogoutButton(),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _accentThemeLabel(BuildContext context) {
    final theme = context.watch<AccentThemeProvider>().accentTheme;
    return AccentPalette.forTheme(theme).name;
  }

  Future<void> _showAccentThemePicker(BuildContext context) {
    final provider = context.read<AccentThemeProvider>();
    return showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        final appColors = AppColors.of(context);
        return Container(
          decoration: BoxDecoration(
            color: appColors.cardBackground,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
          ),
          padding: const EdgeInsets.fromLTRB(24, 16, 24, 32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Handle
              Container(
                width: 40, height: 4,
                decoration: BoxDecoration(
                  color: appColors.divider,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(height: 20),
              Text(
                'Accent Theme',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                  color: Theme.of(context).colorScheme.onSurface,
                ),
              ),
              const SizedBox(height: 20),
              // Every skin's label, blurb and swatch comes off its palette —
              // adding an accent never touches this screen again.
              for (final theme in AccentTheme.values) ...[
                if (theme != AccentTheme.values.first)
                  const SizedBox(height: 10),
                _accentOption(ctx, provider, theme),
              ],
            ],
          ),
        );
      },
    );
  }

  Widget _accentOption(
    BuildContext ctx,
    AccentThemeProvider provider,
    AccentTheme theme,
  ) {
    final palette = AccentPalette.forTheme(theme);
    final isSelected = provider.accentTheme == theme;
    final appColors = AppColors.of(ctx);
    return GestureDetector(
      onTap: () {
        HapticFeedback.selectionClick();
        provider.setAccentTheme(theme);
        Navigator.pop(ctx);
        setState(() {}); // refresh sub-label
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        decoration: BoxDecoration(
          color: isSelected
              ? appColors.avatarRing.withValues(alpha: 0.1)
              : appColors.sectionBackground,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: isSelected ? appColors.avatarRing : appColors.cardBorder,
            width: isSelected ? 2 : 1,
          ),
        ),
        child: Row(
          children: [
            Container(
              width: 22,
              height: 22,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: palette.swatch,
                border: Border.all(color: appColors.cardBorder),
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    palette.name,
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                      color: isSelected
                          ? appColors.avatarRing
                          : Theme.of(ctx).colorScheme.onSurface,
                    ),
                  ),
                  Text(
                    palette.description,
                    style: TextStyle(fontSize: 12, color: appColors.subtleText),
                  ),
                ],
              ),
            ),
            if (isSelected)
              Icon(Icons.check_circle, color: appColors.avatarRing, size: 22),
          ],
        ),
      ),
    );
  }

  // ══════════════════════════════════════════════════════════════
  // HERO
  // ══════════════════════════════════════════════════════════════
  Widget _buildHero({
    required String name, required String year,
    required String avatarId, required int level, required String title,
  }) {
    // Hero fill follows the active accent theme (was a fixed purple gradient)
    final appColors = AppColors.of(context);
    return Container(
      decoration: BoxDecoration(
        color: appColors.cardBackground,
      ),
      child: SafeArea(
        bottom: false,
        child: Stack(
          children: [
            Positioned(
              top: -30, right: -30,
              child: Container(
                width: 160, height: 160,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: Colors.white.withValues(alpha: 0.06),
                ),
              ),
            ),
            Positioned(
              bottom: 20, left: -20,
              child: Container(
                width: 120, height: 120,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: Colors.white.withValues(alpha: 0.04),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 25),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text(
                        'Profile',
                        style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w700),
                      ),
                      GestureDetector(
                        onTap: () => _once.run(() => Navigator.push(
                          context,
                          MaterialPageRoute(builder: (_) => const NotificationSettingsPage()),
                        )),
                        child: Container(
                          width: 36, height: 36,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: Colors.white.withValues(alpha: 0.15),
                          ),
                          child: const Icon(Icons.settings_outlined, color: Colors.white, size: 18),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 20),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      GestureDetector(
                        onTap: () => _once.run(() async {
                          final saved = await Navigator.push<bool>(
                            context,
                            MaterialPageRoute(builder: (_) => const WardrobePage()),
                          );
                          if (saved == true) {
                            _fadeController.reset();
                            _loadAll();
                          }
                        }),
                        child: Stack(
                          clipBehavior: Clip.none,
                          alignment: Alignment.center,
                          children: [
                            SizedBox(
                              width: 98, height: 98,
                              child: AnimatedBuilder(
                                animation: _ringAnimation,
                                builder: (context, _) => CircularProgressIndicator(
                                  value: (_levelInfo?.progressPercent ?? 0.0) * _ringAnimation.value,
                                  strokeWidth: 4,
                                  backgroundColor: Colors.white.withValues(alpha: 0.2),
                                  valueColor: const AlwaysStoppedAnimation<Color>(Colors.white),
                                ),
                              ),
                            ),
                            Container(
                              width: 86, height: 86,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                color: Colors.white.withValues(alpha: 0.15),
                                border: Border.all(color: Colors.white.withValues(alpha: 0.3), width: 2),
                              ),
                              child: Center(
                                child: UserAvatar(
                                  avatarId: avatarId,
                                  size: 86,
                                  bare: true,
                                  animated: true,
                                  semanticLabel: '',
                                ),
                              ),
                            ),
                            Positioned(
                              bottom: -4, right: -4,
                              child: Container(
                                width: 30, height: 30,
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  gradient: LinearGradient(
                                    colors: levelGradient(level),
                                    begin: Alignment.topLeft,
                                    end: Alignment.bottomRight,
                                  ),
                                  border: Border.all(color: Colors.white, width: 2),
                                  boxShadow: [
                                    BoxShadow(
                                      color: levelGradient(level).last.withValues(alpha: 0.5),
                                      blurRadius: 8,
                                    ),
                                  ],
                                ),
                                child: Center(
                                  child: Text(
                                    '$level',
                                    style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w800, color: Colors.white),
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisAlignment: MainAxisAlignment.end,
                          children: [
                            Text(
                              name,
                              style: const TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.w800),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              'Member since $year',
                              style: TextStyle(color: Colors.white.withValues(alpha: 0.65), fontSize: 13),
                            ),
                            const SizedBox(height: 8),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                              decoration: BoxDecoration(
                                borderRadius: BorderRadius.circular(20),
                                color: Colors.white.withValues(alpha: 0.18),
                                border: Border.all(color: Colors.white.withValues(alpha: 0.3)),
                              ),
                              child: Text(
                                '${titleIcon(title)}  $title',
                                style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w600),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
 
  // ══════════════════════════════════════════════════════════════
  // XP CARD
  // ══════════════════════════════════════════════════════════════
  Widget _buildXpCard() {
    final appColors = AppColors.of(context);
    final accentPalette = context.watch<AccentThemeProvider>().palette;
    return Container(
      decoration: BoxDecoration(
        color: appColors.cardBackground,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: accentPalette.statusInfo.withValues(alpha: 0.1),
            blurRadius: 24,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: _levelInfo == null
          ? const Padding(
              padding: EdgeInsets.all(20),
              child: Center(child: CircularProgressIndicator()),
            )
          : Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                children: [
                  Row(
                    children: [
                      Container(
                        width: 40, height: 40,
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(12),
                          color: accentPalette.statusInfo,
                        ),
                        child: const Center(child: Text('⭐', style: TextStyle(fontSize: 20))),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Level ${_levelInfo!.level} — ${_levelInfo!.title}',
                              style: TextStyle(
                                fontSize: 15,
                                fontWeight: FontWeight.w700,
                                color: Theme.of(context).colorScheme.onSurface,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              _levelInfo!.level >= 99
                                  ? 'Max level reached 🏆'
                                  : '${_levelInfo!.xpNeededForNext} XP to level ${_levelInfo!.level + 1}',
                              style: TextStyle(fontSize: 12, color: appColors.subtleText),
                            ),
                          ],
                        ),
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
                        decoration: BoxDecoration(
                          color: accentPalette.statusInfo.withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Text(
                          '${_levelInfo!.currentXp} XP',
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w700,
                            color: accentPalette.statusInfo,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 14),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(100),
                    child: AnimatedBuilder(
                      animation: _xpAnimation,
                      builder: (context, _) => LinearProgressIndicator(
                        value: _levelInfo!.progressPercent * _xpAnimation.value,
                        minHeight: 8,
                        backgroundColor: appColors.sectionBackground,
                        valueColor: AlwaysStoppedAnimation<Color>(accentPalette.statusInfo),
                      ),
                    ),
                  ),
                  const SizedBox(height: 6),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        '${_levelInfo!.xpIntoCurrentLevel} / ${_levelInfo!.xpForNextLevel - _levelInfo!.xpForThisLevel} XP',
                        style: TextStyle(fontSize: 11, color: appColors.subtleText),
                      ),
                      Text(
                        '${(_levelInfo!.progressPercent * 100).toStringAsFixed(0)}%',
                        style: TextStyle(fontSize: 11, color: appColors.subtleText),
                      ),
                    ],
                  ),
                ],
              ),
            ),
    );
  }
 
  // ══════════════════════════════════════════════════════════════
  // STATS ROW
  // ══════════════════════════════════════════════════════════════
  // ══════════════════════════════════════════════════════════════
  // LIFETIME STATS
  // ══════════════════════════════════════════════════════════════
  // Replaces the old four-tile emoji stats row. The dropped 4th tile was
  // 'Streaks' showing _allStreaks.length -- every streak INCLUDING the Coach
  // Max team, which disagreed with the "All Streaks" menu row below (that one
  // uses _streakCount, friends-only). Dropping it removes the mismatch rather
  // than carrying it into the new card.
  //
  // Uses the radius-20 card token shared with _buildXpCard and the top
  // categories card, not the lighter radius-16 one the old tiles had.
  Widget _buildLifetimeStatsCard() {
    final appColors = AppColors.of(context);
    final accentPalette = context.watch<AccentThemeProvider>().palette;

    return Container(
      decoration: BoxDecoration(
        color: appColors.cardBackground,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: accentPalette.statusInfo.withValues(alpha: 0.1),
            blurRadius: 24,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'LIFETIME STATS',
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.8,
              color: appColors.subtleText,
            ),
          ),
          const SizedBox(height: 10),
          // IntrinsicHeight so the hairline dividers span the tallest block
          // rather than collapsing to zero height.
          IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(child: _lifetimeStatBlock(_bestStreak, 'Best streak')),
                _statDivider(),
                Expanded(child: _lifetimeStatBlock(_totalWorkouts, 'Workouts')),
                _statDivider(),
                Expanded(child: _lifetimeStatBlock(_buddyCount, 'Buddies')),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _statDivider() {
    final appColors = AppColors.of(context);
    return Container(width: 1, color: appColors.divider);
  }

  Widget _lifetimeStatBlock(int value, String caption) {
    final appColors = AppColors.of(context);
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        CappedCount(
          value: value,
          style: TextStyle(
            fontSize: 24,
            fontWeight: FontWeight.w800,
            color: Theme.of(context).colorScheme.onSurface,
          ),
        ),
        Text(
          caption,
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w500,
            color: appColors.subtleText,
          ),
        ),
      ],
    );
  }

  // ══════════════════════════════════════════════════════════════
  // THIS MONTH'S TOP CATEGORIES
  // ══════════════════════════════════════════════════════════════
  // Category keys/labels mirror WorkoutSelectionModal._categoryDefs (the
  // canonical "10 category tile" list from the check-in grid). Not shared as
  // a common lookup — this page only touches its own file, matching
  // titleIcon above.
  //
  // The per-category emoji lookup that used to live here is gone: rows are
  // ranked 1/2/3 by number now, and neither of the two new cards uses emoji.
  String _categoryLabel(String category) {
    const map = {
      'strength': 'Strength',
      'cardio': 'Cardio',
      'hiit': 'HIIT',
      'yoga': 'Yoga / stretch',
      'outside': 'Outside',
      'sports': 'Sports',
      'swimming': 'Swimming',
      'cycling': 'Cycling',
      'martial_arts': 'Martial arts',
      'recovery': 'Recovery',
    };
    return map[category] ?? category;
  }

  Widget _buildTopCategoriesCard() {
    final appColors = AppColors.of(context);
    final accentPalette = context.watch<AccentThemeProvider>().palette;
    final topCount = (_favouriteCategories.first['category_count'] as num).toInt();

    return Container(
      decoration: BoxDecoration(
        color: appColors.cardBackground,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: accentPalette.statusInfo.withValues(alpha: 0.1),
            blurRadius: 24,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // The title carries the timeframe on its own — no corner tag.
          Text(
            "This Month's Top Categories",
            style: TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w700,
              color: Theme.of(context).colorScheme.onSurface,
            ),
          ),
          const SizedBox(height: 8),
          for (int i = 0; i < _favouriteCategories.length; i++)
            _buildCategoryRow(
              rank: i + 1,
              category: _favouriteCategories[i]['workout_category'] as String,
              count: (_favouriteCategories[i]['category_count'] as num).toInt(),
              topCount: topCount,
              isTop: i == 0,
            ),
        ],
      ),
    );
  }

  Widget _buildCategoryRow({
    required int rank,
    required String category,
    required int count,
    required int topCount,
    required bool isTop,
  }) {
    final appColors = AppColors.of(context);
    final accentPalette = context.watch<AccentThemeProvider>().palette;
    // No gold slot exists on AccentPalette; statusWarning is its amber, and
    // it is the one warm token that is contrast-tuned per palette (action is
    // reserved for the primary CTA per the brand rule).
    final gold = accentPalette.statusWarning;
    final rankColor = isTop ? gold : appColors.subtleText;
    final barColor = isTop ? gold : appColors.subtleText;
    final fraction = topCount == 0 ? 0.0 : count / topCount;

    return Row(
      children: [
        SizedBox(
          width: 16,
          child: Text(
            '$rank',
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w800,
              color: rankColor,
            ),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                _categoryLabel(category),
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: Theme.of(context).colorScheme.onSurface,
                ),
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: 6),
              ClipRRect(
                borderRadius: BorderRadius.circular(100),
                child: LinearProgressIndicator(
                  value: fraction,
                  minHeight: 5,
                  backgroundColor: appColors.sectionBackground,
                  valueColor: AlwaysStoppedAnimation<Color>(barColor),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(width: 10),
        CappedCount(
          value: count,
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w800,
            color: rankColor,
          ),
        ),
      ],
    );
  }

  // ══════════════════════════════════════════════════════════════
  // MENU
  // ══════════════════════════════════════════════════════════════
  Widget _sectionLabel(String text) {
    final appColors = AppColors.of(context);
    return Text(
      text.toUpperCase(),
      style: TextStyle(
        fontSize: 11,
        fontWeight: FontWeight.w700,
        color: appColors.subtleText,
        letterSpacing: 0.8,
      ),
    );
  }

  // ══════════════════════════════════════════════════════════════
  // LOG OUT
  // ══════════════════════════════════════════════════════════════
  Widget _buildLogoutButton() => LogoutButton(onLogout: _logOut);

  Future<void> _logOut() async {
    HapticFeedback.mediumImpact();
    // AuthService.signOut releases this handset's FCM token while the user is
    // still signed in, ends the Supabase session and clears the Google
    // session so the account picker shows again.
    await AuthService().signOut();
    if (!mounted) return;
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => LoginScreen()),
      (route) => false,
    );
  }
 
  // ══════════════════════════════════════════════════════════════
  // SKELETON — shown while data loads
  // Shows a realistic shimmer layout matching the real page
  // ══════════════════════════════════════════════════════════════
   Widget _buildSkeleton() {
    final appColors = AppColors.of(context);
    return Scaffold(
      backgroundColor: appColors.sectionBackground,
      body: Column(
        children: [
          Container(
            height: 220,
            // Matches _buildHero's fill so the load-flash stays invisible
            decoration: BoxDecoration(
              color: appColors.cardBackground,
            ),
            child: SafeArea(
              bottom: false,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        SkeletonBox(width: 60, height: 18, radius: 6),
                        SkeletonBox.circle(size: 36),
                      ],
                    ),
                    const SizedBox(height: 24),
                    const Row(
                      children: [
                        SkeletonBox.circle(size: 86),
                        SizedBox(width: 16),
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            SkeletonBox(width: 120, height: 20, radius: 6),
                            SizedBox(height: 8),
                            SkeletonBox(width: 90, height: 14, radius: 6),
                            SizedBox(height: 10),
                            SkeletonBox(width: 100, height: 26, radius: 13),
                          ],
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const SkeletonBox(width: double.infinity, height: 110, radius: 18),
                  const SizedBox(height: 14),
                  const Row(
                    children: [
                      Expanded(child: SkeletonBox(width: double.infinity, height: 90, radius: 18)),
                      SizedBox(width: 10),
                      Expanded(child: SkeletonBox(width: double.infinity, height: 90, radius: 18)),
                      SizedBox(width: 10),
                      Expanded(child: SkeletonBox(width: double.infinity, height: 90, radius: 18)),
                      SizedBox(width: 10),
                      Expanded(child: SkeletonBox(width: double.infinity, height: 90, radius: 18)),
                    ],
                  ),
                  const SizedBox(height: 22),
                  const SkeletonBox(width: 70, height: 12, radius: 4),
                  const SizedBox(height: 10),
                  const SkeletonBox(width: double.infinity, height: 160, radius: 18),
                  const SizedBox(height: 22),
                  const SkeletonBox(width: 70, height: 12, radius: 4),
                  const SizedBox(height: 10),
                  const SkeletonBox(width: double.infinity, height: 160, radius: 18),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

}
 
// ── Simple data class for menu items ─────────────────────────────
/// Renders a count, capping anything over 99 as "99+" with a dotted
/// underline, and revealing the exact number in a tooltip on tap.
///
/// Shared by all four numeric displays on the profile page — the three
/// Lifetime Stats blocks and every "This Month's Top Categories" count — so
/// the cap rule lives in exactly one place rather than being re-decided per
/// field. Three-digit values are real here, not an edge case: Century Lifter
/// is 100 workouts and Century Club is a 100-day streak, and buddy counts can
/// pass 99 on a well-connected account.
///
/// The 44x44 minimum tap target is reserved for EVERY value, not just capped
/// ones, so a row's height never depends on whether its number happened to
/// cross 99 — otherwise a card with one capped and one uncapped stat would
/// render them at different heights.
// Public (not _CappedCount) for the same reason resolveStatusSlot/StatusSlot
// are: this file's widget tests reach it directly, and Dart privacy is
// library-level so a private class is untestable from test/.
class CappedCount extends StatefulWidget {
  const CappedCount({super.key, required this.value, required this.style});

  final int value;
  final TextStyle style;

  static const int cap = 99;

  @override
  State<CappedCount> createState() => _CappedCountState();
}

class _CappedCountState extends State<CappedCount> {
  OverlayEntry? _entry;

  @override
  void dispose() {
    // The entry lives in the Overlay, not in this subtree, so it does not go
    // away with the widget — it has to be removed by hand or it outlives the
    // page (e.g. tapping a value then navigating away).
    _removeOverlay();
    super.dispose();
  }

  void _removeOverlay() {
    _entry?.remove();
    _entry = null;
  }

  void _showOverlay() {
    // Re-entrancy guard, not a toggle the user can reach: while the bubble is
    // open its full-screen catcher sits above this widget and takes the tap
    // first, so a second tap on the value closes it via onDismiss. This only
    // stops a second entry ever being inserted.
    if (_entry != null) {
      _removeOverlay();
      return;
    }

    final box = context.findRenderObject() as RenderBox?;
    final overlay = Overlay.maybeOf(context);
    final overlayBox = overlay?.context.findRenderObject() as RenderBox?;
    if (box == null || overlay == null || overlayBox == null) return;

    // Anchor in overlay coordinates: the top and bottom edges of the 44x44
    // tap target, plus its horizontal centre.
    final top = box.localToGlobal(Offset(box.size.width / 2, 0),
        ancestor: overlayBox);
    final bottom = box.localToGlobal(
        Offset(box.size.width / 2, box.size.height),
        ancestor: overlayBox);

    _entry = OverlayEntry(
      builder: (_) => _CappedCountBubble(
        value: widget.value,
        anchorX: top.dx,
        anchorTop: top.dy,
        anchorBottom: bottom.dy,
        overlaySize: overlayBox.size,
        onDismiss: _removeOverlay,
      ),
    );
    overlay.insert(_entry!);
  }

  @override
  Widget build(BuildContext context) {
    final capped = widget.value > CappedCount.cap;

    final label = Text(
      capped ? '${CappedCount.cap}+' : '${widget.value}',
      textAlign: TextAlign.center,
      style: capped
          ? widget.style.copyWith(
              decoration: TextDecoration.underline,
              decorationStyle: TextDecorationStyle.dotted,
              decorationColor: widget.style.color?.withValues(alpha: 0.6),
            )
          : widget.style,
    );

    final target = ConstrainedBox(
      constraints: const BoxConstraints(minWidth: 44, minHeight: 44),
      child: Center(child: label),
    );

    if (!capped) return target;

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: _showOverlay,
      child: target,
    );
  }
}

/// The themed bubble [CappedCount] puts in the Overlay, replacing the
/// framework Tooltip it used to use.
///
/// Same OverlayEntry approach as LiveEventToast (the app's existing custom
/// overlay), but dismissal is a tap rather than a timer: a full-screen
/// transparent catcher sits behind the bubble, so a tap anywhere outside
/// removes it immediately. There is no auto-dismiss duration at all.
class _CappedCountBubble extends StatelessWidget {
  const _CappedCountBubble({
    required this.value,
    required this.anchorX,
    required this.anchorTop,
    required this.anchorBottom,
    required this.overlaySize,
    required this.onDismiss,
  });

  final int value;
  final double anchorX;
  final double anchorTop;
  final double anchorBottom;
  final Size overlaySize;
  final VoidCallback onDismiss;

  static const double _tailW = 12;
  static const double _tailH = 6;
  static const double _gap = 6;

  @override
  Widget build(BuildContext context) {
    final appColors = AppColors.of(context);
    final bg = appColors.cardBackground;

    // Sits above the value by default; flips below only when there is not
    // enough room above, so a value scrolled near the top still shows.
    final below = anchorTop < 96;

    // Fractional alignment rather than an absolute left offset: inside a
    // full-width band, Alignment(-1) puts the child's LEFT edge at the screen
    // edge and Alignment(1) its RIGHT edge, so a wide bubble near an edge is
    // clamped on-screen for free. The tail is only 12px wide, so the same
    // fraction still lands it essentially on the value itself.
    final fx = ((anchorX / overlaySize.width) * 2 - 1).clamp(-1.0, 1.0);

    final bubble = Align(
      alignment: Alignment(fx, 0),
      heightFactor: 1,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(10),
          // The cards underneath use this same cardBackground token, so
          // without an outline the bubble melts into whichever card it
          // happens to cover.
          border: Border.all(color: appColors.cardBorder),
          boxShadow: appColors.clayShadow(),
        ),
        child: Text(
          '$value',
          style: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w700,
            color: appColors.readableForeground(bg),
          ),
        ),
      ),
    );

    final tail = Align(
      alignment: Alignment(fx, 0),
      heightFactor: 1,
      child: CustomPaint(
        size: const Size(_tailW, _tailH),
        painter: _BubbleTailPainter(color: bg, pointingDown: !below),
      ),
    );

    return Material(
      type: MaterialType.transparency,
      child: Stack(
        children: [
          // Tap-away catcher. Behind the bubble in paint order, so taps on the
          // bubble itself are absorbed by it and do not dismiss.
          Positioned.fill(
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: onDismiss,
            ),
          ),
          Positioned(
            left: 0,
            right: 0,
            // Anchoring the BOTTOM of the column to the value's top edge means
            // the bubble stacks upward without needing to know its height.
            top: below ? anchorBottom + _gap : null,
            bottom: below ? null : overlaySize.height - anchorTop + _gap,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: below ? [tail, bubble] : [bubble, tail],
            ),
          ),
        ],
      ),
    );
  }
}

class _BubbleTailPainter extends CustomPainter {
  const _BubbleTailPainter({required this.color, required this.pointingDown});

  final Color color;
  final bool pointingDown;

  @override
  void paint(Canvas canvas, Size size) {
    final path = Path();
    if (pointingDown) {
      path.moveTo(0, 0);
      path.lineTo(size.width, 0);
      path.lineTo(size.width / 2, size.height);
    } else {
      path.moveTo(0, size.height);
      path.lineTo(size.width, size.height);
      path.lineTo(size.width / 2, 0);
    }
    path.close();
    canvas.drawPath(path, Paint()..color = color);
  }

  @override
  bool shouldRepaint(_BubbleTailPainter old) =>
      old.color != color || old.pointingDown != pointingDown;
}


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
