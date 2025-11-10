import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class FriendService {
  final SupabaseClient _supabase = Supabase.instance.client;

  // Search for users by name
  Future<List<Map<String, dynamic>>> searchUsers(String query) async {
    try {
      if (kDebugMode) print('🔎 searchUsers called with: "$query"');
      
      if (query.isEmpty) return [];
      
      final currentUserId = _supabase.auth.currentUser?.id;
      if (kDebugMode) print('👤 Current user ID: $currentUserId');
      
      if (currentUserId == null) {
        if (kDebugMode) print('❌ No user logged in!');
        return [];
      }

      // Search in user_profiles for display names
      final response = await _supabase
          .from('user_profiles')
          .select('id, display_name, age, fitness_level, avatar_id')
          .ilike('display_name', '%$query%')
          .neq('id', currentUserId)
          .limit(20);

      if (kDebugMode) {
        print('✅ Database returned ${response.length} results');
        print('📄 Results: $response');
      }
      
      return List<Map<String, dynamic>>.from(response);
    } catch (e) {
      if (kDebugMode) print('❌ Error searching users: $e');
      return [];
    }
  }

  // Send friend request
  Future<bool> sendFriendRequest(String friendId) async {
    try {
      final currentUserId = _supabase.auth.currentUser?.id;
      if (currentUserId == null) {
        if (kDebugMode) print('❌ No user logged in');
        return false;
      }

      if (kDebugMode) print('📤 Sending friend request from $currentUserId to $friendId');

      // Check if friendship already exists (either direction)
      final existing = await _supabase
          .from('friendships')
          .select()
          .or('and(user_id.eq.$currentUserId,friend_id.eq.$friendId),and(user_id.eq.$friendId,friend_id.eq.$currentUserId)')
          .maybeSingle();

      if (existing != null) {
        if (kDebugMode) print('⚠️ Friendship already exists: ${existing['status']}');
        return false;
      }

      // Create friend request
      final response = await _supabase.from('friendships').insert({
        'user_id': currentUserId,
        'friend_id': friendId,
        'status': 'pending',
      }).select();  // ✅ ADD .select() to get the created record back

      if (kDebugMode) print('✅ Friend request created: $response');

      return true;
    } catch (e) {
      if (kDebugMode) print('❌ Error sending friend request: $e');
      return false;
    }
  }

  // Accept friend request
  Future<bool> acceptFriendRequest(String requestId) async {
    try {
      final currentUserId = _supabase.auth.currentUser?.id;
      if (currentUserId == null) return false;

      if (kDebugMode) print('✅ Accepting friend request: $requestId');

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

      if (kDebugMode) print('✅ Friendship accepted');

      // 🔥 NEW: Create a team streak for this friendship!
      await _createTeamStreak(currentUserId, friendUserId);

      return true;
    } catch (e) {
      if (kDebugMode) print('❌ Error accepting friend request: $e');
      return false;
    }
  }

  // 🔥 NEW: Helper method to create team streak
  Future<void> _createTeamStreak(String userId1, String userId2) async {
    try {
      if (kDebugMode) print('🔥 Creating team streak for $userId1 and $userId2');

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

      // Create team streak
      final teamStreak = await _supabase.from('team_streaks').insert({
        'team_name': '$user1Name & $user2Name',
        'team_emoji': '💪',  // Default emoji
        'current_streak': 0,
        'longest_streak': 0,
        'last_check_in_date': null,
      }).select().single();

      final teamStreakId = teamStreak['id'] as String;

      if (kDebugMode) print('✅ Team streak created: $teamStreakId');

      // Add both members to the team
      await _supabase.from('team_members').insert([
        {
          'team_streak_id': teamStreakId,
          'user_id': userId1,
        },
        {
          'team_streak_id': teamStreakId,
          'user_id': userId2,
        },
      ]);

      if (kDebugMode) print('✅ Team members added');
    } catch (e) {
      if (kDebugMode) print('❌ Error creating team streak: $e');
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
      if (kDebugMode) print('Error declining friend request: $e');
      return false;
    }
  }

  // Get pending friend requests for current user
  Future<List<Map<String, dynamic>>> getPendingRequests() async {
    try {
      final currentUserId = _supabase.auth.currentUser?.id;
      if (currentUserId == null) {
        if (kDebugMode) print('❌ No user logged in');
        return [];
      }

      if (kDebugMode) print('📥 Getting pending requests for $currentUserId');

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
              avatar_id,
              fitness_level
            )
          ''')  // ✅ FIXED: Added comma between avatar_id and fitness_level
          .eq('friend_id', currentUserId)
          .eq('status', 'pending')
          .order('created_at', ascending: false);

      if (kDebugMode) {
        print('✅ Found ${response.length} pending requests');
        for (var req in response) {
          print('  - From: ${req['user_profiles']?['display_name']} (${req['user_id']})');
        }
      }

      return List<Map<String, dynamic>>.from(response);
    } catch (e) {
      if (kDebugMode) print('❌ Error getting pending requests: $e');
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

      // Get friend profiles
      final profiles = await _supabase
          .from('user_profiles')
          .select('*')
          .inFilter('id', friendIds);

      return List<Map<String, dynamic>>.from(profiles);
    } catch (e) {
      if (kDebugMode) print('Error getting friends: $e');
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
}