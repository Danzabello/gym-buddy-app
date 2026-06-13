import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:gym_buddy_app/utils/debug_logger.dart';

class FriendService {
  final SupabaseClient _supabase = Supabase.instance.client;

  // Search for users by USERNAME (not display name)
  Future<List<Map<String, dynamic>>> searchUsers(String query) async {
    try {
      if (kDebugMode) debugLog('🔎 searchUsers called with: "$query"');
      
      if (query.isEmpty) return [];
      
      final currentUserId = _supabase.auth.currentUser?.id;
      
      if (currentUserId == null) {
        if (kDebugMode) debugLog('❌ No user logged in!');
        return [];
      }

      // Remove @ symbol if user typed it
      final cleanQuery = query.startsWith('@') ? query.substring(1) : query;

      // Search by USERNAME (unique identifier for finding friends)
      final response = await _supabase
          .from('user_profiles')
          .select('id, username, display_name, fitness_level, avatar_id') // 🔒 removed age
          .ilike('username', '%$cleanQuery%')
          .neq('id', currentUserId)
          .not('username', 'is', null)
          .limit(20);

      if (kDebugMode) {
        debugLog('✅ Database returned ${response.length} results');
      }
      
      return List<Map<String, dynamic>>.from(response);
    } catch (e) {
      if (kDebugMode) debugLog('❌ Error searching users: $e');
      return [];
    }
  }

  // Send friend request
  Future<bool> sendFriendRequest(String friendId) async {
    try {
      final currentUserId = _supabase.auth.currentUser?.id;
      if (currentUserId == null) {
        if (kDebugMode) debugLog('❌ No user logged in');
        return false;
      }


      // Check if friendship already exists (either direction)
      final existing = await _supabase
          .from('friendships')
          .select()
          .or('and(user_id.eq.$currentUserId,friend_id.eq.$friendId),and(user_id.eq.$friendId,friend_id.eq.$currentUserId)')
          .maybeSingle();

      if (existing != null) {
        if (kDebugMode) debugLog('⚠️ Friendship already exists: ${existing['status']}');
        return false;
      }

      // Create friend request
      final response = await _supabase.from('friendships').insert({
        'user_id': currentUserId,
        'friend_id': friendId,
        'status': 'pending',
      }).select();  // ✅ ADD .select() to get the created record back


      return true;
    } catch (e) {
      if (kDebugMode) debugLog('❌ Error sending friend request: $e');
      return false;
    }
  }

  // Accept friend request with BACKFILL functionality
  Future<bool> acceptFriendRequest(String requestId) async {
    try {
      final currentUserId = _supabase.auth.currentUser?.id;
      if (currentUserId == null) return false;

      if (kDebugMode) debugLog('✅ Accepting friend request: $requestId');

      // Get the friendship details BEFORE updating
      final friendship = await _supabase
          .from('friendships')
          .select('user_id, friend_id')
          .eq('id', requestId)
          .single();

      final friendUserId = friendship['user_id'] as String;

      // Accept the friend request
      await _supabase.from('friendships').update({
        'status': 'accepted',
      }).eq('id', requestId);

      if (kDebugMode) debugLog('✅ Friendship accepted');

      // 🔥 Create a team and get the team ID back
      final teamData = await _createTeamStreakAndGetIds(currentUserId, friendUserId);
      
      // 🔥 BACKFILL: If users have already checked in today, apply it to new team
      if (teamData != null && teamData['teamId'] != null && teamData['streakId'] != null) {
        // Add a small delay to ensure database consistency
        if (kDebugMode) debugLog('⏳ Waiting for database consistency...');
        await Future.delayed(const Duration(milliseconds: 100));
        
        await _backfillTodaysCheckIns(
          teamData['teamId']!, 
          teamData['streakId']!, 
          currentUserId, 
          friendUserId
        );
      }

      return true;
    } catch (e) {
      if (kDebugMode) debugLog('❌ Error accepting friend request: $e');
      return false;
    }
  }

