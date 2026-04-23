import 'package:armature/armature.dart';
import 'package:armature_flutter/armature_flutter.dart';
import 'package:flutter/material.dart' show ThemeMode;

import '../app/theme.dart';
import '../layout/config.dart';
import '../layout/layout_mode.dart';
import './night_mode_store.dart';
import './shared_prefs_night_mode_repository.dart';
import './ui/night_mode_button.dart';

final nightModeFeature =
    createFeature(
        name: "NightMode",
        dependsOn: [layoutFeature],
        stores: (_) =>
            (nightMode: NightModeStore(SharedPrefsNightModeRepository())),
        exports: (api) => api.own,
      )
      ..onStart((api, _) => api.own.nightMode.load())
      // Priority 10 — overrides Layout shell's initialValue (light) when on.
      ..useBehavior(layoutFeature.ports.themeBehavior, (api) {
        if (!api.own.nightMode.state.enabled) return null;
        return (branch: ThemeMode.dark, payload: buildDarkTheme());
      }, priority: 10)
      ..useMultiSlot(
        layoutFeature.ports.actionsSlot,
        (mode, api) => NightModeButton(
          store: api.own.nightMode,
          compact: mode == LayoutMode.phone,
        ),
        order: 3,
      );
