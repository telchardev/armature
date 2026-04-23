import 'package:armature_flutter/armature_flutter.dart';
import 'package:flutter/material.dart';

import '../counter_store.dart';

class CounterBadge extends StatelessWidget {
  final CounterStore store;

  const CounterBadge({super.key, required this.store});

  @override
  Widget build(BuildContext context) {
    return StateObserver(
      builder: (_) {
        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4),
          child: Chip(
            visualDensity: VisualDensity.compact,
            avatar: const Icon(Icons.add_circle_outline, size: 16),
            label: Text('${store.state.value}'),
          ),
        );
      },
    );
  }
}
