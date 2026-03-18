import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class CoinService {
  static final CoinService _instance = CoinService._internal();
  factory CoinService() => _instance;
  CoinService._internal();

  final SupabaseClient _supabase = Supabase.instance.client;

  // ============================================================
  // COIN AMOUNTS
  // ============================================================
  static const int dailyCheckIn = 10;
  static const int partnerBonus = 5;
  static const int milestone7Days = 50;
  static const int milestone30Days = 100;
  static const int milestone100Days = 250;

  // ============================================================
  // GET BALANCE
  // ============================================================
  Future<int> getBalance() async {
    try {
      final userId = _supabase.auth.currentUser?.id;
      if (userId == null) return 0;
      final result = await _supabase
          .from('user_profiles')
          .select('coin_balance')
          .eq('id', userId)
          .single();
      return result['coin_balance'] as int? ?? 0;
    } catch (e) {
      if (kDebugMode) print('❌ Error getting coin balance: $e');
      return 0;
    }
  }

  // ============================================================
  // AWARD COINS
  // ============================================================
  Future<int> awardCoins({
    required int amount,
    required String transactionType,
    required String description,
    String? referenceId,
  }) async {
    try {
      final userId = _supabase.auth.currentUser?.id;
      if (userId == null) return 0;

      final current = await getBalance();
      final newBalance = current + amount;

      await _supabase.from('user_profiles').update({
        'coin_balance': newBalance,
      }).eq('id', userId);

      await _supabase.from('coin_transactions').insert({
        'user_id': userId,
        'amount': amount,
        'transaction_type': transactionType,
        'description': description,
        'reference_id': referenceId,
      });

      if (kDebugMode) print('🪙 Awarded $amount coins ($transactionType) → Balance: $newBalance');
      return newBalance;
    } catch (e) {
      if (kDebugMode) print('❌ Error awarding coins: $e');
      return 0;
    }
  }

  // ============================================================
  // AWARD DAILY CHECK-IN COINS
  // ============================================================
  Future<CoinAwardResult?> awardDailyCheckIn({
    required String streakId,
    required int currentStreak,
    required bool partnerAlsoCheckedIn,
  }) async {
    try {
      final userId = _supabase.auth.currentUser?.id;
      if (userId == null) return null;

      final today = DateTime.now().toIso8601String().split('T')[0];

      // Check if already awarded daily check-in today (globally, not per-streak)
      final existing = await _supabase
          .from('coin_transactions')
          .select('id')
          .eq('user_id', userId)
          .eq('transaction_type', 'daily_checkin')
          .gte('created_at', '${today}T00:00:00Z')
          .maybeSingle();

      if (existing != null) {
        if (kDebugMode) print('⏭️ Already awarded daily check-in coins today');
        return null;
      }

      int totalAwarded = 0;
      List<String> reasons = [];

      // Base daily check-in coins
      await awardCoins(
        amount: dailyCheckIn,
        transactionType: 'daily_checkin',
        description: 'Daily check-in 💪',
        referenceId: streakId,
      );
      totalAwarded += dailyCheckIn;
      reasons.add('+$dailyCheckIn daily check-in');

      // Partner bonus — only once per day globally
      if (partnerAlsoCheckedIn) {
        final existingPartnerBonus = await _supabase
            .from('coin_transactions')
            .select('id')
            .eq('user_id', userId)
            .eq('transaction_type', 'partner_bonus')
            .gte('created_at', '${today}T00:00:00Z')
            .maybeSingle();

        if (existingPartnerBonus == null) {
          await awardCoins(
            amount: partnerBonus,
            transactionType: 'partner_bonus',
            description: 'Partner checked in too! 🤝',
            referenceId: streakId,
          );
          totalAwarded += partnerBonus;
          reasons.add('+$partnerBonus partner bonus');
        }
      }

      // Milestone bonuses
      if (currentStreak == 7) {
        await awardCoins(
          amount: milestone7Days,
          transactionType: 'streak_milestone',
          description: '7-day streak milestone! 🔥',
          referenceId: streakId,
        );
        totalAwarded += milestone7Days;
        reasons.add('+$milestone7Days 7-day milestone!');
      } else if (currentStreak == 30) {
        await awardCoins(
          amount: milestone30Days,
          transactionType: 'streak_milestone',
          description: '30-day streak milestone! 💪',
          referenceId: streakId,
        );
        totalAwarded += milestone30Days;
        reasons.add('+$milestone30Days 30-day milestone!');
      } else if (currentStreak == 100) {
        await awardCoins(
          amount: milestone100Days,
          transactionType: 'streak_milestone',
          description: '100-day streak milestone! 🏆',
          referenceId: streakId,
        );
        totalAwarded += milestone100Days;
        reasons.add('+$milestone100Days 100-day milestone!');
      }

      final newBalance = await getBalance();
      return CoinAwardResult(
        totalAwarded: totalAwarded,
        newBalance: newBalance,
        reasons: reasons,
      );
    } catch (e) {
      if (kDebugMode) print('❌ Error awarding check-in coins: $e');
      return null;
    }
  }

  // ============================================================
  // RETROACTIVE PARTNER BONUS
  // Awards partner bonus to a user who checked in solo earlier
  // but whose partner has now also checked in
  // ============================================================
  Future<bool> awardRetroactivePartnerBonus({
    required String userId,
    required String streakId,
  }) async {
    try {
      final today = DateTime.now().toIso8601String().split('T')[0];

      // Check they got daily_checkin today
      final checkin = await _supabase
          .from('coin_transactions')
          .select('id')
          .eq('user_id', userId)
          .eq('transaction_type', 'daily_checkin')
          .gte('created_at', '${today}T00:00:00Z')
          .maybeSingle();

      if (checkin == null) return false;

      // Check they haven't already received partner_bonus today
      final existing = await _supabase
          .from('coin_transactions')
          .select('id')
          .eq('user_id', userId)
          .eq('transaction_type', 'partner_bonus')
          .gte('created_at', '${today}T00:00:00Z')
          .maybeSingle();

      if (existing != null) return false;

      final profile = await _supabase
          .from('user_profiles')
          .select('coin_balance')
          .eq('id', userId)
          .single();

      final currentBalance = profile['coin_balance'] as int? ?? 0;
      final newBalance = currentBalance + partnerBonus;

      await _supabase.from('user_profiles').update({
        'coin_balance': newBalance,
      }).eq('id', userId);

      await _supabase.from('coin_transactions').insert({
        'user_id': userId,
        'amount': partnerBonus,
        'transaction_type': 'partner_bonus',
        'description': 'Partner checked in too! 🤝',
        'reference_id': streakId,
      });

      if (kDebugMode) print('🪙 Retroactive partner bonus +$partnerBonus → User: $userId | Balance: $newBalance');
      return true;
    } catch (e) {
      if (kDebugMode) print('❌ Error awarding retroactive partner bonus: $e');
      return false;
    }
  }

  // ============================================================
  // SPEND COINS (SHOP PURCHASE)
  // ============================================================
  Future<bool> purchaseItem({
    required String itemId,
    required int cost,
    required String itemName,
  }) async {
    try {
      final userId = _supabase.auth.currentUser?.id;
      if (userId == null) return false;

      final balance = await getBalance();
      if (balance < cost) {
        if (kDebugMode) print('❌ Insufficient coins: $balance < $cost');
        return false;
      }

      final existing = await _supabase
          .from('user_inventory')
          .select('id')
          .eq('user_id', userId)
          .eq('shop_item_id', itemId)
          .maybeSingle();

      if (existing != null) {
        if (kDebugMode) print('❌ Item already owned');
        return false;
      }

      final newBalance = balance - cost;
      await _supabase.from('user_profiles').update({
        'coin_balance': newBalance,
      }).eq('id', userId);

      await _supabase.from('coin_transactions').insert({
        'user_id': userId,
        'amount': -cost,
        'transaction_type': 'shop_purchase',
        'description': 'Purchased: $itemName',
        'reference_id': itemId,
      });

      await _supabase.from('user_inventory').insert({
        'user_id': userId,
        'shop_item_id': itemId,
      });

      if (kDebugMode) print('✅ Purchased $itemName for $cost coins → Balance: $newBalance');
      return true;
    } catch (e) {
      if (kDebugMode) print('❌ Error purchasing item: $e');
      return false;
    }
  }

  // ============================================================
  // GET SHOP ITEMS
  // ============================================================
  Future<List<ShopItem>> getShopItems() async {
    try {
      final userId = _supabase.auth.currentUser?.id;
      final items = await _supabase
          .from('shop_items')
          .select()
          .eq('is_available', true)
          .order('category')
          .order('cost');

      List<String> ownedIds = [];
      if (userId != null) {
        final inventory = await _supabase
            .from('user_inventory')
            .select('shop_item_id')
            .eq('user_id', userId);
        ownedIds = inventory.map<String>((i) => i['shop_item_id'] as String).toList();
      }

      return items.map<ShopItem>((item) => ShopItem.fromMap(item, ownedIds.contains(item['id']))).toList();
    } catch (e) {
      if (kDebugMode) print('❌ Error getting shop items: $e');
      return [];
    }
  }

  // ============================================================
  // GET TRANSACTION HISTORY
  // ============================================================
  Future<List<CoinTransaction>> getTransactionHistory({int limit = 20}) async {
    try {
      final userId = _supabase.auth.currentUser?.id;
      if (userId == null) return [];
      final results = await _supabase
          .from('coin_transactions')
          .select()
          .eq('user_id', userId)
          .order('created_at', ascending: false)
          .limit(limit);
      return results.map<CoinTransaction>((t) => CoinTransaction.fromMap(t)).toList();
    } catch (e) {
      if (kDebugMode) print('❌ Error getting transactions: $e');
      return [];
    }
  }

  // ============================================================
  // EQUIP ITEM
  // ============================================================
  Future<bool> equipItem({required String itemId, required String category}) async {
    try {
      final userId = _supabase.auth.currentUser?.id;
      if (userId == null) return false;

      final itemsInCategory = await _supabase
          .from('user_inventory')
          .select('shop_item_id, shop_items!inner(category)')
          .eq('user_id', userId)
          .eq('shop_items.category', category);

      for (final item in itemsInCategory) {
        await _supabase
            .from('user_inventory')
            .update({'equipped': false})
            .eq('user_id', userId)
            .eq('shop_item_id', item['shop_item_id']);
      }

      await _supabase
          .from('user_inventory')
          .update({'equipped': true})
          .eq('user_id', userId)
          .eq('shop_item_id', itemId);

      if (kDebugMode) print('✅ Equipped item $itemId');
      return true;
    } catch (e) {
      if (kDebugMode) print('❌ Error equipping item: $e');
      return false;
    }
  }
}

