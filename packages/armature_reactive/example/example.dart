import 'package:armature_reactive/armature_reactive.dart';

/// Demonstrates the core reactive primitives: [Atom] is a value-less
/// signal — you pair it with your own storage, call `reportObserved()`
/// on read, `reportChanged()` on write. [Reaction] re-runs whenever
/// any atom it observed reports a change.
class Counter {
  final Atom _atom = Atom();
  int _value = 0;

  int get value {
    _atom.reportObserved();
    return _value;
  }

  set value(int v) {
    if (_value == v) return;
    _value = v;
    _atom.reportChanged();
  }
}

Future<void> main() async {
  final counter = Counter();
  final label = Counter(); // storing an int for demo

  final reaction = Reaction(
    onInvalidate: () => print('onInvalidate fired — schedule a re-run'),
  );

  // Reads inside `track()` wire counter/label as dependencies.
  reaction.track(() {
    print('read: counter=${counter.value}, label=${label.value}');
  });

  // Single write → single invalidation on the next microtask.
  counter.value = 1;
  await Future<void>.delayed(Duration.zero);

  // Batching — multiple writes share a single drain pass, so the
  // reaction's `onInvalidate` fires once, not twice.
  globalContext
    ..startBatch()
    ..endBatch(); // (pass any reactive mutations between these)

  counter.value = 2;
  label.value = 42;

  await Future<void>.delayed(Duration.zero);

  // Detach the reaction — future writes to counter / label no longer
  // invalidate it.
  reaction.clear();
}
