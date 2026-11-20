import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:gym_buddy_app/utils/debug_logger.dart';

// ============================================================
// LEVEL INFO
// Used by profile/progress bar UI
// ============================================================
class LevelInfo {
  final int level;
  final String title;
  final int currentXp;
  final int xpForThisLevel;
  final int xpForNextLevel;
  final int xpIntoCurrentLevel;
  final int xpNeededForNext;
  final double progressPercent; // 0.0 → 1.0

  LevelInfo({
    required this.level,
    required this.title,
    required this.currentXp,
    required this.xpForThisLevel,
    required this.xpForNextLevel,
    required this.xpIntoCurrentLevel,
    required this.xpNeededForNext,
    required this.progressPercent,
  });

  /// The saved copy's form (SavedCopy), read back by [fromSaved].
  Map<String, dynamic> toSaved() => {
        'level': level,
        'title': title,
        'current_xp': currentXp,
        'xp_for_this_level': xpForThisLevel,
        'xp_for_next_level': xpForNextLevel,
        'xp_into_current_level': xpIntoCurrentLevel,
        'xp_needed_for_next': xpNeededForNext,
        'progress_percent': progressPercent,
      };

  factory LevelInfo.fromSaved(Map<String, dynamic> m) => LevelInfo(
        level: m['level'] as int,
        title: m['title'] as String,
        currentXp: m['current_xp'] as int,
        xpForThisLevel: m['xp_for_this_level'] as int,
        xpForNextLevel: m['xp_for_next_level'] as int,
        xpIntoCurrentLevel: m['xp_into_current_level'] as int,
        xpNeededForNext: m['xp_needed_for_next'] as int,
        progressPercent: (m['progress_percent'] as num).toDouble(),
      );

  List<Object> get _fields => [
        level, title, currentXp, xpForThisLevel, xpForNextLevel,
        xpIntoCurrentLevel, xpNeededForNext, progressPercent,
      ];

  @override
  bool operator ==(Object other) {
    if (other is! LevelInfo) return false;
    final a = _fields, b = other._fields;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }

  @override
  int get hashCode => Object.hashAll(_fields);
}

// ============================================================
// LEVEL SERVICE
// ============================================================
class LevelService {
  static final LevelService _instance = LevelService._internal(Supabase.instance.client);
  // A test passes its own client; everyone else gets the one shared instance.
  factory LevelService({SupabaseClient? client}) =>
      client == null ? _instance : LevelService._internal(client);
  LevelService._internal(this._supabase);

  final SupabaseClient _supabase;

  /// [strict] rethrows a failed read instead of returning [], so a caller that
  /// saves the list can tell a failure from a real (empty) answer.
  Future<List<Map<String, dynamic>>> getUnlockedCosmetics({bool strict = false}) async {
    try {
      final userId = _supabase.auth.currentUser?.id;
      if (userId == null) return [];

      final rows = await _supabase
          .from('user_unlocked_cosmetics')
          .select('shop_item_id, unlock_reason, unlocked_at')
          .eq('user_id', userId);

      return List<Map<String, dynamic>>.from(rows);
    } catch (e) {
      if (kDebugMode) debugLog('❌ LevelService.getUnlockedCosmetics: $e');
      if (strict) rethrow;
      return [];
    }
  }

  // ============================================================
  // GET LEVEL INFO (for profile/progress bar UI)
  // ============================================================
  Future<LevelInfo?> getLevelInfo() async {
    try {
      final userId = _supabase.auth.currentUser?.id;
      if (userId == null) return null;

      final profile = await _supabase
          .rpc('get_my_profile')
          .select('xp, level')
          .single();

      final currentXp = profile['xp'] as int? ?? 1;
      final rawLevel = profile['level'] as int? ?? 1;
      final currentLevel = (rawLevel < 1 ? 1 : rawLevel).clamp(1, 99);
      if (kDebugMode) debugLog('🔍 DB profile: xp=${profile['xp']}, level=${profile['level']}, currentLevel=$currentLevel');


      final currentDef = await _supabase
          .from('level_definitions')
          .select('xp_required, title')
          .eq('level', currentLevel)
          .single();

      final nextDef = currentLevel < 99
          ? await _supabase
              .from('level_definitions')
              .select('xp_required')
              .eq('level', currentLevel + 1)
              .maybeSingle()
          : null;

      final xpForThisLevel = currentDef['xp_required'] as int;
      final xpForNextLevel = nextDef?['xp_required'] as int? ?? xpForThisLevel;
      if (kDebugMode) debugLog('🔍 xpForThisLevel=$xpForThisLevel, xpForNextLevel=$xpForNextLevel, currentXp=$currentXp');
      final xpRange = (xpForNextLevel - xpForThisLevel).clamp(1, 999999);
      final xpInto = (currentXp - xpForThisLevel).clamp(0, xpRange);

      return LevelInfo(
        level: currentLevel,
        title: currentDef['title'] as String,
        currentXp: currentXp,
        xpForThisLevel: xpForThisLevel,
        xpForNextLevel: xpForNextLevel,
        xpIntoCurrentLevel: xpInto,
        xpNeededForNext: currentLevel >= 99 ? 0 : (xpForNextLevel - currentXp).clamp(0, 999999),
        progressPercent: (xpInto / xpRange).clamp(0.0, 1.0),
      );
    } catch (e) {
      if (kDebugMode) debugLog('❌ Error getting level info: $e');
      return null;
    }
  }
}