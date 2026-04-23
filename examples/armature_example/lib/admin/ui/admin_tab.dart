import 'package:flutter/material.dart';

import '../../counter/counter_store.dart';

class AdminTab extends StatelessWidget {
  final CounterStore counter;

  const AdminTab({super.key, required this.counter});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.admin_panel_settings_outlined,
                size: 56,
                color: Theme.of(context).colorScheme.primary,
              ),
              const SizedBox(height: 12),
              Text(
                'Admin tools',
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: 8),
              Text(
                'This tab appears reactively while you are logged in as '
                '"admin". Log out and it disappears — the feature is always '
                'resolved, its port-handlers just return null / filtered tabs.',
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodySmall,
              ),
              const SizedBox(height: 20),
              FilledButton.icon(
                onPressed: () => counter.reset(),
                icon: const Icon(Icons.restart_alt),
                label: const Text('Reset Counter via api.of()'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
