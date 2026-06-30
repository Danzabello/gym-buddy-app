import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:gym_buddy_app/utils/debug_logger.dart';

// ══════════════════════════════════════════════════════════════
// MODELS
// ══════════════════════════════════════════════════════════════

class Achievement {
  final String id;
  final String name;
  final String description;
  final String category;
  final String icon;
  final String rarity;
  final int xpReward;
  final int coinReward;
  final int targetValue;
  final int sortOrder;

  final int? progress;
  final DateTime? unlockedAt;

  const Achievement({
    required this.id,
    required this.name,
    required this.description,
    required this.category,
    required this.icon,
    required this.rarity,
    required this.xpReward,
    required this.coinReward,
    required this.targetValue,
    required this.sortOrder,
    this.progress,
    this.unlockedAt,
  });

  bool get isUnlocked => unlockedAt != null;
  bool get hasProgress => progress != null && progress! > 0;
  double get progressPercent =>
      targetValue <= 1 ? (isUnlocked ? 1.0 : 0.0)
      : ((progress ?? 0) / targetValue).clamp(0.0, 1.0);

  factory Achievement.fromRow(Map<String, dynamic> def, Map<String, dynamic>? userRow) {
    return Achievement(
      id:          def['id'] as String,
      name:        def['name'] as String,
      description: def['description'] as String,
      category:    def['category'] as String,
      icon:        def['icon'] as String,
      rarity:      def['rarity'] as String,
      xpReward:    def['xp_reward'] as int,
      coinReward:  def['coin_reward'] as int,
      targetValue: def['target_value'] as int,
      sortOrder:   def['sort_order'] as int,
      progress:    userRow?['progress'] as int?,
      unlockedAt:  userRow?['unlocked_at'] != null
                     ? DateTime.parse(userRow!['unlocked_at'] as String)
                     : null,
    );
  }
}

class AchievementUnlockResult {
  final Achievement achievement;
  final int xpAwarded;
  final int coinsAwarded;
  AchievementUnlockResult({
    required this.achievement,
    required this.xpAwarded,
    required this.coinsAwarded,
  });
}

// ══════════════════════════════════════════════════════════════
// SERVICE
// ══════════════════════════════════════════════════════════════

class AchievementService {
  static final AchievementService _instance = AchievementService._internal();
  factory AchievementService() => _instance;
  AchievementService._internal();

  final SupabaseClient _supabase = Supabase.instance.client;

  String? get _userId => _supabase.auth.currentUser?.id;

  // ── FETCH ALL ────────────────────────────────────────────────
  Future<List<Achievement>> getAll() async {
    try {
      final uid = _userId;
      if (uid == null) return [];

      final results = await Future.wait([
        _supabase.from('achievements').select().order('sort_order'),
        _supabase.from('user_achievements').select().eq('user_id', uid),
      ]);

      final defs     = results[0] as List<dynamic>;
      final userRows = results[1] as List<dynamic>;

      final userMap = {
        for (final r in userRows)
          (r as Map<String, dynamic>)['achievement_id'] as String: r,
      };

      return defs
          .map((d) => Achievement.fromRow(
                d as Map<String, dynamic>,
                userMap[d['id'] as String],
              ))
          .toList();
    } catch (e) {
      if (kDebugMode) debugLog('❌ AchievementService.getAll: $e');
      return [];
    }
  }

