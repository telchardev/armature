import 'package:armature/armature.dart';
import 'package:armature_flutter/armature_flutter.dart';
import 'package:flutter/material.dart' show Icons;

import '../counter/config.dart';
import '../layout/config.dart';
import './history_store.dart';
import './ui/history_tab.dart';

final historyFeature =
    createFeature(
        name: "History",
        dependsOn: [layoutFeature, counterFeature],
        stores: (_) => (history: HistoryStore()),
        exports: (api) => api.own,
      )
      // Cross-feature reactive: subscribe to Counter, push every value.
      ..onStart((api, cleanup) {
        final counter = api.of(counterFeature).counter;
        final history = api.own.history;
        final dispose = counter.subscribe((_, s) => history.push(s.value));
        cleanup.add(dispose);
      })
      ..usePipe(layoutFeature.ports.tabsPipe, (tabs, _) {
        return [
          ...tabs,
          (id: 'history', label: 'History', icon: Icons.history),
        ];
      })
      ..useSingleSlot(layoutFeature.ports.bodySwitchSlot('history'), (_, api) {
        return HistoryTab(store: api.own.history);
      });
