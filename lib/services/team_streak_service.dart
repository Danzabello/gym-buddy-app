import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'break_day_service.dart';
import 'workout_history_service.dart';
import 'level_service.dart';
import 'dart:async' show unawaited;
import 'achievement_service.dart';
import 'package:gym_buddy_app/utils/debug_logger.dart';
import 'package:gym_buddy_app/utils/app_dates.dart';



// ============================================
// MODEL CLASSES (moved outside service)
// ============================================

/// Represents a team member
class TeamMember {
  final String userId;
  final String displayName;
  final String? username;
  final bool isCoachMax;
  final String? avatarId;

  TeamMember({
    required this.userId,
    required this.displayName,
    this.username,
    required this.isCoachMax,
    this.avatarId,
  });
}

/// Represents a check-in status
class CheckInStatus {
  final String userId;
  final String displayName;
  final DateTime checkInTime;
  final int order; // 1 = first (bottom of flame), 2 = second, etc.
  
  CheckInStatus({
    required this.userId,
    required this.displayName,
    required this.checkInTime,
    required this.order,
  });
}

/// Represents a team's streak data
class TeamStreak {
  final String id;
  final String teamId;
  final String teamName;
  final String teamEmoji;
  final int currentStreak;
  final int longestStreak;
  final int totalWorkouts;
  final int bestStreak;
  final DateTime? lastWorkoutDate;
  final DateTime? lastInteractionAt;  
  final bool isCoachMaxTeam;
  final List<TeamMember> members;
  final List<CheckInStatus> todayCheckIns;
  final bool isFavorite; 
  
  TeamStreak({
    required this.id,
    required this.teamId,
    required this.teamName,
    required this.teamEmoji,
    required this.currentStreak,
    required this.longestStreak,
    this.totalWorkouts = 0,
    this.bestStreak = 0,  
    required this.lastWorkoutDate,
    this.lastInteractionAt,        
    required this.isCoachMaxTeam,
    required this.members,
    required this.todayCheckIns,
    this.isFavorite = false, 
  });
  
  // ✅ PRESERVE ALL EXISTING HELPER METHODS
  
  /// Calculate completion percentage for today
  double get completionPercentage {
    if (members.isEmpty) return 0.0;
    final checkedInCount = todayCheckIns.length;
    return checkedInCount / members.length;
  }
  
  /// Check if all members have checked in today
  bool get isCompleteToday {
    return completionPercentage >= 1.0;
  }
  
  /// Check if streak is at risk (no one checked in yet)
  bool get isAtRisk {
    return todayCheckIns.isEmpty;
  }
}

// ============================================
// TEAM STREAK SERVICE
// ============================================

class TeamStreakService {
  final SupabaseClient _supabase = Supabase.instance.client;
  final BreakDayService _breakDayService = BreakDayService();
  final LevelService levelService = LevelService();
  
  static const String coachMaxId = '00000000-0000-0000-0000-000000000001';

  // ============================================
  // GET ALL USER'S ACTIVE STREAKS
  // ============================================
  
