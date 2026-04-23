import 'package:armature/armature.dart';
import 'package:armature_flutter/armature_flutter.dart';
import 'package:flutter/material.dart' show Icons;

import '../auth/config.dart';
import '../counter/config.dart';
import '../layout/config.dart';
import './ui/admin_tab.dart';

final adminFeature =
    createFeature(
        name: "Admin",
        dependsOn: [layoutFeature],
        optionalDependsOn: [authFeature, counterFeature],
      )
      // Reactive tab: handler re-evaluates when auth.state changes.
      // Auth services are always reachable via `api.from` (eager
      // construct + fail-fast); the tab stays hidden when the
      // authenticated user isn't the admin.
      ..usePipe(layoutFeature.ports.tabsPipe, (tabs, api) {
        final user = api.from(authFeature).auth.state.user;
        if (user?.name != 'admin') return tabs;

        return [
          ...tabs,
          (id: 'admin', label: 'Admin', icon: Icons.shield_outlined),
        ];
      })
      // Reactive body: returns null when user is not admin.
      ..useSingleSlot(layoutFeature.ports.bodySwitchSlot('admin'), (_, api) {
        final counter = api.from(counterFeature).counter;

        return AdminTab(counter: counter);
      });
