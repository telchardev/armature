import 'package:armature/armature.dart';
import 'package:armature_flutter/armature_flutter.dart';
import 'package:flutter/material.dart' show Icons;

import '../layout/config.dart';
import './feature_toggles_store.dart';
import './ui/feature_toggles_tab.dart';

final featureTogglesFeature =
    createFeature(
        name: "FeatureToggles",
        dependsOn: [layoutFeature],
        stores: (_) => (featureToggles: FeatureTogglesStore()),
        exports: (api) => api.own,
      )
      ..usePipe(layoutFeature.ports.tabsPipe, (tabs, _) {
        return [
          ...tabs,
          (id: 'toggles', label: 'Toggles', icon: Icons.toggle_on_outlined),
        ];
      })
      ..useSingleSlot(layoutFeature.ports.bodySwitchSlot('toggles'), (_, api) {
        return FeatureTogglesTab(store: api.own.featureToggles);
      });
