import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

// ============================================================
// LEVEL UP RESULT
// Returned by awardCheckInXP so the UI can react to level-ups
// ============================================================
class LevelUpResult {
  final int xpAwarded;
  final int totalXp;
  final int oldLevel;
  final int newLevel;
  final bool didLevelUp;
  final String levelTitle;    // e.g. "Warrior", "Gym Pro"
  final List<String> reasons; // e.g. ["+10 XP daily check-in", "+50 XP 7-day milestone!"]

  LevelUpResult({
    required this.xpAwarded,
    required this.totalXp,
    required this.oldLevel,
    required this.newLevel,
    required this.didLevelUp,
    required this.levelTitle,
    required this.reasons,
  });
}

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
}

// ============================================================
// LEVEL SERVICE
// ============================================================
class LevelService {
  static final LevelService _instance = LevelService._internal();
  factory LevelService() => _instance;
  LevelService._internal();

  final SupabaseClient _supabase = Supabase.instance.client;

  // ============================================================
  // XP AMOUNTS
  // ============================================================
  static const int xpDailyCheckIn   = 10;
  static const int xpCoopBonus      = 5;   // extra when partner also checked in
  static const int xpMilestone7     = 50;
  static const int xpMilestone30    = 50;
  static const int xpMilestone100   = 50;
  static const int xpWorkout        = 15;

  // ============================================================
  // AWARD CHECK-IN XP
  // Called from team_streak_service.dart after streak update
  // ============================================================
  Future<LevelUpResult?> awardCheckInXP({
    required String streakId,
    required int currentStreak,
    required bool partnerAlsoCheckedIn,
  }) async {
    try {
      final userId = _supabase.auth.currentUser?.id;
      if (userId == null) return null;

      final today = DateTime.now().toIso8601String().split('T')[0];

      // Deduplication: only award once per streak per day
      final existing = await _supabase
          .from('xp_transactions')
          .select('id')
          .eq('user_id', userId)
          .eq('reference_id', 'checkin_$streakId')
          .gte('created_at', '${today}T00:00:00Z')
          .maybeSingle();

      if (existing != null) {
        if (kDebugMode) print('⏭️ XP already awarded today for streak $streakId');
        return null;
      }

      int totalXp = xpDailyCheckIn;
      final List<String> reasons = ['+$xpDailyCheckIn XP daily check-in 💪'];

      // Co-op bonus
      if (partnerAlsoCheckedIn) {
        totalXp += xpCoopBonus;
        reasons.add('+$xpCoopBonus XP partner bonus 🤝');
      }

      // Milestone bonuses
      if (currentStreak == 7) {
        totalXp += xpMilestone7;
        reasons.add('+$xpMilestone7 XP 7-day milestone! 🔥');
      } else if (currentStreak == 30) {
        totalXp += xpMilestone30;
        reasons.add('+$xpMilestone30 XP 30-day milestone! 💪');
      } else if (currentStreak == 100) {
        totalXp += xpMilestone100;
        reasons.add('+$xpMilestone100 XP 100-day milestone! 🏆');
      }

      return await _applyXp(
        userId: userId,
        amount: totalXp,
        reason: 'checkin_$streakId',
        reasons: reasons,
      );
    } catch (e) {
      if (kDebugMode) print('❌ Error awarding check-in XP: $e');
      return null;
    }
  }

  // ============================================================
  // AWARD WORKOUT XP
  // Call this from workout_history_service when a workout is logged
  // ============================================================
  Future<LevelUpResult?> awardWorkoutXP({required String workoutId}) async {
    try {
      final userId = _supabase.auth.currentUser?.id;
      if (userId == null) return null;

      // Deduplication: only award once per workout
      final existing = await _supabase
          .from('xp_transactions')
          .select('id')
          .eq('user_id', userId)
          .eq('reference_id', 'workout_$workoutId')
          .maybeSingle();

      if (existing != null) {
        if (kDebugMode) print('⏭️ XP already awarded for workout $workoutId');
        return null;
      }

      return await _applyXp(
        userId: userId,
        amount: xpWorkout,
        reason: 'workout_$workoutId',
        reasons: ['+$xpWorkout XP workout completed 🏋️'],
      );
    } catch (e) {
      if (kDebugMode) print('❌ Error awarding workout XP: $e');
      return null;
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
          .from('user_profiles')
          .select('xp, level')
          .eq('id', userId)
          .single();

      final currentXp = profile['xp'] as int? ?? 0;
      final currentLevel = (profile['level'] as int? ?? 1).clamp(1, 99);

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
      final xpRange = (xpForNextLevel - xpForThisLevel).clamp(1, 999999);
      final xpInto = (currentXp - xpForThisLevel).clamp(0, xpRange);
      final progress = currentLevel >= 99 ? 1.0 : xpInto / xpRange;

      return LevelInfo(
        level: currentLevel,
        title: currentDef['title'] as String,
        currentXp: currentXp,
        xpForThisLevel: xpForThisLevel,
        xpForNextLevel: xpForNextLevel,
        xpIntoCurrentLevel: xpInto,
        xpNeededForNext: currentLevel >= 99 ? 0 : (xpForNextLevel - currentXp).clamp(0, 999999),
        progressPercent: progress.clamp(0.0, 1.0),
      );
    } catch (e) {
      if (kDebugMode) print('❌ Error getting level info: $e');
      return null;
    }
  }

