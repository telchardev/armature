import 'package:flutter/material.dart';

import 'theme_storage.dart';

/// Holds the current [ThemeMode], persists changes to `localStorage`, and
/// notifies listeners when the mode flips.
class ThemeController extends ChangeNotifier {
  ThemeController() : _mode = loadThemeMode();

  ThemeMode _mode;

  ThemeMode get mode => _mode;

  /// Cycles through system → light → dark → system.
  void cycle() {
    _mode = switch (_mode) {
      ThemeMode.system => ThemeMode.light,
      ThemeMode.light => ThemeMode.dark,
      ThemeMode.dark => ThemeMode.system,
    };
    saveThemeMode(_mode);
    notifyListeners();
  }
}

/// Exposes a [ThemeController] to descendants.
class ThemeScope extends InheritedNotifier<ThemeController> {
  const ThemeScope({
    super.key,
    required ThemeController super.notifier,
    required super.child,
  });

  static ThemeController of(BuildContext context) {
    final scope = context.dependOnInheritedWidgetOfExactType<ThemeScope>();
    assert(scope != null, 'No ThemeScope ancestor found');
    return scope!.notifier!;
  }
}
