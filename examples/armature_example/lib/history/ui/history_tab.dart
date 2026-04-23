import 'package:armature_flutter/armature_flutter.dart';
import 'package:flutter/material.dart';

import '../history_store.dart';

class HistoryTab extends StatelessWidget {
  final HistoryStore store;

  const HistoryTab({super.key, required this.store});

  @override
  Widget build(BuildContext context) {
    return StateObserver(
      builder: (_) {
        final values = store.state.values;

        if (values.isEmpty) {
          return const Center(
            child: Padding(
              padding: EdgeInsets.all(24),
              child: Text(
                'Tick the counter to see entries appear here.\n\n'
                'This feature subscribes to Counter in onStart — no widget '
                'needs to pull; changes flow reactively.',
                textAlign: TextAlign.center,
              ),
            ),
          );
        }

        return Column(
          children: [
            Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  Text(
                    'History',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const SizedBox(width: 8),
                  Text(
                    '${values.length}/${HistoryStore.maxEntries}',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                  const Spacer(),
                  TextButton.icon(
                    onPressed: store.clear,
                    icon: const Icon(Icons.delete_sweep),
                    label: const Text('Clear'),
                  ),
                ],
              ),
            ),
            Expanded(
              child: ListView.separated(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                itemCount: values.length,
                separatorBuilder: (_, _) => const Divider(height: 1),
                itemBuilder: (_, i) => ListTile(
                  dense: true,
                  leading: CircleAvatar(
                    radius: 14,
                    child: Text(
                      '${values.length - i}',
                      style: const TextStyle(fontSize: 11),
                    ),
                  ),
                  title: Text('Value: ${values[i]}'),
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}