  /// Get all active streaks for the current user
  Future<List<TeamStreak>> getAllUserStreaks() async {
    try {
      final currentUserId = _supabase.auth.currentUser?.id;
      if (currentUserId == null) {
        if (kDebugMode) debugLog('❌ No user logged in');
        return [];
      }


      // ✅ ONE round trip instead of 9+
      final response = await _supabase
          .rpc('get_user_streaks', params: {'p_user_id': currentUserId});

      if (response == null) return [];

      final List<dynamic> teamsData = response as List<dynamic>;
      final List<TeamStreak> streaks = [];

      for (final teamData in teamsData) {
        try {
          final teamId = teamData['team_id'] as String;
          final streakId = teamData['streak_id'] as String? ?? '';

          if (streakId.isEmpty) continue;

          // Parse members
          final membersRaw = teamData['members'] as List<dynamic>? ?? [];
          final members = membersRaw.map((m) => TeamMember(
            userId: m['user_id'] as String,
            displayName: m['display_name'] ?? 'Unknown',
            username: m['username'] as String?,
            isCoachMax: m['user_id'] == coachMaxId,
            avatarId: m['avatar_id'] as String?,
          )).toList();

          // Parse today's check-ins
          final checkInsRaw = teamData['today_check_ins'] as List<dynamic>? ?? [];
          final now = DateTime.now();
          final today = DateTime(now.year, now.month, now.day);
          int orderIndex = 0;
          final checkIns = <CheckInStatus>[];

          for (final c in checkInsRaw) {
            try {
              final checkInTime = DateTime.parse(c['checked_in_at'] as String);
              checkIns.add(CheckInStatus(
                userId: c['user_id'] as String,
                displayName: members.firstWhere(
                  (m) => m.userId == c['user_id'],
                  orElse: () => TeamMember(
                    userId: c['user_id'],
                    displayName: 'Unknown',
                    isCoachMax: false,
                  ),
                ).displayName,
                checkInTime: checkInTime,
                order: orderIndex + 1,
              ));
              orderIndex++;
            } catch (_) {}
          }

          // Sort check-ins by time
          checkIns.sort((a, b) => a.checkInTime.compareTo(b.checkInTime));
          for (int i = 0; i < checkIns.length; i++) {
            checkIns[i] = CheckInStatus(
              userId: checkIns[i].userId,
              displayName: checkIns[i].displayName,
              checkInTime: checkIns[i].checkInTime,
              order: i + 1,
            );
          }

          final streak = TeamStreak(
            id: streakId,
            teamId: teamId,
            teamName: teamData['team_name'] ?? 'Unnamed Team',
            teamEmoji: teamData['team_emoji'] ?? '🔥',
            currentStreak: teamData['current_streak'] ?? 0,
            longestStreak: teamData['best_streak'] ?? 0,
            totalWorkouts: teamData['total_workouts'] ?? 0,
            bestStreak: teamData['best_streak'] ?? 0,
            lastWorkoutDate: teamData['last_workout_date'] != null
                ? DateTime.parse(teamData['last_workout_date'])
                : null,
            lastInteractionAt: teamData['last_interaction_at'] != null
                ? DateTime.parse(teamData['last_interaction_at'])
                : null,
            isCoachMaxTeam: teamData['is_coach_max_team'] ?? false,
            members: members,
            todayCheckIns: checkIns,
            isFavorite: teamData['is_favorite'] ?? false,
          );

          streaks.add(streak);
          if (kDebugMode) debugLog('✅ Added streak: ${streak.teamName}');
        } catch (e) {
          if (kDebugMode) debugLog('❌ Error parsing team data: $e');
        }
      }

      // Sort: Coach Max first, then by highest streak
      streaks.sort((a, b) {
        if (a.isCoachMaxTeam && !b.isCoachMaxTeam) return -1;
        if (!a.isCoachMaxTeam && b.isCoachMaxTeam) return 1;
        return b.currentStreak.compareTo(a.currentStreak);
      });

      if (kDebugMode) {
        debugLog('✅ Returning ${streaks.length} active streaks');
        for (var s in streaks) {
          debugLog('  - ${s.teamName} (${s.teamId})');
        }
      }

      return streaks;
    } catch (e) {
      if (kDebugMode) debugLog('❌ Error getting user streaks: $e');
      return [];
    }
  }

