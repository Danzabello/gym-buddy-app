import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../theme/app_theme.dart';

class MenuItem {
  final String? emoji;
  final IconData? icon;
  final Color? iconColor;
  final Color color;
  final String label;
  final Color? labelColor;
  final String? sub;
  final bool showChevron;
  final VoidCallback? onTap;

  const MenuItem({
    this.emoji,
    this.icon,
    this.iconColor,
    required this.color,
    required this.label,
    this.labelColor,
    this.sub,
    this.showChevron = true,
    this.onTap,
  }) : assert(emoji != null || icon != null);
}

Widget buildMenuCard(BuildContext context, List<MenuItem> items) {
  final appColors = AppColors.of(context);
  return Container(
    decoration: BoxDecoration(
      color: appColors.cardBackground,
      borderRadius: BorderRadius.circular(18),
      boxShadow: [
        BoxShadow(
          color: Colors.black.withOpacity(0.04),
          blurRadius: 12,
          offset: const Offset(0, 2),
        ),
      ],
    ),
    child: Column(
      children: items.asMap().entries.map((entry) {
        final i = entry.key;
        final item = entry.value;
        return Column(
          children: [
            InkWell(
              onTap: item.onTap == null
                  ? null
                  : () {
                      HapticFeedback.selectionClick();
                      item.onTap!();
                    },
              borderRadius: BorderRadius.vertical(
                top: i == 0 ? const Radius.circular(18) : Radius.zero,
                bottom: i == items.length - 1 ? const Radius.circular(18) : Radius.zero,
              ),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                child: Row(
                  children: [
                    Container(
                      width: 36, height: 36,
                      decoration: BoxDecoration(
                        color: item.color,
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Center(
                        child: item.icon != null
                            ? Icon(item.icon, size: 18, color: item.iconColor ?? Theme.of(context).colorScheme.onSurface)
                            : Text(item.emoji!, style: const TextStyle(fontSize: 17)),
                      ),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            item.label,
                            style: TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.w600,
                              color: item.labelColor ?? Theme.of(context).colorScheme.onSurface,
                            ),
                          ),
                          if (item.sub != null) ...[
                            const SizedBox(height: 1),
                            Text(
                              item.sub!,
                              style: TextStyle(fontSize: 12, color: appColors.subtleText),
                            ),
                          ],
                        ],
                      ),
                    ),
                    if (item.showChevron)
                      Icon(Icons.chevron_right_rounded, color: appColors.subtleText, size: 20),
                  ],
                ),
              ),
            ),
            if (i < items.length - 1)
              Divider(height: 1, indent: 66, color: appColors.divider),
          ],
        );
      }).toList(),
    ),
  );
}
