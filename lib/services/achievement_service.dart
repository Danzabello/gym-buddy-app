import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

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

  // User progress (null = not started)
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

  // ── FETCH ALL (definitions + user progress merged) ──────────
  Future<List<Achievement>> getAll() async {
    try {
      final uid = _userId;
      if (uid == null) return [];

      final results = await Future.wait([
        _supabase.from('achievements').select().order('sort_order'),
        _supabase.from('user_achievements').select().eq('user_id', uid),
      ]);

      final defs    = results[0] as List<dynamic>;
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
      if (kDebugMode) print('❌ AchievementService.getAll: $e');
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

      // Fetch definition
      final def = await _supabase
          .from('achievements')
          .select()
          .eq('id', achievementId)
          .maybeSingle();
      if (def == null) return null;

      final target = def['target_value'] as int;

      // Fetch existing user row
      final existing = await _supabase
          .from('user_achievements')
          .select()
          .eq('user_id', uid)
          .eq('achievement_id', achievementId)
          .maybeSingle();

      // Already unlocked — nothing to do
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

      // Award XP + coins
      final xp    = def['xp_reward'] as int;
      final coins = def['coin_reward'] as int;

      if (xp > 0) {
        await _supabase.from('xp_transactions').insert({
          'user_id':     uid,
          'amount':      xp,
          'reason':      'achievement_$achievementId',
          'reference_id':'achievement_$achievementId',
        });
        await _supabase.rpc('increment_user_xp', params: {'p_user_id': uid, 'p_xp': xp});
      }

      if (coins > 0) {
        await _supabase.from('coin_transactions').insert({
          'user_id':     uid,
          'amount':      coins,
          'type':        'earn',
          'description': 'Achievement: ${def['name']}',
          'reference_id':'achievement_$achievementId',
        });
        await _supabase.rpc('increment_user_coins', params: {'p_user_id': uid, 'p_amount': coins});
      }

      if (kDebugMode) print('🏆 Achievement unlocked: ${def['name']} (+$xp XP, +$coins coins)');

      return AchievementUnlockResult(
        achievement: Achievement.fromRow(def, {
          'progress':    clamped,
          'unlocked_at': DateTime.now().toIso8601String(),
        }),
        xpAwarded:    xp,
        coinsAwarded: coins,
      );
    } catch (e) {
      if (kDebugMode) print('❌ AchievementService._upsertProgress ($achievementId): $e');
      return null;
    }
  }

  // ══════════════════════════════════════════════════════════════
  // PUBLIC CHECK METHODS — call these from event sites
  // ══════════════════════════════════════════════════════════════

  // Call after every streak increment
  Future<List<AchievementUnlockResult>> checkStreakAchievements({
    required int currentStreak,
    required int bestStreak,
    required int previousBest,
    required bool isRealBuddy, // false = Coach Max
    required String teamStreakId,
  }) async {
    final results = <AchievementUnlockResult>[];

    // first_flame — any streak day
    final r1 = await _upsertProgress('first_flame', 1);
    if (r1 != null) results.add(r1);

    // streak milestones
    for (final entry in {
      'week_warrior':      7,
      'two_weeks_strong':  14,
      'month_machine':     30,
      'unstoppable':       60,
      'century_club':      100,
      'half_year_hero':    180,
      'year_of_the_beast': 365,
    }.entries) {
      final r = await _upsertProgress(entry.key, currentStreak >= entry.value ? entry.value : currentStreak);
      if (r != null) results.add(r);
    }

    // personal_best
    if (currentStreak > previousBest) {
      final r = await _upsertProgress('personal_best', 1);
      if (r != null) results.add(r);
    }

    // comeback_king — handled externally, pass progress=1 when applicable

    // Coach Max graduate
    if (!isRealBuddy) {
      final count = await _getCoachMaxCheckinCount();
      final r = await _upsertProgress('coach_max_grad', count);
      if (r != null) results.add(r);
    }

    return results;
  }

  // Call after every mutual co-op check-in (both users checked in)
  Future<List<AchievementUnlockResult>> checkCoopAchievements({
    required String teamStreakId,
    required DateTime myCheckInTime,
    required DateTime partnerCheckInTime,
  }) async {
    final results = <AchievementUnlockResult>[];

    // dynamic_duo — first coop day ever
    final r1 = await _upsertProgress('dynamic_duo', 1);
    if (r1 != null) results.add(r1);

    // in_sync — within 30 mins
    final diff = myCheckInTime.difference(partnerCheckInTime).inMinutes.abs();
    if (diff <= 30) {
      final r = await _upsertProgress('in_sync', 1);
      if (r != null) results.add(r);
    }

    // reliable_partner / ride_or_die / power_couple
    final coopCount = await _getMutualCoopCount(teamStreakId);
    for (final entry in {
      'reliable_partner': 7,
      'ride_or_die':      30,
      'power_couple':     100,
    }.entries) {
      final r = await _upsertProgress(entry.key, coopCount);
      if (r != null) results.add(r);
    }

    // early_bird / night_owl
    final hour = myCheckInTime.toLocal().hour;
    if (hour < 8) {
      final r = await _upsertProgress('early_bird', 1);
      if (r != null) results.add(r);
    }
    if (hour >= 22) {
      final r = await _upsertProgress('night_owl', 1);
      if (r != null) results.add(r);
    }

    return results;
  }

  // Call after every workout completion
  Future<List<AchievementUnlockResult>> checkWorkoutAchievements({
    required int durationMinutes,
    required String workoutType,
  }) async {
    final results = <AchievementUnlockResult>[];
    final uid = _userId;
    if (uid == null) return results;

    // first_rep / warm_up_done / ten_strong / fifty_club / century_lifter
    final total = await _getTotalWorkouts();
    for (final entry in {
      'first_rep':      1,
      'warm_up_done':   5,
      'ten_strong':     10,
      'fifty_club':     50,
      'century_lifter': 100,
    }.entries) {
      final r = await _upsertProgress(entry.key, total);
      if (r != null) results.add(r);
    }

    // speed_demon
    if (durationMinutes < 20) {
      final r = await _upsertProgress('speed_demon', 1);
      if (r != null) results.add(r);
    }

    // marathon
    if (durationMinutes > 90) {
      final r = await _upsertProgress('marathon', 1);
      if (r != null) results.add(r);
    }

    // mixed_bag
    final distinctTypes = await _getDistinctWorkoutTypes();
    final r = await _upsertProgress('mixed_bag', distinctTypes);
    if (r != null) results.add(r);

    // iron_will — 7 consecutive workout days
    final consecutive = await _getConsecutiveWorkoutDays();
    final r2 = await _upsertProgress('iron_will', consecutive);
    if (r2 != null) results.add(r2);

    return results;
  }

  // Call after a friend request is accepted
  Future<List<AchievementUnlockResult>> checkSocialAchievements() async {
    final results = <AchievementUnlockResult>[];
    final friendCount = await _getFriendCount();

    for (final entry in {
      'first_friend':     1,
      'squad_goals':      3,
      'social_butterfly': 5,
      'influencer':       10,
    }.entries) {
      final r = await _upsertProgress(entry.key, friendCount);
      if (r != null) results.add(r);
    }
    return results;
  }

  // Call after a friend request is SENT
  Future<List<AchievementUnlockResult>> checkConnectorAchievement() async {
    final count = await _getSentRequestCount();
    final r = await _upsertProgress('connector', count);
    return r != null ? [r] : [];
  }

  // Call after randomiser is used
  Future<List<AchievementUnlockResult>> checkFeelingLucky() async {
    final r = await _upsertProgress('feeling_lucky', 1);
    return r != null ? [r] : [];
  }

  // Call after XP awarded / level up
  Future<List<AchievementUnlockResult>> checkLevelAchievements(int newLevel) async {
    final results = <AchievementUnlockResult>[];
    for (final entry in {
      'level_5':  5,
      'level_10': 10,
      'level_25': 25,
      'level_50': 50,
      'level_99': 99,
    }.entries) {
      final r = await _upsertProgress(entry.key, newLevel >= entry.value ? entry.value : newLevel);
      if (r != null) results.add(r);
    }
    return results;
  }

  // Call after any coin is earned
  Future<List<AchievementUnlockResult>> checkCoinAchievements() async {
    final results = <AchievementUnlockResult>[];
    final lifetime = await _getLifetimeCoins();
    for (final entry in {
      'coin_collector': 500,
      'rich_in_spirit': 2000,
      'loaded':         10000,
    }.entries) {
      final r = await _upsertProgress(entry.key, lifetime);
      if (r != null) results.add(r);
    }
    return results;
  }

  // Call after any cosmetic unlocked
  Future<List<AchievementUnlockResult>> checkPrestigeAchievements() async {
    final results = <AchievementUnlockResult>[];
    final count = await _getCosmeticCount();
    for (final entry in {
      'collector':     5,
      'hoarder':       15,
      'full_wardrobe': 30,
    }.entries) {
      final r = await _upsertProgress(entry.key, count);
      if (r != null) results.add(r);
    }
    return results;
  }

  // Call on app login — checks loyalty milestones passively
  Future<List<AchievementUnlockResult>> checkLoyaltyAchievements() async {
    final results = <AchievementUnlockResult>[];
    final uid = _userId;
    if (uid == null) return results;

    try {
      final profile = await _supabase
          .from('user_profiles')
          .select('created_at')
          .eq('id', uid)
          .single();

      final created = DateTime.parse(profile['created_at'] as String);
      final daysSince = DateTime.now().difference(created).inDays;

      for (final entry in {
        'day_one':   7,
        'veteran':   30,
        'og_member': 90,
      }.entries) {
        final r = await _upsertProgress(entry.key, daysSince >= entry.value ? entry.value : daysSince);
        if (r != null) results.add(r);
      }
    } catch (e) {
      if (kDebugMode) print('❌ checkLoyaltyAchievements: $e');
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

  Future<int> _getFriendCount() async {
    try {
      final uid = _userId;
      if (uid == null) return 0;
      final res = await _supabase
          .from('friends')
          .select('id')
          .eq('status', 'accepted')
          .or('requester_id.eq.$uid,addressee_id.eq.$uid');
      return (res as List).length;
    } catch (_) { return 0; }
  }

  Future<int> _getSentRequestCount() async {
    try {
      final uid = _userId;
      if (uid == null) return 0;
      final res = await _supabase
          .from('friends')
          .select('id')
          .eq('requester_id', uid);
      return (res as List).length;
    } catch (_) { return 0; }
  }

  Future<int> _getMutualCoopCount(String teamStreakId) async {
    try {
      final res = await _supabase
          .from('daily_team_checkins')
          .select('check_in_date')
          .eq('team_streak_id', teamStreakId);

      // Count dates where 2 check-ins exist
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
      // Get coach max team IDs for this user
      final teams = await _supabase
          .from('buddy_teams')
          .select('id')
          .eq('is_coach_max_team', true)
          .or('user1_id.eq.$uid,user2_id.eq.$uid');
      if ((teams as List).isEmpty) return 0;
      final teamIds = teams.map((t) => t['id'] as String).toList();
      final res = await _supabase
          .from('daily_team_checkins')
          .select('id')
          .eq('user_id', uid)
          .inFilter('team_streak_id', teamIds);
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
          .eq('type', 'earn');
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