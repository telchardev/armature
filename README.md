[![pub package](https://img.shields.io/pub/v/armature.svg?label=armature)](https://pub.dev/packages/armature)
[![pub package](https://img.shields.io/pub/v/armature_flutter.svg?label=armature_flutter)](https://pub.dev/packages/armature_flutter)
[![likes](https://img.shields.io/pub/likes/armature?logo=dart)](https://pub.dev/packages/armature/score)
[![points](https://img.shields.io/pub/points/armature?logo=dart)](https://pub.dev/packages/armature/score)
[![CI](https://github.com/telchardev/armature/actions/workflows/armature_ci.yml/badge.svg?branch=main)](https://github.com/telchardev/armature/actions/workflows/armature_ci.yml)

# armature

A framework for building complex, multi-module Flutter applications with feature-based architecture, reactive state management, and a dependency graph that resolves features at startup.

📖 **[Read the full docs →](https://telchardev.github.io/armature/)**

## Why armature?

Large Flutter applications quickly devolve into a tangled web of providers, singletons, and implicit dependencies. **armature** solves this by:

- **Isolating features** into self-contained modules with explicit dependency declarations
- **Resolving a dependency graph** at startup — features are initialized in the correct order
- **Providing a reactive system** (Atom / Reaction) for fine-grained state tracking
- **Composing UI via slots** — features inject widgets into named extension points without knowing about each other

> **Is armature for your project?** It pays off in apps with several feature areas, multiple developers, or runtime feature toggles. For a one- or two-screen app, Provider or Riverpod ship faster.

---

## Quickstart

A self-contained "hello world" with two features composing through a port. After `flutter pub add armature armature_flutter`, drop this into `lib/main.dart`:

```dart
import 'package:armature/armature.dart';
import 'package:armature_flutter/armature_flutter.dart';
import 'package:flutter/material.dart';

// 1. Counter state as a record — extensible without breaking equality.
typedef CounterState = ({int value});

class CounterStore extends Store<CounterState> {
  CounterStore() : super(state: (value: 0));
  void increment() => update((s) => (value: s.value + 1));
}

// 2. Layout feature owns the app shell and a body slot. No stores.
final bodySlot = createSingleSlot(name: 'layout.body');

final layoutFeature = createFeature(
  name: 'Layout',
  ports: (bodySlot: bodySlot),
);

final layoutRoot = createFeatureRoot(
  feature: layoutFeature,
  widget: Scaffold(
    appBar: AppBar(title: const Text('Counter')),
    body: SingleSlotProvider(
      slot: bodySlot,
      data: null,
      builder: (child, _) => child ?? const SizedBox.shrink(),
    ),
  ),
);

// 3. Counter feature owns state and plugs into the layout's body slot.
final counterFeature = createFeature(
  name: 'Counter',
  dependsOn: [layoutFeature],
  stores: (_) => (counter: CounterStore()),
  exports: (api) => api.own,
)..useSingleSlot(layoutFeature.ports.bodySlot, (_, api) {
  return Center(
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        StoreBuilder<CounterStore>(
          builder: (_, store) => Text(
            '${store.state.value}',
            style: const TextStyle(fontSize: 64),
          ),
        ),
        const SizedBox(height: 16),
        FilledButton(
          onPressed: () => api.own.counter.increment(),
          child: const Text('Increment'),
        ),
      ],
    ),
  );
});

void main() {
  runApp(ArmatureApp(
    features: [layoutFeature, counterFeature],
    child: MaterialApp(home: layoutRoot(data: null)),
  ));
}
```

Two features, one dependency edge, one port — that's the smallest example that actually shows what armature is for. The [docs](https://telchardev.github.io/armature/) walk through each piece (features, stores, tasks, ports, activation) using a Notes/Todo app that grows from this same base.

---

## Architecture

```mermaid
flowchart TB
    reactive["<b>armature_reactive</b><br/>Atom · Reaction · Context"]
    graph["<b>armature_graph</b><br/>Graph · Node · DAG resolution"]
    core["<b>armature</b><br/>AppContainer · Feature · Store · Task · Ports"]
    flutter["<b>armature_flutter</b><br/>ArmatureApp · slot widgets · StoreBuilder · StoreSelector · FeatureGraphOverlay"]

    reactive --> core
    graph --> core
    core --> flutter
```

| Package | Description |
|---------|-------------|
| **armature_reactive** | Lightweight MobX-style reactive primitives (pure Dart, no Flutter dependency) |
| **armature_graph** | Directed acyclic graph with topological resolution and visitor-based activation cascade |
| **armature** | Core framework: AppContainer, Feature, Store, Task, Ports (Pipe, Behavior) |
| **armature_flutter** | Flutter integration: ArmatureApp, slot widgets, reactive providers, StoreBuilder/StoreSelector, debug overlay |

---

## Where to go next

- **[Documentation site](https://telchardev.github.io/armature/)** — full guide: mental model, glossary, every concept walked through with a Notes/Todo example. The 5-feature Notes app lives in the **Examples → Notes app** section as a live preview with the full source.
- **[examples/armature_example](examples/armature_example)** — a larger multi-feature reference app exercising every piece of the framework (auth, admin, feature toggles, history, inspector, theming, debug overlay).
- **API reference** — [armature](https://pub.dev/documentation/armature/latest/) · [armature_flutter](https://pub.dev/documentation/armature_flutter/latest/) · [armature_reactive](https://pub.dev/documentation/armature_reactive/latest/) · [armature_graph](https://pub.dev/documentation/armature_graph/latest/)

---

## Packages

| Package | Version | Dart SDK | pub.dev |
|---------|---------|----------|---------|
| `armature` | 0.3.1 | `^3.9.0` | [→](https://pub.dev/packages/armature) |
| `armature_flutter` | 0.3.1 | `^3.9.0` | [→](https://pub.dev/packages/armature_flutter) |
| `armature_reactive` | 0.1.0 | `^3.9.0` | [→](https://pub.dev/packages/armature_reactive) |
| `armature_graph` | 0.1.0 | `^3.9.0` | [→](https://pub.dev/packages/armature_graph) |

## License

MIT — see [LICENSE](LICENSE).
