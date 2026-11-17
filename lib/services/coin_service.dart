import 'dart:async' show unawaited;
import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:gym_buddy_app/utils/debug_logger.dart';
import 'economy_sync.dart';
import 'package:gym_buddy_app/utils/query_ceilings.dart';
import 'dashboard_refresh.dart';

class CoinService {
  static final CoinService _instance =
      CoinService._internal(Supabase.instance.client);
  factory CoinService({SupabaseClient? client}) =>
      client == null ? _instance : CoinService._internal(client);
  CoinService._internal(this._supabase);

  final SupabaseClient _supabase;

  // ============================================================
  // GET BALANCE
  // ============================================================
  Future<int> getBalance() async {
    try {
      final userId = _supabase.auth.currentUser?.id;
      if (userId == null) return 0;
      final result = await _supabase
          .rpc('get_my_profile')
          .select('coin_balance')
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
      unawaited(EconomySync.instance.refresh());
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
          .select('*, achievements(name)')
          .eq('is_available', true)
          .order('category')
          .order('cost');

      Set<String> ownedIds = {};
      Map<String, bool> equippedById = {};
      if (userId != null) {
        final inventory = await _supabase
            .from('user_inventory')
            .select('shop_item_id, equipped')
            .eq('user_id', userId);
        for (final row in inventory) {
          final id = row['shop_item_id'] as String;
          ownedIds.add(id);
          equippedById[id] = row['equipped'] as bool? ?? false;
        }
      }

      return items
          .map<ShopItem>((item) => ShopItem.fromMap(
                item,
                ownedIds.contains(item['id']),
                isEquipped: equippedById[item['id']] ?? false,
              ))
          .toList();
    } catch (e) {
      if (kDebugMode) debugLog('❌ Error getting shop items: $e');
      return [];
    }
  }

