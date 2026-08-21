// Locks the clay recipe: the stack must stay separated and correctly ordered on
// every accent, and Emerald Ink must land on (near) the values it hardcoded
// before the tokens were derived. A new skin that collapses the stack — or a
// retuned offset that flattens it — fails here rather than on a device.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gym_buddy_app/theme/app_theme.dart';

String hex(Color c) =>
    '#${c.toARGB32().toRadixString(16).padLeft(8, '0').substring(2).toUpperCase()}';

double lightness(Color c) => HSLColor.fromColor(c).lightness;

void main() {
  test('Emerald Ink stays within a hair of its old hardcoded clay set', () {
    final c = AppColors.fromAccent(AccentPalette.emeraldInk);
    final was = {
      'clayBg': const Color(0xFF163828),
      'claySurface': const Color(0xFF1D4A35),
      'claySurfaceLight': const Color(0xFF245A41),
    };
    final now = {
      'clayBg': c.clayBg,
      'claySurface': c.claySurface,
      'claySurfaceLight': c.claySurfaceLight,
    };
    for (final k in was.keys) {
      final ratio = AppColors.contrastRatio(was[k]!, now[k]!);
      debugPrint('$k  was ${hex(was[k]!)} -> now ${hex(now[k]!)}  '
          'contrast between them ${ratio.toStringAsFixed(3)}:1');
      // Under 1.06:1 means the two are within ~5% relative luminance of each
      // other — the residual is the hue drift between the authored clay set
      // (H152) and palette.background (H165), not a lightness change.
      expect(ratio, lessThan(1.06), reason: '$k drifted too far');
      // The lightness recipe itself must be exact.
      expect(lightness(now[k]!), closeTo(lightness(was[k]!), 0.005));
    }
  });

  test('every accent gets a separated, correctly ordered clay stack', () {
    for (final accent in AccentTheme.values) {
      final p = AccentPalette.forTheme(accent);
      final c = AppColors.fromAccent(p);
      final slabVsPage = AppColors.contrastRatio(c.claySurface, c.clayBg);

      debugPrint('${p.name.padRight(12)} bg ${hex(p.background)} -> '
          'clayBg ${hex(c.clayBg)} surface ${hex(c.claySurface)} '
          'edge ${hex(c.claySurfaceLight)} | slab/page '
          '${slabVsPage.toStringAsFixed(2)}:1 | shadow black@'
          '${(c.clayShadowDark.a * 100).toStringAsFixed(1)}% white@'
          '${(c.clayShadowLight.a * 100).toStringAsFixed(1)}% | inkMuted on slab '
          '${AppColors.contrastRatio(c.inkMuted, c.claySurface).toStringAsFixed(2)}:1');

      // The slab must not melt into the page (the failure mode on light accents,
      // where an upward-only recipe clamps all three steps to white).
      expect(slabVsPage, greaterThan(1.08), reason: '${p.name}: flat stack');
      // The lit edge is a highlight: always lighter than its own slab.
      expect(lightness(c.claySurfaceLight),
          greaterThan(lightness(c.claySurface)),
          reason: '${p.name}: edge is not lit');
      // Body text has to survive on the slab.
      expect(AppColors.contrastRatio(p.primaryText, c.claySurface),
          greaterThan(4.5), reason: '${p.name}: primaryText fails AA on clay');
    }
  });

  test('clay shadow tracks surface luminance, not the accent name', () {
    final light = AppColors.fromAccent(AccentPalette.signalBlue);
    final dark = AppColors.fromAccent(AccentPalette.emeraldInk);
    // Harsh black backs off and the white rim comes up as the slab gets lighter.
    expect(light.clayShadowDark.a, lessThan(dark.clayShadowDark.a));
    expect(light.clayShadowLight.a, greaterThan(dark.clayShadowLight.a));
    // Emerald must not visibly shift from the 35% / 6% it shipped with.
    expect(dark.clayShadowDark.a, closeTo(0.35, 0.02));
    expect(dark.clayShadowLight.a, closeTo(0.06, 0.06));
  });

  // The accent picker used to carry these strings and hexes inline. It now reads
  // them off the palette; this pins the swap as byte-identical, and pins the
  // order the picker renders in (it iterates AccentTheme.values).
  test('picker metadata matches the hardcoded list it replaced', () {
    expect(AccentTheme.values,
        [AccentTheme.signalBlue, AccentTheme.limeSpark, AccentTheme.emeraldInk]);

    const was = [
      ('Signal blue', 'Bold electric blue', Color(0xFF0057FF)),
      ('Lime spark', 'Dark with lime accents', Color(0xFFB6FF2E)),
      ('Emerald ink', 'Deep green with cream', Color(0xFF064E3B)),
    ];
    for (var i = 0; i < AccentTheme.values.length; i++) {
      final p = AccentPalette.forTheme(AccentTheme.values[i]);
      expect((p.name, p.description, p.swatch), was[i]);
      // Swatch must stay legible against the option row's border.
      expect(p.swatch.a, 1.0);
    }

    // All three options must be visually distinct from each other.
    final swatches =
        AccentTheme.values.map((t) => AccentPalette.forTheme(t).swatch).toList();
    expect(swatches.toSet().length, 3);
  });
}
