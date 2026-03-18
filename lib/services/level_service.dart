import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class LevelService {
  static final LevelService _instance = LevelService._internal();
  factory LevelService() => _instance;
  LevelService._internal();

  final SupabaseClient _supabase = Supabase.instance.client;

  // ============================================================
  // XP AWARD AMOUNTS
  // ============================================================
  static const int xpDailyCheckIn      = 20;
  static const int xpCoOpBonus         = 15;
  static const int xpMilestone7Days    = 75;
  static const int xpMilestone30Days   = 150;
  static const int xpMilestone100Days  = 300;
  static const int xpFirstBuddy        = 50;

  // ============================================================
  // LEVEL THRESHOLDS
  // Total XP required to REACH each level (index = level number)
  // Level 1 = 0 XP (starting level)
  // ============================================================
  static const List<int> _levelThresholds = [
    0,     // Level 1  — start
    100,   // Level 2  — ~5 days
    250,   // Level 3  — ~12 days
    450,   // Level 4  — ~22 days
    700,   // Level 5  — ~35 days
    1000,  // Level 6  — ~50 days
    1350,  // Level 7  — ~67 days
    1750,  // Level 8  — ~87 days
    2200,  // Level 9  — ~110 days
    2700,  // Level 10 — ~135 days
  ];

  static const int maxLevel = 10;

  // ============================================================
  // LEVEL CALCULATION HELPERS
  // ============================================================

  /// Returns the level (1–10) for a given total XP amount
  static int levelFromXP(int xp) {
    int level = 1;
    for (int i = _levelThresholds.length - 1; i >= 0; i--) {
      if (xp >= _levelThresholds[i]) {
        level = i + 1;
        break;
      }
    }
    return level.clamp(1, maxLevel);
  }

  /// Total XP needed to reach [level]
  static int xpRequiredForLevel(int level) {
    final index = (level - 1).clamp(0, _levelThresholds.length - 1);
    return _levelThresholds[index];
  }

  /// XP needed to reach the NEXT level from current [level]
  static int xpToNextLevel(int currentLevel) {
    if (currentLevel >= maxLevel) return 0;
    return _levelThresholds[currentLevel] - _levelThresholds[currentLevel - 1];
  }

  /// XP earned within the current level (progress bar numerator)
  static int xpProgressInLevel(int totalXP, int currentLevel) {
    final levelStart = xpRequiredForLevel(currentLevel);
    return (totalXP - levelStart).clamp(0, xpToNextLevel(currentLevel));
  }

  /// Progress 0.0–1.0 for the current level's XP bar
  static double levelProgress(int totalXP, int currentLevel) {
    if (currentLevel >= maxLevel) return 1.0;
    final progress = xpProgressInLevel(totalXP, currentLevel);
    final needed = xpToNextLevel(currentLevel);
    if (needed == 0) return 1.0;
    return (progress / needed).clamp(0.0, 1.0);
  }

  // ============================================================
  // GET CURRENT PLAYER LEVEL DATA
  // ============================================================
  Future<PlayerLevelData?> getPlayerLevel() async {
    try {
      final userId = _supabase.auth.currentUser?.id;
      if (userId == null) return null;

      final result = await _supabase
          .from('user_profiles')
          .select('xp, level')
          .eq('id', userId)
          .single();

      final xp    = result['xp'] as int? ?? 0;
      final level = result['level'] as int? ?? 1;

      return PlayerLevelData(
        totalXP:       xp,
        level:         level,
        progress:      levelProgress(xp, level),
        xpInLevel:     xpProgressInLevel(xp, level),
        xpNeeded:      xpToNextLevel(level),
        isMaxLevel:    level >= maxLevel,
      );
    } catch (e) {
      if (kDebugMode) print('❌ LevelService.getPlayerLevel error: $e');
      return null;
    }
  }

  // ============================================================
  // AWARD XP
  // Returns a LevelUpResult if the player leveled up, null otherwise
  // ============================================================
  Future<LevelUpResult?> awardXP({
    required int amount,
    required String transactionType,
    required String description,
    String? referenceId,
  }) async {
    try {
      final userId = _supabase.auth.currentUser?.id;
      if (userId == null) return null;

      // Fetch current xp + level
      final current = await _supabase
          .from('user_profiles')
          .select('xp, level')
          .eq('id', userId)
          .single();

      final currentXP    = current['xp'] as int? ?? 0;
      final currentLevel = current['level'] as int? ?? 1;
      final newXP        = currentXP + amount;
      final newLevel     = levelFromXP(newXP).clamp(1, maxLevel);
      final didLevelUp   = newLevel > currentLevel;

      // Update user_profiles
      await _supabase.from('user_profiles').update({
        'xp':    newXP,
        'level': newLevel,
      }).eq('id', userId);

      // Log xp_transaction
      await _supabase.from('xp_transactions').insert({
        'user_id':          userId,
        'amount':           amount,
        'transaction_type': transactionType,
        'description':      description,
        'reference_id':     referenceId,
      });

      if (kDebugMode) {
        print('⭐ Awarded $amount XP ($transactionType) → Total: $newXP | Level: $newLevel');
        if (didLevelUp) print('🎉 LEVEL UP! $currentLevel → $newLevel');
      }

      if (didLevelUp) {
        // Fetch items that just became unlocked at the new level
        final unlockedItems = await _getNewlyUnlockedItems(newLevel);
        return LevelUpResult(
          previousLevel:  currentLevel,
          newLevel:       newLevel,
          totalXP:        newXP,
          unlockedItems:  unlockedItems,
        );
      }

      return null;
    } catch (e) {
      if (kDebugMode) print('❌ LevelService.awardXP error: $e');
      return null;
    }
  }

  // ============================================================
  // AWARD XP FOR DAILY CHECK-IN
  // Call this alongside CoinService.awardDailyCheckIn
  // ============================================================
  Future<LevelUpResult?> awardCheckInXP({
    required String streakId,
    required int currentStreak,
    required bool partnerAlsoCheckedIn,
  }) async {
    int total = xpDailyCheckIn;
    String description = 'Daily check-in ⭐';

    if (partnerAlsoCheckedIn) {
      total += xpCoOpBonus;
      description = 'Daily check-in + co-op bonus ⭐🤝';
    }

    // Milestone XP bonuses
    if (currentStreak == 7) {
      total += xpMilestone7Days;
      description = '7-day milestone! 🔥';
    } else if (currentStreak == 30) {
      total += xpMilestone30Days;
      description = '30-day milestone! 💪';
    } else if (currentStreak == 100) {
      total += xpMilestone100Days;
      description = '100-day milestone! 🏆';
    }

    return awardXP(
      amount:          total,
      transactionType: 'daily_checkin',
      description:     description,
      referenceId:     streakId,
    );
  }

  // ============================================================
  // PRIVATE: FETCH NEWLY UNLOCKED ITEMS AT A GIVEN LEVEL
  // ============================================================
  Future<List<UnlockedItem>> _getNewlyUnlockedItems(int level) async {
    try {
      final items = await _supabase
          .from('shop_items')
          .select('id, name, category, emoji, unlock_level')
          .eq('unlock_level', level)
          .eq('is_available', true);

      return items.map<UnlockedItem>((item) => UnlockedItem(
        id:       item['id'] as String,
        name:     item['name'] as String,
        category: item['category'] as String,
        emoji:    item['emoji'] as String? ?? '⭐',
      )).toList();
    } catch (e) {
      if (kDebugMode) print('❌ Error fetching unlocked items: $e');
      return [];
    }
  }
}

// ============================================================
// DATA MODELS
// ============================================================

class PlayerLevelData {
  final int totalXP;
  final int level;
  final double progress; // 0.0–1.0 for XP bar
  final int xpInLevel;   // XP earned within current level
  final int xpNeeded;    // XP needed to complete current level
  final bool isMaxLevel;

  const PlayerLevelData({
    required this.totalXP,
    required this.level,
    required this.progress,
    required this.xpInLevel,
    required this.xpNeeded,
    required this.isMaxLevel,
  });
}

class LevelUpResult {
  final int previousLevel;
  final int newLevel;
  final int totalXP;
  final List<UnlockedItem> unlockedItems;

  const LevelUpResult({
    required this.previousLevel,
    required this.newLevel,
    required this.totalXP,
    required this.unlockedItems,
  });
}

class UnlockedItem {
  final String id;
  final String name;
  final String category;
  final String emoji;

  const UnlockedItem({
    required this.id,
    required this.name,
    required this.category,
    required this.emoji,
  });
}