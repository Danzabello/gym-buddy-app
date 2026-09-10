import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../services/coin_service.dart';
import '../../services/level_service.dart';
import '../../widgets/avatar_picker_screen.dart' show AvatarBorderStyle;

/// In-memory selection shared by the Wardrobe hub + its three sub-screens.
/// Nothing here touches Supabase until [save] is called — it then writes
/// only whichever of avatar/border/ring actually changed from the seed.
class WardrobeSelectionState extends ChangeNotifier {
  WardrobeSelectionState._({
    required String avatarId,
    required AvatarBorderStyle border,
    required ShopItem? ringItem,
    required this.ringItems,
    required this.unlockedAvatarIds,
    required this.unlockedBorderIds,
    required this.userLevel,
  })  : _avatarId = avatarId,
        _border = border,
        _ringItem = ringItem,
        _seedAvatarId = avatarId,
        _seedBorder = border,
        _seedRingItemId = ringItem?.id;

  static Future<WardrobeSelectionState> load() async {
    final userId = Supabase.instance.client.auth.currentUser!.id;
    final profile = await Supabase.instance.client
        .from('user_profiles')
        .select('avatar_id, avatar_border')
        .eq('id', userId)
        .single();

    final items = await CoinService().getShopItems();
    final ringItems = items.where((i) => i.category == 'ring_color').toList();
    ShopItem? equippedRing;
    for (final i in ringItems) {
      if (i.isEquipped) equippedRing = i;
    }

    final unlocks = await LevelService().getUnlockedCosmetics();
    final unlockedAvatarIds = unlocks
        .where((u) =>
            u['unlock_reason']?.toString().contains('streak') == true ||
            u['unlock_reason']?.toString().contains('coop') == true ||
            u['unlock_reason']?.toString().contains('level') == true)
        .map((u) => u['shop_item_id'] as String)
        .toSet();
    final unlockedBorderIds = unlocks
        .where((u) => u['shop_item_id'] == 'bold' || u['shop_item_id'] == 'arc')
        .map((u) => u['shop_item_id'] as String)
        .toSet();

    final levelInfo = await LevelService().getLevelInfo();

    return WardrobeSelectionState._(
      avatarId: profile['avatar_id'] as String? ?? 'lion',
      border: AvatarBorderStyle.values.byName(
          profile['avatar_border'] as String? ?? 'simple'),
      ringItem: equippedRing,
      ringItems: ringItems,
      unlockedAvatarIds: unlockedAvatarIds,
      unlockedBorderIds: unlockedBorderIds,
      userLevel: levelInfo?.level ?? 1,
    );
  }

  final List<ShopItem> ringItems;
  final Set<String> unlockedAvatarIds;
  final Set<String> unlockedBorderIds;
  final int userLevel;

  String _avatarId;
  AvatarBorderStyle _border;
  ShopItem? _ringItem;

  final String _seedAvatarId;
  final AvatarBorderStyle _seedBorder;
  final String? _seedRingItemId;

  String get avatarId => _avatarId;
  AvatarBorderStyle get border => _border;
  ShopItem? get ringItem => _ringItem;

  bool get isDirty =>
      _avatarId != _seedAvatarId ||
      _border != _seedBorder ||
      _ringItem?.id != _seedRingItemId;

  void setAvatar(String id) {
    if (_avatarId == id) return;
    _avatarId = id;
    notifyListeners();
  }

  void setBorder(AvatarBorderStyle style) {
    if (_border == style) return;
    _border = style;
    notifyListeners();
  }

  void setRing(ShopItem item) {
    if (_ringItem?.id == item.id) return;
    _ringItem = item;
    notifyListeners();
  }

  Future<void> save() async {
    final userId = Supabase.instance.client.auth.currentUser!.id;

    final profileUpdates = <String, dynamic>{};
    if (_avatarId != _seedAvatarId) profileUpdates['avatar_id'] = _avatarId;
    if (_border != _seedBorder) profileUpdates['avatar_border'] = _border.name;
    if (profileUpdates.isNotEmpty) {
      profileUpdates['updated_at'] = DateTime.now().toUtc().toIso8601String();
      await Supabase.instance.client
          .from('user_profiles')
          .update(profileUpdates)
          .eq('id', userId);
    }

    if (_ringItem != null && _ringItem!.id != _seedRingItemId) {
      await CoinService()
          .equipItem(itemId: _ringItem!.id, category: 'ring_color');
    }
  }
}
