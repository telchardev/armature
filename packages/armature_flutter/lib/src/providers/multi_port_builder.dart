import 'package:armature/advanced.dart' show BehaviorHandler, PipeHandler;
import 'package:armature/framework.dart' show Port;
import 'package:armature/armature.dart'
    show
        AppContainer,
        ArmatureError,
        Behavior,
        BehaviorDescriptor,
        Feature,
        Pipe,
        RenderError;
import 'package:armature_reactive/armature_reactive.dart' show Reaction;
import 'package:flutter/widgets.dart'
    show BuildContext, State, StatefulWidget, Widget;

import '../contexts/container_context.dart' show ContainerContext;
import '../contexts/feature_context.dart' show FeatureContext;
import '../ports/multi_slot.dart' show MultiSlot, MultiSlotHandler;
import '../ports/single_slot.dart' show SingleSlot, SingleSlotHandler;
import '../stores/safe_set_state_mixin.dart' show SafeSetStateMixin;

typedef _AnyPort = Port<dynamic, Object?, Function>;

typedef _ReportError = void Function(Feature feature, ArmatureError error);

/// Reader passed to a [MultiPortBuilder] builder. Each method call reads
/// the current value of a port — atoms the port handlers read during
/// that call are tracked by the enclosing widget's [Reaction], so the
/// builder rebuilds automatically when any of them change.
///
/// Ports that the builder touched during the last build are tracked
/// separately so the widget can subscribe to handler-set flips
/// (feature activation / deactivation) in addition to reactive atom
/// changes — handler-set changes affect `port.apply` output without
/// touching any atom and would otherwise be invisible to a
/// reaction-only tracker.
final class PortReader {
  final AppContainer _container;
  final Feature _feature;
  final Set<_AnyPort> _tracked;
  final _ReportError _reportError;

  PortReader._(
    this._container,
    this._feature,
    this._tracked,
    this._reportError,
  );

  /// Reads the current widget from a [SingleSlot]. Returns `null`
  /// (or [fallback]) if no handler matches.
  Widget? single<TInputData>(
    SingleSlot<TInputData, SingleSlotHandler<TInputData>> slot, {
    required TInputData data,
    Widget? fallback,
  }) {
    _tracked.add(slot);
    try {
      final Widget? value = _container.apply(
        rootFeature: _feature,
        port: slot,
        initialValue: null,
        data: data,
      );
      return value ?? fallback;
    } on Object catch (e, st) {
      _reportRender(e, st);
      return fallback;
    }
  }

  /// Reads the current list of widgets from a [MultiSlot].
  List<Widget> multi<TInputData>(
    MultiSlot<TInputData, MultiSlotHandler<TInputData>> slot, {
    required TInputData data,
    List<Widget> fallback = const <Widget>[],
  }) {
    _tracked.add(slot);
    try {
      return _container.apply(
        rootFeature: _feature,
        port: slot,
        initialValue: <Widget>[],
        data: data,
      );
    } on Object catch (e, st) {
      _reportRender(e, st);
      return fallback;
    }
  }

  /// Reads the current value from a [Pipe].
  TValue pipe<TValue extends Object>(
    Pipe<TValue, PipeHandler<TValue>> pipe, {
    required TValue initialValue,
  }) {
    _tracked.add(pipe);
    try {
      return _container.apply(
        rootFeature: _feature,
        port: pipe,
        initialValue: initialValue,
        data: null,
      );
    } on Object catch (e, st) {
      _reportRender(e, st);
      return initialValue;
    }
  }

  /// Reads the current descriptor from a [Behavior].
  BehaviorDescriptor<TBranch, TPayload>
  behavior<TBranch extends Enum, TPayload>(
    Behavior<TBranch, TPayload, BehaviorHandler<TBranch, TPayload>> behavior, {
    required BehaviorDescriptor<TBranch, TPayload> initialValue,
  }) {
    _tracked.add(behavior);
    try {
      return _container.apply(
        rootFeature: _feature,
        port: behavior,
        initialValue: initialValue,
        data: null,
      );
    } on Object catch (e, st) {
      _reportRender(e, st);
      return initialValue;
    }
  }

