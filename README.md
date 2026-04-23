![CI](https://github.com/telchardev/armature/actions/workflows/armature_ci.yml/badge.svg?branch=main)

# armature

A framework for building complex, multi-module Flutter applications with feature-based architecture, reactive state management, and a dependency graph that resolves features at startup.

## Why armature?

Large Flutter applications quickly become a tangled mess of providers, singletons, and implicit dependencies. **armature** solves this by:

- **Isolating features** into self-contained modules with explicit dependency declarations
- **Resolving a dependency graph** at startup — features are initialized in the correct order
- **Providing a reactive system** (Atom/Reaction) for fine-grained state tracking
- **Composing UI via ports** — features inject widgets into named extension points without knowing about each other

---

## Architecture

```
+---------------------+       +-------------------+
|   armature_reactive   |       |   armature_graph    |
|   (Atom, Reaction,   |       |   (Graph, Node,    |
|    Context)          |       |    DAG resolution) |
+----------+----------+       +---------+---------+
           |                             |
           +-------------+-------------+
                         |
               +---------+---------+
               |      armature       |
               |  (AppContainer,    |
               |   Feature,         |
               |   Store, Task,     |
               |   Ports)           |
               +---------+---------+
                         |
               +---------+---------+
               |  armature_flutter   |
               |  (ArmatureApp, Slots,|
               |   StoreBuilder /   |
               |   StoreSelector,   |
               |   Providers, FGO)  |
               +-------------------+
```

| Package | Description |
|---------|-------------|
| **armature_reactive** | Lightweight MobX-style reactive primitives (pure Dart, no Flutter dependency) |
| **armature_graph** | Directed acyclic graph with topological resolution and visitor-based activation cascade |
| **armature** | Core framework: AppContainer, Feature, Store, Task, Ports (Pipe, Behavior) |
| **armature_flutter** | Flutter integration: ArmatureApp, slot widgets, reactive providers, `StoreBuilder` / `StoreSelector`, debug overlay |

---

## Getting Started

### 1. Add dependencies

```yaml
# pubspec.yaml
dependencies:
  armature: ^0.1.0
  armature_flutter: ^0.1.0
```

### 2. Define a feature

A **Feature** is an isolated module with its own stores, activation, and declared dependencies.

```dart
import 'package:armature/armature.dart';

class CounterStore extends Store<int> {
  CounterStore() : super(state: 0);

  void increment() => update((state) => state + 1);
}

final counterFeature = createFeature(
  name: "Counter",
  stores: (_) => (counter: CounterStore()),
  // Features that declare `stores:` must also declare `exports:` —
  // `api.own` passes the stores record through unchanged.
  exports: (api) => api.own,
);
```

### 3. Run the app

```dart
import 'package:armature_flutter/armature_flutter.dart';
import 'package:flutter/material.dart';

void main() {
  runApp(ArmatureApp(
    features: [counterFeature],
    child: const MyApp(),
  ));
}
```

---

## Core Concepts

### Features & Dependencies

Features declare their parents explicitly. The framework builds a DAG and resolves features in topological order.

```dart
final layoutFeature = createFeature(
  name: "Layout",
  stores: (_) => (activeTab: ActiveTabStore()),
  exports: (api) => api.own,
);

final authFeature = createFeature(
  name: "Auth",
  dependsOn: [layoutFeature],
  stores: (_) => (auth: AuthStore()),
  exports: (api) => api.own,
);

// Optional dependencies stay reachable via `api.from(...)` even when
// inactive — handy for features that merely *decorate* another.
final adminFeature = createFeature(
  name: "Admin",
  dependsOn: [layoutFeature],
  optionalDependsOn: [authFeature],
);
```

### Activation

Without `activation`, a feature auto-activates at `AppContainer.start`. With `activation`, it starts inactive and waits for a trigger to call `toggle(.active / .inactive)`. `onStart` runs on every `inactive→active` transition; stores are constructed once during `AppContainer.start` (eager construct phase) and reused across toggles.

For common patterns there are **activation helpers** so you rarely have to hand-wire subscriptions:

```dart
// Mirror a parent's lifecycle — active iff [authFeature] is active:
adminFeature
  ..activation(whenActive(authFeature));

// Gate on a store's state in a parent feature:
inspectorFeature
  ..activation(whenStoreState(
    feature: featureTogglesFeature,
    store: (exports) => exports.featureToggles,
    predicate: (state) => state.inspector,
  ));

// Other ready-made helpers:
// whenInactive(parent)    — active iff parent is NOT active
// whenAllActive([a, b])   — active iff every listed parent is active
// manualActivation()      — stays disabled until an external toggleFeature call
```

For anything custom, drop to the imperative form:

```dart
adminFeature
  ..activation((parentApi, toggle, cleanup) {
    final auth = parentApi.of(authFeature).auth;
    cleanup.add(auth.subscribe((_, s) {
      toggle(s.user?.name == 'admin' ? .active : .inactive);
    }, fireImmediately: true));
  })
  ..onStart((api, cleanup) async {
    final auth = api.from(authFeature).auth;
    // Per-activation work — `cleanup` runs LIFO on deactivation.
    cleanup.add(auth.subscribe((_, s) => /* react */));
  });
```

### Reactive Feature Status

Inside a port handler / `onStart` / activation setup, `api.statusOf(feature).state` returns the current `FeatureStatus` **reactively** — if you're inside a reaction scope (a port handler body, a `StoreBuilder` / `StoreSelector`), the read subscribes and re-evaluates automatically.

```dart
inspectorSubFeature.useMultiSlot(
  layoutFeature.ports.actionsSlot,
  (_, api) {
    // Hides when inspectorFeature is disabled; reappears on `.active`.
    if (api.statusOf(inspectorFeature).state != .active) return null;
    return IconButton(icon: const Icon(Icons.search), onPressed: ...);
  },
);
```

### Stores & State

`Store<TState>` wraps reactive state with listeners and async tasks. Use records for stores and state:

```dart
typedef User = ({String name});
typedef AuthState = ({User? user});

class AuthStore extends Store<AuthState> {
  AuthStore() : super(state: (user: null));

  late final login = createTask(
    fn: (String name) async {
      await Future<void>.delayed(const Duration(milliseconds: 200));
      update((_) => (user: (name: name)));
    },
    strategy: TaskStrategy.queue,
  );

  void logout() => update((_) => (user: null));
}
```

Access stores from parent features via typed API:

```dart
// In onStart or handler:
final authStore = api.from(authFeature).auth;
final activeTab = api.from(layoutFeature).activeTab;
```

Access stores from widgets — three tools, ordered from imperative to most granular:

```dart
// (1) Imperative one-shot — no rebuild. Best for tap handlers / effects.
onPressed: () => context.store<CounterStore>().increment(),

// (2) Reactive builder — rebuilds on any tracked state read.
StoreBuilder<CounterStore>(
  builder: (context, store) => Text('${store.state}'),
)

// (3) Selector — rebuilds only when the derived value `==`-changes.
StoreSelector<bool>(
  select: (ctx) => ctx.store<CounterStore>().state.isEven,
  builder: (_, isEven) => Text(isEven ? 'even' : 'odd'),
)

// Multi-store mapping via record (record equality short-circuits for free):
StoreSelector<({String name, int count})>(
  select: (ctx) => (
    name: ctx.store<UserStore>().state.name,
    count: ctx.store<CounterStore>().state,
  ),
  builder: (_, data) => Text('${data.name}: ${data.count}'),
)
```

For raw reactive tracking without the typed DI lookup, `StateObserver(builder: ...)` is still available — use it when building custom widgets that read arbitrary `Store.state` / `Atom` reads.

### Ports (Extension Points)

Ports let features extend each other without direct coupling. Inspired by hexagonal architecture (ports & adapters). The owning feature defines the port; child features provide handlers.

Ports are declared at top level; owner binding happens eagerly when you pass `feature:`, or lazily on first apply otherwise:

```dart
// ports.dart
final titleSlot = createSingleSlot<LayoutMode>(name: 'layout.title');
final tabsPipe = createPipe<List<TabSpec>>(name: 'layout.tabs');
final themeBehavior = createBehavior<ThemeMode, ThemeData>(
  name: 'layout.theme',
);

// config.dart — ports record for typed access
final layoutFeature = createFeature(
  name: "Layout",
  ports: (
    titleSlot: titleSlot,
    tabsPipe: tabsPipe,
    themeBehavior: themeBehavior,
  ),
  stores: (_) => (activeTab: ActiveTabStore()),
  exports: (api) => api.own,
);

// Other features access via typed record:
// layoutFeature.ports.titleSlot
```

#### Pipe — sequential transformation

```dart
counterFeature.usePipe(layoutFeature.ports.tabsPipe, (tabs, _) {
  return [...tabs, (id: 'counter', label: 'Counter', icon: Icons.add)];
});
```

#### Behavior — priority-based selection

```dart
nightModeFeature.useBehavior(layoutFeature.ports.themeBehavior, (api) {
  if (!api.own.nightMode.state.enabled) return null;
  return (branch: ThemeMode.dark, payload: ThemeData.dark());
}, priority: 10);
```

### Slots (Flutter UI Composition)

Slots are ports that produce widgets. Handlers return `Widget?` — return `null` to skip rendering. Pass an optional `loader:` builder to render a placeholder while the owning feature is `.pending`.

#### SingleSlot — one widget, highest priority wins

```dart
authFeature.useSingleSlot(
  layoutFeature.ports.titleSlot,
  (_, api) {
    final user = api.own.auth.state.user;
    if (user == null) return null;
    return Text('Hello, ${user.name}');
  },
  priority: 2,
  loader: () => const CircularProgressIndicator(),
);
```

#### MultiSlot — multiple widgets, ordered

```dart
counterFeature.useMultiSlot(
  layoutFeature.ports.fabSlot,
  (_, api) => FloatingActionButton(
    onPressed: () => api.own.counter.increment(),
    child: const Icon(Icons.add),
  ),
  order: 1,
);

// Conditional rendering — return null to skip:
authFeature.useMultiSlot(
  layoutFeature.ports.actionsSlot,
  (_, api) {
    if (api.own.auth.state.user == null) return null;
    return IconButton(
      icon: const Icon(Icons.logout),
      onPressed: api.own.auth.logout,
    );
  },
  order: 2,
);
```

#### Rendering in the widget tree

```dart
SingleSlotProvider(
  slot: titleSlot,
  data: LayoutMode.phone,
  builder: (child, context) => child ?? const Text("No title"),
);

MultiSlotProvider(
  slot: actionsSlot,
  data: LayoutMode.phone,
  builder: (children, context) => Row(children: children),
);

PipeProvider(
  pipe: tabsPipe,
  initialValue: const <TabSpec>[],
  builder: (tabs, context) => TabBar(
    tabs: [for (final t in tabs) Tab(text: t.label)],
  ),
);

// Read multiple ports in a single builder with fine-grained reactivity:
MultiPortBuilder(
  builder: (reader, context) {
    final tabs = reader.pipe(tabsPipe, initialValue: const <TabSpec>[]);
    final actions = reader.multi(actionsSlot, data: LayoutMode.phone);
    return Scaffold(
      appBar: AppBar(actions: actions),
      body: TabBar(tabs: [for (final t in tabs) Tab(text: t.label)]),
    );
  },
);
```

### Reactive Primitives (armature_reactive)

Low-level building blocks — used internally by `Store` / `StateObserver` / `StoreBuilder`, but available standalone:

```dart
final atom = Atom();
final reaction = Reaction(
  onInvalidate: () => print("atom changed!"),
);

reaction.track(() {
  atom.reportObserved();
});

atom.reportChanged(); // fires onInvalidate

reaction.clear();
```

---

## Error Handling

armature provides a sealed [`ArmatureError`](packages/armature/lib/src/errors.dart) hierarchy split by purpose — `on ArmatureError` catches every framework error in one arm.

```
ArmatureError                      // sealed base
  ├── ContainerError             // wrong lifecycle state (disposed, already started)
  ├── ContainerUsageError        // misuse (dispose from a user callback, etc.)
  ├── FeatureConfigurationError  // activation()/onStart() twice, stores-without-exports
  ├── TaskError                  // Task called after dispose
  ├── PortError                  // port misuse (wrong owner, duplicate handler)
  ├── StoreLookupError           // api.store<T>() miss
  ├── FeatureResolutionError     // start-time failure (cycle, missing parent, factory throw)
  ├── HandlerError               // user handler (activation / onStart / port handler) threw
  ├── ListenerError              // onFeatureStatusChanged / onPortChanged listener threw
  └── RenderError                // slot widget build threw
```

**One sink.** Every **user-actionable, recoverable** error lands in `ContainerOptions.errorHandler` with a `source:` label attributing the failure:

| `source` | Means |
|---|---|
| `<feature name>` | The feature this error is about |
| `'<container>'` | Container-lifecycle throws — `onDispose` callback, pre-start failures |
| `'<events>'` | Listener throws on container-scoped events (`portChanged`) — not attributable to a single feature |

```dart
runApp(ArmatureApp(
  features: [...],
  containerOptions: ContainerOptions(
    errorHandler: ({required source, required error, required meta}) {
      switch (error) {
        case HandlerError():
          logger.warning('Handler in $source: $error');
        case RenderError():
          logger.severe('Render in $source: $error');
        case ListenerError():
          logger.info('Listener in $source: $error');
        default:
          logger.warning('$source: $error');
      }
    },
    maxResolveConcurrency: 8,
  ),
  child: const MyApp(),
));
```

**Fatal errors** (the ones that don't reach `errorHandler`) are thrown out of the call that triggered them — programming errors (`ContainerUsageError`, `FeatureConfigurationError`, `TaskError`, registration-time `PortError`, `StoreLookupError`) and start-time `FeatureResolutionError`. Catch them with `on ArmatureError`.

The `Logger` (wired via `ArmatureApp(logger: ...)`) is purely for framework-internal diagnostics — `.debug` traces plus one last-resort `.error` if your own `errorHandler` throws.

---

## Debug Overlay

Enable the debug overlay to visualize the feature graph, inspect state, and see port connections:

```dart
ArmatureApp(
  features: [...],
  child: FeatureGraphOverlay(
    enabled: kDebugMode,
    child: layoutRoot(data: null),
  ),
);
```

Capabilities:

- **Interactive DAG** — pan / zoom / long-press-drag to rearrange nodes; the dragged node gets a soft outer glow for visual feedback.
- **Gesture hint** next to the tab header reminds you what tap / long-press do.
- **Node detail panel** — tap a node to see dependencies, ports, handlers, and a live store inspector that re-renders on state change.
- **State Inspector tab** — every active store's state across the whole app, expandable, pretty-printed (`toJson()` plus a record-aware formatter).
- **Minimap** — viewport-aware overview with auto-updating bounds.
- **Refresh FAB** — picks up newly-added features and current statuses, re-runs layout, **preserves** selection and any manually-dragged node positions.

---

## Container Lifecycle

```dart
// ArmatureApp handles start/dispose automatically.
// For manual control:
final container = ContainerContext.of(context).container;

container.statusOf(authFeature) == FeatureStatus.active;  // true/false
container.status;                         // idle / starting / working / disposed

container.onFeatureStatusChanged(
  feature: authFeature,
  callback: () => print("Auth feature status changed"),
);

container.onPortChanged(
  port: titleSlot,
  callback: () => print("Title slot handler set changed"),
);

// Imperative toggle from outside an activation setup:
await container.toggleFeature(someGatedFeature, .active);

await container.dispose();
```

### Internal API boundary

Symbols annotated `@internal` (e.g. `AppContainer.graph`, `Feature.internal`,
`Port.addHandler`) and files under `package:armature/src/...` are framework
plumbing. Triggering lint warnings (`invalid_use_of_internal_member`,
`implementation_imports`) signals you're reaching into an unstable surface
and may break on upgrade. Use only the public API exported from
`package:armature/armature.dart`.

---

## Full Example

See [`examples/armature_example/`](examples/armature_example/) — a synthetic **Kitchen Sink** showcase: nine tiny features, each isolating one framework capability. Stock Material UI (Inter + `ColorScheme.fromSeed`) so the architecture is what you notice.

**Features:**

- **Layout** — root feature. Declares every port (`titleSlot`, `tabsPipe`, `bodySwitchSlot`, `actionsSlot`, `fabSlot`, `themeBehavior`) and owns `ActiveTabStore`. The shell wires them up with `BehaviorProvider` / `SingleSlotProvider` / `MultiSlotProvider` / `PipeProvider`.
- **Counter** — `Store<CounterState>` with `createVoidTask` / `createTask(.queue)`. Contributes a FAB via `useMultiSlot` that returns `null` unless the Counter tab is active (conditional `null` pattern), plus an always-visible badge in the app bar.
- **History** — depends on Counter. In `onStart`, calls `api.from(counterFeature).counter.subscribe(...)` to mirror every counter tick into its own list. Pure cross-feature reactive propagation.
- **Auth** — repository injected into the stores factory (`SharedPrefsAuthRepository`); `createVoidTask(.once)` for `load()`, `createTask(.queue)` for `login()`. Overrides the `titleSlot` when logged in and adds a conditional logout action to `actionsSlot`.
- **Admin** — **reactive** conditional ports (no `activation()`). `usePipe` / `useSingleSlot` handlers read `api.from(authFeature).auth.state` and re-evaluate when it changes; the tab appears the moment you log in as `admin` and disappears on logout. Uses `optionalDependsOn` for `authFeature` and `counterFeature` — both stay reachable via `api.from` regardless of activation.
- **NightMode** — `useBehavior(priority: 10)` overrides the shell's `BehaviorProvider.initialValue` (light theme) when enabled. Persists via `SharedPreferences`. The action button adapts to `LayoutMode.phone` (icon only) vs `LayoutMode.tablet` (icon + label) — typed slot data in action.
- **FeatureToggles** — runtime switches kept in a `Store`. Consumed by Inspector through the `whenStoreState` activation helper.
- **Inspector** — `..activation(whenStoreState(feature: featureTogglesFeature, store: (e) => e.featureToggles, predicate: (s) => s.inspector))` — one-liner thanks to the activation helpers. Self-contained diagnostic view (build mode, platform, JIT/AOT, refresh counter).
- **InspectorSub** — `optionalDependsOn: [inspectorFeature]`, `..activation(whenActive(inspectorFeature))`. Its `actionsSlot` button lives exactly as long as `inspectorFeature` does: when you toggle Inspector off in FeatureToggles, InspectorSub deactivates and the button disappears automatically.

```
Layout (root)
  ├── Counter
  ├── History         → Counter
  ├── Auth
  ├── Admin           → Auth, Counter (both optional)
  ├── NightMode
  ├── FeatureToggles
  ├── Inspector       → FeatureToggles (activation: whenStoreState)
  └── InspectorSub    → Inspector (optional; activation: whenActive)
```

**Capabilities covered:** feature DAG with `dependsOn` / `optionalDependsOn`, `Store` with records + `copyWith` extensions, `createTask` / `createVoidTask` in both `.once` and `.queue` strategies, every port kind (`Pipe` / `SingleSlot` / `SingleSwitchSlot` / `MultiSlot` / `Behavior` with priorities), conditional `null` from `useMultiSlot` / `useSingleSlot` handlers, `onStart` + `subscribe` + `cleanup` cross-feature reactive, repository injected via the stores factory + `SharedPreferences`, reactive port-handler re-evaluation, activation helpers (`whenStoreState`, `whenActive`), and typed slot data (`LayoutMode` phone/tablet).

Run it with:

```sh
flutter run
```

No API keys, no network — everything is in-process except the two `SharedPreferences`-backed features.

---

## Packages

| Package | Version | Dart SDK | Description |
|---------|---------|----------|-------------|
| [`armature`](https://pub.dev/packages/armature) | 0.1.0 | `^3.11.0` | Core framework — features, stores, tasks, ports |
| [`armature_flutter`](https://pub.dev/packages/armature_flutter) | 0.1.0 | `^3.11.0` | Flutter integration — `ArmatureApp`, slots, providers, debug overlay |
| [`armature_reactive`](https://pub.dev/packages/armature_reactive) | 0.1.0 | `^3.11.0` | Reactive primitives — `Atom`, `Reaction` |
| [`armature_graph`](https://pub.dev/packages/armature_graph) | 0.1.0 | `^3.11.0` | DAG resolver — topological ordering, visitor |

## License

MIT — see [LICENSE](LICENSE).
