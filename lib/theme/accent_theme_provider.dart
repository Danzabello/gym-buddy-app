// lib/theme/accent_theme_provider.dart

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'app_theme.dart';

class AccentThemeProvider extends ChangeNotifier {
  static const _key = 'accent_theme';

  AccentTheme _accentTheme = AccentTheme.emeraldInk;
  AccentTheme get accentTheme => _accentTheme;
  AccentPalette get palette => AccentPalette.forTheme(_accentTheme);

  AccentThemeProvider() {
    _load();
  }

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    final saved = prefs.getString(_key);
    _accentTheme = AccentTheme.values.firstWhere(
      (e) => e.name == saved,
      orElse: () => AccentTheme.emeraldInk,
    );
    notifyListeners();
  }

  Future<void> setAccentTheme(AccentTheme theme) async {
    _accentTheme = theme;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_key, theme.name);
  }
}