  void _reportRender(Object error, StackTrace stackTrace) {
    try {
      _reportError(
        _feature,
        RenderError.wrap(_feature.name, error, stackTrace: stackTrace),
      );
    } on Object {
      // swallow — we're on the build path; the fallback is already correct
    }
  }
}

typedef MultiPortWidgetBuilder =
    Widget Function(PortReader reader, BuildContext context);

/// Reads multiple ports in a single builder with fine-grained reactivity.
///
/// Unlike the per-kind providers ([SingleSlotProvider], [MultiSlotProvider],
/// [PipeProvider], [BehaviorProvider]), `MultiPortBuilder` lets you read
/// any mix of ports inside one flat builder. The widget owns a single
/// [Reaction] whose track/untrack diff follows whatever atoms the last
/// build actually read, plus a set of per-port subscriptions to
/// "handler set changed" events so activation / deactivation of
/// handler-owning features also triggers a rebuild.
///
/// ```dart
/// MultiPortBuilder(
///   builder: (reader, context) {
///     final title = reader.single(titleSlot, data: mode);
///     final actions = reader.multi(actionsSlot, data: mode);
///     final tabs = reader.pipe(tabsPipe, initialValue: const <TabSpec>[]);
///     return Scaffold(
///       appBar: AppBar(
///         title: title ?? const Text('armature'),
///         actions: actions,
///       ),
///       body: _TabBar(tabs),
///     );
///   },
/// );
/// ```
class MultiPortBuilder extends StatefulWidget {
  final MultiPortWidgetBuilder builder;

  const MultiPortBuilder({super.key, required this.builder});

  @override
  State<MultiPortBuilder> createState() => _MultiPortBuilderState();
}

class _MultiPortBuilderState extends State<MultiPortBuilder>
    with SafeSetStateMixin {
  late final Reaction _reaction;

  /// Ports the reader touched in the current build. Cleared at the
  /// start of every [build]; held as an instance field so we don't
  /// allocate a fresh set per build.
  final Set<_AnyPort> _tracked = {};

  /// Scratch list reused by [_reconcile] to collect ports dropped
  /// between builds. Cleared at the start of every reconcile call.
  final List<_AnyPort> _stale = [];

  /// Bound once in [initState] and reused across builds — equivalent
  /// closure was previously rebuilt every [build].
  late final _ReportError _reportError;

  /// Per-port handler-set subscription disposers, keyed by the port
  /// the reader touched. Reconciled on every build so a port dropped
  /// between builds releases its subscription; a newly-read port
  /// picks one up.
  final Map<_AnyPort, void Function()> _handlerSubs = {};

  @override
  void initState() {
    super.initState();
    _reaction = Reaction(onInvalidate: safeSetState);
    _reportError = (f, err) {
      ContainerContext.of(
        context,
      ).container.reportError(feature: f, error: err);
    };
  }

  @override
  Widget build(BuildContext context) {
    final container = ContainerContext.of(context).container;
    final feature = FeatureContext.of(context).feature;
    _tracked.clear();

    final reader = PortReader._(container, feature, _tracked, _reportError);

    late Widget result;
    try {
      _reaction.track(() {
        result = widget.builder(reader, context);
      });
      return result;
    } finally {
      _reconcile(container, _tracked);
    }
  }

  void _reconcile(AppContainer container, Set<_AnyPort> tracked) {
    _stale.clear();
    for (final port in _handlerSubs.keys) {
      if (!tracked.contains(port)) _stale.add(port);
    }
    for (final port in _stale) {
      _handlerSubs.remove(port)!();
    }
    for (final port in tracked) {
      if (_handlerSubs.containsKey(port)) continue;
      _handlerSubs[port] = container.onPortChanged(
        port: port,
        callback: safeSetState,
      );
    }
  }

  @override
  void dispose() {
    _reaction.clear();
    for (final disposer in _handlerSubs.values) {
      disposer();
    }
    _handlerSubs.clear();
    super.dispose();
  }
}
