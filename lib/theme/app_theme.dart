// lib/theme/app_theme.dart

import 'package:flutter/material.dart';

enum AccentTheme { signalBlue, limeSpark, emeraldInk }

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

  // ── Clay tokens (claymorphism) ────────────────────────────────
  final Color clayShadowDark;
  final Color clayShadowLight;
  final Color clayBg;
  final Color claySurface;
  final Color claySurfaceLight;
  final Color inkMuted;
  final Color info;
  final Color success;
  final Color warn;

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
    // Clay tokens default to the emerald clay set; they don't vary by accent
    // theme yet, so light/dark/fromAccent inherit them untouched.
    this.clayShadowDark   = const Color(0x59000000), // black @ 35%
    this.clayShadowLight  = const Color(0x0FFFFFFF), // white @ 6%
    this.clayBg           = const Color(0xFF163828),
    this.claySurface      = const Color(0xFF1D4A35),
    this.claySurfaceLight = const Color(0xFF245A41),
    this.inkMuted         = const Color(0xFFC3D8CB),
    this.info             = const Color(0xFF5B93F2),
    this.success          = const Color(0xFF4ADE80),
    this.warn             = const Color(0xFFFBBF24),
  });

  factory AppColors.fromAccent(AccentPalette p) => AppColors(
    cardBackground: p.cardBackground,
    cardBorder: p.cardBorder,
    sectionBackground: p.sectionBackground,
    subtleText: p.subtleText,
    divider: p.divider,
    inputFill: p.inputFill,
    streakOrange: p.action,
    successGreen: p.statusSuccess,
    avatarRing: p.avatarRing,
  );

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
    Color? clayShadowDark,
    Color? clayShadowLight,
    Color? clayBg,
    Color? claySurface,
    Color? claySurfaceLight,
    Color? inkMuted,
    Color? info,
    Color? success,
    Color? warn,
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
      clayShadowDark: clayShadowDark ?? this.clayShadowDark,
      clayShadowLight: clayShadowLight ?? this.clayShadowLight,
      clayBg: clayBg ?? this.clayBg,
      claySurface: claySurface ?? this.claySurface,
      claySurfaceLight: claySurfaceLight ?? this.claySurfaceLight,
      inkMuted: inkMuted ?? this.inkMuted,
      info: info ?? this.info,
      success: success ?? this.success,
      warn: warn ?? this.warn,
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
      clayShadowDark: Color.lerp(clayShadowDark, other.clayShadowDark, t)!,
      clayShadowLight: Color.lerp(clayShadowLight, other.clayShadowLight, t)!,
      clayBg: Color.lerp(clayBg, other.clayBg, t)!,
      claySurface: Color.lerp(claySurface, other.claySurface, t)!,
      claySurfaceLight: Color.lerp(claySurfaceLight, other.claySurfaceLight, t)!,
      inkMuted: Color.lerp(inkMuted, other.inkMuted, t)!,
      info: Color.lerp(info, other.info, t)!,
      success: Color.lerp(success, other.success, t)!,
      warn: Color.lerp(warn, other.warn, t)!,
    );
  }

  /// Dual clay shadow used by every claymorphic surface.
  /// [inset] swaps the offsets so the surface reads pressed — Flutter's
  /// BoxShadow has no true inset, this is the standard stand-in.
  List<BoxShadow> clayShadow({bool inset = false}) => [
    BoxShadow(
      color: clayShadowDark,
      offset: inset ? const Offset(-6, -6) : const Offset(6, 6),
      blurRadius: 14,
    ),
    BoxShadow(
      color: clayShadowLight,
      offset: inset ? const Offset(4, 4) : const Offset(-4, -4),
      blurRadius: 10,
    ),
  ];

  /// CTA gradient stops, derived from the single brand-orange source
  /// (`streakOrange`, which resolves to `AccentPalette.action` / #EA580C).
  /// Never hardcode a second orange — change `action` and this follows.
  List<Color> get actionGradient => [
    Color.lerp(streakOrange, Colors.white, 0.15)!,
    streakOrange,
  ];

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

class AccentPalette {
  final Color background;
  final Color cardBackground;
  final Color cardBorder;
  final Color sectionBackground;
  final Color primaryText;
  final Color subtleText;
  final Color divider;
  final Color inputFill;
  final Color statusInfo;
  final Color statusSuccess;
  final Color statusDanger;
  final Color statusWarning;
  final Color action;
  final Color heroBackground;
  final Color heroText;
  final Color heroTextMuted;
  final Color avatarRing;
  final Color accentIcon;

