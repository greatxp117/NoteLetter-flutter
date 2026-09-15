import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../services/analytics.dart';

/// Drives [MaterialApp.themeMode]. Three-way (system / light / dark), persisted
/// across launches via SharedPreferences. Defaults to [ThemeMode.system] until
/// the stored preference (if any) loads.
class ThemeNotifier extends ChangeNotifier {
  static const _prefsKey = 'theme_mode';

  ThemeMode _mode = ThemeMode.system;

  ThemeNotifier() {
    _load();
  }

  ThemeMode get themeMode => _mode;

  /// The stored preference (not the resolved brightness). Under
  /// [ThemeMode.system] this is false; callers needing the effective brightness
  /// should read `MediaQuery.platformBrightnessOf`.
  bool get isDark => _mode == ThemeMode.dark;

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    _mode = _parse(prefs.getString(_prefsKey));
    notifyListeners();
  }

  Future<void> setMode(ThemeMode mode) async {
    if (mode == _mode) return;
    _mode = mode;
    notifyListeners();
    // Here and not in [_load]: restoring a stored preference at launch is not
    // somebody changing the theme, and counting it would make every cold start
    // look like a deliberate choice (the reference guards the same way, with
    // its `mounted` ref).
    // The three values spelled out rather than taken from `mode.name`: the
    // enum's identifiers agree with the closed set today by coincidence, and a
    // rename would change what an operator reads with nothing failing. It also
    // keeps the value a literal, which is what INV-25(b)'s RAW-PARAM direction
    // can actually see.
    final theme = switch (mode) {
      ThemeMode.light => 'light',
      ThemeMode.dark => 'dark',
      ThemeMode.system => 'system',
    };
    Analytics.track('theme_changed', {'theme': theme});
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_prefsKey, mode.name);
  }

  /// Cycles system → light → dark → system (the sidebar/drawer toggle).
  void toggle() => setMode(switch (_mode) {
        ThemeMode.system => ThemeMode.light,
        ThemeMode.light => ThemeMode.dark,
        ThemeMode.dark => ThemeMode.system,
      });

  /// Icon for the current mode (used by the sidebar/drawer toggle affordance).
  IconData get modeIcon => switch (_mode) {
        ThemeMode.system => Icons.brightness_auto_outlined,
        ThemeMode.light => Icons.light_mode_outlined,
        ThemeMode.dark => Icons.dark_mode_outlined,
      };

  /// Human label for the current mode.
  String get modeLabel => switch (_mode) {
        ThemeMode.system => 'System theme',
        ThemeMode.light => 'Light theme',
        ThemeMode.dark => 'Dark theme',
      };

  static ThemeMode _parse(String? stored) => switch (stored) {
        'light' => ThemeMode.light,
        'dark' => ThemeMode.dark,
        _ => ThemeMode.system,
      };
}
