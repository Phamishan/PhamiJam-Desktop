import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

enum AppThemeMode { auto, light, dark }

const String _prefsKey = 'phamijam.theme_mode';
const String _accentColorPrefsKey = 'phamijam.accent_color';

class ThemeProvider extends ChangeNotifier {
  AppThemeMode _mode = AppThemeMode.auto;
  Color? _accentColor;

  AppThemeMode get mode => _mode;
  Color? get accentColor => _accentColor;

  ThemeMode get flutterThemeMode {
    switch (_mode) {
      case AppThemeMode.auto:
        return ThemeMode.system;
      case AppThemeMode.light:
        return ThemeMode.light;
      case AppThemeMode.dark:
        return ThemeMode.dark;
    }
  }

  ThemeProvider() {
    _restore();
  }

  Future<void> _restore() async {
    final prefs = await SharedPreferences.getInstance();
    final saved = prefs.getString(_prefsKey);
    final restored = AppThemeMode.values.firstWhere(
      (m) => m.name == saved,
      orElse: () => AppThemeMode.auto,
    );
    final savedAccent = prefs.getInt(_accentColorPrefsKey);
    if (restored != _mode || savedAccent != null) {
      _mode = restored;
      if (savedAccent != null) _accentColor = Color(savedAccent);
      notifyListeners();
    }
  }

  Future<void> setMode(AppThemeMode mode) async {
    if (mode == _mode) return;
    _mode = mode;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_prefsKey, mode.name);
  }

  Future<void> setAccentColor(Color? color) async {
    if (color == _accentColor) return;
    _accentColor = color;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    if (color == null) {
      await prefs.remove(_accentColorPrefsKey);
    } else {
      await prefs.setInt(_accentColorPrefsKey, color.toARGB32());
    }
  }
}
