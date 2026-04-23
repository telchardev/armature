import 'package:armature_flutter/armature_flutter.dart';
import 'package:flutter/material.dart';

import '../../layout/layout_mode.dart';
import '../counter_store.dart';

class CounterTab extends StatelessWidget {
  final CounterStore store;
  final LayoutMode mode;

  const CounterTab({super.key, required this.store, required this.mode});

  @override
  Widget build(BuildContext context) {
    final isPhone = mode == LayoutMode.phone;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            StateObserver(
              builder: (_) => Text(
                '${store.state.value}',
                style: Theme.of(context).textTheme.displayLarge,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'LayoutMode.${mode.name} — buttons in ${isPhone ? 'Column' : 'Row'}',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: 24),
            _Buttons(store: store, horizontal: !isPhone),
          ],
        ),
      ),
    );
  }
}

class _Buttons extends StatelessWidget {
  final CounterStore store;
  final bool horizontal;

  const _Buttons({required this.store, required this.horizontal});

  @override
  Widget build(BuildContext context) {
    final children = [
      FilledButton.icon(
        onPressed: () => store.increment(),
        icon: const Icon(Icons.add),
        label: const Text('Increment (.queue)'),
      ),
      OutlinedButton.icon(
        onPressed: () => store.decrementTo(0),
        icon: const Icon(Icons.south),
        label: const Text('Decrement to 0'),
      ),
      TextButton.icon(
        onPressed: () => store.reset(),
        icon: const Icon(Icons.restart_alt),
        label: const Text('Reset'),
      ),
      TextButton.icon(
        onPressed: () {
          store.debouncedBump();
        },
        icon: const Icon(Icons.timer),
        label: const Text('Debounced bump (300ms)'),
      ),
    ];

    if (horizontal) {
      return Wrap(
        alignment: WrapAlignment.center,
        spacing: 12,
        runSpacing: 12,
        children: children,
      );
    }
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (var i = 0; i < children.length; i++) ...[
          if (i > 0) const SizedBox(height: 10),
          children[i],
        ],
      ],
    );
  }
}
