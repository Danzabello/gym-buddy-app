import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../data/avatar_catalog.dart';
import '../../theme/app_theme.dart';
import '../../widgets/avatar_picker_screen.dart' show AvatarBorderStyle;
import 'wardrobe_avatar_render.dart';
import 'wardrobe_preview_header.dart';
import 'wardrobe_selection_state.dart';
import 'wardrobe_tile.dart';

class WardrobeAvatarScreen extends StatelessWidget {
  const WardrobeAvatarScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final state = context.watch<WardrobeSelectionState>();
    final appColors = AppColors.of(context);

    return Scaffold(
      backgroundColor: appColors.sectionBackground,
      appBar: AppBar(title: const Text('Avatar')),
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
            itemCount: avatarCatalog.length,
            itemBuilder: (_, i) {
              final a = avatarCatalog[i];
              final locked = !a.isStarter && !state.unlockedAvatarIds.contains(a.id);
              return WardrobeTile(
                selected: state.avatarId == a.id,
                locked: locked,
                accentColor: appColors.avatarRing,
                label: a.name,
                caption: locked ? a.unlockReq : null,
                preview: WardrobeAvatarRender(
                  emoji: a.emoji,
                  borderStyle: AvatarBorderStyle.simple,
                  borderColor: a.borderColor,
                  bgColor: appColors.tint(a.color),
                  size: 56,
                ),
                onTap: () => state.setAvatar(a.id),
              );
            },
          ),
        ],
      ),
    );
  }
}
