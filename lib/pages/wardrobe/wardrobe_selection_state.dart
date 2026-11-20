import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../services/coin_service.dart';
import '../../services/tab_refresh.dart';
import '../../widgets/avatar_picker_screen.dart' show AvatarBorderStyle;

/// What Wardrobe knows, part by part. A null part was never answered by the
/// server or the saved copy, and is never painted as a default. Unlocks may be
/// an empty list (a real answer: nothing unlocked); only a failed read is null.
typedef WardrobeParts = ({
  ({String? avatarId, AvatarBorderStyle border})? profile,
  List<ShopItem>? ringItems,
  List<Map<String, dynamic>>? unlocks,
  int? level,
});

const WardrobeParts noWardrobeParts = (profile: null, ringItems: null, unlocks: null, level: null);

/// The equipped avatar and border from the profile row. An unknown stored
/// border throws (a failed read, never a default); a null column is the
/// app's own default for an account that never picked one.
({String? avatarId, AvatarBorderStyle border}) wardrobeProfileFromRow(Map<String, dynamic> row) => (
      avatarId: row['avatar_id'] as String?,
      border: AvatarBorderStyle.values.byName(row['avatar_border'] as String? ?? 'simple'),
    );

/// What the page knows after a load: each part the server answered, else the
/// one known now (the saved copy or an earlier load). A null in [answered] is
/// a failed read, so a failing part never blocks the others.
WardrobeParts wardrobeAfterLoad(WardrobeParts shown, WardrobeParts answered) => (
      profile: answered.profile ?? shown.profile,
      ringItems: answered.ringItems ?? shown.ringItems,
      unlocks: answered.unlocks ?? shown.unlocks,
      level: answered.level ?? shown.level,
    );

/// Whether every part is known. Until then the page stays off the grids, so no
/// empty grid, "Default" ring, locked border or level 1 is painted. Also the
/// rule for saving, and for editing: only parts that all answered in one load
/// are written to the saved copy, and only they let a selection be saved.
bool wardrobeReady(WardrobeParts p) =>
    p.profile != null && p.ringItems != null && p.unlocks != null && p.level != null;

/// What one load saves, or null unless all four of its own reads answered.
Map<String, dynamic>? wardrobeSavedPayload(WardrobeParts answered) => wardrobeReady(answered)
    ? {
        'avatar_id': answered.profile!.avatarId,
        'avatar_border': answered.profile!.border.name,
        'ring_items': [for (final i in answered.ringItems!) i.toSaved()],
        'unlocks': answered.unlocks,
        'level': answered.level,
      }
    : null;

/// Reads [wardrobeSavedPayload]'s output back. No ring items, or a part of
/// the wrong shape, throws (corrupt).
WardrobeParts wardrobeFromSaved(Object d) {
  final m = d as Map<String, dynamic>;
  final ringItems = [
    for (final i in m['ring_items'] as List) ShopItem.fromSaved(Map<String, dynamic>.from(i as Map)),
  ];
  if (ringItems.isEmpty) throw const FormatException('no ring items saved');
  return (
    profile: (
      avatarId: m['avatar_id'] as String?,
      border: AvatarBorderStyle.values.byName(m['avatar_border'] as String),
    ),
    ringItems: ringItems,
    unlocks: [for (final u in m['unlocks'] as List) Map<String, dynamic>.from(u as Map)],
    level: m['level'] as int,
  );
}

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
    required this.editable,
  })  : _avatarId = avatarId,
        _border = border,
        _ringItem = ringItem,
        _seedAvatarId = avatarId,
        _seedBorder = border,
        _seedRingItemId = ringItem?.id;

  /// Built from fully known [parts]. [editable] is true only when those parts
  /// all answered in a load this session. Otherwise they are the saved copy,
  /// and the seeds below may be stale: selections are ignored and [save]
  /// throws, so a stale seed can never decide a write.
  factory WardrobeSelectionState.fromParts(WardrobeParts parts, {required bool editable}) {
    final ringItems = parts.ringItems!;
    ShopItem? equippedRing;
    for (final i in ringItems) {
      if (i.isEquipped) equippedRing = i;
    }

    final unlocks = parts.unlocks!;
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

    return WardrobeSelectionState._(
      avatarId: parts.profile!.avatarId ?? 'lion',
      border: parts.profile!.border,
      ringItem: equippedRing,
      ringItems: ringItems,
      unlockedAvatarIds: unlockedAvatarIds,
      unlockedBorderIds: unlockedBorderIds,
      userLevel: parts.level!,
      editable: editable,
    );
  }

  final List<ShopItem> ringItems;
  final Set<String> unlockedAvatarIds;
  final Set<String> unlockedBorderIds;
  final int userLevel;

  /// False while the screen shows the saved copy: view only, nothing can be saved.
  final bool editable;

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
    if (!editable || _avatarId == id) return;
    _avatarId = id;
    notifyListeners();
  }

  void setBorder(AvatarBorderStyle style) {
    if (!editable || _border == style) return;
    _border = style;
    notifyListeners();
  }

  void setRing(ShopItem item) {
    if (!editable || _ringItem?.id == item.id) return;
    _ringItem = item;
    notifyListeners();
  }

  Future<void> save() async {
    if (!editable) throw StateError('the wardrobe is showing the saved copy');
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
      // The dashboard header, the Schedule rows and Profile show the avatar.
      markStale({AppTab.dashboard, AppTab.schedule, AppTab.profile});
    }

    if (_ringItem != null && _ringItem!.id != _seedRingItemId) {
      await CoinService().equipItem(itemId: _ringItem!.id);
    }
  }
}