  // ============================================================
  // GET EQUIPPED ITEM COLOR for multiple users in one query
  // (e.g. every visible team member's equipped ring_color)
  // ============================================================
  Future<Map<String, String>> getEquippedColorHexForUsers(
    List<String> userIds, {
    String category = 'ring_color',
  }) async {
    if (userIds.isEmpty) return {};
    try {
      final rows = await _supabase
          .from('user_inventory')
          .select('user_id, shop_items!inner(color_hex)')
          .inFilter('user_id', userIds)
          .eq('shop_items.category', category)
          .eq('equipped', true);
      final result = <String, String>{};
      for (final row in rows) {
        final userId = row['user_id'] as String?;
        final hex = (row['shop_items'] as Map<String, dynamic>?)?['color_hex'] as String?;
        if (userId != null && hex != null) result[userId] = hex;
      }
      return result;
    } catch (e) {
      if (kDebugMode) debugLog('❌ Error getting equipped colors for users: $e');
      return {};
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
  // COIN HISTORY PAGE
  // Unlike the loaders above, these throw on failure: the page must tell
  // an error from "no coins yet", and an empty list can't say which.
  // ============================================================

  /// One page of the signed-in user's rows, newest first. `id` breaks ties
  /// because the rows of one check-in share a timestamp, and offset paging
  /// needs a stable order.
  Future<List<CoinTransaction>> getTransactionPage({
    required int offset,
    int limit = kCoinPageSize,
    CoinFilter filter = CoinFilter.all,
  }) async {
    try {
      final userId = _supabase.auth.currentUser?.id;
      if (userId == null) throw StateError('Not signed in');
      var query =
          _supabase.from('coin_transactions').select().eq('user_id', userId);
      if (filter == CoinFilter.earned) query = query.gt('amount', 0);
      if (filter == CoinFilter.spent) query = query.lt('amount', 0);
      final rows = await query
          .order('created_at', ascending: false)
          .order('id', ascending: false)
          .range(offset, offset + limit - 1);
      return rows.map<CoinTransaction>(CoinTransaction.fromMap).toList();
    } catch (e) {
      if (kDebugMode) debugLog('❌ Error getting transaction page: $e');
      rethrow;
    }
  }

  /// Earned and spent (both positive) since the start of the local day six
  /// days ago, so today plus the six days before it.
  // ponytail: sums client-side, so it sees at most PostgREST's 1000-row cap;
  // move to an RPC if a week can ever pass that.
  Future<CoinWeekTotals> getWeekTotals() async {
    try {
      final userId = _supabase.auth.currentUser?.id;
      if (userId == null) throw StateError('Not signed in');
      final start = coinWeekStart(DateTime.now()); // sent as UTC below
      final rows = await _supabase
          .from('coin_transactions')
          .select('amount')
          .eq('user_id', userId)
          .gte('created_at', start.toUtc().toIso8601String())
          .limit(kWeekCoinRowsCeiling);
      var earned = 0, spent = 0;
      for (final r in rows) {
        final a = r['amount'] as int;
        if (a > 0) earned += a;
        if (a < 0) spent -= a;
      }
      return (earned: earned, spent: spent);
    } catch (e) {
      if (kDebugMode) debugLog('❌ Error getting week totals: $e');
      rethrow;
    }
  }

  // ============================================================
  // EQUIP ITEM
  // ============================================================
  // One statement on the server (equip_shop_item): the other owned items in
  // the item's category are unequipped and this one equipped together, or
  // nothing changes. False when the caller does not own the item.
  Future<bool> equipItem({required String itemId}) async {
    try {
      final ok = await _supabase
          .rpc('equip_shop_item', params: {'p_shop_item_id': itemId});
      if (kDebugMode) {
        debugLog(ok == true ? '✅ Equipped item $itemId' : '❌ Item $itemId not equipped');
      }
      if (ok == true) markStale({AppTab.dashboard, AppTab.schedule}); // ring colours
      return ok == true;
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
  final bool isEquipped;
  final int unlockLevel;
  final String? colorHex;
  final String? unlockAchievementId;
  final String? unlockAchievementName;

  ShopItem({
    required this.id,
    required this.name,
    required this.description,
    required this.category,
    required this.cost,
    required this.emoji,
    required this.assetId,
    required this.isOwned,
    this.isEquipped = false,
    this.unlockLevel = 1,
    this.colorHex,
    this.unlockAchievementId,
    this.unlockAchievementName,
  });

  /// The saved copy's form (SavedCopy, class 'shop'), read back by [fromSaved].
  Map<String, dynamic> toSaved() => {
        'id': id,
        'name': name,
        'description': description,
        'category': category,
        'cost': cost,
        'emoji': emoji,
        'asset_id': assetId,
        'owned': isOwned,
        'equipped': isEquipped,
        'unlock_level': unlockLevel,
        'color_hex': colorHex,
        'unlock_achievement_id': unlockAchievementId,
        'unlock_achievement_name': unlockAchievementName,
      };

  factory ShopItem.fromSaved(Map<String, dynamic> m) => ShopItem(
        id: m['id'] as String,
        name: m['name'] as String,
        description: m['description'] as String,
        category: m['category'] as String,
        cost: m['cost'] as int,
        emoji: m['emoji'] as String,
        assetId: m['asset_id'] as String,
        isOwned: m['owned'] as bool,
        isEquipped: m['equipped'] as bool,
        unlockLevel: m['unlock_level'] as int,
        colorHex: m['color_hex'] as String?,
        unlockAchievementId: m['unlock_achievement_id'] as String?,
        unlockAchievementName: m['unlock_achievement_name'] as String?,
      );

  factory ShopItem.fromMap(Map<String, dynamic> map, bool isOwned, {bool isEquipped = false}) {
    return ShopItem(
      id: map['id'] as String,
      name: map['name'] as String,
      description: map['description'] as String? ?? '',
      category: map['category'] as String,
      cost: map['cost'] as int,
      emoji: map['emoji'] as String? ?? '⭐',
      assetId: map['asset_id'] as String? ?? '',
      isOwned: isOwned,
      isEquipped: isEquipped,
      unlockLevel: map['unlock_level'] as int? ?? 1,
      colorHex: map['color_hex'] as String?,
      unlockAchievementId: map['unlock_achievement_id'] as String?,
      unlockAchievementName:
          (map['achievements'] as Map<String, dynamic>?)?['name'] as String?,
    );
  }
}

/// Rows per page on the coin history page; a full page means there may be more.
const kCoinPageSize = 20;

enum CoinFilter { all, earned, spent }

typedef CoinWeekTotals = ({int earned, int spent});

/// Local midnight six days before [now]'s day (DateTime normalises the day).
@visibleForTesting
DateTime coinWeekStart(DateTime now) =>
    DateTime(now.year, now.month, now.day - 6);

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
