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
import 'services/checkin_history_service.dart';
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
import 'home/dashboard_clock.dart';
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
part 'home/logout_button.dart';
part 'home/nav_bar.dart';
part 'home/profile_page.dart';
part 'home/weekly_plan_dialog.dart';


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
