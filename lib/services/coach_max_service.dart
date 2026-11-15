import 'dart:async';
import 'dart:math';
import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:gym_buddy_app/utils/debug_logger.dart';
import 'package:gym_buddy_app/utils/app_dates.dart';
import 'achievement_service.dart';

class CoachMaxService {
  final SupabaseClient _supabase;
  CoachMaxService({SupabaseClient? client}) : _supabase = client ?? Supabase.instance.client;
  
  static const String coachMaxId = '00000000-0000-0000-0000-000000000001';
  static const String coachMaxName = 'Coach Max';

  // ============================================
  // INITIALIZE COACH MAX FOR NEW USER
  // ============================================
  
  /// Create Coach Max team for a new user (call this after signup/onboarding)
  Future<bool> initializeCoachMaxForUser(String userId) async {
    try {

      // Team, both members and the streak row are created server-side
      // (LIVE-23/25: the client can no longer insert team rows).
      // Today's schedule row is made server-side too (the
      // coach-max-schedule-rows job, within 5 minutes): the client never
      // inserts into coach_max_schedule.
      final result = await _supabase.rpc('ensure_coach_max_team') as Map<String, dynamic>;
      if (kDebugMode) {
        debugLog(result['created'] == true
            ? '✅ Coach Max initialized successfully!'
            : '✅ Coach Max team already exists');
      }
      return true;
    } catch (e) {
      if (kDebugMode) debugLog('❌ Error initializing Coach Max: $e');
      return false;
    }
  }

  /// Get user's Coach Max team (if exists)
  Future<String?> _getCoachMaxTeam(String userId) async {
    try {
      final response = await _supabase
          .from('team_members')
          .select('team_id, buddy_teams!inner(is_coach_max_team)')
          .eq('user_id', userId)
          .eq('buddy_teams.is_coach_max_team', true)
          .maybeSingle();

      return response?['team_id'];
    } catch (e) {
      if (kDebugMode) debugLog('Error getting Coach Max team: $e');
      return null;
    }
  }

  // ============================================
  // COACH MAX DAILY CHECK-IN
  // ============================================

  /// If today's schedule row exists and Coach Max has not checked in yet,
  /// check him in when its time has passed. A best-effort early fire for a
  /// user who opens the app; the hourly coach-max-cron is the authority when
  /// the app is closed. The row itself is made by the server only (the
  /// coach-max-schedule-rows job and coach-max-cron): with no row yet, this
  /// does nothing.
  Future<void> runDueCoachMaxCheckIn(String userId) async {
    try {
      // The user's own local date key — matches the server's per-user scheduled_date.
      final todayStr = localTodayString();

      final existing = await _supabase
          .from('coach_max_schedule')
          .select('id, has_checked_in')
          .eq('user_id', userId)
          .eq('scheduled_date', todayStr)
          .maybeSingle();

      if (existing != null && existing['has_checked_in'] == false) {
        await _executeScheduledCheckIn(userId, existing['id']);
      }
    } catch (e) {
      if (kDebugMode) debugLog('❌ Error running Coach Max check-in: $e');
    }
  }

  /// Execute a scheduled check-in if time has passed
  Future<void> _executeScheduledCheckIn(String userId, String scheduleId) async {
    try {
      final schedule = await _supabase
          .from('coach_max_schedule')
          .select('scheduled_date, scheduled_time, has_checked_in')
          .eq('id', scheduleId)
          .single();

      if (schedule['has_checked_in'] == true) {
        return; // Already checked in
      }

      final scheduledDate = schedule['scheduled_date'] as String;
      final scheduledTime = schedule['scheduled_time'] as String;
      
      final scheduledDateTime = DateTime.parse('$scheduledDate $scheduledTime');
      
      // Only check in if scheduled time has passed
      if (DateTime.now().isAfter(scheduledDateTime)) {
        await checkInCoachMax(userId);
      }
    } catch (e) {
      if (kDebugMode) debugLog('❌ Error executing scheduled check-in: $e');
    }
  }

  // ============================================
  // COACH MAX CHECK-IN EXECUTION
  // ============================================

  /// Check in Coach Max for the user's team
  Future<bool> checkInCoachMax(String userId) async {
    try {
      if (kDebugMode) debugLog('🤖 Coach Max checking in...');

      // Get user's Coach Max team
      final teamId = await _getCoachMaxTeam(userId);
      if (teamId == null) {
        if (kDebugMode) debugLog('❌ No Coach Max team found');
        return false;
      }

      // Get the active streak for this team
      final streak = await _supabase
          .from('team_streaks')
          .select('id')
          .eq('team_id', teamId)
          .eq('is_active', true)
          .maybeSingle();

      if (streak == null) {
        if (kDebugMode) debugLog('❌ No active streak found');
        return false;
      }

      final streakId = streak['id'] as String;
      // The user's own local date key — matches safe_user_tz() server-side.
      final today = localTodayString();

      // Check if Coach Max already checked in today
      final existingCheckIn = await _supabase
          .from('daily_team_checkins')
          .select('id')
          .eq('team_streak_id', streakId)
          .eq('user_id', coachMaxId)
          .eq('check_in_date', today)
          .maybeSingle();

      if (existingCheckIn != null) {
        if (kDebugMode) debugLog('✅ Coach Max already checked in today');
        return true;
      }

      // LIVE-15-adjacent fix: the daily_team_checkins insert and the
      // coach_max_schedule update (plus the no-schedule-row instant-checkin
      // fallback that used to live here) are now enforced server-side by
      // check_in_coach_max, which re-derives the caller's own local "today"
      // and rejects the check-in if scheduled_time hasn't passed yet or no
      // schedule row exists at all -- the client had no time-window check
      // of its own before this.
      final result = await _supabase.rpc('check_in_coach_max', params: {
        'p_user_id': userId,
      }) as Map<String, dynamic>;

      if (result['checked_in'] != true) {
        if (kDebugMode) {
          debugLog('❌ Coach Max check-in not performed: ${result['reason']}');
        }
        return false;
      }

      if (kDebugMode) debugLog('✅ Coach Max checked in successfully!');

      unawaited(AchievementService().checkSpecialAchievements());

      return true;
    } catch (e) {
      if (kDebugMode) debugLog('❌ Error checking in Coach Max: $e');
      return false;
    }
  }

