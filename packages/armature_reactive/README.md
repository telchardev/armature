# armature_reactive

Lightweight MobX-style reactive primitives — `Atom`, `Reaction`, and
automatic dependency tracking — for **pure Dart**. No Flutter
dependency; consumed by [`armature`](https://pub.dev/packages/armature)
and [`armature_flutter`](https://pub.dev/packages/armature_flutter) but
usable standalone.

## Core primitives

### `Atom<T>`

An observable cell. Reads inside a reaction register the reading reaction
as an observer; writes notify every registered observer.

```dart
final counter = Atom<int>(0);

counter.value = 1;            // imperative write
print(counter.value);         // imperative read
```

### `Reaction`

A side-effect that re-runs when any tracked atom changes. Use `track()`
to open a dependency-scope — every atom read inside gets wired as a
dependency.

```dart
final reaction = Reaction(onInvalidate: () {
  print('dependencies changed');
});

reaction.track(() {
  print(counter.value); // reading inside track → tracked
});

counter.value = 2; // invokes onInvalidate asynchronously
```

Call `reaction.clear()` when done — detaches the reaction from all
atoms it observed.

### Batching

Multiple writes inside `startBatch()` / `endBatch()` coalesce into a
single invalidation pass. Useful when you want "N writes, 1 reaction
fire".

```dart
startBatch();
a.value = 1;
b.value = 2;
endBatch();  // reactions observing a or b fire exactly once
```

Reactions re-run until they stabilise (fixed-point); the iteration cap
(`ReactiveConfig.maxIterations`, default 100) guards against
oscillating cycles.

## Install

```yaml
dependencies:
  armature_reactive: ^0.1.0
```

## Learn more

- [`armature`](https://pub.dev/packages/armature) — feature framework
  that builds Store / State on top of these primitives.
- [Monorepo README](https://github.com/telchardev/armature) — full
  architecture and examples.

## License

MIT — see [LICENSE](LICENSE).