  /// Get streak data for a specific team
  Future<TeamStreak?> _getTeamStreakData(String teamId) async {
    try {
      if (kDebugMode) debugLog('  🔍 Getting streak data for team: $teamId');
      
      // Get team info
      final teamResponse = await _supabase
          .from('buddy_teams')
          .select('id, team_name, team_emoji, is_coach_max_team')
          .eq('id', teamId)
          .single();

      if (kDebugMode) debugLog('  ✅ Team info: ${teamResponse['team_name']}');

      // Get active streak
      final streakResponse = await _supabase
          .from('team_streaks')
          .select('*, is_favorite')
          .eq('team_id', teamId)
          .eq('is_active', true)
          .maybeSingle();

      if (streakResponse == null) {
        if (kDebugMode) debugLog('  ⚠️ No active streak found for team: $teamId');
        return null;
      }

      if (kDebugMode) debugLog('  ✅ Found active streak: ${streakResponse['id']}');

      // Get team members
      final membersResponse = await _supabase
      .from('team_members')
      .select('user_id, user_profiles!inner(display_name, avatar_id, username)')
      .eq('team_id', teamId);

      if (kDebugMode) debugLog('  ✅ Found ${membersResponse.length} team members');

      final members = <TeamMember>[];
      for (final member in membersResponse) {
        final profile = member['user_profiles'];
        members.add(TeamMember(
          userId: member['user_id'],
          displayName: profile['display_name'] ?? 'Unknown',
          username: profile['username'],  // ← ADD THIS
          isCoachMax: member['user_id'] == coachMaxId,
          avatarId: profile?['avatar_id'],
        ));
      }

      // Get today's check-ins for this team
      final todayCheckIns = await _getTodayCheckIns(
        streakResponse['id'],
        teamId,
      );

      if (kDebugMode) debugLog('  ✅ Found ${todayCheckIns.length} check-ins today');

      return TeamStreak(
        id: streakResponse['id'] ?? '',
        teamId: teamId,
        teamName: teamResponse['team_name'] ?? 'Unnamed Team',
        teamEmoji: teamResponse['team_emoji'] ?? '🔥',
        currentStreak: streakResponse['current_streak'] ?? 0,
        longestStreak: streakResponse['longest_streak'] ?? 0,
        totalWorkouts: streakResponse['total_workouts'] ?? 0, 
        bestStreak: streakResponse['best_streak'] ?? 0, 
        lastWorkoutDate: streakResponse['last_workout_date'] != null
            ? DateTime.parse(streakResponse['last_workout_date'])
            : null,
        lastInteractionAt: streakResponse['last_interaction_at'] != null
            ? DateTime.parse(streakResponse['last_interaction_at'])
            : null,
        isCoachMaxTeam: teamResponse['is_coach_max_team'] ?? false,
        members: members,
        todayCheckIns: todayCheckIns,
        isFavorite: streakResponse['is_favorite'] == true,  // ⭐ ADD THIS LINE
      );
    } catch (e) {
      if (kDebugMode) debugLog('  ❌ Error getting team streak data: $e');
      return null;
    }
  }

  /// Get today's check-ins for a team
  Future<List<CheckInStatus>> _getTodayCheckIns(String? streakId, String teamId) async {
    if (streakId == null) return [];
    
    try {
      // ✅ FIX: Get ALL recent check-ins and filter in Dart to avoid timezone issues
      if (kDebugMode) debugLog('  📅 Getting recent check-ins for streak: $streakId');
      
      final response = await _supabase
          .from('daily_team_checkins')
          .select('''
            user_id,
            check_in_time,
            check_in_date,
            user_profiles!inner(display_name)
          ''')
          .eq('team_streak_id', streakId)
          .order('check_in_time', ascending: false)
          .limit(20);

      if (kDebugMode) {
        debugLog('  📊 Found ${response.length} total check-ins for this streak');
      }

      // Filter to today's check-ins in Dart
      final now = DateTime.now();
      final today = DateTime(now.year, now.month, now.day);
      
      final checkIns = <CheckInStatus>[];
      int orderIndex = 0;
      
      for (var record in response) {
        try {
          final checkInDate = DateTime.parse(record['check_in_date']);
          final checkInDay = DateTime(checkInDate.year, checkInDate.month, checkInDate.day);
          
          if (checkInDay.isAtSameMomentAs(today)) {
            checkIns.add(CheckInStatus(
              userId: record['user_id'],
              displayName: record['user_profiles']['display_name'] ?? 'Unknown',
              checkInTime: DateTime.parse(record['check_in_time']),
              order: orderIndex + 1,
            ));
            orderIndex++;
          }
        } catch (e) {
          if (kDebugMode) debugLog('  ⚠️ Error parsing check-in date: $e');
        }
      }
      
      // Sort by check-in time (earliest first)
      checkIns.sort((a, b) => a.checkInTime.compareTo(b.checkInTime));
      
      // Re-assign order after sorting
      for (int i = 0; i < checkIns.length; i++) {
        checkIns[i] = CheckInStatus(
          userId: checkIns[i].userId,
          displayName: checkIns[i].displayName,
          checkInTime: checkIns[i].checkInTime,
          order: i + 1,
        );
      }

      if (kDebugMode) {
        debugLog('  ✅ Found ${checkIns.length} check-ins for today');
        for (var checkIn in checkIns) {
          debugLog('     - ${checkIn.displayName} at ${checkIn.checkInTime}');
        }
      }

      return checkIns;
    } catch (e) {
      if (kDebugMode) debugLog('❌ Error getting today check-ins: $e');
      return [];
    }
  }

