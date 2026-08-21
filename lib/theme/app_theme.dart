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
    // Fallbacks for the legacy `light` / `dark` themes, which have no accent
    // palette to derive from. `fromAccent` computes all six per accent.
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

  /// Lightness offsets (HSL points /100) that define the clay stack. Measured
  /// off the Emerald Ink set these tokens used to hardcode:
  /// bg #0B1F1A (L 8.2) → clayBg #163828 (L 15.3) → claySurface #1D4A35
  /// (L 20.2) → claySurfaceLight #245A41 (L 24.7).
  static const _clayBgShift      = 0.071;
  static const _claySurfaceShift = 0.120; // 7.1 + 4.9
  static const _clayEdgeShift    = 0.045; // lit edge, always *up* from the slab

  static Color _shiftLightness(Color c, double delta) {
    final hsl = HSLColor.fromColor(c);
    return hsl.withLightness((hsl.lightness + delta).clamp(0.0, 1.0)).toColor();
  }

  factory AppColors.fromAccent(AccentPalette p) {
    // Dark accents stack the clay upward off the page. Light accents have no
    // headroom above (signalBlue's background is L96.5 — every step would clamp
    // to white and the stack would vanish), so they stack downward instead. The
    // lit edge is always lighter than its own slab: it's a highlight, not a step.
    final dir = p.background.computeLuminance() < 0.5 ? 1.0 : -1.0;
    final clayBg = _shiftLightness(p.background, _clayBgShift * dir);
    final claySurface = _shiftLightness(p.background, _claySurfaceShift * dir);
    final claySurfaceLight = _shiftLightness(claySurface, _clayEdgeShift);

    // Shadow strength tracks the slab's own luminance, not the accent's name,
    // so a new skin gets the right treatment for free. Black carries the drop on
    // dark clay (35%) but reads as soot on light clay, so it backs off to 12%;
    // the white rim is the inverse — 6% suffices on dark, 90% to be seen on
    // light. Lerped rather than branched: no crossover threshold to mis-tune.
    final t = claySurface.computeLuminance();

    return AppColors(
      cardBackground: p.cardBackground,
      cardBorder: p.cardBorder,
      sectionBackground: p.sectionBackground,
      subtleText: p.subtleText,
      divider: p.divider,
      inputFill: p.inputFill,
      streakOrange: p.action,
      successGreen: p.statusSuccess,
      avatarRing: p.avatarRing,
      clayBg: clayBg,
      claySurface: claySurface,
      claySurfaceLight: claySurfaceLight,
      clayShadowDark: Colors.black.withValues(alpha: 0.35 + (0.12 - 0.35) * t),
      clayShadowLight: Colors.white.withValues(alpha: 0.06 + (0.90 - 0.06) * t),
      // ponytail: subtleText is the muted ink by definition, and it clears AA on
      // the two dark accents (emerald 5.93:1, lime 4.24:1) — but only 3.52:1 on
      // signalBlue's lighter slab, i.e. AA-large, not AA-normal. Give it the
      // contrast-floor treatment `tint()` already models if Step 2 puts small
      // muted text on light clay.
      inkMuted: p.subtleText,
      // These three were left on their fixed defaults when the clay tokens were
      // derived — the palette has carried per-accent status roles all along, so
      // a skin's own info/success/warning never reached the clay surfaces.
      info: p.statusInfo,
      success: p.statusSuccess,
      warn: p.statusWarning,
    );
  }

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

  /// A role colour composited over [surface] at the lowest alpha that still
  /// reads as a distinct container — at least [floor] contrast against the
  /// surface it sits on. Returns the finished opaque colour, so call sites can
  /// drop it straight into `color:` with no further maths.
  ///
  /// Why this isn't a constant: a flat 12% tint lands at only ~1.1–1.3:1 on
  /// *every* accent (light included), which is why tinted chips and icon tiles
  /// were rendering near-invisible. The required alpha depends on both the role
  /// and the surface, so it has to be computed, not hardcoded. Solving it here
  /// means a new accent or a retuned surface can't silently break call sites.
  ///
  /// [surface] defaults to [cardBackground], the usual host for a tinted chip.
  Color tint(Color role, {Color? surface, double floor = 1.5}) {
    final bg = surface ?? cardBackground;
    // ponytail: linear 1% scan, ~92 iterations worst case. Cheap enough at the
    // handful of tints on screen; make it a binary search if it ever shows up
    // in a frame profile.
    for (var step = 8; step <= 100; step++) {
      final candidate = Color.alphaBlend(role.withValues(alpha: step / 100), bg);
      if (contrastRatio(candidate, bg) >= floor) return candidate;
    }
    return Color.alphaBlend(role.withValues(alpha: 1), bg);
  }

  /// Whichever of white / near-black is more readable on [background].
  ///
  /// A fixed `Colors.white` foreground cannot work here: button backgrounds
  /// that come from a role vary per accent, so white passes on one accent and
  /// fails badly on another (the duration button measured 4.83:1 on signalBlue
  /// but 1.64:1 on emeraldInk). Picking per-render keeps every combination
  /// legible without pinning the background to one hue.
  Color readableForeground(Color background) {
    const dark = Color(0xFF111827); // near-black ink
    return contrastRatio(Colors.white, background) >=
            contrastRatio(dark, background)
        ? Colors.white
        : dark;
  }

  /// WCAG relative-luminance contrast ratio between two opaque colours.
  /// Same maths used to pick the per-accent status role values.
  static double contrastRatio(Color a, Color b) {
    final la = a.computeLuminance();
    final lb = b.computeLuminance();
    final hi = la > lb ? la : lb;
    final lo = la > lb ? lb : la;
    return (hi + 0.05) / (lo + 0.05);
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

class AccentPalette {
  /// Everything the settings picker needs to render this skin lives here, so
  /// adding a skin is a palette edit, never a screen edit.
  final String name;
  final String description;
  /// The single colour that identifies this skin in the picker. Deliberately
  /// its own field: it is `heroBackground` on signalBlue/emeraldInk but
  /// `avatarRing` on limeSpark (whose hero is a near-black card), so no one
  /// existing field carries it across all three. Each palette points it at the
  /// shared const it already uses, so the hex is still declared exactly once.
  final Color swatch;

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
  /// Secondary identity accent — not a status. Profile/identity rows, sheet
  /// header accents, "waiting for partner" panels. Replaces the ad-hoc
  /// brand-adjacent purple that had accumulated in several files.
  final Color secondaryAccent;
  final Color action;
  final Color heroBackground;
  final Color heroText;
  final Color heroTextMuted;
  final Color avatarRing;
  final Color accentIcon;

  const AccentPalette({
    required this.name,
    required this.description,
    required this.swatch,
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
    required this.secondaryAccent,
    required this.action,
    required this.heroBackground,
    required this.heroText,
    required this.heroTextMuted,
    required this.avatarRing,
    required this.accentIcon,
  });

  static const _emeraldDeep = Color(0xFF064E3B);

  static const emeraldInk = AccentPalette(
    name: 'Emerald ink',
    description: 'Deep green with cream',
    swatch: _emeraldDeep,
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
    secondaryAccent: Color(0xFFA78BFA), // 6.30 bg / 5.04 card
    action: Color(0xFFEA580C),
    heroBackground: _emeraldDeep,
    heroText: Color(0xFFF8E7C9),
    heroTextMuted: Color(0xFFB9CFC3),
    avatarRing: Color(0xFFF8E7C9),
    accentIcon: Color(0xFFF8E7C9),
  );

  static const _blueSignal = Color(0xFF0057FF);

  static const signalBlue = AccentPalette(
    name: 'Signal blue',
    description: 'Bold electric blue',
    swatch: _blueSignal,
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
    // the app's established purple; light accent renders these sites unchanged
    secondaryAccent: Color(0xFF7C3AED), // 5.32 bg / 5.70 card
    action: Color(0xFFEA580C),
    heroBackground: _blueSignal,
    heroText: Color(0xFFF8F7F4),
    heroTextMuted: Color(0xFFC7D6FF),
    avatarRing: _blueSignal,
    accentIcon: _blueSignal,
  );

  static const _limeSpark = Color(0xFFB6FF2E);

  static const limeSpark = AccentPalette(
    name: 'Lime spark',
    description: 'Dark with lime accents',
    swatch: _limeSpark,
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
    secondaryAccent: Color(0xFFA78BFA), // 6.20 bg / 5.55 card
    action: Color(0xFFEA580C),
    heroBackground: Color(0xFF23262F),
    heroText: Color(0xFFEDEEF0),
    heroTextMuted: _limeSpark,
    avatarRing: _limeSpark,
    accentIcon: _limeSpark,
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