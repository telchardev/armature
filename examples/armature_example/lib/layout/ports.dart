import 'package:armature/armature.dart' show createBehavior, createPipe;
import 'package:armature_flutter/armature_flutter.dart';
import 'package:flutter/material.dart' show IconData, ThemeData, ThemeMode;

import './layout_mode.dart';

typedef TabSpec = ({String id, String label, IconData icon});

final titleSlot = createSingleSlot<LayoutMode>(name: 'layout.title');

final tabsPipe = createPipe<List<TabSpec>>(name: 'layout.tabs');

final bodyKeyedSlot = createKeyedSingleSlot<LayoutMode>(name: 'layout.body');

final actionsSlot = createMultiSlot<LayoutMode>(name: 'layout.actions');

final fabSlot = createMultiSlot<LayoutMode>(name: 'layout.fab');

final themeBehavior = createBehavior<ThemeMode, ThemeData>(
  name: 'layout.theme',
);
