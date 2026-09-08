import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../theme/app_theme.dart';
import '../theme/accent_theme_provider.dart';
import '../services/coin_service.dart';
import '../services/level_service.dart';

Color _hexToColor(String hex) =>
    Color(int.parse('FF${hex.replaceFirst('#', '')}', radix: 16));

class ShopPage extends StatefulWidget {
  const ShopPage({super.key});

  @override
  State<ShopPage> createState() => _ShopPageState();
}

class _ShopPageState extends State<ShopPage> with SingleTickerProviderStateMixin {
  final CoinService _coinService = CoinService();
  late TabController _tabController;

  int _coinBalance = 0;
  List<ShopItem> _allItems = [];
  bool _isLoading = true;

  final List<Map<String, dynamic>> _categories = [
    {'key': 'all', 'label': 'All', 'emoji': '🛍️'},
    {'key': 'avatar_frame', 'label': 'Frames', 'emoji': '🖼️'},
    {'key': 'badge', 'label': 'Badges', 'emoji': '🏅'},
    {'key': 'streak_emoji', 'label': 'Emojis', 'emoji': '✨'},
    {'key': 'avatar', 'label': 'Avatars', 'emoji': '🦁'},
    {'key': 'ring_color', 'label': 'Ring Colors', 'emoji': '⭕'},
  ];

  int _userLevel = 1;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: _categories.length, vsync: this);
    _loadData();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _loadData() async {
    setState(() => _isLoading = true);
    final balance = await _coinService.getBalance();
    final items = await _coinService.getShopItems();
    final levelInfo = await LevelService().getLevelInfo();
    if (mounted) {
      setState(() {
        _coinBalance = balance;
        _allItems = items;
        _userLevel = levelInfo?.level ?? 1;
        _isLoading = false;
      });
    }
  }

  List<ShopItem> _getItemsForCategory(String category) {
    if (category == 'all') return _allItems;
    return _allItems.where((i) => i.category == category).toList();
  }

  /// Ring colors have no emoji (the DB row's `emoji` is null → defaults to
  /// ⭐), so every place that shows an item's identity needs to swap in the
  /// actual color swatch instead.
  Widget _itemPreview(ShopItem item, {required double size}) {
    if (item.category == 'ring_color' && item.colorHex != null) {
      return Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: _hexToColor(item.colorHex!),
          border: Border.all(color: Colors.white.withOpacity(0.5), width: 2),
        ),
      );
    }
    return Text(item.emoji, style: TextStyle(fontSize: size * 0.65));
  }

  bool _isLevelLocked(ShopItem item) =>
      !item.isOwned &&
      item.unlockAchievementId == null &&
      _userLevel < item.unlockLevel;

  Future<void> _purchaseItem(ShopItem item) async {
    // Achievement-gated items are auto-granted by a DB trigger, never bought,
    // and level-locked items aren't actionable until the user levels up.
    if (!item.isOwned &&
        (item.unlockAchievementId != null || _isLevelLocked(item))) {
      return;
    }

    if (item.isOwned) {
      await _coinService.equipItem(itemId: item.id, category: item.category);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
                '${item.category == 'ring_color' ? '⭕' : item.emoji} ${item.name} equipped!'),
            backgroundColor: AppColors.of(context).successGreen,
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          ),
        );
        _loadData();
      }
      return;
    }

    if (_coinBalance < item.cost) {
      _showInsufficientCoins(item);
      return;
    }

    final confirmed = await _showPurchaseDialog(item);
    if (confirmed != true) return;

    final success = await _coinService.purchaseItem(
      itemId: item.id,
      cost: item.cost,
      itemName: item.name,
    );

    if (mounted) {
      if (success) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Row(
              children: [
                _itemPreview(item, size: 20),
                const SizedBox(width: 8),
                Text('${item.name} purchased!'),
              ],
            ),
            backgroundColor: AppColors.of(context).successGreen,
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          ),
        );
        _loadData();
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: const Text('Purchase failed. Try again.'),
              backgroundColor:
                  context.read<AccentThemeProvider>().palette.statusDanger),
        );
      }
    }
  }

  Future<bool?> _showPurchaseDialog(ShopItem item) {
    final colors = AppColors.of(context);
    return showDialog<bool>(
      context: context,
      builder: (context) {
        final colors = AppColors.of(context);
        return Dialog(
          backgroundColor: colors.cardBackground,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 80,
                  height: 80,
                  decoration: BoxDecoration(
                    color: colors.sectionBackground,
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Center(child: _itemPreview(item, size: 40)),
                ),
                const SizedBox(height: 16),
                Text(item.name,
                    style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                        color: Theme.of(context).colorScheme.onSurface)),
                const SizedBox(height: 8),
                Text(item.description,
                    textAlign: TextAlign.center,
                    style: TextStyle(color: colors.subtleText, fontSize: 14)),
                const SizedBox(height: 20),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                  decoration: BoxDecoration(
                    // Coin/currency branding, not a status — gold stays fixed
                    // across accents, same ruling as achievements' legendary.
                    color: const Color(0xFFFFFBEB),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: const Color(0xFFFDE68A)),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Text('🪙', style: TextStyle(fontSize: 20)),
                      const SizedBox(width: 8),
                      Text('${item.cost} coins',
                          style: const TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                              color: Color(0xFFD97706))),
                    ],
                  ),
                ),
                const SizedBox(height: 24),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: () => Navigator.pop(context, false),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: Theme.of(context).colorScheme.onSurface,
                          side: BorderSide(color: colors.divider),
                          padding: const EdgeInsets.symmetric(vertical: 12),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        ),
                        child: const Text('Cancel'),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Container(
                        decoration: BoxDecoration(
                          gradient: const LinearGradient(
                              colors: [Color(0xFF3B82F6), Color(0xFF8B5CF6)]),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: ElevatedButton(
                          onPressed: () => Navigator.pop(context, true),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.transparent,
                            shadowColor: Colors.transparent,
                            padding: const EdgeInsets.symmetric(vertical: 12),
                            shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12)),
                          ),
                          child: const Text('Buy!',
                              style: TextStyle(
                                  color: Colors.white, fontWeight: FontWeight.bold)),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  void _showInsufficientCoins(ShopItem item) {
    final needed = item.cost - _coinBalance;
    showDialog(
      context: context,
      builder: (context) {
        final colors = AppColors.of(context);
        return Dialog(
          backgroundColor: colors.cardBackground,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text('🪙', style: TextStyle(fontSize: 48)),
                const SizedBox(height: 16),
                Text('Not enough coins!',
                    style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                        color: Theme.of(context).colorScheme.onSurface)),
                const SizedBox(height: 8),
                Text('You need $needed more coins to buy ${item.name}.',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: colors.subtleText, fontSize: 14)),
                const SizedBox(height: 8),
                Text('Keep checking in daily to earn more! 💪',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: colors.subtleText, fontSize: 13)),
                const SizedBox(height: 24),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: () => Navigator.pop(context),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF3B82F6),
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12)),
                    ),
                    child: const Text('Got it!',
                        style: TextStyle(
                            color: Colors.white, fontWeight: FontWeight.bold)),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final colors = AppColors.of(context);
    return Scaffold(
      backgroundColor: colors.sectionBackground,
      body: NestedScrollView(
        headerSliverBuilder: (context, innerBoxIsScrolled) => [
          SliverAppBar(
            expandedHeight: 140,
            floating: false,
            pinned: true,
            elevation: 0,
            flexibleSpace: FlexibleSpaceBar(
              background: SafeArea(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('Shop',
                            style: TextStyle(
                                fontSize: 28, fontWeight: FontWeight.bold)),
                        const SizedBox(height: 12),
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 16, vertical: 10),
                          decoration: BoxDecoration(
                            // Tinted gold, not a status role: this is currency
                            // chrome, matching the gold coin chip and prices
                            // kept elsewhere in this file. Surface is passed
                            // explicitly — the pill sits on the Scaffold's
                            // sectionBackground, not on a card.
                            color: colors.tint(const Color(0xFFD97706),
                                surface: colors.sectionBackground),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Text('🪙', style: TextStyle(fontSize: 20)),
                              const SizedBox(width: 8),
                              Text(
                                '$_coinBalance coins',
                                style: const TextStyle(
                                    fontSize: 18, fontWeight: FontWeight.bold),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
            ),
            bottom: TabBar(
              controller: _tabController,
              isScrollable: true,
              indicatorColor: cs.onSurface,
              labelColor: cs.onSurface,
              unselectedLabelColor: colors.subtleText,
              labelStyle:
                  const TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
              tabs: _categories
                  .map((c) => Tab(text: '${c['emoji']} ${c['label']}'))
                  .toList(),
            ),
          ),
        ],
        body: _isLoading
            ? const Center(child: CircularProgressIndicator())
            : TabBarView(
                controller: _tabController,
                children: _categories.map((category) {
                  final items = _getItemsForCategory(category['key']!);
                  if (items.isEmpty) {
                    return Center(
                      child: Text(
                        'No items available',
                        style: TextStyle(color: colors.subtleText),
                      ),
                    );
                  }
                  return RefreshIndicator(
                    onRefresh: _loadData,
                    child: GridView.builder(
                      // The nav bar floats over the body (extendBody), so
                      // reserve its height or the last row hides under it.
                      padding: EdgeInsets.fromLTRB(
                        16, 16, 16,
                        16 + 62 + MediaQuery.paddingOf(context).bottom,
                      ),
                      gridDelegate:
                          const SliverGridDelegateWithFixedCrossAxisCount(
                        crossAxisCount: 2,
                        crossAxisSpacing: 12,
                        mainAxisSpacing: 12,
                        childAspectRatio: 0.8,
                      ),
                      itemCount: items.length,
                      itemBuilder: (context, index) =>
                          _buildShopCard(items[index]),
                    ),
                  );
                }).toList(),
              ),
      ),
    );
  }

  Widget _buildShopCard(ShopItem item) {
    final colors = AppColors.of(context);
    final canAfford = _coinBalance >= item.cost;
    final isAchievementGated = item.unlockAchievementId != null;
    final isLevelLocked = _isLevelLocked(item);
    final isLocked = !item.isOwned && (isAchievementGated || isLevelLocked);
    final isTappable = item.isOwned || !isLocked;
    return GestureDetector(
      onTap: isTappable ? () => _purchaseItem(item) : null,
      child: Container(
        decoration: BoxDecoration(
          color: colors.cardBackground,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: item.isOwned
                ? colors.successGreen
                : colors.divider,
            width: item.isOwned ? 2 : 1,
          ),
          boxShadow: [
            BoxShadow(
                color: Colors.black.withOpacity(0.05),
                blurRadius: 8,
                offset: const Offset(0, 2)),
          ],
        ),
        child: Column(
          children: [
            // Item preview
            Expanded(
              child: Container(
                decoration: BoxDecoration(
                  color: item.isOwned
                      ? colors.successGreen.withOpacity(0.12)
                      : colors.sectionBackground,
                  borderRadius:
                      const BorderRadius.vertical(top: Radius.circular(15)),
                ),
                child: Stack(
                  children: [
                    Center(child: _itemPreview(item, size: 52)),
                    if (item.isOwned)
                      Positioned(
                        top: 8,
                        right: 8,
                        child: Container(
                          padding: const EdgeInsets.all(4),
                          decoration: BoxDecoration(
                            color: colors.successGreen,
                            shape: BoxShape.circle,
                          ),
                          child: const Icon(Icons.check,
                              color: Colors.white, size: 12),
                        ),
                      ),
                    if (!item.isOwned && (isLocked || !canAfford))
                      Positioned.fill(
                        child: Container(
                          decoration: BoxDecoration(
                            color: Colors.black.withOpacity(0.05),
                            borderRadius: const BorderRadius.vertical(
                                top: Radius.circular(15)),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
            // Item info
            Padding(
              padding: const EdgeInsets.all(10),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(item.name,
                      style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                          color: Theme.of(context).colorScheme.onSurface),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis),
                  const SizedBox(height: 6),
                  if (item.isOwned)
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(
                        color: colors.successGreen,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: const Text('Equip',
                          style: TextStyle(
                              color: Colors.white,
                              fontSize: 12,
                              fontWeight: FontWeight.w600)),
                    )
                  else if (isAchievementGated)
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Not purchasable',
                            style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w700,
                                color: colors.subtleText)),
                        Text(
                            item.unlockAchievementName ?? 'Achievement locked',
                            style: TextStyle(
                                fontSize: 11, color: colors.subtleText),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis),
                      ],
                    )
                  else if (isLevelLocked)
                    Row(
                      children: [
                        Icon(Icons.lock_outline,
                            size: 13, color: colors.subtleText),
                        const SizedBox(width: 4),
                        Text('Locked · Lvl ${item.unlockLevel}',
                            style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w700,
                                color: colors.subtleText)),
                      ],
                    )
                  else
                    Row(
                      children: [
                        const Text('🪙', style: TextStyle(fontSize: 13)),
                        const SizedBox(width: 4),
                        Text('${item.cost}',
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w700,
                              color: canAfford
                                  ? const Color(0xFFD97706)
                                  : colors.subtleText,
                            )),
                        if (!canAfford) ...[
                          const Spacer(),
                          Icon(Icons.lock_outline,
                              size: 14, color: colors.subtleText),
                        ],
                      ],
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}