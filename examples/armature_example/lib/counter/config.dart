import 'package:armature/armature.dart';
import 'package:armature_flutter/armature_flutter.dart';
import 'package:flutter/material.dart' show FloatingActionButton, Icon, Icons;

import '../layout/config.dart';
import './counter_store.dart';
import './ui/counter_badge.dart';
import './ui/counter_tab.dart';

final counterFeature =
    createFeature(
        name: "Counter",
        dependsOn: [layoutFeature],
        stores: (_) => (counter: CounterStore()),
        exports: (api) => api.own,
      )
      ..usePipe(layoutFeature.ports.tabsPipe, (tabs, _) {
        return [
          ...tabs,
          (id: 'counter', label: 'Counter', icon: Icons.add_circle_outline),
        ];
      })
      ..useSingleSlot(layoutFeature.ports.bodySwitchSlot('counter'), (
        mode,
        api,
      ) {
        return CounterTab(store: api.own.counter, mode: mode);
      })
      // Always-visible badge showing current value in the app bar.
      ..useMultiSlot(
        layoutFeature.ports.actionsSlot,
        (_, api) => CounterBadge(store: api.own.counter),
        order: 0,
      )
      // FAB only when Counter tab is active — demonstrates conditional null.
      ..useMultiSlot(layoutFeature.ports.fabSlot, (_, api) {
        final activeTab = api.from(layoutFeature).activeTab.state;
        if (activeTab != 'counter') return null;
        return FloatingActionButton(
          heroTag: 'counter_fab',
          onPressed: () => api.own.counter.increment(),
          tooltip: 'Increment',
          child: const Icon(Icons.add),
        );
      }, order: 1);
