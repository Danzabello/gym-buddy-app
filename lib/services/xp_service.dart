import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

// ============================================================
// XP AWARD RESULT
// ============================================================
class XpAwardResult {
  final int xpAwarded;
  final int totalXp;
  final int oldLevel;
  final int newLevel;
  final bool didLevelUp;
  final String? newTitle;       // e.g. "Warrior" — only set on level-up
  final List<String> reasons;

  XpAwardResult({
    required this.xpAwarded,
    required this.totalXp,
    required this.oldLevel,
    required this.newLevel,
    required this.didLevelUp,
    this.newTitle,
    required this.reasons,
  });
}

// ============================================================
// LEVEL INFO
// ============================================================
class LevelInfo {
  final int level;
  final String title;
  final int xpForThisLevel;     // XP required to reach this level
  final int xpForNextLevel;     // XP required to reach NEXT level (0 if max)
  final int currentXp;          // User's total XP
  final int xpIntoCurrentLevel; // XP earned since hitting this level
  final int xpNeededForNext;    // XP still needed for next level
  final double progressPercent; // 0.0 → 1.0 for progress bar

  LevelInfo({
    required this.level,
    required this.title,
    required this.xpForThisLevel,
    required this.xpForNextLevel,
    required this.currentXp,
    required this.xpIntoCurrentLevel,
    required this.xpNeededForNext,
    required this.progressPercent,
  });
}

// ============================================================
// XP SERVICE
// ============================================================
class XpService {
  static final XpService _instance = XpService._internal();
  factory XpService() => _instance;
  XpService._internal();

  final SupabaseClient _supabase = Supabase.instance.client;

  // ============================================================
  // XP AMOUNTS
  // ============================================================
  static const int dailyCheckIn = 10;
  static const int completedWorkout = 15;
  static const int coopSession = 20;
  static const int milestone7Days = 50;
  static const int milestone30Days = 50;
  static const int milestone100Days = 50;

  // ============================================================
  // GET CURRENT XP + LEVEL
  // ============================================================
  Future<Map<String, int>> getXpAndLevel() async {
    try {
      final userId = _supabase.auth.currentUser?.id;
      if (userId == null) return {'xp': 0, 'level': 1};

      final result = await _supabase
          .from('user_profiles')
          .select('xp, level')
          .eq('id', userId)
          .single();

      return {
        'xp': result['xp'] as int? ?? 0,
        'level': result['level'] as int? ?? 1,
      };
    } catch (e) {
      if (kDebugMode) print('❌ Error getting XP/level: $e');
      return {'xp': 0, 'level': 1};
    }
  }

  // ============================================================
  // GET FULL LEVEL INFO (for profile/progress bar UI)
  // ============================================================
  Future<LevelInfo?> getLevelInfo() async {
    try {
      final userId = _supabase.auth.currentUser?.id;
      if (userId == null) return null;

      final profileResult = await _supabase
          .from('user_profiles')
          .select('xp, level')
          .eq('id', userId)
          .single();

      final currentXp = profileResult['xp'] as int? ?? 0;
      final currentLevel = profileResult['level'] as int? ?? 1;

      // Get current level definition
      final currentDef = await _supabase
          .from('level_definitions')
          .select('xp_required, title')
          .eq('level', currentLevel)
          .single();

      // Get next level definition (null if level 99)
      final nextDef = currentLevel < 99
          ? await _supabase
              .from('level_definitions')
              .select('xp_required')
              .eq('level', currentLevel + 1)
              .maybeSingle()
          : null;

      final xpForThisLevel = currentDef['xp_required'] as int;
      final xpForNextLevel = nextDef?['xp_required'] as int? ?? 0;
      final xpIntoCurrentLevel = currentXp - xpForThisLevel;
      final xpRangeForLevel = xpForNextLevel > 0
          ? xpForNextLevel - xpForThisLevel
          : 1;
      final progressPercent = currentLevel >= 99
          ? 1.0
          : (xpIntoCurrentLevel / xpRangeForLevel).clamp(0.0, 1.0);

      return LevelInfo(
        level: currentLevel,
        title: currentDef['title'] as String,
        xpForThisLevel: xpForThisLevel,
        xpForNextLevel: xpForNextLevel,
        currentXp: currentXp,
        xpIntoCurrentLevel: xpIntoCurrentLevel,
        xpNeededForNext: currentLevel >= 99
            ? 0
            : (xpForNextLevel - currentXp).clamp(0, 999999),
        progressPercent: progressPercent,
      );
    } catch (e) {
      if (kDebugMode) print('❌ Error getting level info: $e');
      return null;
    }
  }

