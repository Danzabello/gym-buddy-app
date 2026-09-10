import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../data/avatar_catalog.dart';
import '../../theme/app_theme.dart';
import '../../widgets/avatar_picker_screen.dart' show AvatarBorderStyle;
import 'wardrobe_avatar_render.dart';
import 'wardrobe_preview_header.dart';
import 'wardrobe_selection_state.dart';
import 'wardrobe_tile.dart';

// Border unlock thresholds — hardcoded the same way AvatarPickerScreen
// hardcodes its "Bold border unlocks at Level 3" / "...Level 7" toasts;
// there's no DB-backed unlock_level for these two shop_item_id rows.
const Map<AvatarBorderStyle, int> _borderUnlockLevel = {
  AvatarBorderStyle.bold: 3,
  AvatarBorderStyle.arc: 7,
};

class WardrobeBorderScreen extends StatelessWidget {
  const WardrobeBorderScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final state = context.watch<WardrobeSelectionState>();
    final appColors = AppColors.of(context);
    final avatar = avatarCatalogById(state.avatarId);

    return Scaffold(
      backgroundColor: appColors.sectionBackground,
      appBar: AppBar(title: const Text('Border')),
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
            itemCount: AvatarBorderStyle.values.length,
            itemBuilder: (_, i) {
              final style = AvatarBorderStyle.values[i];
              final locked = style != AvatarBorderStyle.simple &&
                  !state.unlockedBorderIds.contains(style.name);
              return WardrobeTile(
                selected: state.border == style,
                locked: locked,
                accentColor: appColors.avatarRing,
                label: borderStyleLabel(style),
                caption: locked ? 'Level ${_borderUnlockLevel[style]}' : null,
                preview: WardrobeAvatarRender(
                  emoji: avatar.emoji,
                  borderStyle: style,
                  borderColor: avatar.borderColor,
                  bgColor: appColors.tint(avatar.color),
                  size: 56,
                ),
                onTap: () => state.setBorder(style),
              );
            },
          ),
        ],
      ),
    );
  }
}
