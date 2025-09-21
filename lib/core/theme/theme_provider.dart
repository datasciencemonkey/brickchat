import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../constants/app_constants.dart';

enum AppThemeMode {
  light,
  dark,
  system,
}

class ThemeNotifier extends StateNotifier<AppThemeMode> {
  ThemeNotifier() : super(AppThemeMode.system) {
    _loadTheme();
  }

  static const String _themeKey = 'theme_mode';

  Future<void> _loadTheme() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final themeString = prefs.getString(_themeKey);

      if (themeString != null) {
        switch (themeString) {
          case AppConstants.lightTheme:
            state = AppThemeMode.light;
            break;
          case AppConstants.darkTheme:
            state = AppThemeMode.dark;
            break;
          case AppConstants.systemTheme:
          default:
            state = AppThemeMode.system;
            break;
        }
      }
    } catch (e) {
      state = AppThemeMode.system;
    }
  }

  Future<void> setThemeMode(AppThemeMode themeMode) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      String themeString;

      switch (themeMode) {
        case AppThemeMode.light:
          themeString = AppConstants.lightTheme;
          break;
        case AppThemeMode.dark:
          themeString = AppConstants.darkTheme;
          break;
        case AppThemeMode.system:
          themeString = AppConstants.systemTheme;
          break;
      }

      await prefs.setString(_themeKey, themeString);
      state = themeMode;
    } catch (e) {
      // Handle error silently and maintain current state
    }
  }

  void toggleTheme() {
    switch (state) {
      case AppThemeMode.light:
        setThemeMode(AppThemeMode.dark);
        break;
      case AppThemeMode.dark:
        setThemeMode(AppThemeMode.light);
        break;
      case AppThemeMode.system:
        setThemeMode(AppThemeMode.light);
        break;
    }
  }

  bool isDarkMode(BuildContext context) {
    switch (state) {
      case AppThemeMode.light:
        return false;
      case AppThemeMode.dark:
        return true;
      case AppThemeMode.system:
        return MediaQuery.platformBrightnessOf(context) == Brightness.dark;
    }
  }
}

final themeProvider = StateNotifierProvider<ThemeNotifier, AppThemeMode>((ref) {
  return ThemeNotifier();
});

final isDarkModeProvider = Provider<bool>((ref) {
  final themeMode = ref.watch(themeProvider);

  switch (themeMode) {
    case AppThemeMode.light:
      return false;
    case AppThemeMode.dark:
      return true;
    case AppThemeMode.system:
      return WidgetsBinding.instance.platformDispatcher.platformBrightness == Brightness.dark;
  }
});

extension ThemeContext on WidgetRef {
  ThemeNotifier get themeNotifier => read(themeProvider.notifier);
  AppThemeMode get currentThemeMode => watch(themeProvider);
  bool get isDarkMode => watch(isDarkModeProvider);
}