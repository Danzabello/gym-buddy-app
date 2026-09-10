import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../theme/app_theme.dart';
import 'wardrobe_avatar_render.dart';
import 'wardrobe_preview_header.dart';
import 'wardrobe_selection_state.dart';
import 'wardrobe_tile.dart';

class WardrobeRingScreen extends StatelessWidget {
  const WardrobeRingScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final state = context.watch<WardrobeSelectionState>();
    final appColors = AppColors.of(context);

    return Scaffold(
      backgroundColor: appColors.sectionBackground,
      appBar: AppBar(title: const Text('Ring colour')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 32),
        children: [
          const WardrobePreviewHeader(),
          GridView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 3,
              crossAxisSpacing: 10,
              mainAxisSpacing: 10,
              childAspectRatio: 0.85,
            ),
            itemCount: state.ringItems.length,
            itemBuilder: (_, i) {
              final item = state.ringItems[i];
              final locked = !item.isOwned;
              final color = item.colorHex != null
                  ? hexToColor(item.colorHex!)
                  : appColors.avatarRing;

              final String? caption;
              if (!locked) {
                caption = null;
              } else if (item.unlockAchievementId != null) {
                caption = item.unlockAchievementName ?? 'Achievement';
              } else if (state.userLevel < item.unlockLevel) {
                caption = 'Lvl ${item.unlockLevel}';
              } else {
                caption = '🪙 ${item.cost} in Shop';
              }

              return WardrobeTile(
                selected: state.ringItem?.id == item.id,
                locked: locked,
                accentColor: color,
                label: item.name.replaceAll(' Ring', ''),
                caption: caption,
                preview: Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: color,
                    border: Border.all(color: appColors.cardBorder),
                  ),
                ),
                onTap: () => state.setRing(item),
              );
            },
          ),
        ],
      ),
    );
  }
}
