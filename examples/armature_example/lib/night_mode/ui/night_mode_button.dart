import 'package:armature_flutter/armature_flutter.dart';
import 'package:flutter/material.dart';

import '../night_mode_store.dart';

class NightModeButton extends StatelessWidget {
  final NightModeStore store;
  final bool compact;

  const NightModeButton({
    super.key,
    required this.store,
    required this.compact,
  });

  @override
  Widget build(BuildContext context) {
    return StateObserver(
      builder: (_) {
        final enabled = store.state.enabled;
        final icon = enabled
            ? Icons.dark_mode_outlined
            : Icons.light_mode_outlined;
        final label = enabled ? 'Dark' : 'Light';

        if (compact) {
          return IconButton(
            tooltip: '$label mode',
            onPressed: store.toggle,
            icon: Icon(icon),
          );
        }
        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4),
          child: TextButton.icon(
            onPressed: store.toggle,
            icon: Icon(icon, size: 18),
            label: Text('$label mode'),
          ),
        );
      },
    );
  }
}