  // ── UPSERT PROGRESS + UNLOCK IF MET ─────────────────────────
  Future<AchievementUnlockResult?> _upsertProgress(
    String achievementId,
    int newProgress,
  ) async {
    try {
      final uid = _userId;
      if (uid == null) return null;

      final def = await _supabase
          .from('achievements')
          .select()
          .eq('id', achievementId)
          .maybeSingle();
      if (def == null) return null;

      final target = def['target_value'] as int;

      final existing = await _supabase
          .from('user_achievements')
          .select()
          .eq('user_id', uid)
          .eq('achievement_id', achievementId)
          .maybeSingle();

      if (existing != null && existing['unlocked_at'] != null) return null;

      final clamped   = newProgress.clamp(0, target);
      final didUnlock = clamped >= target;

      await _supabase.from('user_achievements').upsert({
        'user_id':        uid,
        'achievement_id': achievementId,
        'progress':       clamped,
        if (didUnlock) 'unlocked_at': DateTime.now().toIso8601String(),
      }, onConflict: 'user_id,achievement_id');

      if (!didUnlock) return null;

      final xp    = def['xp_reward'] as int;
      final coins = def['coin_reward'] as int;

      // Server looks up the correct xp_reward/coin_reward itself and
      // pays out atomically — replaces the manual ledger writes + direct
      // coin_balance update (S2 audit fix: client could previously pass
      // any amount, not just the real reward value).
      try {
        await _supabase.rpc('award_achievement_rewards', params: {
          'p_achievement_id': achievementId,
        });
      } catch (e) {
        debugLog('❌ Error awarding achievement rewards ($achievementId): $e');
      }

      if (kDebugMode) debugLog('🏆 Unlocked: ${def['name']} (+$xp XP, +$coins coins)');

      return AchievementUnlockResult(
        achievement: Achievement.fromRow(def, {
          'progress':    clamped,
          'unlocked_at': DateTime.now().toIso8601String(),
        }),
        xpAwarded:    xp,
        coinsAwarded: coins,
      );
    } catch (e) {
      if (kDebugMode) debugLog('❌ AchievementService._upsertProgress ($achievementId): $e');
      return null;
    }
  }

  // ── SERVER-VERIFIED UNLOCK ──────────────────────────────────────
  // Calls verify_achievement_progress, which independently re-derives
  // real progress from the actual underlying tables server-side — the
  // client never supplies a progress number for these IDs. Closes the
  // same vulnerability class as the old S2 coin/XP bug, but for
  // achievements (found live: a past streak-data corruption bug
  // permanently unlocked 10 achievements with target values the real
  // data never met).
  Future<AchievementUnlockResult?> _verifyAndUnlock(String achievementId) async {
    try {
      final result = await _supabase.rpc('verify_achievement_progress', params: {
        'p_achievement_id': achievementId,
      }) as Map<String, dynamic>?;

      if (result == null || result['unlocked'] != true) return null;

      final def = await _supabase
          .from('achievements')
          .select()
          .eq('id', achievementId)
          .maybeSingle();
      if (def == null) return null;

      return AchievementUnlockResult(
        achievement: Achievement.fromRow(def, {
          'progress': def['target_value'],
          'unlocked_at': DateTime.now().toIso8601String(),
        }),
        xpAwarded: result['xp_awarded'] as int? ?? 0,
        coinsAwarded: result['coins_awarded'] as int? ?? 0,
      );
    } catch (e) {
      if (kDebugMode) debugLog('❌ verify_achievement_progress ($achievementId): $e');
      return null;
    }
  }

  // ══════════════════════════════════════════════════════════════
  // PUBLIC CHECK METHODS
  // ══════════════════════════════════════════════════════════════

  Future<List<AchievementUnlockResult>> checkStreakAchievements({
    required int currentStreak,
    required int bestStreak,
    required int previousBest,
    required bool isRealBuddy,
    required String teamStreakId,
  }) async {
    final results = <AchievementUnlockResult>[];

    // Server-verified — re-derives real best_streak from team_streaks
    // itself rather than trusting currentStreak/bestStreak params.
    for (final id in [
      'first_flame',
      'week_warrior',
      'two_weeks_strong',
      'month_machine',
      'unstoppable',
      'century_club',
      'half_year_hero',
      'year_of_the_beast',
      'personal_best',
    ]) {
      final r = await _verifyAndUnlock(id);
      if (r != null) results.add(r);
    }

    if (!isRealBuddy) {
      final r = await _verifyAndUnlock('coach_max_grad');
      if (r != null) results.add(r);
    }

    return results;
  }

  Future<List<AchievementUnlockResult>> checkCoopAchievements({
    required String teamStreakId,
    required DateTime myCheckInTime,
    required DateTime partnerCheckInTime,
  }) async {
    final results = <AchievementUnlockResult>[];
    // Fully server-verified — re-derives mutual check-in days, timing
    // overlap, and time-of-day directly from daily_team_checkins.
    // Note: early_bird/night_owl now use UTC server-side rather than
    // phone-local time (the server has no concept of the caller's
    // timezone) — a deliberate, documented simplification for a
    // low-stakes flavor achievement. Params kept for call-site
    // compatibility, no longer used here.
    for (final id in [
      'dynamic_duo',
      'in_sync',
      'reliable_partner',
      'ride_or_die',
      'power_couple',
      'early_bird',
      'night_owl',
    ]) {
      final r = await _verifyAndUnlock(id);
      if (r != null) results.add(r);
    }
    return results;
  }

