import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../theme/app_theme.dart';

/// Generic locked/unlocked/selected tile — same visual treatment
/// AvatarPickerScreen uses for its earnable-avatar grid (dimmed emoji +
/// lock badge + caption), reused here for all three Wardrobe categories.
class WardrobeTile extends StatelessWidget {
  final Widget preview;
  final String label;
  final bool selected;
  final bool locked;
  final String? caption;
  final Color accentColor;
  final VoidCallback? onTap;

  const WardrobeTile({
    super.key,
    required this.preview,
    required this.label,
    required this.selected,
    required this.locked,
    required this.accentColor,
    this.caption,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final appColors = AppColors.of(context);
    return GestureDetector(
      onTap: locked || onTap == null
          ? null
          : () {
              HapticFeedback.selectionClick();
              onTap!();
            },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 4),
        decoration: BoxDecoration(
          color: selected
              ? accentColor.withOpacity(0.1)
              : appColors.cardBackground,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: selected ? accentColor : appColors.cardBorder,
            width: selected ? 2 : 1,
          ),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Stack(
              alignment: Alignment.topRight,
              children: [
                Opacity(opacity: locked ? 0.4 : 1.0, child: preview),
                if (locked)
                  Container(
                    padding: const EdgeInsets.all(2),
                    decoration: BoxDecoration(
                        color: appColors.cardBackground, shape: BoxShape.circle),
                    child: Icon(Icons.lock_rounded,
                        size: 12, color: appColors.subtleText),
                  ),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                color: locked
                    ? appColors.subtleText
                    : (selected
                        ? accentColor
                        : Theme.of(context).colorScheme.onSurface),
              ),
            ),
            if (caption != null) ...[
              const SizedBox(height: 2),
              Text(
                caption!,
                textAlign: TextAlign.center,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 9, color: appColors.subtleText, height: 1.3),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
