import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../data/avatar_catalog.dart';
import '../../theme/app_theme.dart';
import 'wardrobe_avatar_render.dart';
import 'wardrobe_selection_state.dart';

/// Persistent header shown on the Wardrobe hub and all three sub-screens —
/// composited icon + border + ring preview that updates live as the user
/// taps around, since it just reads from the shared [WardrobeSelectionState].
class WardrobePreviewHeader extends StatelessWidget {
  const WardrobePreviewHeader({super.key});

  @override
  Widget build(BuildContext context) {
    final state = context.watch<WardrobeSelectionState>();
    final appColors = AppColors.of(context);
    final avatar = avatarCatalogById(state.avatarId);
    final ringColor = state.ringItem?.colorHex != null
        ? hexToColor(state.ringItem!.colorHex!)
        : appColors.avatarRing;
    final ringName = state.ringItem?.name.replaceAll(' Ring', '') ?? 'Default';

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 24),
      decoration: BoxDecoration(
        color: appColors.claySurface,
        borderRadius: BorderRadius.circular(20),
        boxShadow: appColors.clayShadow(),
      ),
      child: Column(
        children: [
          Container(
            width: 132,
            height: 132,
            padding: const EdgeInsets.all(6),
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(color: ringColor, width: 6),
            ),
            child: WardrobeAvatarRender(
              emoji: avatar.emoji,
              borderStyle: state.border,
              borderColor: avatar.borderColor,
              bgColor: appColors.tint(avatar.color),
              size: 108,
            ),
          ),
          const SizedBox(height: 12),
          Text(
            '${avatar.name} · ${borderStyleLabel(state.border)} · $ringName',
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: appColors.inkMuted,
            ),
          ),
        ],
      ),
    );
  }
}
