import 'package:armature_flutter/armature_flutter.dart';
import 'package:flutter/foundation.dart' show kDebugMode;
import 'package:flutter/material.dart';

import '../feature_toggles_store.dart';

class FeatureTogglesTab extends StatelessWidget {
  final FeatureTogglesStore store;

  const FeatureTogglesTab({super.key, required this.store});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 520),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Feature toggles',
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: 8),
              Text(
                'Toggling a feature flips the corresponding feature\'s '
                'activation state. The Inspector feature subscribes to this '
                'state and calls toggle(state: ...) on every change.',
                style: Theme.of(context).textTheme.bodySmall,
              ),
              const SizedBox(height: 16),
              Card(
                margin: EdgeInsets.zero,
                child: StateObserver(
                  builder: (_) {
                    final state = store.state;
                    return Column(
                      children: [
                        SwitchListTile(
                          title: const Text('Inspector'),
                          subtitle: Text(
                            kDebugMode
                                ? 'Gates the Inspector tab and all its ports.'
                                : 'Disabled in release builds — Inspector '
                                      'never activates regardless of this flag.',
                          ),
                          value: state.inspector,
                          onChanged: store.setInspector,
                        ),
                      ],
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
