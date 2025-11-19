import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

// ============================================
// MODEL CLASSES (moved outside service)
// ============================================

/// Represents a team member
class TeamMember {
  final String userId;
  final String displayName;
  final bool isCoachMax;
  final String? avatarId;

  TeamMember({
    required this.userId,
    required this.displayName,
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
  final DateTime? lastWorkoutDate;
  final bool isCoachMaxTeam;
  final List<TeamMember> members;
  final List<CheckInStatus> todayCheckIns;
  
  TeamStreak({
    required this.id,
    required this.teamId,
    required this.teamName,
    required this.teamEmoji,
    required this.currentStreak,
    required this.longestStreak,
    required this.lastWorkoutDate,
    required this.isCoachMaxTeam,
    required this.members,
    required this.todayCheckIns,
  });
  
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
        if (kDebugMode) print('🔄 Processing team: ${team['team_name']} ($teamId)');
        
        // Get active streak for this team
        final streakData = await _getTeamStreakData(teamId);
        if (streakData != null) {
          if (kDebugMode) print('✅ Added streak: ${streakData.teamName}');
          streaks.add(streakData);
        } else {
          if (kDebugMode) print('⚠️ No streak data for team: ${team['team_name']}');
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
          .select()
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
      .select('user_id, user_profiles!inner(display_name, avatar_id)')
      .eq('team_id', teamId);

      if (kDebugMode) print('  ✅ Found ${membersResponse.length} team members');

      final members = <TeamMember>[];
      for (final member in membersResponse) {
        final profile = member['user_profiles'];
        members.add(TeamMember(
          userId: member['user_id'],
          displayName: profile['display_name'] ?? 'Unknown',
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
        lastWorkoutDate: streakResponse['last_workout_date'] != null
            ? DateTime.parse(streakResponse['last_workout_date'])
            : null,
        isCoachMaxTeam: teamResponse['is_coach_max_team'] ?? false,
        members: members,
        todayCheckIns: todayCheckIns,
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
  
  Future<Map<String, dynamic>> checkInAllTeams() async {
    try {
      final currentUserId = _supabase.auth.currentUser?.id;
      if (currentUserId == null) {
        return {'success': false, 'message': 'Not logged in'};
      }

      // ✅ FIX: Use UTC date consistently
      final now = DateTime.now().toUtc();
      final todayUtc = DateTime.utc(now.year, now.month, now.day);
      final today = todayUtc.toIso8601String().split('T')[0];
      
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
      };
    } catch (e) {
      if (kDebugMode) print('❌ Error checking in: $e');
      return {'success': false, 'message': 'Error: $e'};
    }
  }

  /// Helper method to check in Coach Max
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
    
    final totalMembers = membersResponse.length;

    // Get today's check-ins
    final checkInsResponse = await _supabase
        .from('daily_team_checkins')
        .select('user_id')
        .eq('team_streak_id', streakId)
        .eq('check_in_date', today)
        .neq('user_id', coachMaxId);

    final checkedInMembers = checkInsResponse.length;

    if (kDebugMode) {
      print('📊 Team check-in status: $checkedInMembers/$totalMembers');
      print('📊 Team members: ${membersResponse.map((m) => m['user_id'])}');
      print('📊 Checked in: ${checkInsResponse.map((m) => m['user_id'])}');
    }

    // If all members checked in, increment streak
    if (checkedInMembers >= totalMembers) {
      if (kDebugMode) print('🎉 All members checked in! Incrementing streak...');
      await _incrementStreak(streakId, today);
    } else {
      if (kDebugMode) print('⏳ Waiting for more members to check in...');
    }
  } catch (e) {
    if (kDebugMode) print('❌ Error updating team streak: $e');
  }
}

  /// Increment streak when all members check in
  Future<void> _incrementStreak(String streakId, String today) async {
    try {
      // Get current streak data
      final streakData = await _supabase
          .from('team_streaks')
          .select()
          .eq('id', streakId)
          .single();

      final currentStreak = (streakData['current_streak'] as int?) ?? 0;
      final longestStreak = (streakData['longest_streak'] as int?) ?? 0;
      final lastWorkoutDate = streakData['last_workout_date'] as String?;

      int newStreak = currentStreak;
      int newLongest = longestStreak;

      if (lastWorkoutDate == null) {
        // First workout
        newStreak = 1;
        newLongest = 1;
      } else {
        final lastDate = DateTime.parse(lastWorkoutDate);
        final todayDate = DateTime.parse(today);
        final daysDifference = todayDate.difference(lastDate).inDays;

        if (daysDifference == 0) {
          // Already counted today
          return;
        } else if (daysDifference == 1) {
          // Consecutive day - increment
          newStreak = currentStreak + 1;
          if (newStreak > longestStreak) {
            newLongest = newStreak;
          }
        } else {
          // Streak broken - reset to 1
          newStreak = 1;
        }
      }

      // Update streak
      await _supabase.from('team_streaks').update({
        'current_streak': newStreak,
        'longest_streak': newLongest,
        'last_workout_date': today,
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
      final now = DateTime.now().toUtc();
      final todayUtc = DateTime.utc(now.year, now.month, now.day);
      final today = todayUtc.toIso8601String().split('T')[0];

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
            *,
            buddy_teams!inner(team_name, team_emoji)
          ''')
          .inFilter('team_id', teamIds)
          .eq('is_active', false)
          .order('end_date', ascending: false)
          .limit(limit);

      return List<Map<String, dynamic>>.from(response);
    } catch (e) {
      if (kDebugMode) print('❌ Error getting streak history: $e');
      return [];
    }
  }
}