  // ============================================
  // MOTIVATIONAL MESSAGES
  // ============================================

  /// Get a motivational message from Coach Max based on context
  String getMotivationalMessage({
    int currentStreak = 0,
    bool hasCheckedInToday = false,
    String? messageType,
  }) {
    final random = Random();
    
    // If specific type requested
    if (messageType != null) {
      final messages = _getMessagesByType(messageType, currentStreak);
      return messages[random.nextInt(messages.length)];
    }

    // Context-based messages
    if (hasCheckedInToday) {
      return _getCheckedInMessages(currentStreak)[random.nextInt(_getCheckedInMessages(currentStreak).length)];
    }

    if (currentStreak == 0) {
      return _getFirstTimeMessages()[random.nextInt(_getFirstTimeMessages().length)];
    }

    if (currentStreak >= 30) {
      return _getLongStreakMessages(currentStreak)[random.nextInt(_getLongStreakMessages(currentStreak).length)];
    }

    if (currentStreak >= 7) {
      return _getWeekStreakMessages(currentStreak)[random.nextInt(_getWeekStreakMessages(currentStreak).length)];
    }

    return _getGeneralMessages(currentStreak)[random.nextInt(_getGeneralMessages(currentStreak).length)];
  }

  List<String> _getMessagesByType(String type, int currentStreak) {
    switch (type) {
      case 'motivational':
        return [
          "You're stronger than you think! Let's do this! 💪",
          "Every workout counts. You've got this!",
          "Consistency beats perfection. Keep showing up!",
          "Your future self will thank you for this workout!",
          currentStreak > 0 
            ? "Day $currentStreak! You're building something incredible!"
            : "Today is day 1 of your journey! Let's make it count!",
        ];
      case 'chill':
        return [
          "Hey! Ready when you are 😊",
          "No rush, but I'm here whenever you're ready!",
          "Take your time, I'll be here 🤙",
          "Feeling good today? Let's get moving when you're ready!",
          currentStreak > 0
            ? "Day $currentStreak vibes! You're doing great 🌟"
            : "No pressure, just here to support you!",
        ];
      case 'drill_sergeant':
        return [
          "DROP AND GIVE ME 20! Let's GO!",
          "No excuses! Time to work!",
          "Winners train, losers complain. Which are you?",
          "Pain is temporary, glory is forever! MOVE IT!",
          currentStreak > 0
            ? "DAY $currentStreak! KEEP THAT FIRE BURNING! 🔥"
            : "TODAY IS DAY ONE! LET'S BUILD A WARRIOR!",
        ];
      default:
        return _getGeneralMessages(currentStreak);
    }
  }

  List<String> _getFirstTimeMessages() {
    return [
      "Welcome to the team! Let's start your fitness journey! 🚀",
      "Ready to build something great? Let's get started!",
      "Day 1 starts now! You've got this! 💪",
      "Every champion started somewhere. Today is your day!",
    ];
  }

  List<String> _getCheckedInMessages(int currentStreak) {
    return [
      "Already done! Nice work today! 🎉",
      "Crushed it! See you tomorrow! 💪",
      "That's what I'm talking about! Great job! 🔥",
      "Boom! Another day in the books! 📚",
      "You're unstoppable! Keep it going! ⚡",
      currentStreak > 0
        ? "Day $currentStreak complete! Streak alive! 🔥"
        : "Day 1 complete! The journey begins! 🌟",
    ];
  }

  List<String> _getWeekStreakMessages(int currentStreak) {
    return [
      "$currentStreak days strong! You're building something special! 🔥",
      "Look at that $currentStreak-day streak! Consistency is key! 💪",
      "A week down! Your dedication is inspiring!",
      "This is becoming a habit! Love it! 📈",
      "$currentStreak consecutive days! You're on fire! 🔥",
    ];
  }

  List<String> _getLongStreakMessages(int currentStreak) {
    return [
      "$currentStreak DAYS! You're a legend! 🏆",
      "This $currentStreak-day streak is INSANE! Keep it alive! 🔥🔥🔥",
      "You're in the zone! Don't stop now! 💎",
      "Champion mentality! $currentStreak days strong! 👑",
      "$currentStreak days and counting! Unstoppable! ⚡",
    ];
  }

  List<String> _getGeneralMessages(int currentStreak) {
    return [
      "Ready to work? Let's do this! 💪",
      "Another day, another opportunity! Let's go!",
      "Time to get after it! You in?",
      "Let's keep the momentum going! 🚀",
      "Show up and show out! Let's get it!",
      currentStreak > 0
        ? "Day $currentStreak awaits! Let's make it count! 🔥"
        : "Your journey starts today! Let's go! 💪",
    ];
  }
}