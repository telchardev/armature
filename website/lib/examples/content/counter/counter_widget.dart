import 'package:armature_flutter/armature_flutter.dart';
import 'package:flutter/material.dart';

import 'counter_store.dart';

/// Mounts a [CounterStore] and observes it reactively.
///
/// The store is created in `initState` and disposed in `dispose`, so the
/// preview state resets when the user navigates away and back.
class CounterDemoWidget extends StatefulWidget {
  const CounterDemoWidget({super.key});

  @override
  State<CounterDemoWidget> createState() => _CounterDemoWidgetState();
}

class _CounterDemoWidgetState extends State<CounterDemoWidget> {
  late final CounterStore _store;

  @override
  void initState() {
    super.initState();
    _store = CounterStore();
  }

  @override
  void dispose() {
    _store.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
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
              '${_store.state.value}',
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
                onPressed: () => _store.increment(),
                icon: const Icon(Icons.add),
                label: const Text('Increment (queue)'),
              ),
              OutlinedButton.icon(
                onPressed: () => _store.debouncedBump(),
                icon: const Icon(Icons.timer_outlined),
                label: const Text('Debounced bump (400ms)'),
              ),
              TextButton.icon(
                onPressed: () => _store.reset(),
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
