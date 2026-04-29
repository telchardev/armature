import 'package:armature/armature.dart';
import 'package:armature_flutter/armature_flutter.dart';
import 'package:flutter/material.dart' show Icons;

import '../feature_toggles/config.dart';
import '../layout/config.dart';
import './inspector_store.dart';
import './ui/inspector_tab.dart';

final inspectorFeature =
    createFeature(
        name: "Inspector",
        dependsOn: [layoutFeature, featureTogglesFeature],
        stores: (_) => (inspector: InspectorStore()),
        exports: (api) => api.own,
      )
      ..usePipe(layoutFeature.ports.tabsPipe, (tabs, _) {
        return [
          ...tabs,
          (id: 'inspector', label: 'Inspector', icon: Icons.biotech_outlined),
        ];
      })
      ..useSingleSlot(layoutFeature.ports.bodyKeyedSlot('inspector'), (_, api) {
        return InspectorTab(store: api.own.inspector);
      })
      ..onStart((api, cleanup) async {
        await Future<void>.delayed(const Duration(seconds: 3));

        cleanup.add(() => api.own.inspector.clear());
      })
      // Reactive gate: activation tracks the `inspector` toggle in
      // FeatureToggles. In release builds the feature never activates,
      // regardless of the toggle.
      ..activation(
        whenStoreState(
          feature: featureTogglesFeature,
          store: (e) => e.featureToggles,
          predicate: (s) => s.inspector,
        ),
      );