  // ============================================
  // GET HIGHEST STREAK (for main display)
  // ============================================
  
  /// Get the user's highest current streak (for main dashboard display)
  Future<TeamStreak?> getHighestStreak() async {
    final streaks = await getAllUserStreaks();
    if (streaks.isEmpty) return null;
    
    // Return highest streak (already sorted)
    return streaks.reduce((a, b) => 
      a.currentStreak > b.currentStreak ? a : b
    );
  }

  // ============================================
  // CHECK-IN FOR ALL TEAMS
  // ============================================
  
  /// Check in for ALL active teams (one check-in updates all streaks)
  
  Future<Map<String, dynamic>> checkInAllTeams({
    String? selectedTemplateId,
    String? workoutName,
    String? workoutCategory,
    String? workoutEmoji,
    int? durationMinutes,
    String? notes,
  }) async {
    try {
      final currentUserId = _supabase.auth.currentUser?.id;
      if (currentUserId == null) {
        return {'success': false, 'message': 'Not logged in'};
      }

      // ✅ Check if user is on break today and auto-cancel it
      final onBreak = await _breakDayService.isCurrentUserOnBreakToday();
      if (onBreak) {
        if (kDebugMode) debugLog('🔄 User was on break, cancelling it...');
        await _breakDayService.cancelBreakDay();
      }

      // The user's own local date key — matches safe_user_tz() server-side.
      final today = localTodayString();

      if (kDebugMode) debugLog('🔄 Check-in date: $today (user-local)');
      
      // Get all user's teams
      final streaks = await getAllUserStreaks();
      
      if (streaks.isEmpty) {
        return {'success': false, 'message': 'No teams found'};
      }

      // Check if already checked in today
      final alreadyCheckedIn = streaks.any((streak) => 
        streak.todayCheckIns.any((checkIn) => checkIn.userId == currentUserId)
      );
      
      if (alreadyCheckedIn) {
        return {'success': false, 'message': 'Already checked in today!'};
      }

      // ✅ NEW: Log workout if template provided
      if (selectedTemplateId != null && workoutName != null && 
          workoutCategory != null && workoutEmoji != null && 
          durationMinutes != null) {
        
        final workoutHistoryService = WorkoutHistoryService();
        
        // Get buddy info from first non-Coach Max team
        String? buddyId;
        String? teamId;
        
        for (var streak in streaks) {
          if (!streak.isCoachMaxTeam && streak.members.length > 1) {
            teamId = streak.teamId;
            // Find the buddy (not current user)
            final buddy = streak.members.firstWhere(
              (m) => m.userId != currentUserId,
              orElse: () => streak.members.first,
            );
            buddyId = buddy.userId;
            break;
          }
        }
        
        await workoutHistoryService.logWorkout(
          templateId: selectedTemplateId,
          workoutName: workoutName,
          workoutCategory: workoutCategory,
          workoutEmoji: workoutEmoji,
          actualDurationMinutes: durationMinutes,
          buddyId: buddyId,
          teamId: teamId,
          notes: notes,
        );
        
        if (kDebugMode) debugLog('✅ Workout logged to history');
      }

      int successCount = 0;
      LevelUpResult? levelUpResult;

      for (final streak in streaks) {
        if (kDebugMode) debugLog('🔄 Checking in to team: ${streak.teamName}');
        
        try {
          final result = await _checkInToTeam(streak.id, streak.teamId, today);
          successCount++;
          levelUpResult ??= result;
          
          if (streak.isCoachMaxTeam) {
            if (kDebugMode) debugLog('🤖 Auto-checking in Coach Max...');
            await _checkInCoachMax(streak.id, today);
          }
        } catch (e) {
          if (kDebugMode) debugLog('❌ Failed check-in for ${streak.teamName}: $e');
        }
      }

      if (kDebugMode) {
        debugLog('✅ Checked in to $successCount/${streaks.length} teams');
      }

      // 🏆 Workout achievements
      List<AchievementUnlockResult> workoutAchievements = [];
      if (successCount > 0) {
        workoutAchievements = await AchievementService().checkWorkoutAchievements(
          durationMinutes: durationMinutes ?? 0,
          workoutType: workoutName ?? 'workout',
        );
      }

      final partnerBonusTransaction = await _supabase
          .from('coin_transactions')
          .select('id')
          .eq('user_id', currentUserId)
          .eq('transaction_type', 'partner_bonus')
          .gte('created_at', '${today}T00:00:00Z')
          .maybeSingle();

      return {
        'success': true,
        'message': 'Checked in to $successCount team${successCount == 1 ? '' : 's'}!',
        'teams_updated': successCount,
        'break_cancelled': onBreak,
        'level_up': levelUpResult,
        'partner_bonus_earned': partnerBonusTransaction != null,
        'workout_achievements': workoutAchievements,
      };
    } catch (e) {
      if (kDebugMode) debugLog('❌ Error checking in: $e');
      return {'success': false, 'message': 'Could not complete check-in. Please try again.'};
    }
  }

