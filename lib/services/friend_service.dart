import 'package:supabase_flutter/supabase_flutter.dart';

class FriendService {
  final SupabaseClient _supabase = Supabase.instance.client;

  // Search for users by name
  Future<List<Map<String, dynamic>>> searchUsers(String query) async {
    try {
      if (query.isEmpty) return [];
      
      final currentUserId = _supabase.auth.currentUser?.id;
      if (currentUserId == null) return [];

      // Search in user_profiles for display names
      final response = await _supabase
          .from('user_profiles')
          .select('id, display_name, age, fitness_level')
          .ilike('display_name', '%$query%')
          .neq('id', currentUserId)  // Don't show current user
          .limit(20);

      return List<Map<String, dynamic>>.from(response);
    } catch (e) {
      print('Error searching users: $e');
      return [];
    }
  }

  // Send friend request
  Future<bool> sendFriendRequest(String friendId) async {
    try {
      final currentUserId = _supabase.auth.currentUser?.id;
      if (currentUserId == null) return false;

      // Check if friendship already exists
      final existing = await _supabase
          .from('friendships')
          .select()
          .or('user_id.eq.$currentUserId,friend_id.eq.$currentUserId')
          .or('user_id.eq.$friendId,friend_id.eq.$friendId')
          .maybeSingle();

      if (existing != null) {
        print('Friendship already exists');
        return false;
      }

      // Create friend request
      await _supabase.from('friendships').insert({
        'user_id': currentUserId,
        'friend_id': friendId,
        'status': 'pending',
      });

      return true;
    } catch (e) {
      print('Error sending friend request: $e');
      return false;
    }
  }

  // Accept friend request
  Future<bool> acceptFriendRequest(String requestId) async {
    try {
      await _supabase
          .from('friendships')
          .update({'status': 'accepted'})
          .eq('id', requestId);

      return true;
    } catch (e) {
      print('Error accepting friend request: $e');
      return false;
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
      print('Error declining friend request: $e');
      return false;
    }
  }

  // Get pending friend requests for current user
  Future<List<Map<String, dynamic>>> getPendingRequests() async {
    try {
      final currentUserId = _supabase.auth.currentUser?.id;
      if (currentUserId == null) return [];

      // Get requests where current user is the friend_id (someone requested them)
      final response = await _supabase
          .from('friendships')
          .select('''
            id,
            user_id,
            created_at,
            user_profiles!user_id (
              display_name,
              age,
              fitness_level
            )
          ''')
          .eq('friend_id', currentUserId)
          .eq('status', 'pending');

      return List<Map<String, dynamic>>.from(response);
    } catch (e) {
      print('Error getting pending requests: $e');
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
      print('Error getting friends: $e');
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