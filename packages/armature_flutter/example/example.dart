import 'package:armature/armature.dart';
import 'package:armature_flutter/armature_flutter.dart';
import 'package:flutter/material.dart';

/// A compact but "selling" demo of `armature_flutter` — three features
/// compose one screen through ports, without knowing about each other:
///
/// - **Layout** (root) owns three ports: a tabs `Pipe`, a body
///   `SingleSwitchSlot` (route-keyed), an actions `MultiSlot`.
/// - **Counter** contributes a tab, a body, and a `+` button.
/// - **History** `optionalDependsOn: [counter]` and activates via
///   `whenActive(counter)` — when counter is toggled off, History
///   quietly deactivates and its tab / body / button disappear.
///
/// Along the way it shows:
/// - `context.store<T>()` — one-shot imperative read.
/// - `StoreBuilder<T>` — reactive wrapper + typed DI.
/// - `StoreSelector<V>` — equality-based derived rebuild.
/// - `PipeProvider`, `SingleSlotProvider`, `MultiSlotProvider`.
/// - activation helpers + `api.of(parent).store` cross-feature reads.

// ── Stores ──

class CounterStore extends Store<int> {
  CounterStore() : super(state: 0);
  void increment() => update((s) => s + 1);
  void reset() => update((_) => 0);
}

class HistoryStore extends Store<List<int>> {
  HistoryStore() : super(state: const []);
  void push(int v) => update((s) => [...s, v]);
  void clear() => update((_) => const []);
}

class ActiveTabStore extends Store<String> {
  ActiveTabStore() : super(state: 'counter');
  void select(String tab) => update((_) => tab);
}

typedef TabSpec = ({String id, String label});

// ── Ports (owner: layoutFeature) ──

final tabsPipe = createPipe<List<TabSpec>>(name: 'layout.tabs');
final bodySwitchSlot = createSingleSwitchSlot<String>(name: 'layout.body');
final actionsSlot = createMultiSlot<String>(
  name: 'layout.actions',
  orderDirection: MultiSlotOrderDirection.asc,
);

// ── Features ──

final layoutFeature = createFeature(
  name: 'Layout',
  ports: (tabs: tabsPipe, body: bodySwitchSlot, actions: actionsSlot),
  stores: (_) => (activeTab: ActiveTabStore()),
  exports: (api) => api.own,
);

final counterFeature =
    createFeature(
        name: 'Counter',
        dependsOn: [layoutFeature],
        stores: (_) => (counter: CounterStore()),
        exports: (api) => api.own,
      )
      ..usePipe(
        layoutFeature.ports.tabs,
        (tabs, _) => [...tabs, (id: 'counter', label: 'Counter')],
      )
      ..useSingleSlot(
        layoutFeature.ports.body('counter'),
        (_, _) => const _CounterBody(),
      )
      ..useMultiSlot(
        layoutFeature.ports.actions,
        (tab, api) => tab != 'counter'
            ? null
            : FloatingActionButton(
                heroTag: 'inc',
                onPressed: api.own.counter.increment,
                child: const Icon(Icons.add),
              ),
        order: 1,
      );

final historyFeature =
    createFeature(
        name: 'History',
        dependsOn: [layoutFeature],
        optionalDependsOn: [counterFeature],
        stores: (_) => (history: HistoryStore()),
        exports: (api) => api.own,
      )
      // Mirrors Counter's lifecycle. Remove counterFeature from the
      // ArmatureApp features list and History stays `.disabled` — its
      // tab / body / action silently disappear.
      ..activation(whenActive(counterFeature))
      ..onStart((api, cleanup) {
        final counter = api.of(counterFeature).counter;
        cleanup.add(
          counter.subscribe((_, v) {
            if (v != 0) api.own.history.push(v);
          }),
        );
      })
      ..usePipe(
        layoutFeature.ports.tabs,
        (tabs, _) => [...tabs, (id: 'history', label: 'History')],
      )
      ..useSingleSlot(
        layoutFeature.ports.body('history'),
        (_, _) => const _HistoryBody(),
      )
      ..useMultiSlot(
        layoutFeature.ports.actions,
        (tab, api) => tab != 'history'
            ? null
            : FloatingActionButton(
                heroTag: 'clear',
                backgroundColor: Colors.red,
                onPressed: api.own.history.clear,
                child: const Icon(Icons.delete),
              ),
        order: 2,
      );

// ── UI ──

class _Shell extends StatelessWidget {
  const _Shell();

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      theme: ThemeData(colorSchemeSeed: Colors.indigo, useMaterial3: true),
      // `StoreBuilder<ActiveTabStore>` — reactive read of the owner's
      // tab state, rebuilds the shell on tab switch.
      home: StoreBuilder<ActiveTabStore>(
        builder: (context, activeTab) => Scaffold(
          appBar: AppBar(
            title: const Text('armature demo'),
            bottom: PreferredSize(
              preferredSize: const Size.fromHeight(56),
              child: PipeProvider<List<TabSpec>>(
                pipe: tabsPipe,
                initialValue: const [],
                builder: (tabs, _) => Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  child: Wrap(
                    spacing: 6,
                    children: [
                      for (final t in tabs)
                        FilterChip(
                          label: Text(t.label),
                          selected: t.id == activeTab.state,
                          onSelected: (_) => activeTab.select(t.id),
                        ),
                    ],
                  ),
                ),
              ),
            ),
          ),
          body: SingleSlotProvider(
            slot: bodySwitchSlot(activeTab.state),
            data: activeTab.state,
            builder: (child, _) =>
                child ?? const Center(child: Text('empty tab')),
          ),
          floatingActionButton: MultiSlotProvider(
            slot: actionsSlot,
            data: activeTab.state,
            builder: (kids, _) => Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                for (final k in kids)
                  Padding(padding: const EdgeInsets.all(4), child: k),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _CounterBody extends StatelessWidget {
  const _CounterBody();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          // Full rebuild on any counter change.
          StoreBuilder<CounterStore>(
            builder: (_, s) =>
                Text('${s.state}', style: const TextStyle(fontSize: 96)),
          ),
          const SizedBox(height: 16),
          // Derived — rebuilds only when parity flips.
          StoreSelector<bool>(
            select: (ctx) => ctx.store<CounterStore>().state.isEven,
            builder: (_, isEven) => Text(
              isEven ? 'even' : 'odd',
              style: const TextStyle(fontSize: 18, color: Colors.grey),
            ),
          ),
          const SizedBox(height: 24),
          TextButton(
            // Imperative one-shot — no rebuild here.
            onPressed: () => context.store<CounterStore>().reset(),
            child: const Text('reset'),
          ),
        ],
      ),
    );
  }
}

class _HistoryBody extends StatelessWidget {
  const _HistoryBody();

  @override
  Widget build(BuildContext context) {
    return StoreBuilder<HistoryStore>(
      builder: (_, s) => s.state.isEmpty
          ? const Center(child: Text('no history yet — tap + on Counter tab'))
          : ListView.builder(
              itemCount: s.state.length,
              itemBuilder: (_, i) => ListTile(
                leading: CircleAvatar(child: Text('${i + 1}')),
                title: Text('counter = ${s.state[i]}'),
              ),
            ),
    );
  }
}

// ── Main ──

final layoutRoot = createFeatureRoot<void>(
  feature: layoutFeature,
  widget: const _Shell(),
);

void main() {
  runApp(
    ArmatureApp(
      features: [layoutFeature, counterFeature, historyFeature],
      child: layoutRoot(data: null),
    ),
  );
}
