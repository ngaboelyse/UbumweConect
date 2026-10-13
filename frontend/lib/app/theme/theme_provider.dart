import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Theme mode controller. Backed by SharedPreferences so the choice survives
/// app restarts. The Settings screen dark-mode switch drives this; app.dart
/// watches it and feeds MaterialApp.router's themeMode.
final themeModeProvider = StateNotifierProvider<ThemeModeController, ThemeMode>(
  (ref) => ThemeModeController(),
);

class ThemeModeController extends StateNotifier<ThemeMode> {
  ThemeModeController() : super(ThemeMode.system) {
    _load();
  }

  static const _key = 'dark_mode';

  Future<void> _load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final isDark = prefs.getBool(_key) ?? false;
      state = isDark ? ThemeMode.dark : ThemeMode.light;
    } catch (_) {
      // Defaults to system theme if storage is unavailable.
    }
  }

  Future<void> setDarkMode(bool isDark) async {
    state = isDark ? ThemeMode.dark : ThemeMode.light;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_key, isDark);
    } catch (_) {}
  }

  /// Current value as a simple bool for switches.
  bool get isDarkMode => state == ThemeMode.dark;
}
