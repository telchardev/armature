import 'package:armature/armature.dart' show Store;
import 'package:flutter/widgets.dart';

import '../contexts/store_context.dart' show StoreContext;
import './state_observer.dart' show StateObserver;

/// Reactive builder that looks up `T` via [StoreContext] and rebuilds
/// whenever the store's observed state changes.
///
/// Combines [StateObserver] (reactive tracking) with the typed DI
/// lookup into a single wrapper so the common pattern
///
/// ```dart
/// StateObserver(
///   builder: (context) {
///     final store = StoreContext.of<CounterStore>(context);
///     return Text('${store.state.count}');
///   },
/// )
/// ```
///
/// becomes
///
/// ```dart
/// StoreBuilder<CounterStore>(
///   builder: (context, store) => Text('${store.state.count}'),
/// )
/// ```
///
/// The inner [StateObserver] owns a [Reaction] that tracks any
/// `store.state` / `Atom` read during the build — reads don't have to
/// go through the `store` argument to be tracked (`context.store<T>()`
/// inside the builder works the same way).
///
/// For imperative reads (tap handlers, etc.) without rebuilds, call
/// `context.store<T>()` or [StoreContext.of] directly.
class StoreBuilder<T extends Store> extends StatelessWidget {
  /// Called with the resolved store; the returned widget is what the
  /// enclosing [StoreBuilder] renders.
  final Widget Function(BuildContext context, T store) builder;

  const StoreBuilder({super.key, required this.builder});

  @override
  Widget build(BuildContext context) {
    return StateObserver(
      builder: (ctx) => builder(ctx, StoreContext.of<T>(ctx)),
    );
  }
}
