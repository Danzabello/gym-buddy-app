import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'break_day_service.dart';
import 'workout_history_service.dart';


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
  
  static const String coachMaxId = '00000000-0000-0000-0000-000000000001';

  // ============================================
  // GET ALL USER'S ACTIVE STREAKS
  // ============================================
  
  /// Get all active streaks for the current user
  Future<List<TeamStreak>> getAllUserStreaks() async {
    try {
      final currentUserId = _supabase.auth.currentUser?.id;
      if (currentUserId == null) {
        if (kDebugMode) print('❌ No user logged in');
        return [];
      }

      if (kDebugMode) print('🔍 Getting all streaks for user: $currentUserId');

  
      // Get all teams user is part of
      final teamsResponse = await _supabase
          .from('team_members')
          .select('''
            team_id,
            buddy_teams!inner(
              id,
              team_name,
              team_emoji,
              is_coach_max_team
            )
          ''')
          .eq('user_id', currentUserId);

      if (kDebugMode) {
        print('📊 Teams response: $teamsResponse');
        print('📊 Found ${teamsResponse.length} team memberships');
      }

      final List<TeamStreak> streaks = [];

      for (final teamData in teamsResponse) {
        final team = teamData['buddy_teams'];
        if (team == null) {
          if (kDebugMode) print('⚠️ Skipping null team data');
          continue;
        }
        
        final teamId = team['id'] as String;
        if (kDebugMode) print('🔄 Processing team: ${team['team_name']} ($teamId)');  // ← Debug line
        
        // Get active streak for this team
        final streakData = await _getTeamStreakData(teamId);
        if (streakData != null) {
          if (kDebugMode) print('✅ Added streak: ${streakData.teamName}');
          streaks.add(streakData);
        }
      }
      
      // Sort: Coach Max team first, then by highest streak
      streaks.sort((a, b) {
        if (a.isCoachMaxTeam && !b.isCoachMaxTeam) return -1;
        if (!a.isCoachMaxTeam && b.isCoachMaxTeam) return 1;
        return b.currentStreak.compareTo(a.currentStreak);
      });

      if (kDebugMode) {
        print('✅ Returning ${streaks.length} active streaks');
        for (var s in streaks) {
          print('  - ${s.teamName} (${s.teamId})');
        }
      }

      return streaks;
    } catch (e) {
      if (kDebugMode) print('❌ Error getting user streaks: $e');
      return [];
    }
  }

  /// Get streak data for a specific team
  Future<TeamStreak?> _getTeamStreakData(String teamId) async {
    try {
      if (kDebugMode) print('  🔍 Getting streak data for team: $teamId');
      
      // Get team info
      final teamResponse = await _supabase
          .from('buddy_teams')
          .select('id, team_name, team_emoji, is_coach_max_team')
          .eq('id', teamId)
          .single();

      if (kDebugMode) print('  ✅ Team info: ${teamResponse['team_name']}');

      // Get active streak
      final streakResponse = await _supabase
          .from('team_streaks')
          .select('*, is_favorite')
          .eq('team_id', teamId)
          .eq('is_active', true)
          .maybeSingle();

      if (streakResponse == null) {
        if (kDebugMode) print('  ⚠️ No active streak found for team: $teamId');
        return null;
      }

      if (kDebugMode) print('  ✅ Found active streak: ${streakResponse['id']}');

      // Get team members
      final membersResponse = await _supabase
      .from('team_members')
      .select('user_id, user_profiles!inner(display_name, avatar_id, username)')
      .eq('team_id', teamId);

      if (kDebugMode) print('  ✅ Found ${membersResponse.length} team members');

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

      if (kDebugMode) print('  ✅ Found ${todayCheckIns.length} check-ins today');

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
      if (kDebugMode) print('  ❌ Error getting team streak data: $e');
      return null;
    }
  }

  /// Get today's check-ins for a team
  Future<List<CheckInStatus>> _getTodayCheckIns(String? streakId, String teamId) async {
    if (streakId == null) return [];
    
    try {
      // ✅ FIX: Get ALL recent check-ins and filter in Dart to avoid timezone issues
      if (kDebugMode) print('  📅 Getting recent check-ins for streak: $streakId');
      
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
        print('  📊 Found ${response.length} total check-ins for this streak');
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
          if (kDebugMode) print('  ⚠️ Error parsing check-in date: $e');
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
        print('  ✅ Found ${checkIns.length} check-ins for today');
        for (var checkIn in checkIns) {
          print('     - ${checkIn.displayName} at ${checkIn.checkInTime}');
        }
      }

      return checkIns;
    } catch (e) {
      if (kDebugMode) print('❌ Error getting today check-ins: $e');
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
        if (kDebugMode) print('🔄 User was on break, cancelling it...');
        await _breakDayService.cancelBreakDay();
      }

      // ✅ FIX: Use UTC date consistently
      final now = DateTime.now();
      final today = DateTime(now.year, now.month, now.day).toIso8601String().split('T')[0];
      
      if (kDebugMode) print('🔄 Check-in date: $today (UTC)');
      
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
        
        if (kDebugMode) print('✅ Workout logged to history');
      }

      int successCount = 0;
      
      // Check in to each team
      for (final streak in streaks) {
        if (kDebugMode) print('🔄 Checking in to team: ${streak.teamName}');
        
        final success = await _checkInToTeam(streak.id, streak.teamId, today);
        if (success) {
          successCount++;
          
          // ✅ If this is a Coach Max team, make Coach Max check in too
          if (streak.isCoachMaxTeam) {
            if (kDebugMode) print('🤖 Auto-checking in Coach Max...');
            await _checkInCoachMax(streak.id, today);
          }
        }
      }

      if (kDebugMode) {
        print('✅ Checked in to $successCount/${streaks.length} teams');
      }

      return {
        'success': true,
        'message': 'Checked in to $successCount team${successCount == 1 ? '' : 's'}!',
        'teams_updated': successCount,
        'break_cancelled': onBreak,
      };
    } catch (e) {
      if (kDebugMode) print('❌ Error checking in: $e');
      return {'success': false, 'message': 'Error: $e'};
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
        if (kDebugMode) print('✅ Coach Max already checked in');
        return;
      }

      // Check in Coach Max
      await _supabase.from('daily_team_checkins').insert({
        'team_streak_id': streakId,
        'user_id': coachMaxId,
        'check_in_date': today,
        'check_in_time': DateTime.now().toUtc().toIso8601String(),
      });

      if (kDebugMode) print('✅ Coach Max checked in successfully');
    } catch (e) {
      if (kDebugMode) print('❌ Error checking in Coach Max: $e');
    }
  }

  /// Check in to a specific team
  Future<bool> _checkInToTeam(String streakId, String teamId, String today) async {
    try {
      final currentUserId = _supabase.auth.currentUser?.id;
      if (currentUserId == null) return false;

      final now = DateTime.now().toUtc();

      // Insert check-in
      await _supabase.from('daily_team_checkins').insert({
        'team_streak_id': streakId,
        'user_id': currentUserId,
        'check_in_date': today,
        'check_in_time': now.toIso8601String(),
      });

      // Update streak if all members have checked in
      await _updateTeamStreak(streakId, teamId, today);

      return true;
    } catch (e) {
      if (kDebugMode) print('❌ Error checking in to team: $e');
      return false;
    }
  }

  /// Update team streak after check-in
  Future<void> _updateTeamStreak(String streakId, String teamId, String today) async {
    try {
      // Get total members (excluding Coach Max for counting)
      final membersResponse = await _supabase
          .from('team_members')
          .select('user_id')
          .eq('team_id', teamId)
          .neq('user_id', coachMaxId);
      
      final memberIds = membersResponse.map((m) => m['user_id'] as String).toList();
      final totalMembers = memberIds.length;

      if (kDebugMode) print('📊 Team has $totalMembers members (excluding Coach Max)');

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
        print('📊 Team participation status:');
        print('  - Total members: $totalMembers');
        print('  - Checked in: $checkedInMembers');
        print('  - Participating (check-in OR break): $participatingMembers');
        for (var userId in memberIds) {
          final onBreak = breakDayStatus[userId] ?? false;
          final checkedIn = checkInsResponse.any((c) => c['user_id'] == userId);
          print('  - User $userId: ${onBreak ? "ON BREAK" : checkedIn ? "CHECKED IN" : "MISSING"}');
        }
      }

      // ✅ If all members are participating (checked in or on break), increment streak
      if (participatingMembers >= totalMembers) {
        if (kDebugMode) print('🎉 All members participating! Incrementing streak...');
        await _incrementStreak(streakId, teamId, today);
      } else {
        if (kDebugMode) print('⏳ Waiting for more members... ($participatingMembers/$totalMembers participating)');
      }
    } catch (e) {
      if (kDebugMode) print('❌ Error updating team streak: $e');
    }
  }

  /// Increment streak when all members check in
  Future<void> _incrementStreak(String streakId, String teamId, String today) async {
    try {
      // Get current streak data
      final streakData = await _supabase
          .from('team_streaks')
          .select()
          .eq('id', streakId)
          .single();

      final currentStreak = (streakData['current_streak'] as int?) ?? 0;
      final longestStreak = (streakData['longest_streak'] as int?) ?? 0;
      final totalWorkouts = (streakData['total_workouts'] as int?) ?? 0; 
      final bestStreak = (streakData['best_streak'] as int?) ?? 0;
      final lastWorkoutDate = streakData['last_workout_date'] as String?;

      // Get all team members (excluding Coach Max)
      final membersResponse = await _supabase
          .from('team_members')
          .select('user_id')
          .eq('team_id', teamId)
          .neq('user_id', coachMaxId);
      
      final memberIds = membersResponse.map((m) => m['user_id'] as String).toList();

      int newStreak = currentStreak;
      int newLongest = longestStreak;

      if (lastWorkoutDate == null || lastWorkoutDate == today) {
        // ✅ CASE 1: First workout ever OR already updated today
        if (lastWorkoutDate == today && currentStreak > 0) {
          // Already incremented today, don't double-increment
          // BUT: if currentStreak is 0, we should still increment (fresh start)
          if (kDebugMode) print('ℹ️ Streak already incremented today');
          return;
        }
        // First workout ever OR restarting from 0
        newStreak = 1;
        newLongest = currentStreak > 0 ? longestStreak : 1;
        if (kDebugMode) print('🎉 ${currentStreak == 0 ? "Starting fresh from 0" : "First workout"} - Streak: 1');
      }else {
        final lastDate = DateTime.parse(lastWorkoutDate);
        final todayDate = DateTime.parse(today);
        final daysDifference = todayDate.difference(lastDate).inDays;

        if (daysDifference == 1) {
          // ✅ CASE 2: CONSECUTIVE DAY - CHECK BREAK DAY LOGIC
          // Get today's check-ins
          final checkInsResponse = await _supabase
              .from('daily_team_checkins')
              .select('user_id')
              .eq('team_streak_id', streakId)
              .eq('check_in_date', today)
              .neq('user_id', coachMaxId);
          
          final checkedInUsers = checkInsResponse.map((c) => c['user_id'] as String).toSet();
          
          // Get break day status for all members
          final breakDayStatus = await _breakDayService.getTeamBreakDayStatus(memberIds, today);
          
          if (kDebugMode) {
            print('📊 Break day analysis for $today:');
            for (var userId in memberIds) {
              final onBreak = breakDayStatus[userId] ?? false;
              final checkedIn = checkedInUsers.contains(userId);
              print('  - User $userId: ${onBreak ? "ON BREAK" : checkedIn ? "CHECKED IN" : "NOT CHECKED IN"}');
            }
          }
          
          // Check if at least one person worked out (checked in and NOT on break)
          final someoneWorkedOut = memberIds.any((userId) {
            final onBreak = breakDayStatus[userId] ?? false;
            final checkedIn = checkedInUsers.contains(userId);
            return checkedIn && !onBreak;
          });
          
          if (someoneWorkedOut) {
            // ✅ At least one person worked out - streak continues and increments
            newStreak = currentStreak + 1;
            if (newStreak > longestStreak) {
              newLongest = newStreak;
            }
            if (kDebugMode) print('🔥 Streak incremented! Someone worked out.');
          } else {
            // ❌ Everyone took a break - streak stays same (doesn't increment but doesn't break)
            newStreak = currentStreak; // Stay the same
            if (kDebugMode) print('😴 Everyone on break - streak stays at $currentStreak');
          }
        } else if (daysDifference > 1) {
          // ✅ CASE 3: MORE THAN 1 DAY GAP - CHECK IF GAP IS FILLED WITH BREAK DAYS
          if (kDebugMode) print('⏰ Gap detected: $daysDifference days since last workout');
          
          // ✅ FIX: If current streak is already 0, don't bother checking the gap
          // Just start fresh at 1
          if (currentStreak == 0) {
            newStreak = 1;
            newLongest = longestStreak > 0 ? longestStreak : 1;
            if (kDebugMode) print('🆕 Starting fresh from 0 - Streak: 1');
          } else {
            // Check if the gap is filled with break days
            bool gapIsValid = true;
            
            // Check each day in the gap
            for (int i = 1; i < daysDifference; i++) {
              final checkDate = lastDate.add(Duration(days: i));
              final checkDateStr = DateTime(checkDate.year, checkDate.month, checkDate.day)
                  .toIso8601String()
                  .split('T')[0];
              
              // Get break day status for that day
              final breakStatus = await _breakDayService.getTeamBreakDayStatus(memberIds, checkDateStr);
              
              // If everyone was on break that day, the gap is valid
              final everyoneOnBreak = memberIds.every((userId) => breakStatus[userId] ?? false);
              
              if (!everyoneOnBreak) {
                // Someone wasn't on break but didn't check in - streak broken
                gapIsValid = false;
                break;
              }
            }
            
            if (gapIsValid) {
              // Gap was all break days - treat as consecutive
              newStreak = currentStreak + 1;
              if (newStreak > longestStreak) {
                newLongest = newStreak;
              }
              if (kDebugMode) print('🔥 Gap filled by break days - streak continues!');
            } else {
              // Streak broken - reset to 1
              newStreak = 1;
              if (kDebugMode) print('💔 Streak broken - resetting to 1');
            }
          }
        } else if (daysDifference == 0) {
          // Same day as last workout - should not happen, but handle it
          if (kDebugMode) print('ℹ️ Already counted today, skipping');
          return;
        }
      }

      // Update streak
      await _supabase.from('team_streaks').update({
        'current_streak': newStreak,
        'longest_streak': newLongest,
        'total_workouts': totalWorkouts + 1,
        'best_streak': newStreak > bestStreak ? newStreak : bestStreak, 
        'last_workout_date': today,
        'last_interaction_at': DateTime.now().toUtc().toIso8601String(), 
        'updated_at': DateTime.now().toUtc().toIso8601String(),
      }).eq('id', streakId);

      if (kDebugMode) {
        print('✅ Streak updated! Current: $newStreak, Longest: $newLongest');
      }
    } catch (e) {
      if (kDebugMode) print('❌ Error incrementing streak: $e');
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

      // ✅ FIX: Use UTC date
      final now = DateTime.now();
      final today = DateTime(now.year, now.month, now.day).toIso8601String().split('T')[0];

      final response = await _supabase
          .from('daily_team_checkins')
          .select('id')
          .eq('user_id', currentUserId)
          .eq('check_in_date', today)
          .limit(1);

      return response.isNotEmpty;
    } catch (e) {
      if (kDebugMode) print('❌ Error checking today status: $e');
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
      if (kDebugMode) print('❌ Error getting streak history: $e');
      return [];
    }
  }

  Future<void> checkAndResetBrokenStreaks() async {
    try {
      final currentUserId = _supabase.auth.currentUser?.id;
      if (currentUserId == null) return;

      if (kDebugMode) print('🔍 Checking for broken streaks...');

      final streaks = await getAllUserStreaks();
      
      for (final streak in streaks) {
        await _checkStreakStatus(streak);
      }

      if (kDebugMode) print('✅ Streak check complete');
    } catch (e) {
      if (kDebugMode) print('❌ Error checking streaks: $e');
    }
  }

  /// Check if a specific streak should be reset
  Future<void> _checkStreakStatus(TeamStreak streak) async {
    try {
      if (streak.lastWorkoutDate == null) return; // New streak, nothing to check

      final now = DateTime.now();
      final today = DateTime(now.year, now.month, now.day);
      final yesterday = today.subtract(const Duration(days: 1));
      final lastWorkout = DateTime(
        streak.lastWorkoutDate!.year,
        streak.lastWorkoutDate!.month,
        streak.lastWorkoutDate!.day,
      );

      // If last workout was today or yesterday, streak is fine
      if (lastWorkout.isAtSameMomentAs(today) || 
          lastWorkout.isAtSameMomentAs(yesterday)) {
        return;
      }

      // Check if the gap is filled with break days
      final daysSinceLastWorkout = today.difference(lastWorkout).inDays;
      
      if (daysSinceLastWorkout > 1) {
        // Get all team members (excluding Coach Max)
        final membersResponse = await _supabase
            .from('team_members')
            .select('user_id')
            .eq('team_id', streak.teamId)
            .neq('user_id', coachMaxId);
        
        final memberIds = membersResponse.map((m) => m['user_id'] as String).toList();
        
        // Check each day in the gap
        bool gapIsValid = true;
        
        for (int i = 1; i < daysSinceLastWorkout; i++) {
          final checkDate = lastWorkout.add(Duration(days: i));
          final checkDateStr = DateTime(checkDate.year, checkDate.month, checkDate.day)
              .toIso8601String()
              .split('T')[0];
          
          // Get break day status for that day
          final breakStatus = await _breakDayService.getTeamBreakDayStatus(memberIds, checkDateStr);
          
          // If everyone was on break that day, the gap is valid
          final everyoneOnBreak = memberIds.every((userId) => breakStatus[userId] ?? false);
          
          if (!everyoneOnBreak) {
            // Someone wasn't on break but didn't check in - streak broken
            gapIsValid = false;
            break;
          }
        }
        
        if (!gapIsValid) {
          // Streak is broken - reset it
          if (kDebugMode) print('💔 Resetting broken streak: ${streak.teamName}');
          await _resetStreak(streak.id);
        } else {
          if (kDebugMode) print('✅ Gap filled by break days: ${streak.teamName}');
        }
      }
    } catch (e) {
      if (kDebugMode) print('❌ Error checking streak status: $e');
    }
  }

  /// Reset a streak to 0
  Future<void> _resetStreak(String streakId) async {
    try {
      await _supabase.from('team_streaks').update({
        'current_streak': 0,
        'updated_at': DateTime.now().toUtc().toIso8601String(),
      }).eq('id', streakId);

      if (kDebugMode) print('✅ Streak reset to 0');
    } catch (e) {
      if (kDebugMode) print('❌ Error resetting streak: $e');
    }
  }

  Future<Map<String, dynamic>> checkInBothBuddiesForWorkout({
    required String userId,
    required String buddyId, 
    required String teamId,
  }) async {
    try {
      if (kDebugMode) print('🏋️ Checking in both buddies for workout...');
      if (kDebugMode) print('   User: $userId');
      if (kDebugMode) print('   Buddy: $buddyId');
      if (kDebugMode) print('   Team: $teamId');

      // Get today's date
      final now = DateTime.now();
      final today = DateTime(now.year, now.month, now.day).toIso8601String().split('T')[0];

      // Get the team's active streak
      final streakResponse = await _supabase
          .from('team_streaks')
          .select('id')
          .eq('team_id', teamId)
          .eq('is_active', true)
          .maybeSingle();

      if (streakResponse == null) {
        if (kDebugMode) print('⚠️ No active streak found for team');
        return {'success': false, 'message': 'No active streak for this team'};
      }

      final streakId = streakResponse['id'] as String;
      int checkedInCount = 0;

      // Check in the current user (if not already checked in)
      final userCheckedIn = await _checkInUserToTeamSafe(
        userId, 
        streakId, 
        teamId, 
        today,
      );
      if (userCheckedIn) checkedInCount++;

      // Check in the buddy (if not already checked in)
      final buddyCheckedIn = await _checkInUserToTeamSafe(
        buddyId, 
        streakId, 
        teamId, 
        today,
      );
      if (buddyCheckedIn) checkedInCount++;

      // Now check if streak should be updated
      // (this will only increment if ALL members are now checked in)
      await _updateTeamStreak(streakId, teamId, today);

      if (kDebugMode) {
        print('✅ Buddy workout check-in complete!');
        print('   New check-ins created: $checkedInCount');
      }

      return {
        'success': true,
        'message': checkedInCount > 0 
            ? 'Both buddies checked in! 🎉' 
            : 'Already checked in today',
        'new_checkins': checkedInCount,
      };
    } catch (e) {
      if (kDebugMode) print('❌ Error in buddy workout check-in: $e');
      return {'success': false, 'message': 'Error: $e'};
    }
  }

  /// Safely check in a specific user to a specific team
  /// Returns true if a NEW check-in was created, false if already existed
  Future<bool> _checkInUserToTeamSafe(
    String userId,
    String streakId,
    String teamId,
    String today,
  ) async {
    try {
      // Check if this user already checked in to THIS team today
      final existing = await _supabase
          .from('daily_team_checkins')
          .select('id')
          .eq('team_streak_id', streakId)
          .eq('user_id', userId)
          .eq('check_in_date', today)
          .maybeSingle();

      if (existing != null) {
        if (kDebugMode) print('   ℹ️ User $userId already checked in to this team today');
        return false; // Already checked in, no new check-in created
      }

      // Create the check-in
      final now = DateTime.now().toUtc();
      await _supabase.from('daily_team_checkins').insert({
        'team_streak_id': streakId,
        'user_id': userId,
        'check_in_date': today,
        'check_in_time': now.toIso8601String(),
      });

      if (kDebugMode) print('   ✅ Created check-in for user $userId');
      return true; // New check-in created
    } catch (e) {
      if (kDebugMode) print('   ❌ Error checking in user $userId: $e');
      return false;
    }
  }

  Future<int> checkInAllTeamsForUser(String userId) async {
    print('🔄 Checking in user $userId to all their teams...');
    
    int checkedInCount = 0;
    int skippedNoStreak = 0;
    int skippedAlreadyCheckedIn = 0;
    
    try {
      // Use database function to get ALL team IDs for this user (bypasses RLS)
      final teamIdsResponse = await _supabase
          .rpc('get_user_team_ids', params: {'target_user_id': userId});
      
      final List<dynamic> teamIds = teamIdsResponse as List<dynamic>;
      print('   📊 Found ${teamIds.length} teams for user (via RPC)');
      
      if (teamIds.isEmpty) {
        print('   ⚠️ No teams found for user');
        return 0;
      }
      
      // Get today's date
      final now = DateTime.now();
      final todayStr = DateTime(now.year, now.month, now.day).toIso8601String().split('T')[0];
      
      // Process each team
      for (final teamData in teamIds) {
        final teamId = teamData['team_id'] as String;
        
        try {
          // Get team info
          final teamResponse = await _supabase
              .from('buddy_teams')
              .select('team_name')
              .eq('id', teamId)
              .maybeSingle();
          
          final teamName = teamResponse?['team_name'] ?? 'Unknown Team';
          print('   🔍 Processing team: $teamName ($teamId)');
          
          // Get the active streak for this team
          final streakResponse = await _supabase
              .from('team_streaks')
              .select('id, current_streak')
              .eq('team_id', teamId)
              .eq('is_active', true)
              .maybeSingle();
          
          if (streakResponse == null) {
            print('      ⏭️ Skipped (no active streak)');
            skippedNoStreak++;
            continue;
          }
          
          final streakId = streakResponse['id'] as String;
          
          // Check if user already checked in today
          // ✅ FIX: Use 'team_streak_id' not 'streak_id'
          final existingCheckin = await _supabase
              .from('daily_team_checkins')
              .select('id')
              .eq('team_streak_id', streakId)  // ← FIXED
              .eq('user_id', userId)
              .eq('check_in_date', todayStr)
              .maybeSingle();
          
          if (existingCheckin != null) {
            print('      ⏭️ Skipped (already checked in)');
            skippedAlreadyCheckedIn++;
            continue;
          }
          
          // Create the check-in
          // ✅ FIX: Use 'team_streak_id' and add 'check_in_time'
          await _supabase.from('daily_team_checkins').insert({
            'team_streak_id': streakId,  // ← FIXED
            'user_id': userId,
            'check_in_date': todayStr,
            'check_in_time': DateTime.now().toUtc().toIso8601String(),  // ← ADDED
          });
          
          print('      ✅ Checked in to $teamName');
          checkedInCount++;
          
          // Check if all team members have checked in and increment streak
          await _checkTeamStreakAfterBuddyCheckin(teamId, streakId, todayStr);
          
        } catch (e) {
          print('      ❌ Error processing team $teamId: $e');
        }
      }
      
    } catch (e) {
      print('   ❌ Error getting teams: $e');
    }
    
    print('✅ User $userId check-in summary:');
    print('   - Checked in: $checkedInCount');
    print('   - Skipped (no streak): $skippedNoStreak');
    print('   - Skipped (already checked in): $skippedAlreadyCheckedIn');
    
    return checkedInCount;
  }

  Future<void> _checkTeamStreakAfterBuddyCheckin(String teamId, String streakId, String todayStr) async {
    try {
      // Get team info to check if it's a Coach Max team
      final teamInfo = await _supabase
          .from('buddy_teams')
          .select('is_coach_max_team')
          .eq('id', teamId)
          .single();
      final isCoachMaxTeam = teamInfo['is_coach_max_team'] == true;
      
      // Get team members
      final membersResponse = await _supabase
          .from('team_members')
          .select('user_id')
          .eq('team_id', teamId);
      
      final members = membersResponse as List<dynamic>;
      final allMemberIds = members.map((m) => m['user_id'] as String).toList();
      
      // For Coach Max teams, we only count the human member (not Coach Max)
      // Coach Max teams have exactly 2 members: the user and Coach Max
      // We just need 1 human to check in
      final humanMemberCount = isCoachMaxTeam ? 1 : allMemberIds.length;
      
      print('      📊 Team has $humanMemberCount human members (isCoachMaxTeam: $isCoachMaxTeam)');
      
      // Get today's check-ins for this streak (excluding Coach Max check-ins for count)
      final checkinsResponse = await _supabase
          .from('daily_team_checkins')
          .select('user_id')
          .eq('team_streak_id', streakId)
          .eq('check_in_date', todayStr);
      
      final checkins = checkinsResponse as List<dynamic>;
      final checkedInUserIds = checkins.map((c) => c['user_id'] as String).toSet();
      
      // For regular teams: all members must check in
      // For Coach Max teams: just the human needs to check in (Coach Max auto-checks in after)
      final humanCheckIns = isCoachMaxTeam 
          ? checkedInUserIds.where((id) => allMemberIds.contains(id)).length
          : checkedInUserIds.length;
      
      print('      📊 Checked in: $humanCheckIns/$humanMemberCount');
      
      final allCheckedIn = humanCheckIns >= humanMemberCount;
      
      if (allCheckedIn && humanMemberCount > 0) {
        // Check if streak was already incremented today
        final streakData = await _supabase
            .from('team_streaks')
            .select('current_streak, last_workout_date')
            .eq('id', streakId)
            .single();
        
        final lastWorkoutDate = streakData['last_workout_date'] as String?;
        
        if (lastWorkoutDate == todayStr) {
          print('      ℹ️ Streak already incremented today');
          return;
        }
        
        final currentStreak = streakData['current_streak'] as int? ?? 0;
        
        await _supabase
            .from('team_streaks')
            .update({
              'current_streak': currentStreak + 1,
              'last_workout_date': todayStr,
              'updated_at': DateTime.now().toUtc().toIso8601String(),
            })
            .eq('id', streakId);
        
        print('      🎉 All members checked in! Streak: ${currentStreak + 1}');
        
        // Auto check-in Coach Max if this is a Coach Max team
        if (isCoachMaxTeam) {
          await _checkInCoachMaxForBuddy(streakId, todayStr);
        }
      }
    } catch (e) {
      print('      ⚠️ Error checking streak: $e');
    }
  }

  /// Helper: Check in Coach Max
  Future<void> _checkInCoachMaxForBuddy(String streakId, String todayStr) async {
    try {
      // Use the static coachMaxId constant
      // ✅ FIX: Use 'team_streak_id' not 'streak_id'
      final existing = await _supabase
          .from('daily_team_checkins')
          .select('id')
          .eq('team_streak_id', streakId)  // ← FIXED
          .eq('user_id', coachMaxId)
          .eq('check_in_date', todayStr)
          .maybeSingle();
      
      if (existing != null) return;
      
      // Create check-in
      await _supabase.from('daily_team_checkins').insert({
        'team_streak_id': streakId,  // ← FIXED
        'user_id': coachMaxId,
        'check_in_date': todayStr,
        'check_in_time': DateTime.now().toUtc().toIso8601String(),  // ← ADDED
      });
      
      print('      🤖 Coach Max checked in');
    } catch (e) {
      print('      ⚠️ Error checking in Coach Max: $e');
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
          if (kDebugMode) print('🎯 Found shared team: $teamId');
          return teamId;
        }
      }

      if (kDebugMode) print('⚠️ No shared team found between $userId and $buddyId');
      return null;
    } catch (e) {
      if (kDebugMode) print('❌ Error finding team with buddy: $e');
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

      if (kDebugMode) print('⭐ Toggled favorite for team $teamId to $isFavorite');
    } catch (e) {
      if (kDebugMode) print('❌ Error toggling favorite: $e');
      rethrow;
    }
  }

}