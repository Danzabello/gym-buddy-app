import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Service to manage friend nicknames
/// Nicknames are personal - only YOU see the nicknames YOU set
class NicknameService {
  final SupabaseClient _supabase = Supabase.instance.client;
  
  // Cache nicknames in memory to avoid repeated database calls
  Map<String, String>? _nicknameCache;
  DateTime? _cacheTime;
  static const Duration _cacheDuration = Duration(minutes: 5);

  /// Get all nicknames for the current user
  /// Returns a map of {friendId: nickname}
  Future<Map<String, String>> getAllNicknames({bool forceRefresh = false}) async {
    try {
      // Return cached data if still valid
      if (!forceRefresh && 
          _nicknameCache != null && 
          _cacheTime != null &&
          DateTime.now().difference(_cacheTime!) < _cacheDuration) {
        return _nicknameCache!;
      }

      final currentUserId = _supabase.auth.currentUser?.id;
      if (currentUserId == null) return {};

      final response = await _supabase
          .from('friend_nicknames')
          .select('friend_id, nickname')
          .eq('user_id', currentUserId);

      final nicknames = <String, String>{};
      for (final row in response) {
        nicknames[row['friend_id']] = row['nickname'];
      }

      // Update cache
      _nicknameCache = nicknames;
      _cacheTime = DateTime.now();

      if (kDebugMode) {
        print('📛 Loaded ${nicknames.length} nicknames');
      }

      return nicknames;
    } catch (e) {
      if (kDebugMode) print('❌ Error loading nicknames: $e');
      return _nicknameCache ?? {};
    }
  }

  /// Get nickname for a specific friend
  /// Returns null if no nickname is set
  Future<String?> getNickname(String friendId) async {
    final nicknames = await getAllNicknames();
    return nicknames[friendId];
  }

  /// Get the display name to show for a friend
  /// Priority: nickname > displayName
  Future<String> getDisplayNameForFriend(String friendId, String defaultName) async {
    final nickname = await getNickname(friendId);
    return nickname ?? defaultName;
  }

  /// Set or update a nickname
  Future<bool> setNickname(String friendId, String nickname) async {
    try {
      final currentUserId = _supabase.auth.currentUser?.id;
      if (currentUserId == null) return false;

      await _supabase.from('friend_nicknames').upsert({
        'user_id': currentUserId,
        'friend_id': friendId,
        'nickname': nickname,
        'updated_at': DateTime.now().toUtc().toIso8601String(),
      }, onConflict: 'user_id, friend_id');

      // Update cache
      _nicknameCache?[friendId] = nickname;

      if (kDebugMode) print('✅ Nickname set for $friendId: $nickname');
      return true;
    } catch (e) {
      if (kDebugMode) print('❌ Error setting nickname: $e');
      return false;
    }
  }

  /// Remove a nickname
  Future<bool> removeNickname(String friendId) async {
    try {
      final currentUserId = _supabase.auth.currentUser?.id;
      if (currentUserId == null) return false;

      await _supabase
          .from('friend_nicknames')
          .delete()
          .eq('user_id', currentUserId)
          .eq('friend_id', friendId);

      // Update cache
      _nicknameCache?.remove(friendId);

      if (kDebugMode) print('✅ Nickname removed for $friendId');
      return true;
    } catch (e) {
      if (kDebugMode) print('❌ Error removing nickname: $e');
      return false;
    }
  }

  /// Clear the cache (call when user logs out)
  void clearCache() {
    _nicknameCache = null;
    _cacheTime = null;
  }

  /// Force refresh the cache
  Future<void> refreshCache() async {
    await getAllNicknames(forceRefresh: true);
  }
}

// Global instance for easy access
final nicknameService = NicknameService();