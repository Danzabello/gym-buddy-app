import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Service to sync check-ins across all teams
/// This ensures that when a user checks in, ALL their teams get the check-in
/// even if the team was created after the check-in happened
class TeamSyncService {
  final SupabaseClient _supabase = Supabase.instance.client;

  /// Sync today's check-ins across all user's teams
  /// Call this on home screen load to ensure all teams are up to date
  Future<Map<String, dynamic>> syncAllTeamsCheckIns() async {
    try {
      final currentUserId = _supabase.auth.currentUser?.id;
      if (currentUserId == null) {
        return {'success': false, 'message': 'Not logged in', 'synced': 0};
      }

      if (kDebugMode) print('🔄 SYNC: Starting team check-in sync for user: $currentUserId');

      // Get today's date (local time)
      final now = DateTime.now();
      final today = DateTime(now.year, now.month, now.day).toIso8601String().split('T')[0];
      
      if (kDebugMode) print('📅 SYNC: Checking for date: $today');

      // Step 1: Check if user has checked in today (in ANY team)
      final userCheckIn = await _supabase
          .from('daily_team_checkins')
          .select('check_in_time, team_streak_id')
          .eq('user_id', currentUserId)
          .eq('check_in_date', today)
          .limit(1)
          .maybeSingle();

      if (userCheckIn == null) {
        if (kDebugMode) print('⏭️ SYNC: User hasn\'t checked in today yet, nothing to sync');
        return {'success': true, 'message': 'No check-ins to sync', 'synced': 0};
      }

      if (kDebugMode) print('✅ SYNC: User checked in today at ${userCheckIn['check_in_time']}');

      // Step 2: Get ALL user's team streak IDs
      // ✅ FIXED: Correct relationship path through buddy_teams
      final allTeamsResponse = await _supabase
          .from('team_members')
          .select('''
            team_id,
            buddy_teams!inner(
              id,
              team_name,
              team_streaks!inner(
                id
              )
            )
          ''')
          .eq('user_id', currentUserId);

      if (kDebugMode) print('📊 SYNC: Found ${allTeamsResponse.length} teams for user');

      // Step 3: Get list of team streak IDs that already have today's check-in
      final existingCheckIns = await _supabase
          .from('daily_team_checkins')
          .select('team_streak_id')
          .eq('user_id', currentUserId)
          .eq('check_in_date', today);

      final checkedInStreakIds = existingCheckIns
          .map<String>((c) => c['team_streak_id'] as String)
          .toSet();

      if (kDebugMode) print('✅ SYNC: User has already checked in to ${checkedInStreakIds.length} teams');

      // Step 4: Find teams that need the check-in backfilled
      int syncedCount = 0;
      final List<String> syncedTeams = [];

      for (final teamData in allTeamsResponse) {
        final team = teamData['buddy_teams'];
        
        if (team == null) {
          continue;
        }

        // ✅ FIXED: Access team_streaks from within buddy_teams
        final streaks = team['team_streaks'];
        
        if (streaks == null || (streaks as List).isEmpty) {
          if (kDebugMode) print('⏭️ SYNC: No active streak for team: ${team['team_name']}');
          continue;
        }

        final teamName = team['team_name'] as String;
        final streakId = streaks[0]['id'] as String;

        // Skip if already checked in to this team
        if (checkedInStreakIds.contains(streakId)) {
          if (kDebugMode) print('⏭️ SYNC: Already checked in to team: $teamName');
          continue;
        }

        // Backfill the check-in for this team
        if (kDebugMode) print('🔄 SYNC: Backfilling check-in for team: $teamName');
        
        try {
          await _supabase.from('daily_team_checkins').insert({
            'team_streak_id': streakId,
            'user_id': currentUserId,
            'check_in_date': today,
            'check_in_time': userCheckIn['check_in_time'], // Use the same time as original check-in
          });

          syncedCount++;
          syncedTeams.add(teamName);
          if (kDebugMode) print('✅ SYNC: Successfully backfilled check-in for: $teamName');

          // Check if this completes the team's check-ins for today
          await _checkAndUpdateTeamStreak(streakId, teamData['team_id'], today);
          
        } catch (e) {
          if (kDebugMode) print('⚠️ SYNC: Error backfilling for $teamName: $e');
        }
      }

      if (syncedCount > 0) {
        if (kDebugMode) print('🎉 SYNC: Successfully synced $syncedCount teams: ${syncedTeams.join(", ")}');
        return {
          'success': true,
          'message': 'Synced check-ins to $syncedCount team${syncedCount == 1 ? "" : "s"}',
          'synced': syncedCount,
          'teams': syncedTeams,
        };
      } else {
        if (kDebugMode) print('✅ SYNC: All teams already up to date');
        return {
          'success': true,
          'message': 'All teams already synced',
          'synced': 0,
        };
      }

    } catch (e) {
      if (kDebugMode) print('❌ SYNC ERROR: $e');
      return {
        'success': false,
        'message': 'Sync error: $e',
        'synced': 0,
      };
    }
  }

  /// Check if all team members have checked in and update streak if needed
  Future<void> _checkAndUpdateTeamStreak(String streakId, String teamId, String today) async {
    try {
      // Get all team members (excluding Coach Max)
      final membersResponse = await _supabase
          .from('team_members')
          .select('user_id')
          .eq('team_id', teamId)
          .neq('user_id', '00000000-0000-0000-0000-000000000001'); // Coach Max ID

      final totalMembers = membersResponse.length;

      // Get today's check-ins (excluding Coach Max)
      final checkInsResponse = await _supabase
          .from('daily_team_checkins')
          .select('user_id')
          .eq('team_streak_id', streakId)
          .eq('check_in_date', today)
          .neq('user_id', '00000000-0000-0000-0000-000000000001');

      final checkedInMembers = checkInsResponse.length;

      if (kDebugMode) {
        print('📊 SYNC: Team check-in status: $checkedInMembers/$totalMembers');
      }

      // If all members checked in, update the streak
      if (checkedInMembers >= totalMembers) {
        if (kDebugMode) print('🎉 SYNC: All members checked in! Updating streak...');
        
        // Get current streak data
        final streakData = await _supabase
            .from('team_streaks')
            .select('current_streak, longest_streak, last_workout_date')
            .eq('id', streakId)
            .single();

        // Only update if not already updated today
        if (streakData['last_workout_date'] != today) {
          final currentStreak = (streakData['current_streak'] as int?) ?? 0;
          final longestStreak = (streakData['longest_streak'] as int?) ?? 0;
          final lastWorkoutDate = streakData['last_workout_date'] as String?;

          int newStreak = 1;
          int newLongest = longestStreak;

          if (lastWorkoutDate != null) {
            final lastDate = DateTime.parse(lastWorkoutDate);
            final todayDate = DateTime.parse(today);
            final daysDifference = todayDate.difference(lastDate).inDays;

            if (daysDifference == 1) {
              // Consecutive day - increment
              newStreak = currentStreak + 1;
              if (newStreak > longestStreak) {
                newLongest = newStreak;
              }
            }
          } else {
            // First workout ever
            newLongest = 1;
          }

          await _supabase.from('team_streaks').update({
            'current_streak': newStreak,
            'longest_streak': newLongest,
            'last_workout_date': today,
            'updated_at': DateTime.now().toIso8601String(),
          }).eq('id', streakId);

          if (kDebugMode) {
            print('✅ SYNC: Streak updated! Current: $newStreak, Longest: $newLongest');
          }
        }
      }
    } catch (e) {
      if (kDebugMode) print('❌ SYNC: Error updating team streak: $e');
    }
  }
}