  Future<void> _checkInCoachMax(String streakId, String today) async {
    try {
      // Check if Coach Max already checked in
      final existing = await _supabase
          .from('daily_team_checkins')
          .select('id')
          .eq('team_streak_id', streakId)
          .eq('user_id', coachMaxId)
          .eq('check_in_date', today)
          .maybeSingle();

      if (existing != null) {
        if (kDebugMode) debugLog('✅ Coach Max already checked in');
        return;
      }

      // Check in Coach Max
      await _supabase.from('daily_team_checkins').insert({
        'team_streak_id': streakId,
        'user_id': coachMaxId,
        'check_in_date': today,
        'check_in_time': DateTime.now().toUtc().toIso8601String(),
      });

      if (kDebugMode) debugLog('✅ Coach Max checked in successfully');
    } catch (e) {
      if (kDebugMode) debugLog('❌ Error checking in Coach Max: $e');
    }
  }

  /// Check in to a specific team
  Future<LevelUpResult?> _checkInToTeam(String streakId, String teamId, String today) async {
    try {
      final currentUserId = _supabase.auth.currentUser?.id;
      if (currentUserId == null) return null;

      final now = DateTime.now().toUtc();

      await _supabase.from('daily_team_checkins').insert({
        'team_streak_id': streakId,
        'user_id': currentUserId,
        'check_in_date': today,
        'check_in_time': now.toIso8601String(),
      });

      return await _updateTeamStreak(streakId, teamId, today);
    } catch (e) {
      if (kDebugMode) debugLog('❌ Error checking in to team: $e');
      return null;
    }
  }

  /// Update team streak after check-in
  Future<LevelUpResult?> _updateTeamStreak(String streakId, String teamId, String today) async {
    try {
      // Get total members (excluding Coach Max for counting)
      final membersResponse = await _supabase
          .from('team_members')
          .select('user_id')
          .eq('team_id', teamId)
          .neq('user_id', coachMaxId);
      
      final memberIds = membersResponse.map((m) => m['user_id'] as String).toList();
      final totalMembers = memberIds.length;

      if (kDebugMode) debugLog('📊 Team has $totalMembers members (excluding Coach Max)');

      // Get today's check-ins (excluding Coach Max)
      final checkInsResponse = await _supabase
          .from('daily_team_checkins')
          .select('user_id')
          .eq('team_streak_id', streakId)
          .eq('check_in_date', today)
          .neq('user_id', coachMaxId);

      final checkedInMembers = checkInsResponse.length;

      // ✅ NEW: Get break day status for all members
      final breakDayStatus = await _breakDayService.getTeamBreakDayStatus(memberIds, today);
      
      // Count how many people are participating today (checked in OR on break)
      int participatingMembers = 0;
      for (var userId in memberIds) {
        final onBreak = breakDayStatus[userId] ?? false;
        final checkedIn = checkInsResponse.any((c) => c['user_id'] == userId);
        
        if (onBreak || checkedIn) {
          participatingMembers++;
        }
      }

      if (kDebugMode) {
        debugLog('📊 Team participation status:');
        debugLog('  - Total members: $totalMembers');
        debugLog('  - Checked in: $checkedInMembers');
        debugLog('  - Participating (check-in OR break): $participatingMembers');
        for (var userId in memberIds) {
          final onBreak = breakDayStatus[userId] ?? false;
          final checkedIn = checkInsResponse.any((c) => c['user_id'] == userId);
        }
      }

      // ✅ If all members are participating (checked in or on break), increment streak
      if (participatingMembers >= totalMembers) {
        if (kDebugMode) debugLog('🎉 All members participating! Incrementing streak...');
        return await _incrementStreak(streakId, teamId, today);
      } else {
        if (kDebugMode) debugLog('⏳ Waiting for more members... ($participatingMembers/$totalMembers participating)');
      }
      return null;
    } catch (e) {
      if (kDebugMode) debugLog('❌ Error updating team streak: $e');
      return null;
    }
  }

