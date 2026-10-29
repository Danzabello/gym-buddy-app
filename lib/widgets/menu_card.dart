import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../theme/app_theme.dart';
import '../utils/run_once.dart';

class MenuItem {
  final String? emoji;
  final IconData? icon;
  final Color? iconColor;
  final Color color;
  final String label;
  final Color? labelColor;
  final String? sub;
  final bool showChevron;
  /// Return the push/show future so a repeat tap is ignored until it is dismissed.
  final FutureOr<void> Function()? onTap;

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
          color: Colors.black.withValues(alpha: 0.04),
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
            _GuardedInkWell(
              onTap: item.onTap,
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

/// InkWell whose tap is ignored while the previous tap's action is running.
class _GuardedInkWell extends StatefulWidget {
  final FutureOr<void> Function()? onTap;
  final BorderRadius borderRadius;
  final Widget child;

  const _GuardedInkWell({required this.onTap, required this.borderRadius, required this.child});

  @override
  State<_GuardedInkWell> createState() => _GuardedInkWellState();
}

class _GuardedInkWellState extends State<_GuardedInkWell> {
  final _once = RunOnce();

  @override
  void dispose() {
    _once.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final onTap = widget.onTap;
    return InkWell(
      onTap: onTap == null
          ? null
          : () => _once.run(() {
                HapticFeedback.selectionClick();
                return onTap();
              }),
      borderRadius: widget.borderRadius,
      child: widget.child,
    );
  }
}
