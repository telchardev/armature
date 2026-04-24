import 'package:armature/armature.dart';
import 'package:armature_flutter/armature_flutter.dart';

import './active_tab_store.dart';
import './ports.dart';
import './ui/layout_shell.dart';

// Layout owns `themeBehavior` — it exposes the port but cannot register a
// handler on its own port (framework rule). The default (light) theme is
// applied as `BehaviorProvider.initialValue` in the shell: when every handler
// returns null, the behavior's `apply()` falls back to `initialValue`.
final layoutFeature = createFeature(
  name: "Layout",
  ports: (
    titleSlot: titleSlot,
    tabsPipe: tabsPipe,
    bodyKeyedSlot: bodyKeyedSlot,
    actionsSlot: actionsSlot,
    fabSlot: fabSlot,
    themeBehavior: themeBehavior,
  ),
  stores: (_) => (activeTab: ActiveTabStore()),
  exports: (api) => api.own,
);

final layoutRoot = createFeatureRoot(
  feature: layoutFeature,
  widget: const LayoutShell(),
);
