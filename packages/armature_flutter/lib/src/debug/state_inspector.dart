import 'package:armature/armature.dart'
    show FeatureDebugInfo, FeatureStatus, Store;
import 'package:flutter/widgets.dart';
import 'package:meta/meta.dart' show internal;

import '../services/state_observer.dart' show StateObserver;
import './debug_theme.dart';
import './format_state.dart' show formatState;

/// Displays live state of each [Store] across all features. Framework-
/// internal.
@internal
class StateInspectorPanel extends StatelessWidget {
  final List<FeatureDebugInfo> features;

  const StateInspectorPanel({super.key, required this.features});

  @override
  Widget build(BuildContext context) {
    final entries = <({String featureName, Store store})>[];

    for (final f in features) {
      if (f.status != FeatureStatus.active) continue;
      for (final s in f.stores) {
        entries.add((featureName: f.name, store: s));
      }
    }

    if (entries.isEmpty) {
      return const Center(
        child: Text(
          'No stores available',
          style: TextStyle(
            color: kTextGrey,
            fontSize: 12,
            decoration: TextDecoration.none,
          ),
        ),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 12),
      itemCount: entries.length,
      itemBuilder: (_, index) {
        final e = entries[index];
        return _StoreStateCard(featureName: e.featureName, store: e.store);
      },
    );
  }
}

class _StoreStateCard extends StatefulWidget {
  final String featureName;
  final Store store;

  const _StoreStateCard({required this.featureName, required this.store});

  @override
  State<_StoreStateCard> createState() => _StoreStateCardState();
}

class _StoreStateCardState extends State<_StoreStateCard> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: GestureDetector(
        onTap: () => setState(() => _expanded = !_expanded),
        child: SizedBox(
          width: double.infinity,
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: kStoreCardBg,
              borderRadius: BorderRadius.circular(6),
              border: Border.all(color: kStoreCardBorder),
            ),
            child: Padding(
              padding: const EdgeInsets.all(10),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      Text(
                        '${widget.store.runtimeType}',
                        style: const TextStyle(
                          color: kTextWhite,
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                          decoration: TextDecoration.none,
                        ),
                      ),
                      const SizedBox(width: 6),
                      Text(
                        widget.featureName,
                        style: const TextStyle(
                          color: kTextGrey,
                          fontSize: 10,
                          decoration: TextDecoration.none,
                        ),
                      ),
                      const Spacer(),
                      Text(
                        _expanded ? '▾' : '▸',
                        style: const TextStyle(
                          color: kTextGrey,
                          fontSize: 12,
                          decoration: TextDecoration.none,
                        ),
                      ),
                    ],
                  ),
                  if (_expanded) ...[
                    const SizedBox(height: 6),
                    ConstrainedBox(
                      constraints: const BoxConstraints(maxHeight: 300),
                      child: SingleChildScrollView(
                        child: StateObserver(
                          builder: (_) {
                            final state = widget.store.state;
                            return Text(
                              formatState(state),
                              style: const TextStyle(
                                color: kTextGrey,
                                fontSize: 10,
                                fontFamily: 'monospace',
                                decoration: TextDecoration.none,
                              ),
                            );
                          },
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
