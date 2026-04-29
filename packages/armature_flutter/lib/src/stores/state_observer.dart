import 'package:armature_reactive/armature_reactive.dart' show Reaction;
import 'package:flutter/widgets.dart'
    show StatefulWidget, Widget, WidgetBuilder, BuildContext, State;

import './safe_set_state_mixin.dart' show SafeSetStateMixin;

/// Reactive rebuild wrapper. Runs [builder] inside its own [Reaction]
/// so every `Store.state` / `Atom` read during the build registers a
/// dependency; any of them changing schedules a rebuild via
/// [SafeSetStateMixin.safeSetState].
///
/// Use when a widget reads reactive state directly but doesn't want
/// to subscribe to a full port — e.g. rendering a store's value
/// without a provider in between.
///
/// ```dart
/// StateObserver(
///   builder: (context) {
///     final count = StoreContext.of<CounterStore>(context).state;
///     return Text('$count');
///   },
/// )
/// ```
class StateObserver extends StatefulWidget {
  final WidgetBuilder builder;

  const StateObserver({super.key, required this.builder});

  @override
  State<StateObserver> createState() => _StateObserverState();
}

class _StateObserverState extends State<StateObserver> with SafeSetStateMixin {
  late final Reaction _reaction;

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
    return _reaction.track(() => widget.builder(context));
  }
}
