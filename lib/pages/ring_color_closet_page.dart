import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../theme/app_theme.dart';
import '../services/coin_service.dart';
import '../services/level_service.dart';

Color _hexToColor(String hex) =>
    Color(int.parse('FF${hex.replaceFirst('#', '')}', radix: 16));

/// Equip-only closet for the `ring_color` shop category — mirrors the Accent
/// Theme picker's swatch/name/checkmark row, but DB-backed via user_inventory
/// (the accent theme is a local SharedPreferences pref, not a fit here).
class RingColorClosetPage extends StatefulWidget {
  const RingColorClosetPage({super.key});

  @override
  State<RingColorClosetPage> createState() => _RingColorClosetPageState();
}

class _RingColorClosetPageState extends State<RingColorClosetPage> {
  final CoinService _coinService = CoinService();
  List<ShopItem> _items = [];
  bool _isLoading = true;
  int _userLevel = 1;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    setState(() => _isLoading = true);
    final items = await _coinService.getShopItems();
    final levelInfo = await LevelService().getLevelInfo();
    if (mounted) {
      setState(() {
        _items = items.where((i) => i.category == 'ring_color').toList();
        _userLevel = levelInfo?.level ?? 1;
        _isLoading = false;
      });
    }
  }

  bool _isLevelLocked(ShopItem item) =>
      item.unlockAchievementId == null && _userLevel < item.unlockLevel;

  Future<void> _equip(ShopItem item) async {
    HapticFeedback.selectionClick();
    final success =
        await _coinService.equipItem(itemId: item.id, category: 'ring_color');
    if (success && mounted) _loadData();
  }

  Color _equippedColor(AppColors colors) {
    final equipped = _items.where((i) => i.isEquipped);
    if (equipped.isEmpty) return colors.avatarRing;
    final hex = equipped.first.colorHex;
    return hex != null ? _hexToColor(hex) : colors.avatarRing;
  }

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    final owned = _items.where((i) => i.isOwned).toList();
    final locked = _items.where((i) => !i.isOwned).toList()
      ..sort((a, b) =>
          (a.unlockAchievementId == null ? 0 : 1)
              .compareTo(b.unlockAchievementId == null ? 0 : 1));

    return Scaffold(
      backgroundColor: colors.sectionBackground,
      appBar: AppBar(title: const Text('Ring Colors')),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
              children: [
                Center(
                  child: Container(
                    width: 96,
                    height: 96,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      border: Border.all(
                          color: _equippedColor(colors), width: 6),
                    ),
                  ),
                ),
                const SizedBox(height: 28),
                if (owned.isNotEmpty) ...[
                  _sectionLabel('Owned', colors),
                  const SizedBox(height: 10),
                  for (final item in owned) ...[
                    _buildRingRow(item, colors, locked: false),
                    const SizedBox(height: 10),
                  ],
                  const SizedBox(height: 12),
                ],
                if (locked.isNotEmpty) ...[
                  _sectionLabel('Locked', colors),
                  const SizedBox(height: 10),
                  for (final item in locked) ...[
                    _buildRingRow(item, colors, locked: true),
                    const SizedBox(height: 10),
                  ],
                ],
              ],
            ),
    );
  }

  Widget _sectionLabel(String label, AppColors colors) => Text(
        label.toUpperCase(),
        style: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.5,
          color: colors.subtleText,
        ),
      );

  Widget _buildRingRow(ShopItem item, AppColors colors, {required bool locked}) {
    final swatch = item.colorHex != null
        ? _hexToColor(item.colorHex!)
        : colors.avatarRing;
    final isAchievementGated = item.unlockAchievementId != null;
    final isEquipped = !locked && item.isEquipped;

    final String statusText;
    if (!locked) {
      statusText = isEquipped ? 'Equipped' : 'Tap to equip';
    } else if (isAchievementGated) {
      statusText =
          'Not purchasable · ${item.unlockAchievementName ?? 'Achievement'}';
    } else if (_isLevelLocked(item)) {
      statusText = 'Locked · Lvl ${item.unlockLevel}';
    } else {
      // Level requirement already met — this item is only coin-locked, so
      // showing "Locked · Lvl X" here would wrongly read as a level gate.
      statusText = '🪙 ${item.cost} in Shop';
    }

    return GestureDetector(
      onTap: (!locked && !isEquipped) ? () => _equip(item) : null,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        decoration: BoxDecoration(
          color: isEquipped
              ? colors.avatarRing.withOpacity(0.1)
              : colors.cardBackground,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: isEquipped ? colors.avatarRing : colors.cardBorder,
            width: isEquipped ? 2 : 1,
          ),
        ),
        child: Row(
          children: [
            Container(
              width: 22,
              height: 22,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: locked ? swatch.withOpacity(0.35) : swatch,
                border: Border.all(color: colors.cardBorder),
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    item.name,
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                      color: locked
                          ? colors.subtleText
                          : (isEquipped
                              ? colors.avatarRing
                              : Theme.of(context).colorScheme.onSurface),
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  Text(
                    statusText,
                    style: TextStyle(fontSize: 12, color: colors.subtleText),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
            if (isEquipped)
              Icon(Icons.check_circle, color: colors.avatarRing, size: 22)
            else if (locked)
              Icon(Icons.lock_outline, color: colors.subtleText, size: 18),
          ],
        ),
      ),
    );
  }
}
