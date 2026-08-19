// Sanity check for AppColors.tint(): every status role must clear the
// perceptibility floor as a container fill, on every accent.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gym_buddy_app/theme/app_theme.dart';

void main() {
  test('tint() clears its floor for every role on every accent', () {
    for (final accent in AccentTheme.values) {
      final p = AccentPalette.forTheme(accent);
      final c = AppColors.fromAccent(p);
      final roles = <String, Color>{
        'action': p.action,
        'statusInfo': p.statusInfo,
        'statusSuccess': p.statusSuccess,
        'statusDanger': p.statusDanger,
        'statusWarning': p.statusWarning,
      };
      for (final e in roles.entries) {
        final surface = c.cardBackground;
        final tinted = c.tint(e.value);
        final ratio = AppColors.contrastRatio(tinted, surface);

        // recover the alpha the helper settled on, for reporting
        var alpha = 1.0;
        for (var s = 8; s <= 100; s++) {
          final cand = Color.alphaBlend(e.value.withValues(alpha: s / 100), surface);
          if (AppColors.contrastRatio(cand, surface) >= 1.5) { alpha = s / 100; break; }
        }
        final old = AppColors.contrastRatio(
            Color.alphaBlend(e.value.withValues(alpha: 0.12), surface), surface);
        // ignore: avoid_print
        print('${accent.name.padRight(11)} ${e.key.padRight(14)} '
            'old 0.12 -> ${old.toStringAsFixed(2)}x   '
            'new ${alpha.toStringAsFixed(2)} -> ${ratio.toStringAsFixed(2)}x');

        expect(ratio, greaterThanOrEqualTo(1.5),
            reason: '${accent.name}/${e.key} below floor');
      }
    }
  });

  test('rarity pill label clears 4.5:1 on the tinted fill, all 4 tiers', () {
    for (final accent in AccentTheme.values) {
      final p = AccentPalette.forTheme(accent);
      final c = AppColors.fromAccent(p);
      // mirrors _rarityBg / _rarityFloor in achievements_page.dart
      const floors = {
        'uncommon': 1.5, 'rare': 1.8, 'epic': 2.1, 'legendary': 2.1,
      };
      for (final e in floors.entries) {
        final hue = e.key == 'legendary'
            ? const Color(0xFFD97706)   // fixed top-tier hue
            : p.statusInfo;
        final pill = c.tint(hue, floor: e.value);
        final label = p.primaryText;    // == colorScheme.onSurface
        final ratio = AppColors.contrastRatio(label, pill);
        // ignore: avoid_print
        print('${accent.name.padRight(11)} ${e.key.padRight(10)} '
            'label vs pill ${ratio.toStringAsFixed(2)}x');
        expect(ratio, greaterThanOrEqualTo(4.5),
            reason: '${accent.name}/${e.key} label unreadable on pill');
      }
    }
  });

  test('floor is overridable per call', () {
    final c = AppColors.fromAccent(AccentPalette.emeraldInk);
    final soft = c.tint(AccentPalette.emeraldInk.statusInfo, floor: 1.2);
    final hard = c.tint(AccentPalette.emeraldInk.statusInfo, floor: 2.0);
    expect(AppColors.contrastRatio(soft, c.cardBackground),
        greaterThanOrEqualTo(1.2));
    expect(AppColors.contrastRatio(hard, c.cardBackground),
        greaterThanOrEqualTo(2.0));
    expect(soft, isNot(equals(hard)));
  });
}