  // 🔥 Modified: Create team streak and return both team and streak IDs
  Future<Map<String, String>?> _createTeamStreakAndGetIds(String userId1, String userId2) async {
    try {

      // Get both users' display names
      final user1Profile = await _supabase
          .from('user_profiles')
          .select('display_name')
          .eq('id', userId1)
          .single();

      final user2Profile = await _supabase
          .from('user_profiles')
          .select('display_name')
          .eq('id', userId2)
          .single();

      final user1Name = user1Profile['display_name'] as String;
      final user2Name = user2Profile['display_name'] as String;

      // Create buddy team
      final team = await _supabase.from('buddy_teams').insert({
        'team_name': '$user1Name & $user2Name',
        'team_emoji': '💪',
        'is_coach_max_team': false,
        'max_members': 2,
        'created_by': userId1,
      }).select().single();

      final teamId = team['id'] as String;
      if (kDebugMode) debugLog('✅ Team created: $teamId');

      // Add both members to the team
      await _supabase.from('team_members').insert([
        {
          'team_id': teamId,
          'user_id': userId1,
          'role': 'member',
        },
        {
          'team_id': teamId,
          'user_id': userId2,
          'role': 'member',
        },
      ]);

      if (kDebugMode) debugLog('✅ Team members added');

      // Create team streak
      final teamStreak = await _supabase.from('team_streaks').insert({
        'team_id': teamId,
        'current_streak': 0,
        'longest_streak': 0,
        'is_active': true,
      }).select().single();

      final streakId = teamStreak['id'] as String;
      if (kDebugMode) debugLog('✅ Team streak created: $streakId');

      return {
        'teamId': teamId,
        'streakId': streakId,
      };
    } catch (e) {
      if (kDebugMode) debugLog('❌ Error creating team streak: $e');
      return null;
    }
  }

  // 🔥 NEW: Backfill today's check-ins for newly created team
  Future<void> _backfillTodaysCheckIns(
    String teamId, 
    String streakId, 
    String userId1, 
    String userId2
  ) async {
    try {
      // Use consistent UTC date for today
      final now = DateTime.now().toUtc();
      final todayUtc = DateTime.utc(now.year, now.month, now.day);
      final today = todayUtc.toIso8601String().split('T')[0];
      
      if (kDebugMode) {
        debugLog('🔄 Checking for today\'s check-ins to backfill (date: $today)...');
      }

      // ADD THIS DEBUG BLOCK HERE - BEFORE USER1 QUERY
      if (kDebugMode) {
        debugLog('   🔍 Querying for user1 check-in:');
        debugLog('      - check_in_date: $today');
      }

      // Check if user1 has checked in today (in ANY team)
      final user1CheckIn = await _supabase
          .from('daily_team_checkins')
          .select('check_in_time')
          .eq('user_id', userId1)
          .eq('check_in_date', today)
          .limit(1)
          .maybeSingle();

      // ADD THIS DEBUG BLOCK HERE - BEFORE USER2 QUERY
      if (kDebugMode) {
        debugLog('   🔍 Querying for user2 check-in:');
        debugLog('      - check_in_date: $today');
      }

      // Check if user2 has checked in today (in ANY team)  
      final user2CheckIn = await _supabase
          .from('daily_team_checkins')
          .select('check_in_time')
          .eq('user_id', userId2)
          .eq('check_in_date', today)
          .limit(1)
          .maybeSingle();

      // ADD THIS DEBUG BLOCK HERE - AFTER BOTH QUERIES
      if (kDebugMode) {
        debugLog('   📊 User1 query result: $user1CheckIn');
        debugLog('   📊 User2 query result: $user2CheckIn');
      }

      debugLog('🔍 User1 check-in found: ${user1CheckIn != null ? "YES" : "NO"}');
      debugLog('🔍 User2 check-in found: ${user2CheckIn != null ? "YES" : "NO"}');

      if (user1CheckIn != null) {
        debugLog('   User1 check-in time: ${user1CheckIn['check_in_time']}');
      }
      if (user2CheckIn != null) {
        debugLog('   User2 check-in time: ${user2CheckIn['check_in_time']}');
      }


      int backfilledCount = 0;

      // Backfill user1's check-in if they checked in today
      if (user1CheckIn != null) {
        await _supabase.from('daily_team_checkins').insert({
          'team_streak_id': streakId,
          'user_id': userId1,
          'check_in_date': today,
          'check_in_time': user1CheckIn['check_in_time'],
        });
        backfilledCount++;
      }

      // Backfill user2's check-in if they checked in today
      if (user2CheckIn != null) {
        await _supabase.from('daily_team_checkins').insert({
          'team_streak_id': streakId,
          'user_id': userId2,
          'check_in_date': today,
          'check_in_time': user2CheckIn['check_in_time'],
        });
        backfilledCount++;
      }

      // If both users had checked in today, update the streak immediately
      if (backfilledCount == 2) {
        if (kDebugMode) debugLog('🔥 Both users had checked in - updating streak!');
        
        // Set the streak to 1 and update the last_workout_date to today
        await _supabase.from('team_streaks').update({
          'current_streak': 1,
          'longest_streak': 1,
          'last_workout_date': today,  // This is crucial!
          'updated_at': DateTime.now().toUtc().toIso8601String(),
        }).eq('id', streakId);

        if (kDebugMode) debugLog('✅ Streak updated to 1 for new team with date: $today');
      } else if (backfilledCount == 1) {
        if (kDebugMode) debugLog('⏳ Only one user had checked in - waiting for the other');
        // Don't update the streak, but the check-in is recorded
      } else {
        if (kDebugMode) debugLog('🆕 Neither user had checked in yet today');
      }

    } catch (e) {
      if (kDebugMode) debugLog('❌ Error backfilling check-ins: $e');
    }
  }