  /// Increment streak when all members check in
  Future<LevelUpResult?> _incrementStreak(String streakId, String teamId, String today, {bool isCoachMaxTeam = false}) async {
    try {
      // Streak math now lives server-side (recompute_team_streak RPC)
      // — single source of truth shared with the Coach Max cron,
      // CoachMaxService, and TeamSyncService. Replaces the local
      // date-diff/break-day logic that used to live here.
      final result = await _supabase.rpc('recompute_team_streak', params: {
        'p_streak_id': streakId,
        'p_check_in_date': today,
      }) as Map<String, dynamic>?;

      if (result == null || result['updated'] != true) {
        if (kDebugMode) debugLog('ℹ️ Streak not updated: ${result?['reason']}');
        return null;
      }

      final newStreak = result['new_streak'] as int;
      final oldBestStreak = (result['old_best_streak'] as int?) ?? 0;
      final newBestStreak = (result['new_best_streak'] as int?) ?? newStreak;

      // Award rewards after streak update — server-validated and atomic.
      // Replaces CoinService.awardDailyCheckIn/awardRetroactivePartnerBonus
      // + LevelService.awardCheckInXP (S2/S3 audit fix). Also fixes a
      // pre-existing double-XP-on-checkin bug from a since-removed
      // DB trigger.
      final currentUserId = _supabase.auth.currentUser?.id;
      bool didLevelUp = false;
      int newLevelAfterCheckin = 1;
      if (currentUserId != null) {
        try {
          final rewardResult = await _supabase.rpc('award_checkin_rewards', params: {
            'p_streak_id': streakId,
            'p_check_in_date': today,
          }) as Map<String, dynamic>?;

          if (rewardResult != null && rewardResult['already_awarded'] != true) {
            didLevelUp = rewardResult['did_level_up'] as bool? ?? false;
            newLevelAfterCheckin = rewardResult['new_level'] as int? ?? 1;
          }
        } catch (e) {
          debugLog('❌ Error awarding check-in rewards: $e');
        }

        // Recomputed only to gate the co-op achievement check below — NOT
        // used for any reward payout (those are server-side now).
        final coopCheckIns = await _supabase
            .from('daily_team_checkins')
            .select('user_id')
            .eq('team_streak_id', streakId)
            .eq('check_in_date', today)
            .neq('user_id', coachMaxId);
        final partnerAlsoCheckedIn = coopCheckIns.length >= 2;

        // 🏆 Achievement checks — fire-and-forget
        unawaited(() async {
          final achievementService = AchievementService();

          await achievementService.checkStreakAchievements(
            currentStreak: newStreak,
            bestStreak: newBestStreak,
            previousBest: oldBestStreak,
            isRealBuddy: !isCoachMaxTeam,
            teamStreakId: streakId,
          );

          if (didLevelUp) {
            await achievementService.checkLevelAchievements(newLevelAfterCheckin);
          }

          await achievementService.checkCoinAchievements();

          if (!isCoachMaxTeam && partnerAlsoCheckedIn) {
            final checkins = await _supabase
                .from('daily_team_checkins')
                .select('user_id, check_in_time')
                .eq('team_streak_id', streakId)
                .eq('check_in_date', today);

            if (checkins.length >= 2) {
              final times = checkins
                  .map((c) => DateTime.parse(c['check_in_time'] as String))
                  .toList()
                ..sort();
              await achievementService.checkCoopAchievements(
                teamStreakId: streakId,
                myCheckInTime: times.last,
                partnerCheckInTime: times.first,
              );
            }
          }
        }());

        // Grant milestone cosmetic unlocks
        final milestoneKey = switch (newStreak) {
          30  => 'streak_30',
          60  => 'streak_60',
          90  => 'streak_90',
          100 => 'streak_100',
          _   => null,
        };
        if (milestoneKey != null) {
          levelService.grantMilestoneUnlock(milestoneKey: milestoneKey); // fire-and-forget
        }

        return null;
      }

      if (kDebugMode) {
        debugLog('✅ Streak updated! Current: $newStreak, Longest: ${result['longest_streak']}');
      }

      return null;
    } catch (e) {
      if (kDebugMode) debugLog('❌ Error incrementing streak: $e');
      return null;
    }
  }