  // ============================================================
  // INTERNAL: APPLY XP + CHECK FOR LEVEL UP
  // ============================================================
  Future<LevelUpResult?> _applyXp({
    required String userId,
    required int amount,
    required String reason,
    required List<String> reasons,
  }) async {
    try {
      // Get current state
      final profile = await _supabase
          .from('user_profiles')
          .select('xp, level')
          .eq('id', userId)
          .single();

      final currentXp = profile['xp'] as int? ?? 0;
      final oldLevel = (profile['level'] as int? ?? 1).clamp(1, 99);
      final newXp = currentXp + amount;

      // Calculate new level via DB function
      final newLevelRaw = await _supabase
          .rpc('get_level_for_xp', params: {'total_xp': newXp});
      final newLevel = ((newLevelRaw as int?) ?? oldLevel).clamp(1, 99);

      // Update profile
      await _supabase.from('user_profiles').update({
        'xp': newXp,
        'level': newLevel,
      }).eq('id', userId);

      // Log transaction
      await _supabase.from('xp_transactions').insert({
        'user_id': userId,
        'amount': amount,
        'transaction_type': 'xp_award',
        'description': reason,
        'reference_id': reason,
      });

      final didLevelUp = newLevel > oldLevel;

      // Fetch title for new level
      final titleResult = await _supabase
          .from('level_definitions')
          .select('title')
          .eq('level', newLevel)
          .maybeSingle();
      final levelTitle = titleResult?['title'] as String? ?? 'Newcomer';

      if (didLevelUp) {
        if (kDebugMode) print('🎉 LEVEL UP! $oldLevel → $newLevel ($levelTitle)');
        await _grantLevelUnlocks(userId: userId, newLevel: newLevel);
      }

      if (kDebugMode) {
        print('⭐ +$amount XP ($reason) → Total: $newXp | Level: $newLevel');
      }

      return LevelUpResult(
        xpAwarded: amount,
        totalXp: newXp,
        oldLevel: oldLevel,
        newLevel: newLevel,
        didLevelUp: didLevelUp,
        levelTitle: levelTitle,
        reasons: reasons,
      );
    } catch (e) {
      if (kDebugMode) print('❌ Error applying XP: $e');
      return null;
    }
  }

  // ============================================================
  // GRANT COSMETIC UNLOCKS ON LEVEL UP
  // ============================================================
  Future<void> _grantLevelUnlocks({
    required String userId,
    required int newLevel,
  }) async {
    try {
      final unlockable = await _supabase
          .from('cosmetic_unlock_conditions')
          .select('shop_item_id')
          .eq('unlock_type', 'level')
          .eq('required_level', newLevel);

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
          'unlock_reason': 'level_$newLevel',
        });

        if (kDebugMode) print('🎁 Unlocked cosmetic $shopItemId at level $newLevel');
      }
    } catch (e) {
      if (kDebugMode) print('❌ Error granting level unlocks: $e');
    }
  }

  // ============================================================
  // GRANT MILESTONE UNLOCK
  // Call this when a milestone is hit (e.g. streak_7, streak_30)
  // ============================================================
  Future<void> grantMilestoneUnlock({required String milestoneKey}) async {
    try {
      final userId = _supabase.auth.currentUser?.id;
      if (userId == null) return;

      final unlockable = await _supabase
          .from('cosmetic_unlock_conditions')
          .select('shop_item_id')
          .eq('unlock_type', 'milestone')
          .eq('milestone_key', milestoneKey);

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
}