  Future<List<AchievementUnlockResult>> checkWorkoutAchievements({
    required int durationMinutes,
    required String workoutType,
  }) async {
    final results = <AchievementUnlockResult>[];
    final uid = _userId;
    if (uid == null) return results;

    // Fully server-verified — re-derives workout count, duration,
    // distinct types, and consecutive days from the workouts table
    // itself. durationMinutes/workoutType params kept for signature
    // compatibility, no longer used for the unlock decision.
    for (final id in [
      'first_rep',
      'warm_up_done',
      'ten_strong',
      'fifty_club',
      'century_lifter',
      'marathon',
      'mixed_bag',
      'iron_will',
    ]) {
      final r = await _verifyAndUnlock(id);
      if (r != null) results.add(r);
    }

    return results;
  }

  Future<List<AchievementUnlockResult>> checkSocialAchievements() async {
    final results = <AchievementUnlockResult>[];
    // Server-verified — re-derives friend count from friendships itself.
    for (final id in ['first_friend', 'squad_goals', 'social_butterfly', 'influencer']) {
      final r = await _verifyAndUnlock(id);
      if (r != null) results.add(r);
    }
    return results;
  }

  Future<List<AchievementUnlockResult>> checkConnectorAchievement() async {
    final r = await _verifyAndUnlock('connector');
    return r != null ? [r] : [];
  }

  Future<List<AchievementUnlockResult>> checkFeelingLucky() async {
    final r = await _upsertProgress('feeling_lucky', 1);
    return r != null ? [r] : [];
  }

  Future<List<AchievementUnlockResult>> checkLevelAchievements(int newLevel) async {
    final results = <AchievementUnlockResult>[];
    // Server-verified — re-reads level from user_profiles directly
    // (already server-authoritative since tonight's S2 fix). newLevel
    // param kept for call-site compatibility, no longer used here.
    for (final id in ['level_5', 'level_10', 'level_25', 'level_50', 'level_99']) {
      final r = await _verifyAndUnlock(id);
      if (r != null) results.add(r);
    }
    return results;
  }

  Future<List<AchievementUnlockResult>> checkCoinAchievements() async {
    final results = <AchievementUnlockResult>[];
    // Server-verified — sums all positive coin_transactions directly
    // (also fixes SB-7's 'earn'-only filter bug, which previously
    // missed daily_checkin/partner_bonus/achievement-type earnings).
    for (final id in ['coin_collector', 'rich_in_spirit', 'loaded']) {
      final r = await _verifyAndUnlock(id);
      if (r != null) results.add(r);
    }
    return results;
  }

  Future<List<AchievementUnlockResult>> checkPrestigeAchievements() async {
    final results = <AchievementUnlockResult>[];
    // Server-verified — counts user_inventory directly.
    for (final id in ['collector', 'hoarder', 'full_wardrobe']) {
      final r = await _verifyAndUnlock(id);
      if (r != null) results.add(r);
    }
    return results;
  }

  Future<List<AchievementUnlockResult>> checkLoyaltyAchievements() async {
    final results = <AchievementUnlockResult>[];
    final uid = _userId;
    if (uid == null) return results;

    // Server-verified — re-derives account age from
    // user_profiles.created_at directly.
    for (final id in ['day_one', 'veteran', 'og_member']) {
      final r = await _verifyAndUnlock(id);
      if (r != null) results.add(r);
    }
    return results;
  }

  // ══════════════════════════════════════════════════════════════
  // PRIVATE HELPERS
  // ══════════════════════════════════════════════════════════════

  Future<int> _getTotalWorkouts() async {
    try {
      final uid = _userId;
      if (uid == null) return 0;
      final res = await _supabase
          .from('workouts')
          .select('id')
          .eq('user_id', uid)
          .eq('status', 'completed');
      return (res as List).length;
    } catch (_) { return 0; }
  }

