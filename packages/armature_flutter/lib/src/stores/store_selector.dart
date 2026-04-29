import 'package:armature_reactive/armature_reactive.dart' show Reaction;
import 'package:flutter/widgets.dart';

import './safe_set_state_mixin.dart' show SafeSetStateMixin;

/// Reactive widget that derives a value from one or more stores and
/// rebuilds the [builder] subtree **only when the derived value
/// changes** (by `==`).
///
/// Compared to `StoreBuilder<T>` / `StateObserver` — which invoke
/// their builder on every tracked-atom change — [StoreSelector] adds
/// an equality short-circuit: when [select]'s output `==` the
/// previous value, the cached widget is returned directly and the
/// subtree is not rebuilt. Use this to:
///
/// 1. **Derive a scalar** (perf optimisation).
/// 2. **Combine multiple stores** into a record or view-model.
/// 3. **Narrow a large state** to the one field a widget actually
///    needs.
///
/// ```dart
/// // 1. Scalar derivation — Text rebuilds only when parity flips:
/// StoreSelector<bool>(
///   select: (ctx) => ctx.store<CounterStore>().state.isEven,
///   builder: (_, isEven) => Text(isEven ? 'even' : 'odd'),
/// )
///
/// // 2. Multi-store record — rebuilds on any field change, thanks to
/// //    Dart 3's structural `==` on records:
/// StoreSelector<({String name, int count})>(
///   select: (ctx) => (
///     name: ctx.store<UserStore>().state.name,
///     count: ctx.store<CounterStore>().state,
///   ),
///   builder: (_, data) => Text('${data.name}: ${data.count}'),
/// )
///
/// // 3. View-model — `DashboardVm` must override `==` / `hashCode`
/// //    (e.g. via `freezed` / `equatable`) for the short-circuit to
/// //    fire:
/// StoreSelector<DashboardVm>(
///   select: (ctx) => DashboardVm.fromStores(
///     ctx.store<UserStore>(),
///     ctx.store<OrdersStore>(),
///   ),
///   builder: (_, vm) => DashboardView(vm: vm),
/// )
/// ```
///
/// **Tracking scope.** Only reads executed inside [select] are
/// tracked. Reads inside [builder] (e.g. `context.store<X>().state`)
/// are **not** — they won't re-invalidate the selector. Pull reactive
/// reads into [select] when you want them to drive rebuilds, or use
/// `StoreBuilder<T>` / `StateObserver` instead if granular caching
/// isn't needed.
///
/// **Custom equality.** The short-circuit relies on `==`. Records and
/// primitives work out of the box; mutable classes need `==` /
/// `hashCode` overrides (or a value-equality helper like `freezed` /
/// `equatable`) — otherwise every [select] call produces a new
/// instance and the cache never hits.
class StoreSelector<V> extends StatefulWidget {
  /// Computes the derived value. Invoked inside a [Reaction] so every
  /// `Store.state` / `Atom` read during execution is registered as a
  /// dependency; any of them changing re-runs [select] and the result
  /// is compared to the cached value.
  final V Function(BuildContext context) select;

  /// Builds the subtree for [value]. Only re-invoked when [select]
  /// produces a `!=`-different value; otherwise the previously-built
  /// widget instance is returned and Flutter skips the subtree diff.
  final Widget Function(BuildContext context, V value) builder;

  const StoreSelector({super.key, required this.select, required this.builder});

  @override
  State<StoreSelector<V>> createState() => _StoreSelectorState<V>();
}

class _StoreSelectorState<V> extends State<StoreSelector<V>>
    with SafeSetStateMixin {
  late final Reaction _reaction;
  V? _lastValue;
  Widget? _lastChild;
  bool _hasValue = false;

  @override
  void initState() {
    super.initState();
    _reaction = Reaction(onInvalidate: safeSetState);
  }

  @override
  void dispose() {
    _reaction.clear();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    late V value;
    _reaction.track(() {
      value = widget.select(context);
    });

    if (_hasValue && _lastValue == value) {
      // Cached widget skips the selector's subtree diff. Inherited-
      // widget deps deeper down still rebuild via their own Elements.
      return _lastChild!;
    }
    _hasValue = true;
    _lastValue = value;
    _lastChild = widget.builder(context, value);
    return _lastChild!;
  }
}
