# armature_reactive

Lightweight MobX-style reactive primitives — `Atom`, `Reaction`, and
automatic dependency tracking — for **pure Dart**. No Flutter
dependency; consumed by [`armature`](https://pub.dev/packages/armature)
and [`armature_flutter`](https://pub.dev/packages/armature_flutter) but
usable standalone.

## Core primitives

### `Atom`

A value-less reactive signal. Pair an atom with your own storage —
call `reportObserved()` on read so the ambient reaction subscribes,
and `reportChanged()` on write to fan out invalidations.

```dart
class Counter {
  final _atom = Atom();
  int _value = 0;

  int get value {
    _atom.reportObserved();
    return _value;
  }

  set value(int next) {
    if (next == _value) return;
    _value = next;
    _atom.reportChanged();
  }
}
```

### `Reaction`

A side-effect that re-runs when any tracked atom changes. Use `track()`
to open a dependency-scope — every `Atom.reportObserved` call inside
wires that atom as a dependency.

```dart
final counter = Counter();
final reaction = Reaction(onInvalidate: () {
  print('dependencies changed');
});

reaction.track(() {
  print(counter.value); // reading inside track → tracked
});

counter.value = 2; // schedules onInvalidate on the next batch drain
```

Call `reaction.clear()` when done — detaches the reaction from every
atom it observed.

### Batching

Multiple writes inside `Context.startBatch()` / `Context.endBatch()`
coalesce into a single invalidation pass. Useful when you want
"N writes, 1 reaction fire". Use `globalContext` unless you've created
your own `Context`.

```dart
globalContext.startBatch();
a.value = 1;
b.value = 2;
globalContext.endBatch();  // reactions observing a or b fire once
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