  // ============================================================
  // CORE AWARD XP
  // ============================================================
  Future<XpAwardResult?> _awardXp({
    required int amount,
    required String reason,
  }) async {
    try {
      final userId = _supabase.auth.currentUser?.id;
      if (userId == null) return null;

      // Get current state
      final current = await getXpAndLevel();
      final currentXp = current['xp']!;
      final oldLevel = current['level']!;
      final newXp = currentXp + amount;

      // Calculate new level using DB function
      final levelResult = await _supabase
          .rpc('get_level_for_xp', params: {'total_xp': newXp});
      final newLevel = (levelResult as int?)?.clamp(1, 99) ?? oldLevel;

      // Update user_profiles
      await _supabase.from('user_profiles').update({
        'xp': newXp,
        'level': newLevel,
      }).eq('id', userId);

      // Log transaction
      await _supabase.from('xp_transactions').insert({
        'user_id': userId,
        'amount': amount,
        'reason': reason,
      });

      final didLevelUp = newLevel > oldLevel;
      String? newTitle;

      if (didLevelUp) {
        // Fetch title for new level
        final titleResult = await _supabase
            .from('level_definitions')
            .select('title')
            .eq('level', newLevel)
            .maybeSingle();
        newTitle = titleResult?['title'] as String?;

        if (kDebugMode) {
          print('🎉 LEVEL UP! $oldLevel → $newLevel ($newTitle)');
        }

        // Trigger cosmetic unlocks for new level
        await _checkAndGrantLevelUnlocks(userId: userId, newLevel: newLevel);
      }

      if (kDebugMode) {
        print('⭐ Awarded $amount XP ($reason) → Total: $newXp | Level: $newLevel');
      }

      return XpAwardResult(
        xpAwarded: amount,
        totalXp: newXp,
        oldLevel: oldLevel,
        newLevel: newLevel,
        didLevelUp: didLevelUp,
        newTitle: newTitle,
        reasons: ['+$amount XP ($reason)'],
      );
    } catch (e) {
      if (kDebugMode) print('❌ Error awarding XP: $e');
      return null;
    }
  }

  // ============================================================
  // AWARD DAILY CHECK-IN XP
  // ============================================================
  Future<XpAwardResult?> awardDailyCheckIn({
    required String streakId,
    required int currentStreak,
  }) async {
    try {
      final userId = _supabase.auth.currentUser?.id;
      if (userId == null) return null;

      final today = DateTime.now().toIso8601String().split('T')[0];

      // Deduplication: only award once per day per streak
      final existing = await _supabase
          .from('xp_transactions')
          .select('id')
          .eq('user_id', userId)
          .eq('reason', 'daily_checkin_$streakId')
          .gte('created_at', '${today}T00:00:00Z')
          .maybeSingle();

      if (existing != null) {
        if (kDebugMode) print('⏭️ XP already awarded today for streak $streakId');
        return null;
      }

      int totalXp = dailyCheckIn;
      List<String> reasons = ['+$dailyCheckIn daily check-in'];

      // Milestone bonuses
      if (currentStreak == 7) {
        totalXp += milestone7Days;
        reasons.add('+$milestone7Days 7-day milestone! 🔥');
      } else if (currentStreak == 30) {
        totalXp += milestone30Days;
        reasons.add('+$milestone30Days 30-day milestone! 💪');
      } else if (currentStreak == 100) {
        totalXp += milestone100Days;
        reasons.add('+$milestone100Days 100-day milestone! 🏆');
      }

      final result = await _awardXp(
        amount: totalXp,
        reason: 'daily_checkin_$streakId',
      );

      if (result != null) {
        result.reasons.clear();
        result.reasons.addAll(reasons);
      }

      return result;
    } catch (e) {
      if (kDebugMode) print('❌ Error awarding check-in XP: $e');
      return null;
    }
  }