  const AccentPalette({
    required this.background,
    required this.cardBackground,
    required this.cardBorder,
    required this.sectionBackground,
    required this.primaryText,
    required this.subtleText,
    required this.divider,
    required this.inputFill,
    required this.statusInfo,
    required this.statusSuccess,
    required this.statusDanger,
    required this.statusWarning,
    required this.action,
    required this.heroBackground,
    required this.heroText,
    required this.heroTextMuted,
    required this.avatarRing,
    required this.accentIcon,
  });

  static const emeraldInk = AccentPalette(
    background: Color(0xFF0B1F1A),
    cardBackground: Color(0xFF123328),
    cardBorder: Color(0xFF1F4A3A),
    sectionBackground: Color(0xFF0F291F),
    primaryText: Color(0xFFF8E7C9),
    subtleText: Color(0xFFB9CFC3),
    divider: Color(0xFF1F4A3A),
    inputFill: Color(0xFF123328),
    statusInfo: Color(0xFF5FA396),
    statusSuccess: Color(0xFF10B981),
    statusDanger: Color(0xFFF87171),   // 6.20:1 on background
    statusWarning: Color(0xFFFBBF24),  // 10.27:1 on background
    action: Color(0xFFEA580C),
    heroBackground: Color(0xFF064E3B),
    heroText: Color(0xFFF8E7C9),
    heroTextMuted: Color(0xFFB9CFC3),
    avatarRing: Color(0xFFF8E7C9),
    accentIcon: Color(0xFFF8E7C9),
  );

  static const signalBlue = AccentPalette(
    background: Color(0xFFF8F7F4),
    cardBackground: Color(0xFFFFFFFF),
    cardBorder: Color(0xFFE5E7EB),
    sectionBackground: Color(0xFFF0F2F7),
    primaryText: Color(0xFF1A1A2E),
    subtleText: Color(0xFF6B7280),
    divider: Color(0xFFE5E7EB),
    inputFill: Color(0xFFF9FAFB),
    statusInfo: Color(0xFF0B84A5),
    statusSuccess: Color(0xFF10B981),
    statusDanger: Color(0xFFDC2626),   // 4.51:1 on light background
    statusWarning: Color(0xFFB45309),  // 4.69:1 — amber must go dark on light
    action: Color(0xFFEA580C),
    heroBackground: Color(0xFF0057FF),
    heroText: Color(0xFFF8F7F4),
    heroTextMuted: Color(0xFFC7D6FF),
    avatarRing: Color(0xFF0057FF),
    accentIcon: Color(0xFF0057FF),
  );

  static const limeSpark = AccentPalette(
    background: Color(0xFF1A1D24),
    cardBackground: Color(0xFF23262F),
    cardBorder: Color(0xFF2E323C),
    sectionBackground: Color(0xFF1E212A),
    primaryText: Color(0xFFEDEEF0),
    subtleText: Color(0xFF9A9EA8),
    divider: Color(0xFF2E323C),
    inputFill: Color(0xFF23262F),
    statusInfo: Color(0xFF8B8FFF),
    statusSuccess: Color(0xFF4ADE80),
    statusDanger: Color(0xFFF87171),   // 6.10:1 — red-400, matches 400 family
    statusWarning: Color(0xFFFBBF24),  // 10.10:1 on background
    action: Color(0xFFEA580C),
    heroBackground: Color(0xFF23262F),
    heroText: Color(0xFFEDEEF0),
    heroTextMuted: Color(0xFFB6FF2E),
    avatarRing: Color(0xFFB6FF2E),
    accentIcon: Color(0xFFB6FF2E),
  );

  static AccentPalette forTheme(AccentTheme theme) => switch (theme) {
    AccentTheme.signalBlue => signalBlue,
    AccentTheme.limeSpark => limeSpark,
    AccentTheme.emeraldInk => emeraldInk,
  };
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

  // ── Accent-driven theme ───────────────────────────────────────
  static ThemeData fromAccent(AccentPalette palette) {
    final brightness = ThemeData.estimateBrightnessForColor(palette.background);
    return ThemeData(
      useMaterial3: true,
      brightness: brightness,
      colorScheme: ColorScheme.fromSeed(
        seedColor: palette.heroBackground,
        brightness: brightness,
      ).copyWith(
        onSurface: palette.primaryText,
        surface: palette.cardBackground,
        primary: palette.avatarRing,
      ),
      scaffoldBackgroundColor: palette.background,
      cardColor: palette.cardBackground,
      dividerColor: palette.divider,
      appBarTheme: AppBarTheme(
        backgroundColor: Colors.transparent,
        elevation: 0,
        foregroundColor: palette.primaryText,
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: palette.inputFill,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: palette.cardBorder),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: palette.cardBorder),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: palette.avatarRing, width: 2),
        ),
      ),
      extensions: [AppColors.fromAccent(palette)],
    );
  }
}