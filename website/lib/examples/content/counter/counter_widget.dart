import 'package:armature/armature.dart';
import 'package:armature_flutter/armature_flutter.dart';
import 'package:flutter/material.dart';

import 'counter_store.dart';

/// Feature owning the [CounterStore]. The framework constructs the store
/// on container start and disposes it on container teardown — no manual
/// `store.dispose()` needed in widget code.
final counterFeature = createFeature(
  name: 'Counter',
  stores: (_) => (counter: CounterStore()),
  exports: (api) => api.own,
);

final counterRoot = createFeatureRoot(
  feature: counterFeature,
  widget: const CounterView(),
);

class CounterView extends StatelessWidget {
  const CounterView({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final store = StoreContext.of<CounterStore>(context);
    return Container(
      padding: const EdgeInsets.all(32),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerLowest,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: theme.colorScheme.outlineVariant),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          StateObserver(
            builder: (_) => Text(
              '${store.state.value}',
              style: theme.textTheme.displayLarge?.copyWith(
                fontWeight: FontWeight.w700,
                color: theme.colorScheme.primary,
              ),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'reactive store — updates via StateObserver',
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 24),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            alignment: WrapAlignment.center,
            children: [
              FilledButton.icon(
                onPressed: () => store.increment(),
                icon: const Icon(Icons.add),
                label: const Text('Increment (queue)'),
              ),
              OutlinedButton.icon(
                onPressed: () => store.debouncedBump(),
                icon: const Icon(Icons.timer_outlined),
                label: const Text('Debounced bump (400ms)'),
              ),
              TextButton.icon(
                onPressed: () => store.reset(),
                icon: const Icon(Icons.restart_alt),
                label: const Text('Reset'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

void main() {
  runApp(
    ArmatureApp(
      features: [counterFeature],
      child: MaterialApp(home: counterRoot(data: null)),
    ),
  );
}
