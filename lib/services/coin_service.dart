import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:gym_buddy_app/utils/debug_logger.dart';

class CoinService {
  static final CoinService _instance = CoinService._internal();
  factory CoinService() => _instance;
  CoinService._internal();

  final SupabaseClient _supabase = Supabase.instance.client;

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
      if (kDebugMode) debugLog('❌ Error getting coin balance: $e');
      return 0;
    }
  }

  // ============================================================
  // SPEND COINS (SHOP PURCHASE)
  // Server validates funds + ownership atomically via the
  // purchase_shop_item RPC (S2 audit fix — was a direct
  // coin_balance write before).
  // ============================================================
  Future<bool> purchaseItem({
    required String itemId,
    required int cost,
    required String itemName,
  }) async {
    try {
      final result = await _supabase.rpc('purchase_shop_item', params: {
        'p_shop_item_id': itemId,
      });

      final success = result?['success'] as bool? ?? false;
      if (!success) {
        if (kDebugMode) debugLog('❌ Purchase failed: ${result?['reason']}');
        return false;
      }

      if (kDebugMode) {
        debugLog('✅ Purchased $itemName for $cost coins → Balance: ${result?['new_balance']}');
      }
      return true;
    } catch (e) {
      if (kDebugMode) debugLog('❌ Error purchasing item: $e');
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
      if (kDebugMode) debugLog('❌ Error getting shop items: $e');
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
      if (kDebugMode) debugLog('❌ Error getting transactions: $e');
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

      if (kDebugMode) debugLog('✅ Equipped item $itemId');
      return true;
    } catch (e) {
      if (kDebugMode) debugLog('❌ Error equipping item: $e');
      return false;
    }
  }
}

// ============================================================
// DATA MODELS
// ============================================================

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