  // ============================================
  // CHECK IF USER HAS CHECKED IN TODAY
  // ============================================
  
  /// Check if user has checked in to ANY team today
  Future<bool> hasCheckedInToday() async {
    try {
      final currentUserId = _supabase.auth.currentUser?.id;
      if (currentUserId == null) return false;

      // The user's own local date key — matches safe_user_tz() server-side.
      final today = localTodayString();

      final response = await _supabase
          .from('daily_team_checkins')
          .select('id')
          .eq('user_id', currentUserId)
          .eq('check_in_date', today)
          .limit(1);

      return response.isNotEmpty;
    } catch (e) {
      if (kDebugMode) debugLog('❌ Error checking today status: $e');
      return false;
    }
  }

  // ============================================
  // STREAK HISTORY
  // ============================================
  
  /// Get all past streaks (ended streaks) for a user
  Future<List<Map<String, dynamic>>> getStreakHistory({int limit = 10}) async {
    try {
      final currentUserId = _supabase.auth.currentUser?.id;
      if (currentUserId == null) return [];

      // Get user's teams
      final teamsResponse = await _supabase
          .from('team_members')
          .select('team_id')
          .eq('user_id', currentUserId);

      final teamIds = teamsResponse.map((t) => t['team_id'] as String).toList();
      
      if (teamIds.isEmpty) return [];

      // Get ended streaks
      final response = await _supabase
          .from('team_streaks')
          .select('''
            id,
            team_name,
            team_emoji,
            current_streak,
            best_streak,
            total_workouts,
            members,
            is_coach_max_team,
            last_interaction_at,
            is_favorite
          ''')
          .order('current_streak', ascending: false);

      return List<Map<String, dynamic>>.from(response);
    } catch (e) {
      if (kDebugMode) debugLog('❌ Error getting streak history: $e');
      return [];
    }
  }

  Future<void> checkAndResetBrokenStreaks() async {
    try {
      final currentUserId = _supabase.auth.currentUser?.id;
      if (currentUserId == null) return;

      if (kDebugMode) debugLog('🔍 Checking for broken streaks...');

      final streaks = await getAllUserStreaks();
      
      for (final streak in streaks) {
        await _checkStreakStatus(streak);
      }

      if (kDebugMode) debugLog('✅ Streak check complete');
    } catch (e) {
      if (kDebugMode) debugLog('❌ Error checking streaks: $e');
    }
  }

