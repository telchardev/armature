import 'package:armature/armature.dart';
import 'package:armature_flutter/armature_flutter.dart';
import 'package:flutter/material.dart' show Icons, Text, IconButton, Icon;

import '../layout/config.dart';
import './auth_store.dart';
import './shared_prefs_auth_repository.dart';
import './ui/auth_tab.dart';

final authFeature =
    createFeature(
        name: "Auth",
        dependsOn: [layoutFeature],
        stores: (_) => (auth: AuthStore(SharedPrefsAuthRepository())),
        exports: (api) => api.own,
      )
      ..onStart((api, _) => api.own.auth.load())
      ..usePipe(layoutFeature.ports.tabsPipe, (tabs, _) {
        return [
          ...tabs,
          (id: 'auth', label: 'Auth', icon: Icons.person_outline),
        ];
      })
      ..useSingleSlot(layoutFeature.ports.bodyKeyedSlot('auth'), (_, api) {
        return AuthTab(store: api.own.auth);
      })
      // Override the app-bar title when logged in.
      ..useSingleSlot(layoutFeature.ports.titleSlot, (_, api) {
        final user = api.own.auth.state.user;
        if (user == null) return null;
        return Text('Hello, ${user.name}');
      })
      // Show logout icon only when logged in — conditional null.
      ..useMultiSlot(layoutFeature.ports.actionsSlot, (_, api) {
        if (api.own.auth.state.user == null) return null;
        return IconButton(
          tooltip: 'Log out',
          onPressed: api.own.auth.logout,
          icon: const Icon(Icons.logout),
        );
      }, order: 2);
