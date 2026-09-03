import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gym_buddy_app/theme/app_theme.dart';

void main() {
  group('AccentPalette.emeraldInk', () {
    test('avatarRing is the new emerald green', () {
      expect(AccentPalette.emeraldInk.avatarRing, const Color(0xFF50C878));
    });

    test('accentIcon is the new emerald green', () {
      expect(AccentPalette.emeraldInk.accentIcon, const Color(0xFF50C878));
    });
  });

  group('AccentPalette.signalBlue regression lock', () {
    test('avatarRing is unchanged', () {
      expect(AccentPalette.signalBlue.avatarRing, const Color(0xFF0057FF));
    });

    test('accentIcon is unchanged', () {
      expect(AccentPalette.signalBlue.accentIcon, const Color(0xFF0057FF));
    });
  });

  group('AccentPalette.limeSpark regression lock', () {
    test('avatarRing is unchanged', () {
      expect(AccentPalette.limeSpark.avatarRing, const Color(0xFFB6FF2E));
    });

    test('accentIcon is unchanged', () {
      expect(AccentPalette.limeSpark.accentIcon, const Color(0xFFB6FF2E));
    });
  });

  group('AccentPalette.gold', () {
    test('emeraldInk has a non-null gold field', () {
      expect(AccentPalette.emeraldInk.gold, isNotNull);
    });

    test('signalBlue has a non-null gold field', () {
      expect(AccentPalette.signalBlue.gold, isNotNull);
    });

    test('limeSpark has a non-null gold field', () {
      expect(AccentPalette.limeSpark.gold, isNotNull);
    });
  });

  group('AppColors.danger', () {
    test('fromAccent maps danger from the palette statusDanger', () {
      final colors = AppColors.fromAccent(AccentPalette.signalBlue);
      expect(colors.danger, AccentPalette.signalBlue.statusDanger);
    });
  });
}
