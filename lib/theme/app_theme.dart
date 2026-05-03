// lib/theme/app_theme.dart

import 'package:flutter/material.dart';

/// All custom colour tokens that don't map to standard Material slots.
/// Access via: AppColors.of(context).cardBackground etc.
class AppColors extends ThemeExtension<AppColors> {
  final Color cardBackground;
  final Color cardBorder;
  final Color sectionBackground;
  final Color subtleText;
  final Color divider;
  final Color inputFill;
  final Color streakOrange;
  final Color successGreen;
  final Color avatarRing;

  const AppColors({
    required this.cardBackground,
    required this.cardBorder,
    required this.sectionBackground,
    required this.subtleText,
    required this.divider,
    required this.inputFill,
    required this.streakOrange,
    required this.successGreen,
    required this.avatarRing,
  });

  static AppColors of(BuildContext context) =>
      Theme.of(context).extension<AppColors>()!;

  @override
  AppColors copyWith({
    Color? cardBackground,
    Color? cardBorder,
    Color? sectionBackground,
    Color? subtleText,
    Color? divider,
    Color? inputFill,
    Color? streakOrange,
    Color? successGreen,
    Color? avatarRing,
  }) {
    return AppColors(
      cardBackground: cardBackground ?? this.cardBackground,
      cardBorder: cardBorder ?? this.cardBorder,
      sectionBackground: sectionBackground ?? this.sectionBackground,
      subtleText: subtleText ?? this.subtleText,
      divider: divider ?? this.divider,
      inputFill: inputFill ?? this.inputFill,
      streakOrange: streakOrange ?? this.streakOrange,
      successGreen: successGreen ?? this.successGreen,
      avatarRing: avatarRing ?? this.avatarRing,
    );
  }

  @override
  AppColors lerp(AppColors? other, double t) {
    if (other is! AppColors) return this;
    return AppColors(
      cardBackground: Color.lerp(cardBackground, other.cardBackground, t)!,
      cardBorder: Color.lerp(cardBorder, other.cardBorder, t)!,
      sectionBackground: Color.lerp(sectionBackground, other.sectionBackground, t)!,
      subtleText: Color.lerp(subtleText, other.subtleText, t)!,
      divider: Color.lerp(divider, other.divider, t)!,
      inputFill: Color.lerp(inputFill, other.inputFill, t)!,
      streakOrange: Color.lerp(streakOrange, other.streakOrange, t)!,
      successGreen: Color.lerp(successGreen, other.successGreen, t)!,
      avatarRing: Color.lerp(avatarRing, other.avatarRing, t)!,
    );
  }

  // ── Light tokens ──────────────────────────────────────────────
  static const light = AppColors(
    cardBackground:    Color(0xFFFFFFFF),
    cardBorder:        Color(0xFFE5E7EB),
    sectionBackground: Color(0xFFF0F2F7),
    subtleText:        Color(0xFF9CA3AF),
    divider:           Color(0xFFE5E7EB),
    inputFill:         Color(0xFFF9FAFB),
    streakOrange:      Color(0xFFFF6B35),
    successGreen:      Color(0xFF10B981),
    avatarRing:        Color(0xFF3B82F6),
  );

  // ── Dark tokens ───────────────────────────────────────────────
  static const dark = AppColors(
    cardBackground:    Color(0xFF1E1E2E),
    cardBorder:        Color(0xFF2A2A3E),
    sectionBackground: Color(0xFF13131F),
    subtleText:        Color(0xFF6B7280),
    divider:           Color(0xFF2A2A3E),
    inputFill:         Color(0xFF252535),
    streakOrange:      Color(0xFFFF6B35),
    successGreen:      Color(0xFF10B981),
    avatarRing:        Color(0xFF4D9FFF),
  );
}

class AppTheme {
  AppTheme._();

  static const _seedColor = Color(0xFF3B82F6); // brand blue

  // ── Light theme ───────────────────────────────────────────────
  static ThemeData get light => ThemeData(
    useMaterial3: true,
    brightness: Brightness.light,
    colorScheme: ColorScheme.fromSeed(
      seedColor: _seedColor,
      brightness: Brightness.light,
    ),
    scaffoldBackgroundColor: const Color(0xFFF0F2F7),
    cardColor: Colors.white,
    dividerColor: const Color(0xFFE5E7EB),
    appBarTheme: const AppBarTheme(
      backgroundColor: Colors.transparent,
      elevation: 0,
      foregroundColor: Color(0xFF1A1A2E),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: const Color(0xFFF9FAFB),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: Color(0xFFE5E7EB)),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: Color(0xFFE5E7EB)),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: _seedColor, width: 2),
      ),
    ),
    extensions: const [AppColors.light],
  );

  // ── Dark theme ────────────────────────────────────────────────
  static ThemeData get dark => ThemeData(
    useMaterial3: true,
    brightness: Brightness.dark,
    colorScheme: ColorScheme.fromSeed(
      seedColor: _seedColor,
      brightness: Brightness.dark,
    ),
    scaffoldBackgroundColor: const Color(0xFF0F0F1A),
    cardColor: const Color(0xFF1E1E2E),
    dividerColor: const Color(0xFF2A2A3E),
    appBarTheme: const AppBarTheme(
      backgroundColor: Colors.transparent,
      elevation: 0,
      foregroundColor: Colors.white,
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: const Color(0xFF252535),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: Color(0xFF2A2A3E)),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: Color(0xFF2A2A3E)),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: _seedColor, width: 2),
      ),
    ),
    extensions: const [AppColors.dark],
  );
}