  /// Check if a specific streak should be reset
  Future<void> _checkStreakStatus(TeamStreak streak) async {
    try {
      if (streak.lastWorkoutDate == null) return;
      if (streak.currentStreak == 0) return; // Already reset, nothing to do

      final now = DateTime.now();
      final today = DateTime(now.year, now.month, now.day);
      final yesterday = today.subtract(const Duration(days: 1));
      final lastWorkout = DateTime(
        streak.lastWorkoutDate!.year,
        streak.lastWorkoutDate!.month,
        streak.lastWorkoutDate!.day,
      );

      // ✅ If last workout was today or yesterday, streak is fine
      if (lastWorkout.isAtSameMomentAs(today) ||
          lastWorkout.isAtSameMomentAs(yesterday)) {
        return;
      }

      // ✅ NEW: If ANY member has checked in today, don't reset
      // The streak just hasn't been incremented yet (waiting for partner)
      final anyCheckedInToday = streak.todayCheckIns.isNotEmpty;
      if (anyCheckedInToday) {
        if (kDebugMode) debugLog('⏳ ${streak.teamName}: partial check-in today, skipping reset');
        return;
      }

      // Check if gap is filled with break days
      final daysSinceLastWorkout = today.difference(lastWorkout).inDays;

      final membersResponse = await _supabase
          .from('team_members')
          .select('user_id')
          .eq('team_id', streak.teamId)
          .neq('user_id', coachMaxId);

      final memberIds = membersResponse.map((m) => m['user_id'] as String).toList();

      bool gapIsValid = true;

      for (int i = 1; i < daysSinceLastWorkout; i++) {
        final checkDate = lastWorkout.add(Duration(days: i));
        final checkDateStr = DateTime(checkDate.year, checkDate.month, checkDate.day)
            .toIso8601String()
            .split('T')[0];

        final breakStatus = await _breakDayService.getTeamBreakDayStatus(memberIds, checkDateStr);
        final everyoneOnBreak = memberIds.every((userId) => breakStatus[userId] ?? false);

        if (!everyoneOnBreak) {
          gapIsValid = false;
          break;
        }
      }

      if (!gapIsValid) {
        if (kDebugMode) debugLog('💔 Resetting broken streak: ${streak.teamName}');
        await _resetStreak(streak.id);
      } else {
        if (kDebugMode) debugLog('✅ Gap filled by break days: ${streak.teamName}');
      }
    } catch (e) {
      if (kDebugMode) debugLog('❌ Error checking streak status: $e');
    }
  }

  /// Reset a streak to 0
  Future<void> _resetStreak(String streakId) async {
    try {
      await _supabase.from('team_streaks').update({
        'current_streak': 0,
        'updated_at': DateTime.now().toUtc().toIso8601String(),
      }).eq('id', streakId);

      if (kDebugMode) debugLog('✅ Streak reset to 0');
    } catch (e) {
      if (kDebugMode) debugLog('❌ Error resetting streak: $e');
    }
  }

  /// Check in [userId] (a co-op partner) across all their active teams.
  /// Validated server-side against the real [workoutId] session that
  /// proves they're a genuine participant — replaces the old
  /// friend-on-shared-team client insert (S3 audit fix).
  Future<int> checkInAllTeamsForUser(String userId, {required String workoutId}) async {
    try {
      final count = await _supabase.rpc('checkin_team_for_user', params: {
        'p_target_user_id': userId,
        'p_workout_id': workoutId,
      });
      debugLog('✅ Proxy check-in: $count teams for $userId');
      return count as int? ?? 0;
    } catch (e) {
      debugLog('❌ Error in checkInAllTeamsForUser: $e');
      return 0;
    }
  }

  /// Find the team that contains both the current user and their buddy
  /// Returns the team ID or null if not found
  Future<String?> findTeamWithBuddy(String userId, String buddyId) async {
    try {
      // Get all teams the current user is in (excluding Coach Max teams)
      final userTeams = await _supabase
          .from('team_members')
          .select('team_id, buddy_teams!inner(is_coach_max_team)')
          .eq('user_id', userId);

      for (final teamData in userTeams) {
        // Skip Coach Max teams
        if (teamData['buddy_teams']['is_coach_max_team'] == true) continue;

        final teamId = teamData['team_id'] as String;

        // Check if buddy is also in this team
        final buddyInTeam = await _supabase
            .from('team_members')
            .select('id')
            .eq('team_id', teamId)
            .eq('user_id', buddyId)
            .maybeSingle();

        if (buddyInTeam != null) {
          if (kDebugMode) debugLog('🎯 Found shared team: $teamId');
          return teamId;
        }
      }

      return null;
    } catch (e) {
      if (kDebugMode) debugLog('❌ Error finding team with buddy: $e');
      return null;
    }
  }

  Future<List<TeamStreak>> getFavoriteStreaks() async {
    final allStreaks = await getAllUserStreaks();
    return allStreaks.where((streak) => streak.isFavorite).toList();
  }

  // Toggle favorite status
  Future<void> toggleFavorite(String teamId, bool isFavorite) async {
    try {
      await _supabase
          .from('team_streaks')
          .update({'is_favorite': isFavorite})
          .eq('id', teamId);

      if (kDebugMode) debugLog('⭐ Toggled favorite for team $teamId to $isFavorite');
    } catch (e) {
      if (kDebugMode) debugLog('❌ Error toggling favorite: $e');
      rethrow;
    }
  }

}