  // ============================================================
  // AWARD WORKOUT COMPLETION XP
  // ============================================================
  Future<XpAwardResult?> awardWorkoutCompleted({
    required String workoutId,
    bool withBuddy = false,
  }) async {
    try {
      final userId = _supabase.auth.currentUser?.id;
      if (userId == null) return null;

      // Deduplication: only award once per workout
      final existing = await _supabase
          .from('xp_transactions')
          .select('id')
          .eq('user_id', userId)
          .eq('reason', 'workout_$workoutId')
          .maybeSingle();

      if (existing != null) {
        if (kDebugMode) print('⏭️ XP already awarded for workout $workoutId');
        return null;
      }

      int totalXp = completedWorkout;
      List<String> reasons = ['+$completedWorkout workout completed 🏋️'];

      if (withBuddy) {
        totalXp += coopSession;
        reasons.add('+$coopSession co-op session bonus 🤝');
      }

      final result = await _awardXp(
        amount: totalXp,
        reason: 'workout_$workoutId',
      );

      if (result != null) {
        result.reasons.clear();
        result.reasons.addAll(reasons);
      }

      return result;
    } catch (e) {
      if (kDebugMode) print('❌ Error awarding workout XP: $e');
      return null;
    }
  }

  // ============================================================
  // CHECK & GRANT LEVEL UNLOCK COSMETICS
  // ============================================================
  Future<void> _checkAndGrantLevelUnlocks({
    required String userId,
    required int newLevel,
  }) async {
    try {
      // Find all cosmetics that unlock at this level
      final unlockable = await _supabase
          .from('cosmetic_unlock_conditions')
          .select('shop_item_id')
          .eq('unlock_type', 'level')
          .eq('required_level', newLevel);

      if (unlockable.isEmpty) return;

      for (final row in unlockable) {
        final shopItemId = row['shop_item_id'] as String;

        // Check not already unlocked
        final alreadyUnlocked = await _supabase
            .from('user_unlocked_cosmetics')
            .select('id')
            .eq('user_id', userId)
            .eq('shop_item_id', shopItemId)
            .maybeSingle();

        if (alreadyUnlocked != null) continue;

        await _supabase.from('user_unlocked_cosmetics').insert({
          'user_id': userId,
          'shop_item_id': shopItemId,
          'unlock_reason': 'level_$newLevel',
        });

        if (kDebugMode) print('🎁 Unlocked cosmetic $shopItemId at level $newLevel');
      }
    } catch (e) {
      if (kDebugMode) print('❌ Error granting level unlocks: $e');
    }
  }

  // ============================================================
  // CHECK & GRANT MILESTONE UNLOCK COSMETICS
  // Called externally when a milestone is hit
  // ============================================================
  Future<void> grantMilestoneUnlock({
    required String milestoneKey, // e.g. 'streak_7', 'streak_30', 'workouts_10'
  }) async {
    try {
      final userId = _supabase.auth.currentUser?.id;
      if (userId == null) return;

      final unlockable = await _supabase
          .from('cosmetic_unlock_conditions')
          .select('shop_item_id')
          .eq('unlock_type', 'milestone')
          .eq('milestone_key', milestoneKey);

      if (unlockable.isEmpty) return;

      for (final row in unlockable) {
        final shopItemId = row['shop_item_id'] as String;

        final alreadyUnlocked = await _supabase
            .from('user_unlocked_cosmetics')
            .select('id')
            .eq('user_id', userId)
            .eq('shop_item_id', shopItemId)
            .maybeSingle();

        if (alreadyUnlocked != null) continue;

        await _supabase.from('user_unlocked_cosmetics').insert({
          'user_id': userId,
          'shop_item_id': shopItemId,
          'unlock_reason': 'milestone_$milestoneKey',
        });

        if (kDebugMode) print('🎁 Unlocked cosmetic $shopItemId via milestone $milestoneKey');
      }
    } catch (e) {
      if (kDebugMode) print('❌ Error granting milestone unlock: $e');
    }
  }

  // ============================================================
  // GET UNLOCKED COSMETICS FOR USER
  // ============================================================
  Future<List<String>> getUnlockedCosmeticIds() async {
    try {
      final userId = _supabase.auth.currentUser?.id;
      if (userId == null) return [];

      final result = await _supabase
          .from('user_unlocked_cosmetics')
          .select('shop_item_id')
          .eq('user_id', userId);

      return result.map<String>((r) => r['shop_item_id'] as String).toList();
    } catch (e) {
      if (kDebugMode) print('❌ Error getting unlocked cosmetics: $e');
      return [];
    }
  }
}