  // Decline friend request
  Future<bool> declineFriendRequest(String requestId) async {
    try {
      await _supabase
          .from('friendships')
          .delete()
          .eq('id', requestId);

      return true;
    } catch (e) {
      if (kDebugMode) debugLog('Error declining friend request: $e');
      return false;
    }
  }

  // Get pending friend requests for current user
  Future<List<Map<String, dynamic>>> getPendingRequests() async {
    try {
      final currentUserId = _supabase.auth.currentUser?.id;
      if (currentUserId == null) {
        if (kDebugMode) debugLog('❌ No user logged in');
        return [];
      }


      // Get pending friend requests WHERE YOU ARE THE RECIPIENT
      final response = await _supabase
          .from('friendships')
          .select('''
            id,
            user_id,
            friend_id,
            status,
            created_at,
            user_profiles!friendships_user_id_fkey (
              id,
              display_name,
              username,
              avatar_id,
              fitness_level
            )
          ''')
          .eq('friend_id', currentUserId)
          .eq('status', 'pending')
          .order('created_at', ascending: false);

      if (kDebugMode) {
        debugLog('✅ Found ${response.length} pending requests');
        for (var req in response) {
        }
      }

      return List<Map<String, dynamic>>.from(response);
    } catch (e) {
      if (kDebugMode) debugLog('❌ Error getting pending requests: $e');
      return [];
    }
  }

  // Get accepted friends
  Future<List<Map<String, dynamic>>> getFriends() async {
    try {
      final currentUserId = _supabase.auth.currentUser?.id;
      if (currentUserId == null) return [];


      // Get all accepted friendships where user is either user_id or friend_id
      final response = await _supabase
          .from('friendships')
          .select()
          .eq('status', 'accepted')
          .or('user_id.eq.$currentUserId,friend_id.eq.$currentUserId');

      if (kDebugMode) debugLog('📊 Found ${response.length} accepted friendships');

      // Extract friend IDs
      final friendIds = <String>[];
      for (final friendship in response) {
        if (friendship['user_id'] == currentUserId) {
          friendIds.add(friendship['friend_id']);
        } else {
          friendIds.add(friendship['user_id']);
        }
      }


      if (friendIds.isEmpty) return [];

      // Get friend profiles (now including username)
      final profiles = await _supabase
          .from('user_profiles')
          .select('id, username, display_name, avatar_id, avatar_border, fitness_level, looking_for_buddy, workout_days_per_week') // 🔒 explicit, no age/gender
          .inFilter('id', friendIds);

      if (kDebugMode) debugLog('✅ Loaded ${profiles.length} friend profiles');

      return List<Map<String, dynamic>>.from(profiles);
    } catch (e) {
      if (kDebugMode) debugLog('❌ Error getting friends: $e');
      return [];
    }
  }

  // Check if two users are friends
  Future<bool> areFriends(String userId1, String userId2) async {
    try {
      final response = await _supabase
          .from('friendships')
          .select()
          .eq('status', 'accepted')
          .or('user_id.eq.$userId1,friend_id.eq.$userId1')
          .or('user_id.eq.$userId2,friend_id.eq.$userId2')
          .maybeSingle();

      return response != null;
    } catch (e) {
      return false;
    }
  }

