# armature

[![pub package](https://img.shields.io/pub/v/armature.svg)](https://pub.dev/packages/armature)
[![likes](https://img.shields.io/pub/likes/armature?logo=dart)](https://pub.dev/packages/armature/score)
[![points](https://img.shields.io/pub/points/armature?logo=dart)](https://pub.dev/packages/armature/score)
[![CI](https://github.com/telchardev/armature/actions/workflows/armature_ci.yml/badge.svg?branch=main)](https://github.com/telchardev/armature/actions/workflows/armature_ci.yml)

Feature-based application framework with dependency-graph resolution,
reactive stores, typed ports (`Pipe` / `Behavior` / slots), and tasks.
**Pure Dart**; pair with
[`armature_flutter`](https://pub.dev/packages/armature_flutter) for
Flutter UI.

Large applications quickly devolve into a web of providers and
singletons. `armature` solves this by giving each feature explicit
dependencies, eager store construction, and extension points
(ports) that other features plug into without mutual knowledge.

## Install

```yaml
dependencies:
  armature: ^0.2.0
  armature_flutter: ^0.2.0   # if you want the Flutter integration
```

## Quickstart

### Define a feature

```dart
import 'package:armature/armature.dart';

class CounterStore extends Store<int> {
  CounterStore() : super(state: 0);
  void increment() => update((s) => s + 1);
}

final counterFeature = createFeature(
  name: "Counter",
  stores: (_) => (counter: CounterStore()),
  exports: (api) => api.own, // pass-through — children see { counter }
);
```

### Declare dependencies

```dart
final authFeature = createFeature(
  name: "Auth",
  stores: (_) => (auth: AuthStore()),
  exports: (api) => api.own,
);

final adminFeature = createFeature(
  name: "Admin",
  dependsOn: [authFeature],        // required parent
  optionalDependsOn: [counterFeature], // optional — reachable via `api.of`
);
```

### Activate + react

```dart
adminFeature
  ..activation(whenActive(authFeature))
  ..onStart((api, cleanup) async {
    final auth = api.of(authFeature).auth;
    cleanup.add(auth.subscribe((_, state) {
      if (state.user?.name == 'admin') {
        api.own.someStore.doWork();
      }
    }));
  });
```

### Run the container

```dart
final container = AppContainer(
  features: [authFeature, counterFeature, adminFeature],
  options: ContainerOptions(
    errorHandler: ({required source, required error, required meta}) {
      // source = feature name / '<container>' / '<events>'
      logger.warn('[$source] $error');
    },
  ),
);

await container.start();
// ...later:
await container.dispose();
```

## Core concepts

### Features

- **`createFeature({name, dependsOn, optionalDependsOn, stores, exports, ports})`** —
  the sole constructor. Store / export factories are records-based:
  `(counter: CounterStore(), repo: NotesStore())`.
- **Lifecycle** — `disabled` → `pending` → `active` → back to
  `disabled`. Stores are constructed eagerly during `start()`; only
  `onStart` reruns on activation cycles.
- **Activation helpers** — `manualActivation`, `whenActive(parent)`,
  `whenInactive(parent)`, `whenAllActive([...])`, `whenStoreState(...)`.

### Stores

`Store<T>` wraps reactive state with listeners, async tasks, and
structural integration into the feature's `scopeApi`.

```dart
class AuthStore extends Store<({User? user})> {
  AuthStore() : super(state: (user: null));

  late final login = createTask(
    fn: (String name) async {
      await Future.delayed(const Duration(milliseconds: 200));
      update((_) => (user: (name: name)));
    },
    strategy: TaskStrategy.queue,
  );

  void logout() => update((_) => (user: null));
}
```

### Ports

Extension points that other features plug into. Three kinds in
`armature` core:

- **`Pipe<T>`** — sequential transformation. Each active handler
  receives the previous value, returns the next.
- **`Behavior<TBranch, TPayload>`** — priority-based selection. Active
  handlers return `BehaviorDescriptor(...)`; highest priority wins.
- **Slots** (`SingleSlot` / `MultiSlot`) — Flutter widgets; live in
  `armature_flutter`.

```dart
// In owner's ports record:
final themeBehavior = createBehavior<ThemeMode, ThemeData>(name: 'theme');

// In child feature:
nightFeature.useBehavior(layoutFeature.ports.themeBehavior, (api) {
  if (!api.own.night.state.enabled) return null;
  return (branch: ThemeMode.dark, payload: ThemeData.dark());
}, priority: 10);
```

### Tasks

Strategy-backed async operations:

- `.once` — blocks concurrent invocations until done.
- `.queue` — FIFO sequential queue.
- `.latest` — only the most recent input finishes.
- `.debounce(duration)` — fires once after quiet period.
- `.throttle(duration, edge)` — rate-limit with leading / trailing
  edge control.

### Error routing

Everything user-actionable reaches `ContainerOptions.errorHandler`:

| What | Error type | `source` |
|---|---|---|
| `onStart` / `activation` / handler throw | `HandlerError` | feature name |
| Listener throw on `featureStatusChanged` | `ListenerError` | feature name |
| Listener throw on `portChanged` | `ListenerError` | `'<events>'` |
| Port mis-scoped apply | `PortError` | feature name |
| Slot widget build throw | `RenderError` | feature name |
| `onDispose` callback throw | `HandlerError` | `'<container>'` |

## Learn more

- [`armature_flutter`](https://pub.dev/packages/armature_flutter) — Flutter
  integration: `ArmatureApp`, slot widgets, providers, debug overlay.
- [`armature_reactive`](https://pub.dev/packages/armature_reactive) —
  underlying reactive primitives.
- [`armature_graph`](https://pub.dev/packages/armature_graph) — DAG
  resolver used for dependency graph.
- [Monorepo README](https://github.com/telchardev/armature) — full
  architecture reference with extended examples.

## License

MIT — see [LICENSE](LICENSE).