// ============================================================
// DATA MODELS
// ============================================================

class CoinAwardResult {
  final int totalAwarded;
  final int newBalance;
  final List<String> reasons;

  CoinAwardResult({
    required this.totalAwarded,
    required this.newBalance,
    required this.reasons,
  });
}

class ShopItem {
  final String id;
  final String name;
  final String description;
  final String category;
  final int cost;
  final String emoji;
  final String assetId;
  final bool isOwned;

  ShopItem({
    required this.id,
    required this.name,
    required this.description,
    required this.category,
    required this.cost,
    required this.emoji,
    required this.assetId,
    required this.isOwned,
  });

  factory ShopItem.fromMap(Map<String, dynamic> map, bool isOwned) {
    return ShopItem(
      id: map['id'] as String,
      name: map['name'] as String,
      description: map['description'] as String? ?? '',
      category: map['category'] as String,
      cost: map['cost'] as int,
      emoji: map['emoji'] as String? ?? '⭐',
      assetId: map['asset_id'] as String? ?? '',
      isOwned: isOwned,
    );
  }
}

class CoinTransaction {
  final String id;
  final int amount;
  final String transactionType;
  final String description;
  final DateTime createdAt;

  CoinTransaction({
    required this.id,
    required this.amount,
    required this.transactionType,
    required this.description,
    required this.createdAt,
  });

  factory CoinTransaction.fromMap(Map<String, dynamic> map) {
    return CoinTransaction(
      id: map['id'] as String,
      amount: map['amount'] as int,
      transactionType: map['transaction_type'] as String,
      description: map['description'] as String? ?? '',
      createdAt: DateTime.parse(map['created_at'] as String),
    );
  }
}