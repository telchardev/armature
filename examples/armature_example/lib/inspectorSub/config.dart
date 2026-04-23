import 'package:armature/armature.dart';
import 'package:armature_flutter/armature_flutter.dart';
import 'package:flutter/material.dart' show Icons, IconButton, Icon;

import '../inspector/config.dart';
import '../layout/config.dart';

// Activation gate at the feature level: InspectorSub lives exactly as
// long as inspectorFeature does. When Inspector is off (toggle in
// FeatureToggles), this feature deactivates — its slot handler stops
// firing, and the button disappears without a per-handler branch.
final inspectorSubFeature =
    createFeature(
        name: "InspectorSub",
        dependsOn: [layoutFeature],
        optionalDependsOn: [inspectorFeature],
      )
      ..useMultiSlot(layoutFeature.ports.actionsSlot, (_, api) {
        return IconButton(
          tooltip: 'Show inspector',
          onPressed: () {
            api.of(layoutFeature).activeTab.setTab('inspector');
          },
          icon: const Icon(Icons.biotech),
        );
      }, order: 4)
      ..activation(whenActive(inspectorFeature));
