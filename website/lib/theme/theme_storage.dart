import 'package:flutter/material.dart';
import 'package:web/web.dart' as web;

const _kStorageKey = 'armature.themeMode';

/// Reads the last persisted [ThemeMode] from `localStorage`.
///
/// Returns [ThemeMode.system] if nothing is stored or the stored value is
/// unrecognised.
ThemeMode loadThemeMode() {
  final stored = web.window.localStorage.getItem(_kStorageKey);
  return switch (stored) {
    'light' => ThemeMode.light,
    'dark' => ThemeMode.dark,
    _ => ThemeMode.system,
  };
}

/// Persists [mode] to `localStorage` under a fixed key.
void saveThemeMode(ThemeMode mode) {
  web.window.localStorage.setItem(_kStorageKey, mode.name);
}
