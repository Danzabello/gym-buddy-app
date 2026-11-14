import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../theme/app_theme.dart';
import '../utils/workout_time.dart';

/// Two tiers, theme-driven: short sessions (and an unknown duration) read as
/// neutral, longer ones get the accent nod.
Color durationColor(BuildContext context, int? minutes) {
  final appColors = AppColors.of(context);
  if (minutes == null) return appColors.subtleText;
  if (minutes <= 30) return appColors.subtleText;
  return appColors.streakOrange; // resolves to accentPalette.action
}

/// The "Set Duration" bottom sheet of the two schedule sheets: a slider and
/// quick-pick chips, starting at [initial]. [onSet] receives the chosen
/// minutes when the button is tapped, just before the sheet closes.
Future<void> showCustomDurationDialog(
  BuildContext context, {
  required int initial,
  required ValueChanged<int> onSet,
}) {
  int tempDuration = initial;

  return showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (sheetContext) {
      final appColors = AppColors.of(sheetContext);
      return StatefulBuilder(
        builder: (sheetContext, setSheetState) {
          final dialColor = durationColor(context, tempDuration);
          return Container(
          padding: EdgeInsets.fromLTRB(
            24, 20, 24, MediaQuery.of(sheetContext).padding.bottom + 20,
          ),
          decoration: BoxDecoration(
            color: appColors.cardBackground,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 40, height: 4,
                decoration: BoxDecoration(
                  color: appColors.divider,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(height: 20),
              Text('Set Duration',
                  style: TextStyle(
                    fontSize: 20, fontWeight: FontWeight.bold,
                    color: Theme.of(sheetContext).colorScheme.onSurface,
                  )),
              const SizedBox(height: 24),
              AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                padding: const EdgeInsets.symmetric(horizontal: 40, vertical: 24),
                decoration: BoxDecoration(
                  color: dialColor.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(24),
                  border: Border.all(color: dialColor.withValues(alpha: 0.4), width: 2),
                ),
                child: Text(formatDuration(tempDuration),
                    style: TextStyle(
                      fontSize: 52, fontWeight: FontWeight.bold,
                      color: dialColor,
                    )),
              ),
              const SizedBox(height: 28),
              SliderTheme(
                data: SliderTheme.of(sheetContext).copyWith(
                  activeTrackColor: dialColor,
                  inactiveTrackColor: appColors.cardBorder,
                  thumbColor: dialColor,
                  overlayColor: dialColor.withValues(alpha: 0.2),
                  trackHeight: 10,
                  thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 16),
                  overlayShape: const RoundSliderOverlayShape(overlayRadius: 28),
                ),
                child: Slider(
                  value: tempDuration.toDouble(),
                  min: 15, max: 180, divisions: 33,
                  onChanged: (value) {
                    final rounded = (value / 5).round() * 5;
                    HapticFeedback.selectionClick();
                    setSheetState(() => tempDuration = rounded);
                  },
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text('15 min', style: TextStyle(color: appColors.subtleText, fontSize: 13)),
                    Text('3 hours', style: TextStyle(color: appColors.subtleText, fontSize: 13)),
                  ],
                ),
              ),
              const SizedBox(height: 24),
              Wrap(
                spacing: 10, runSpacing: 10,
                alignment: WrapAlignment.center,
                children: [15, 30, 45, 60, 90, 120].map((mins) {
                  final isSelected = tempDuration == mins;
                  final chipColor = durationColor(context, mins);
                  return GestureDetector(
                    onTap: () {
                      HapticFeedback.lightImpact();
                      setSheetState(() => tempDuration = mins);
                    },
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 200),
                      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
                      decoration: BoxDecoration(
                        color: isSelected
                            ? chipColor.withValues(alpha: 0.15)
                            : appColors.sectionBackground,
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(
                          color: isSelected ? chipColor : appColors.cardBorder,
                          width: isSelected ? 2 : 1,
                        ),
                      ),
                      child: Text(formatDuration(mins),
                          style: TextStyle(
                            fontSize: 15, fontWeight: FontWeight.w600,
                            color: isSelected ? chipColor
                                : Theme.of(sheetContext).colorScheme.onSurface,
                          )),
                    ),
                  );
                }).toList(),
              ),
              const SizedBox(height: 28),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: () {
                    HapticFeedback.mediumImpact();
                    onSet(tempDuration);
                    Navigator.pop(sheetContext);
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: dialColor,
                      foregroundColor: appColors.readableForeground(dialColor),
                      padding: const EdgeInsets.symmetric(vertical: 18),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16)),
                    ),
                    child: const Text('Set Duration',
                        style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold)),
                  ),
                ),
              ],
            ),
          );
        },
      );
    },
  );
}
