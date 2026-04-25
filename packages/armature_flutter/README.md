# armature_flutter

[![pub package](https://img.shields.io/pub/v/armature_flutter.svg)](https://pub.dev/packages/armature_flutter)
[![likes](https://img.shields.io/pub/likes/armature_flutter?logo=dart)](https://pub.dev/packages/armature_flutter/score)
[![points](https://img.shields.io/pub/points/armature_flutter?logo=dart)](https://pub.dev/packages/armature_flutter/score)
[![CI](https://github.com/telchardev/armature/actions/workflows/armature_ci.yml/badge.svg?branch=main)](https://github.com/telchardev/armature/actions/workflows/armature_ci.yml)

Flutter integration for [`armature`](https://pub.dev/packages/armature) —
app bootstrap, slot widgets, reactive providers, and an interactive
feature-graph debug overlay.

## Install

```yaml
dependencies:
  armature: ^0.3.1
  armature_flutter: ^0.3.1
```

## Quickstart

Wrap your app with `ArmatureApp`, register your features, and mount a
feature root:

```dart
import 'package:armature/armature.dart';
import 'package:armature_flutter/armature_flutter.dart';
import 'package:flutter/material.dart';

final counterFeature = createFeature(
  name: 'Counter',
  stores: (_) => (counter: CounterStore()),
  exports: (api) => api.own,
);

final counterRoot = createFeatureRoot(
  feature: counterFeature,
  widget: const CounterScreen(),
);

void main() {
  runApp(ArmatureApp(
    features: [counterFeature],
    child: counterRoot(data: null),
  ));
}
```

## Reading store state in widgets

Three tools, ordered from imperative to most granular:

### `context.store<T>()` — one-shot

For event handlers and imperative reads. Does **not** rebuild.

```dart
ElevatedButton(
  onPressed: () => context.store<CounterStore>().increment(),
  child: const Text('+'),
)
```

### `StoreBuilder<T>` — reactive

Rebuilds on any tracked `.state` / atom read inside the builder.

```dart
StoreBuilder<CounterStore>(
  builder: (context, store) => Text('${store.state}'),
)
```

### `StoreSelector<V>` — equality-based

Rebuilds **only** when the derived value changes. Great for deriving
scalars or combining multiple stores into a record / view-model.

```dart
StoreSelector<({String name, int count})>(
  select: (ctx) => (
    name: ctx.store<UserStore>().state.name,
    count: ctx.store<CounterStore>().state,
  ),
  builder: (_, data) => Text('${data.name}: ${data.count}'),
)
```

## Slots — composing UI across features

Slots are ports that produce widgets. The owning feature declares the
slot; child features contribute widgets via extensions.

### `SingleSlot` — pick by priority

```dart
// owner (layoutFeature) declares the slot at top level:
final titleSlot = createSingleSlot<LayoutMode>(name: 'layout.title');

final layoutFeature = createFeature(
  name: 'Layout',
  ports: (titleSlot: titleSlot),
  stores: (_) => (activeTab: ActiveTabStore()),
  exports: (api) => api.own,
);

// child feature contributes a widget:
authFeature.useSingleSlot(
  layoutFeature.ports.titleSlot,
  (mode, api) => Text('Hello, ${api.own.auth.state.user?.name}'),
  priority: 2,
);

// owner (or any descendant) renders the slot:
SingleSlotProvider(
  slot: layoutFeature.ports.titleSlot,
  data: LayoutMode.phone,
  builder: (child, _) => child ?? const Text('No title'),
)
```

### `KeyedSingleSlot` / `KeyedMultiSlot` — same slot, indexed by string key

A keyed slot is a *family* of slots — one per key — sharing a single
declaration. Useful when a parent hosts several routes / tabs in the
same conceptual position.

```dart
// owner declares the keyed slot:
final bodyKeyedSlot = createKeyedSingleSlot<LayoutMode>(name: 'layout.body');

final layoutFeature = createFeature(
  name: 'Layout',
  ports: (body: bodyKeyedSlot),
  stores: (_) => (activeTab: ActiveTabStore()),
  exports: (api) => api.own,
);

// each child feature contributes to a specific key:
counterFeature.useSingleSlot(
  layoutFeature.ports.body('counter'),
  (mode, api) => CounterTab(store: api.own.counter),
);

historyFeature.useSingleSlot(
  layoutFeature.ports.body('history'),
  (mode, api) => HistoryTab(store: api.own.history),
);

// render the active tab's slot:
SingleSlotProvider(
  slot: layoutFeature.ports.body(activeTab),
  data: LayoutMode.phone,
  builder: (child, _) => child ?? const Text('Empty tab'),
)
```

`createKeyedMultiSlot` is the same idea for `MultiSlot` (one list of
widgets per key).

### Other slot kinds and providers

- **`MultiSlot`** — collects all active widgets, sorts by `order`.
  Default `orderDirection` is `MultiSlotOrderDirection.asc`.
- **`PipeProvider` / `BehaviorProvider`** — reactive providers for
  pipe / behavior ports.
- **`MultiPortBuilder`** — reads any mix of ports in a single builder
  with fine-grained reactive tracking. Each `reader.*` call tracks
  exactly one port; rebuilds fire only for the ports that change:

  ```dart
  MultiPortBuilder(
    builder: (reader, _) {
      final tabs = reader.pipe(tabsPipe, initialValue: const <TabSpec>[]);
      final actions = reader.multi(actionsSlot, data: LayoutMode.phone);
      return Scaffold(
        appBar: AppBar(actions: actions),
        body: TabBar(tabs: [for (final t in tabs) Tab(text: t.label)]),
      );
    },
  )
  ```

- **`StateObserver`** — raw reactive builder for arbitrary `Atom` /
  `Store.state` reads, no DI lookup. Use when you build custom widgets
  that touch reactive state outside the typed `StoreBuilder` /
  `StoreSelector` path.

## Debug overlay

Wrap your app with `FeatureGraphOverlay` to get an interactive
feature-graph inspector (enable only in debug):

```dart
runApp(ArmatureApp(
  features: [...],
  child: FeatureGraphOverlay(
    enabled: kDebugMode,
    child: rootBuilder(data: null),
  ),
));
```

Features:

- Pan / zoom / long-press-drag the DAG.
- Tap a node → see dependencies, stores (live state), ports, handlers.
- Refresh button — re-snapshots status + adds any features appearing
  post-start; preserves drag positions.
- Live State Inspector tab — every active store's state, re-renders on
  change.

## Testing

`package:armature_flutter/test_utils.dart`:

```dart
import 'package:armature/test_utils.dart';
import 'package:armature_flutter/test_utils.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('renders counter', (tester) async {
    final container = await startedContainer(features: [counterFeature]);
    // pumpFeature auto-installs a FlutterRenderer on the container if
    // none is set yet. For containers built outside ArmatureApp, call
    // initTestRenderer(container) explicitly only if you need a custom
    // FlutterRendererOptions.
    await pumpFeature(
      tester,
      container: container,
      feature: counterFeature,
      child: StoreBuilder<CounterStore>(
        builder: (_, s) => Text('${s.state}'),
      ),
    );
    expect(find.text('0'), findsOneWidget);
  });
}
```

## Learn more

- [`armature`](https://pub.dev/packages/armature) — core framework
  (features, stores, ports, container).
- [`armature_reactive`](https://pub.dev/packages/armature_reactive) —
  underlying reactive primitives.
- [`armature_graph`](https://pub.dev/packages/armature_graph) — DAG
  resolver used for dependency graph.
- [Monorepo README](https://github.com/telchardev/armature) — full
  architecture with extended examples.

## License

MIT — see [LICENSE](LICENSE).
