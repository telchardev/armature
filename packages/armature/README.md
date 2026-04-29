# armature

[![pub package](https://img.shields.io/pub/v/armature.svg)](https://pub.dev/packages/armature)
[![likes](https://img.shields.io/pub/likes/armature?logo=dart)](https://pub.dev/packages/armature/score)
[![points](https://img.shields.io/pub/points/armature?logo=dart)](https://pub.dev/packages/armature/score)
[![CI](https://github.com/telchardev/armature/actions/workflows/armature_ci.yml/badge.svg?branch=main)](https://github.com/telchardev/armature/actions/workflows/armature_ci.yml)

Feature-based application framework with dependency-graph resolution, reactive stores, typed ports (`Pipe` / `Behavior` / Slots), and tasks. **Pure Dart**; pair with [`armature_flutter`](https://pub.dev/packages/armature_flutter) for Flutter UI.

Large applications quickly devolve into a web of providers and singletons. `armature` solves this by giving each feature explicit dependencies, eager store construction, and extension points (ports) that other features plug into without mutual knowledge.

## Install

```yaml
dependencies:
  armature: ^0.4.0
  armature_flutter: ^0.4.0   # if you want the Flutter integration
```

## Quickstart

A self-contained Pure Dart "hello world" with two features composing through a dependency. The Logger feature subscribes to the Counter feature's store and prints every change.

```dart
import 'package:armature/armature.dart';

typedef CounterState = ({int value});

class CounterStore extends Store<CounterState> {
  CounterStore() : super(state: (value: 0));
  void increment() => update((s) => (value: s.value + 1));
}

final counterFeature = createFeature(
  name: 'Counter',
  stores: (_) => (counter: CounterStore()),
  exports: (api) => api.own,
);

// A second feature observes the counter through the dependency edge.
final loggerFeature = createFeature(
  name: 'Logger',
  dependsOn: [counterFeature],
)..onStart((api, cleanup) {
  final counter = api.of(counterFeature).counter;
  cleanup.subscribe(
    counter,
    (_, s) => print('counter: ${s.value}'),
    fireImmediately: true,
  );
  counter.increment();
  counter.increment();
});

Future<void> main() async {
  final container = AppContainer(
    features: [counterFeature, loggerFeature],
  );
  await container.start();
  // Logger prints: counter: 0, counter: 1, counter: 2
  await container.stop();
}
```

For the Flutter integration (`ArmatureApp`, slot widgets, `StoreBuilder`/`StoreSelector`, debug overlay), see [`armature_flutter`](https://pub.dev/packages/armature_flutter).

## Core concepts

### Features

- **`createFeature({name, dependsOn, optionalDependsOn, stores, exports, ports})`** — the sole constructor. Store / export factories are records-based: `(counter: CounterStore(), repo: NotesStore())`.
- **Lifecycle** — `disabled` → `pending` → `active` → back to `disabled`. Stores are constructed eagerly during `start()`; only `onStart` reruns on activation cycles.
- **Activation helpers** — `manualActivation`, `whenActive(parent)`, `whenInactive(parent)`, `whenAllActive([...])`, `whenStoreState(...)`.

### Stores

`Store<T>` wraps reactive state with listeners, async tasks, and structural integration into the feature's `scopeApi`.

```dart
typedef NotesState = ({List<String> items});

class NotesStore extends Store<NotesState> {
  NotesStore() : super(state: (items: const []));

  void add(String text) => update((s) => (items: [...s.items, text]));

  late final persist = createVoidTask(
    fn: () async => await db.write(state.items),
    strategy: TaskStrategy.debounce(Duration(milliseconds: 300)),
  );
}
```

### Ports

Extension points that other features plug into. Three kinds in `armature` core:

- **`Pipe<T>`** — sequential transformation. Each active handler receives the previous value, returns the next.
- **`Behavior<TBranch, TPayload>`** — priority-based selection. Active handlers return `BehaviorDescriptor(...)`; highest priority wins.
- **Slots** (`SingleSlot` / `MultiSlot`) — Flutter widgets; live in `armature_flutter`.

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

Strategy-backed async operations. `strategy:` is optional — `Store.createTask` / `createVoidTask` default to `.queue`.

- `.queue` **(default)** — FIFO sequential queue.
- `.once` — blocks concurrent invocations until done.
- `.latest` — only the most recent input finishes.
- `.debounce(duration)` — fires once after quiet period.
- `.throttle(duration, edge)` — rate-limit with leading / trailing edge control.

Lifecycle: `task.reset()` returns the state to `TaskIdle` (cancels coalesced callers from `.latest` / `.debounce` / `.throttle(trailing)` with `TaskError`, drops state writes from any in-flight run, clears the `.once` cache). Pass `autoReset: duration` at creation to schedule the same transition automatically after `TaskDone` / `TaskFailed`.

**Picking `TError`** — the third generic decides which thrown values land in `TaskFailed` (sticky, observable in UI) vs propagate from `await task(...)` and revert state to `TaskIdle`:

| `TError =` | Behaviour | When to use |
|---|---|---|
| `Exception` | `Exception` subclasses stick; `Error` propagates | Default for API / IO. Domain failures show in UI; programming bugs surface to the error handler. |
| domain class (e.g. `ApiError`) | Only that family sticks | Strongly typed errors; UI pattern-matches on specific cases. |
| `Never` | Nothing sticks | Task isn't expected to throw in normal flow — any throw is a bug. |
| `Object` | Everything sticks, including bugs | Last resort. Loses the bug-vs-domain distinction. |

```dart
// Default for API/IO calls.
late final fetchUser = createTask<int, User, Exception>(
  fn: (id) async => api.getUser(id),
);

// Typed exception hierarchy.
late final placeOrder = createTask<OrderRequest, OrderId, OrderError>(
  fn: (req) async => api.placeOrder(req),
);

// Strict — fn shouldn't fail; any throw escalates to the caller.
late final increment = createVoidTask<int, Never>(
  fn: () async => state.value + 1,
);
```

### Error routing

Everything user-actionable reaches `ContainerOptions.errorHandler`:

| What | Error type | `source` |
|---|---|---|
| `onStart` / `activation` / handler throw | `HandlerError` | feature name |
| Listener throw on `featureStatusChanged` | `ListenerError` | feature name |
| Listener throw on `portChanged` | `ListenerError` | `'<events>'` |
| Port mis-scoped apply | `PortError` | feature name |
| Slot widget build throw | `RenderError` | feature name |

## Advanced surface

`package:armature/armature.dart` exposes the ~25 symbols you need to author features, stores, tasks, and ports. Two extra barrels exist for narrower needs:

```dart
import 'package:armature/advanced.dart';   // application-level escape hatch
import 'package:armature/framework.dart';  // sibling-package plumbing
```

* **`advanced.dart`** — handler / listener typedefs (`BehaviorHandler`, `PipeHandler`, `TaskFn`, `StateChangeListener`, ...), individual `TaskStrategy*` constructor classes, debug-overlay mirrors (`ContainerDebug`, `FeatureDebugInfo`, `PortDebugInfo`), and `LoggerDebugInfo`. Reach for it when you need to type-annotate a handler field, build a custom debug overlay, or implement a custom `Logger`.
* **`framework.dart`** — base port hierarchy (`Port`, `AnyPort`, `PortType`, `PortSubscription`). This is plumbing that `armature_flutter` and custom `Renderer` implementations need; **application code should not import it** — typed APIs (`Pipe`, `Behavior`, slot widgets) cover every end-user scenario.

Day-to-day feature / store code only needs `armature.dart`.

## Learn more

- 📖 **[Documentation site](https://telchardev.github.io/armature/)** — full guide with mental model, glossary, and a Notes/Todo example that builds out every concept.
- [`armature_flutter`](https://pub.dev/packages/armature_flutter) — Flutter integration: `ArmatureApp`, slot widgets, providers, debug overlay.
- [`armature_reactive`](https://pub.dev/packages/armature_reactive) — underlying reactive primitives.
- [`armature_graph`](https://pub.dev/packages/armature_graph) — DAG resolver used for dependency graph.
- [examples/armature_example](https://github.com/telchardev/armature/tree/main/examples/armature_example) — multi-feature reference app.

## License

MIT — see [LICENSE](LICENSE).
