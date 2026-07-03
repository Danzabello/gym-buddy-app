import 'dart:math';
import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:gym_buddy_app/utils/debug_logger.dart';
import 'package:gym_buddy_app/utils/app_dates.dart';

class CoachMaxService {
  final SupabaseClient _supabase = Supabase.instance.client;
  
  static const String coachMaxId = '00000000-0000-0000-0000-000000000001';
  static const String coachMaxName = 'Coach Max';

  // ============================================
  // INITIALIZE COACH MAX FOR NEW USER
  // ============================================
  
  /// Create Coach Max team for a new user (call this after signup/onboarding)
  Future<bool> initializeCoachMaxForUser(String userId) async {
    try {

      // Check if user already has a Coach Max team
      final existingTeam = await _getCoachMaxTeam(userId);
      if (existingTeam != null) {
        if (kDebugMode) debugLog('✅ Coach Max team already exists');
        return true;
      }

      // Step 1: Create the buddy team
      final teamId = await _createCoachMaxTeam(userId);
      if (teamId == null) {
        if (kDebugMode) debugLog('❌ Failed to create Coach Max team');
        return false;
      }

      // Step 2: Add user and Coach Max as team members
      await _addTeamMembers(teamId, userId);

      // Step 3: Create initial streak record
      await _createInitialStreak(teamId);

      // Step 4: Schedule first Coach Max check-in
      await scheduleCoachMaxCheckIn(userId);

      if (kDebugMode) debugLog('✅ Coach Max initialized successfully!');
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

  /// Create the Coach Max buddy team
  Future<String?> _createCoachMaxTeam(String userId) async {
    try {
      final response = await _supabase
          .from('buddy_teams')
          .insert({
            'team_name': 'Coach Max',
            'team_emoji': '🤖',
            'is_coach_max_team': true,
            'max_members': 2,
            'created_by': userId,
          })
          .select('id')
          .single();

      if (kDebugMode) debugLog('✅ Created Coach Max team: ${response['id']}');
      return response['id'] as String;
    } catch (e) {
      if (kDebugMode) debugLog('❌ Error creating Coach Max team: $e');
      return null;
    }
  }

  /// Add user and Coach Max as team members
  Future<void> _addTeamMembers(String teamId, String userId) async {
    try {
      // Add user as owner
      await _supabase.from('team_members').insert({
        'team_id': teamId,
        'user_id': userId,
        'role': 'owner',
      });

      // Add Coach Max as member
      await _supabase.from('team_members').insert({
        'team_id': teamId,
        'user_id': coachMaxId,
        'role': 'coach_max',
      });

      if (kDebugMode) debugLog('✅ Added team members (user + Coach Max)');
    } catch (e) {
      if (kDebugMode) debugLog('❌ Error adding team members: $e');
    }
  }

  /// Create initial streak record for the team
  Future<void> _createInitialStreak(String teamId) async {
    try {
      await _supabase.from('team_streaks').insert({
        'team_id': teamId,
        'current_streak': 0,
        'longest_streak': 0,
        'is_active': true,
      });

      if (kDebugMode) debugLog('✅ Created initial streak record');
    } catch (e) {
      if (kDebugMode) debugLog('❌ Error creating streak: $e');
    }
  }

  // ============================================
  // COACH MAX DAILY CHECK-IN SCHEDULING
  // ============================================

  /// Schedule Coach Max's check-in for today (random time between 7am–5pm in
  /// THIS USER's local time — the device's zone IS the user's zone). This is
  /// a best-effort early-fire; the authoritative per-user scheduler is the
  /// coach-max-cron edge function.
  Future<void> scheduleCoachMaxCheckIn(String userId) async {
    try {
      // The user's own local date key — matches the cron's per-user scheduled_date.
      final todayStr = localTodayString();

      // Check if already scheduled for today
      final existing = await _supabase
          .from('coach_max_schedule')
          .select('id, has_checked_in')
          .eq('user_id', userId)
          .eq('scheduled_date', todayStr)
          .maybeSingle();

      if (existing != null) {
        if (kDebugMode) debugLog('✅ Coach Max already scheduled for today');
        
        // If scheduled but hasn't checked in, execute check-in if time has passed
        if (existing['has_checked_in'] == false) {
          await _executeScheduledCheckIn(userId, existing['id']);
        }
        return;
      }

      // Generate random check-in time in the 7am–5pm local window
      final randomTime = _generateRandomCheckInTime();

      // Schedule the check-in
      await _supabase.from('coach_max_schedule').insert({
        'user_id': userId,
        'scheduled_date': todayStr,
        'scheduled_time': randomTime,
        'has_checked_in': false,
      });

      if (kDebugMode) {
        debugLog('✅ Scheduled Coach Max check-in for $randomTime');
      }

      // If the scheduled wall-clock time has already passed today, check in
      // immediately. scheduled_time is the user's local wall-clock, and
      // DateTime.now() is the same device-local frame, so the comparison is
      // DST-correct. The cron is the authority when the app isn't open.
      final nowLocal = DateTime.now();
      final scheduledDateTime = DateTime(
        nowLocal.year,
        nowLocal.month,
        nowLocal.day,
        int.parse(randomTime.split(':')[0]),
        int.parse(randomTime.split(':')[1]),
      );

      if (nowLocal.isAfter(scheduledDateTime)) {
        await checkInCoachMax(userId);
      }
    } catch (e) {
      if (kDebugMode) debugLog('❌ Error scheduling Coach Max: $e');
    }
  }

  /// Generate a random check-in time between 07:00 and 17:00 in the user's
  /// own local time. Matches the coach-max-cron per-user window; the stored
  /// value is interpreted as the user's wall-clock by client and cron alike.
  String _generateRandomCheckInTime() {
    final random = Random();
    // 07:00–16:59 → any minute in the 10-hour [07:00, 17:00) local window.
    final minutesIntoWindow = random.nextInt(10 * 60);
    final hour = 7 + (minutesIntoWindow ~/ 60);
    final minute = minutesIntoWindow % 60;
    return '${hour.toString().padLeft(2, '0')}:${minute.toString().padLeft(2, '0')}:00';
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

      // Get the scheduled time for this check-in
      final schedule = await _supabase
          .from('coach_max_schedule')
          .select('scheduled_time')
          .eq('user_id', userId)
          .eq('scheduled_date', today)
          .maybeSingle();

      final checkInTime = schedule != null
          ? DateTime.parse('$today ${schedule['scheduled_time']}')
          : DateTime.now();

      // Perform check-in
      await _supabase.from('daily_team_checkins').insert({
        'team_streak_id': streakId,
        'user_id': coachMaxId,
        'check_in_date': today,
        'check_in_time': checkInTime.toIso8601String(),
      });

      // Mark schedule as complete
      if (schedule != null) {
        await _supabase
            .from('coach_max_schedule')
            .update({
              'has_checked_in': true,
              'checked_in_at': DateTime.now().toIso8601String(),
            })
            .eq('user_id', userId)
            .eq('scheduled_date', today);
      }

      if (kDebugMode) debugLog('✅ Coach Max checked in successfully!');
      
      // Check if both have checked in and update streak
      await _checkAndUpdateStreak(streakId, teamId, today);

      return true;
    } catch (e) {
      if (kDebugMode) debugLog('❌ Error checking in Coach Max: $e');
      return false;
    }
  }

  /// Check if both team members checked in and update streak
  Future<void> _checkAndUpdateStreak(String streakId, String teamId, String today) async {
    try {
      // Get all non-Coach-Max members
      final members = await _supabase
          .from('team_members')
          .select('user_id')
          .eq('team_id', teamId)
          .neq('user_id', coachMaxId);

      final totalMembers = members.length;

      // Get today's check-ins (excluding Coach Max)
      final checkIns = await _supabase
          .from('daily_team_checkins')
          .select('user_id')
          .eq('team_streak_id', streakId)
          .eq('check_in_date', today)
          .neq('user_id', coachMaxId);

      final checkedInMembers = checkIns.length;

      if (kDebugMode) {
        debugLog('📊 Team status: $checkedInMembers/$totalMembers members checked in');
      }

      // If all members checked in, update streak
      if (checkedInMembers >= totalMembers) {
        await _updateStreak(streakId, today);
      }
    } catch (e) {
      if (kDebugMode) debugLog('❌ Error checking streak status: $e');
    }
  }

  /// Update the streak when both team members have checked in
  Future<void> _updateStreak(String streakId, String today) async {
    try {
      // Streak math now lives server-side (recompute_team_streak RPC)
      // — single source of truth shared with TeamStreakService, the
      // Coach Max cron, and TeamSyncService.
      final result = await _supabase.rpc('recompute_team_streak', params: {
        'p_streak_id': streakId,
        'p_check_in_date': today,
      });

      if (kDebugMode) {
        debugLog('✅ Streak updated via recompute_team_streak → $result');
      }
    } catch (e) {
      if (kDebugMode) debugLog('❌ Error updating streak: $e');
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