  // Get friendship status between two users
  Future<String> getFriendshipStatus(String otherUserId) async {
    try {
      final currentUserId = _supabase.auth.currentUser?.id;
      if (currentUserId == null) return 'none';

      final response = await _supabase
          .from('friendships')
          .select()
          .or('user_id.eq.$currentUserId,friend_id.eq.$currentUserId')
          .or('user_id.eq.$otherUserId,friend_id.eq.$otherUserId')
          .maybeSingle();

      if (response == null) return 'none';
      return response['status'];
    } catch (e) {
      return 'none';
    }
  }

  // 🆕 Remove a friend (deletes friendship and team streak)
  Future<bool> removeFriend(String friendId) async {
    try {
      final currentUserId = _supabase.auth.currentUser?.id;
      if (currentUserId == null) {
        if (kDebugMode) debugLog('❌ No user logged in');
        return false;
      }


      // Step 1: Find the team between these two users (excluding Coach Max teams)
      final teamData = await _findTeamBetweenUsers(currentUserId, friendId);
      
      if (teamData != null) {
        final teamId = teamData['id'] as String;
        final teamName = teamData['team_name'] as String;
        
        if (kDebugMode) debugLog('🗑️ Found team to delete: $teamName ($teamId)');
        
        // Step 2: Delete all check-ins for this team's streak
        try {
          // First get the streak ID
          final streakResponse = await _supabase
              .from('team_streaks')
              .select('id')
              .eq('team_id', teamId)
              .maybeSingle();
          
          if (streakResponse != null) {
            final streakId = streakResponse['id'] as String;
            
            // Delete check-ins
            await _supabase
                .from('daily_team_checkins')
                .delete()
                .eq('team_streak_id', streakId);
            
            if (kDebugMode) debugLog('✅ Deleted check-ins for streak: $streakId');
          }
        } catch (e) {
          if (kDebugMode) debugLog('⚠️ Error deleting check-ins: $e');
        }
        
        // Step 3: Delete the team streak
        try {
          await _supabase
              .from('team_streaks')
              .delete()
              .eq('team_id', teamId);
          
          if (kDebugMode) debugLog('✅ Deleted team streak');
        } catch (e) {
          if (kDebugMode) debugLog('⚠️ Error deleting team streak: $e');
        }
        
        // Step 4: Delete team members
        try {
          await _supabase
              .from('team_members')
              .delete()
              .eq('team_id', teamId);
          
          if (kDebugMode) debugLog('✅ Deleted team members');
        } catch (e) {
          if (kDebugMode) debugLog('⚠️ Error deleting team members: $e');
        }
        
        // Step 5: Delete the buddy team itself
        try {
          await _supabase
              .from('buddy_teams')
              .delete()
              .eq('id', teamId);
          
          if (kDebugMode) debugLog('✅ Deleted buddy team: $teamName');
        } catch (e) {
          if (kDebugMode) debugLog('⚠️ Error deleting buddy team: $e');
        }
      } else {
        if (kDebugMode) debugLog('ℹ️ No team found between users (may already be deleted)');
      }

      // Step 6: Delete the friendship record
      await _supabase
          .from('friendships')
          .delete()
          .or('and(user_id.eq.$currentUserId,friend_id.eq.$friendId),and(user_id.eq.$friendId,friend_id.eq.$currentUserId)');

      if (kDebugMode) debugLog('✅ Friendship removed successfully');
      return true;
    } catch (e) {
      if (kDebugMode) debugLog('❌ Error removing friend: $e');
      return false;
    }
  }

  /// Helper: Find the team between two users (excluding Coach Max teams)
  Future<Map<String, dynamic>?> _findTeamBetweenUsers(String userId1, String userId2) async {
    try {
      // Get all teams that userId1 is in (excluding Coach Max)
      final user1Teams = await _supabase
          .from('team_members')
          .select('team_id, buddy_teams!inner(id, team_name, is_coach_max_team)')
          .eq('user_id', userId1);

      for (final teamData in user1Teams) {
        final team = teamData['buddy_teams'];
        if (team == null) continue;
        
        // Skip Coach Max teams
        if (team['is_coach_max_team'] == true) continue;

        final teamId = team['id'] as String;

        // Check if userId2 is also in this team
        final user2InTeam = await _supabase
            .from('team_members')
            .select('id')
            .eq('team_id', teamId)
            .eq('user_id', userId2)
            .maybeSingle();

        if (user2InTeam != null) {
          // Found the team between these two users
          return team;
        }
      }

      return null;
    } catch (e) {
      if (kDebugMode) debugLog('❌ Error finding team between users: $e');
      return null;
    }
  }
}