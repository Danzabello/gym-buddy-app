import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

/// Two tiers, theme-driven: short sessions (and an unknown duration) read as
/// neutral, longer ones get the accent nod.
Color durationColor(BuildContext context, int? minutes) {
  final appColors = AppColors.of(context);
  if (minutes == null) return appColors.subtleText;
  if (minutes <= 30) return appColors.subtleText;
  return appColors.streakOrange; // resolves to accentPalette.action
}