  Future<int> _getDistinctWorkoutTypes() async {
    try {
      final uid = _userId;
      if (uid == null) return 0;
      final res = await _supabase
          .from('workouts')
          .select('workout_type')
          .eq('user_id', uid)
          .eq('status', 'completed');
      final types = (res as List).map((r) => r['workout_type']).toSet();
      return types.length;
    } catch (_) { return 0; }
  }

  Future<int> _getConsecutiveWorkoutDays() async {
    try {
      final uid = _userId;
      if (uid == null) return 0;
      final res = await _supabase
          .from('workouts')
          .select('completed_at')
          .eq('user_id', uid)
          .eq('status', 'completed')
          .order('completed_at', ascending: false);

      final dates = (res as List)
          .map((r) {
            final raw = r['completed_at'] ?? r['updated_at'];
            if (raw == null) return null;
            final d = DateTime.parse(raw as String);
            return DateTime(d.year, d.month, d.day);
          })
          .whereType<DateTime>()
          .toSet()
          .toList()
        ..sort((a, b) => b.compareTo(a));

      if (dates.isEmpty) return 0;
      int streak = 1;
      for (int i = 1; i < dates.length; i++) {
        if (dates[i - 1].difference(dates[i]).inDays == 1) {
          streak++;
        } else {
          break;
        }
      }
      return streak;
    } catch (_) { return 0; }
  }

  // ── FIX: use user_id / friend_id columns (not requester/addressee) ──
  Future<int> _getFriendCount() async {
    try {
      final uid = _userId;
      if (uid == null) return 0;
      final res = await _supabase
          .from('friendships')
          .select('id')
          .eq('status', 'accepted')
          .or('user_id.eq.$uid,friend_id.eq.$uid');
      return (res as List).length;
    } catch (_) { return 0; }
  }

  Future<int> _getSentRequestCount() async {
    try {
      final uid = _userId;
      if (uid == null) return 0;
      final res = await _supabase
          .from('friendships')
          .select('id')
          .eq('user_id', uid);
      return (res as List).length;
    } catch (_) { return 0; }
  }

  Future<int> _getMutualCoopCount(String teamStreakId) async {
    try {
      final res = await _supabase
          .from('daily_team_checkins')
          .select('check_in_date')
          .eq('team_streak_id', teamStreakId);

      final dateCounts = <String, int>{};
      for (final r in res as List) {
        final d = r['check_in_date'] as String;
        dateCounts[d] = (dateCounts[d] ?? 0) + 1;
      }
      return dateCounts.values.where((c) => c >= 2).length;
    } catch (_) { return 0; }
  }

  Future<int> _getCoachMaxCheckinCount() async {
    try {
      final uid = _userId;
      if (uid == null) return 0;
      final teamRows = await _supabase
          .from('team_members')
          .select('team_id, buddy_teams!inner(is_coach_max_team)')
          .eq('user_id', uid)
          .eq('buddy_teams.is_coach_max_team', true);
      if ((teamRows as List).isEmpty) return 0;
      final teamIds = teamRows.map((t) => t['team_id'] as String).toList();
      final streakRows = await _supabase
          .from('team_streaks')
          .select('id')
          .inFilter('team_id', teamIds);
      final streakIds = (streakRows as List).map((s) => s['id'] as String).toList();
      if (streakIds.isEmpty) return 0;
      final res = await _supabase
          .from('daily_team_checkins')
          .select('id')
          .eq('user_id', uid)
          .inFilter('team_streak_id', streakIds);
      return (res as List).length;
    } catch (_) { return 0; }
  }

  Future<int> _getLifetimeCoins() async {
    try {
      final uid = _userId;
      if (uid == null) return 0;
      final res = await _supabase
          .from('coin_transactions')
          .select('amount')
          .eq('user_id', uid)
          .eq('transaction_type', 'earn'); // ── FIX: was 'type'
      return (res as List).fold<int>(0, (sum, r) => sum + (r['amount'] as int));
    } catch (_) { return 0; }
  }

  Future<int> _getCosmeticCount() async {
    try {
      final uid = _userId;
      if (uid == null) return 0;
      final res = await _supabase
          .from('user_inventory')
          .select('id')
          .eq('user_id', uid);
      return (res as List).length;
    } catch (_) { return 0; }
  }
}