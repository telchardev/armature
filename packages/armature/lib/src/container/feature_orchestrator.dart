import 'dart:async';
import 'dart:collection' show Queue;

import 'package:armature_graph/armature_graph.dart'
    show Graph, GraphNodeStatus, GraphVisitor;
import 'package:meta/meta.dart';

import '../errors.dart' show ContainerUsageError, HandlerError;
import '../feature/cleanup.dart' show CleanupBag;
import '../feature/feature.dart' show AnyFeature;
import '../feature/feature_status.dart' show FeatureStatus, ToggleState;
import '../user_callback_zone.dart' show runAsUserCallback;
import './container.dart' show AppContainer;

/// Visitor-side of the feature state machine.
///
/// All tree-traversal, state tracking, cascade ordering, and required-
/// parent propagation live in [Graph]. This class supplies only:
///
///   * [shouldBeActive] — reads the runtime's `ownActive` flag.
///   * [onActivate] — fresh per-activation [CleanupBag], awaited
///     `onStart` callback, and per-feature port emission.
///   * [onDeactivate] — per-activation cleanup bag run.
///   * [onError] — forwards caught visitor exceptions to the host.
///
/// Owns startup-time orchestration: builds the underlying [Graph] on
/// first [start] (eagerly constructing every feature's stores in
/// topological order), wires per-feature toggles + lifetime cleanup on
/// the per-container runtime, installs each feature's recorded port
/// bindings into the container's handler map, then runs `activation`
/// setups followed by a single resolve cascade.
///
/// **Invariant:** feature `stores` factories must be synchronous.
/// The eager construct phase relies on this — an async factory would
/// leave the zone-tracked store-map collection in [Store.track] open
/// while other features' factories ran, letting their stores leak into
/// the wrong feature's map.
@internal
final class FeatureOrchestrator implements GraphVisitor<AnyFeature> {
  FeatureOrchestrator({required this.host, required List<AnyFeature> features})
    : _features = features;

  final AppContainer host;

  final List<AnyFeature> _features;

  /// Populated on every [start] (built by [_buildGraph]) and cleared
  /// by [teardown] so the next cycle starts from an empty graph.
  Graph<AnyFeature>? _graph;

  Graph<AnyFeature> get graph {
    final g = _graph;
    if (g == null) {
      throw ContainerUsageError(
        'FeatureOrchestrator.graph is unavailable until AppContainer.start() '
        'succeeds in constructing the dependency graph.',
      );
    }
    return g;
  }

  /// True during the user setup phase only. `_onToggle` uses this to
  /// skip `graph.recompute` while setups are still mutating
  /// `ownActive` flags; a single consolidated `graph.resolve` afterwards
  /// applies every toggle in one cascade.
  bool _inSetupPhase = false;

  /// FIFO buffer of [_onToggle] calls awaiting cascade dispatch. Each
  /// entry carries the feature whose [Graph.recompute] will run plus
  /// the [Completer] returned synchronously to the caller. The drain
  /// loop pops one entry at a time and `await`s its recompute, so two
  /// rapid toggles on different features are observed in invocation
  /// order even when the second is issued from inside the first's
  /// lifecycle callbacks.
  final Queue<_PendingToggle> _pendingToggles = Queue<_PendingToggle>();

  /// Whether [_drainPendingToggles] is currently running. Re-entrant
  /// `_onToggle` calls (e.g. from inside an `onStart` body) observe
  /// this flag, append to [_pendingToggles] and return the completer's
  /// future without spawning a parallel drain.
  bool _draining = false;

  /// Current lifecycle status of [feature]. `FeatureStatus.disabled`
  /// before [start] succeeds.
  FeatureStatus statusOf(AnyFeature feature) {
    return switch (_graph?.statusOf(feature)) {
      GraphNodeStatus.active => FeatureStatus.active,
      GraphNodeStatus.pending => FeatureStatus.pending,
      GraphNodeStatus.disabled || null => FeatureStatus.disabled,
    };
  }

  /// Builds the graph (on first call) then runs the startup sequence:
  /// 1. **Install-port-handlers phase** — every feature's recorded
  ///    [PortBinding]s are installed into the container's per-container
  ///    handler map. No-op across retries since the map is empty on
  ///    every fresh `start()` of this container.
  /// 2. **Construct phase** — run every feature's stores factory in
  ///    topological order through its runtime. Factory throw aborts
  ///    `start()` fail-fast.
  /// 3. **Setup phase** — run user [activationSetup]s. Their `toggle(...)`
  ///    calls just flip the runtime's `ownActive`; the cascade is
  ///    deferred via [_inSetupPhase].
  /// 4. **Resolve phase** — single `graph.resolve()` applies every
  ///    toggle in one cascade.
  Future<void> start() async {
    final g = _graph ??= _buildGraph();

    // Phase 1: install port handlers declared in each feature's
    // config cascade. Must happen before construct because stores
    // factories may observe port values indirectly via scopeApi.
    _installPortHandlers(g);
    if (host.isStopping) return;

    // Phase 2: eager construct. First factory throw aborts start.
    _runConstructPhase(g);
    if (host.isStopping) return;

    // Phase 3: user setups. Batched toggles, no cascade.
    _inSetupPhase = true;
    try {
      await _runActivationSetups(g);
    } finally {
      _inSetupPhase = false;
    }
    if (host.isStopping) return;

    // Phase 4: one cascade (tail-awaits any nested recomputes).
    await g.resolve();
  }

  /// Installs every feature's recorded [PortBinding]s into the
  /// container's port-handler map. The map is per-container, so stale
  /// handlers from a previous container instance never leak into this
  /// one — we always install a fresh handler set on each `start()`.
  void _installPortHandlers(Graph<AnyFeature> g) {
    for (final f in g.topologicalOrder()) {
      if (host.isStopping) return;
      for (final binding in f.config.portBindings) {
        host.addPortHandler(
          port: binding.port,
          feature: f,
          handler: binding.handler,
        );
      }
    }
  }

  /// Constructs every feature's stores in topological order via their
  /// per-container runtime.
  void _runConstructPhase(Graph<AnyFeature> g) {
    for (final f in g.topologicalOrder()) {
      if (host.isStopping) return;
      host.runtimeOf(f).construct();
    }
  }

  /// Teardown: deactivate all active features (graph handles ordering),
  /// then have each runtime release its stores, cleanup bags, and
  /// status store. The runtimes themselves are discarded by the
  /// container after teardown — the next container instantiates fresh
  /// runtimes.
  Future<void> teardown() async {
    final g = _graph;
    if (g == null) return;
    await g.shutdown();
    for (final f in g.topologicalOrder()) {
      await host
          .runtimeOf(f)
          .teardown(
            onError: (e, st) => host.reportError(
              feature: f,
              error: HandlerError.wrap(
                f.name,
                e,
                source: '<feature-teardown>',
                stackTrace: st,
              ),
            ),
          );
    }
    _graph = null;
  }

  // === GraphVisitor<AnyFeature> ===

  /// Feature should be active iff its runtime's `ownActive` flag is set.
  @override
  bool shouldBeActive(AnyFeature feature) => host.runtimeOf(feature).ownActive;

  @override
  Future<void> onActivate(AnyFeature feature) async {
    final stopwatch = Stopwatch()..start();
    await host
        .runtimeOf(feature)
        .activate(
          onError: (e, st) => host.reportError(
            feature: feature,
            error: HandlerError.wrap(
              feature.name,
              e,
              source: '<activation-cleanup>',
              stackTrace: st,
            ),
          ),
        );
    stopwatch.stop();
    host.recordResolveTime(feature.name, stopwatch.elapsed);
  }

  @override
  Future<void> onDeactivate(AnyFeature feature) async {
    await host.runtimeOf(feature).deactivate();
  }

  /// Single post-commit notification dispatcher. Graph fires this hook
  /// on every status transition (`.pending`, `.active`, `.disabled`).
  @override
  void onStatusChanged(AnyFeature feature, GraphNodeStatus newStatus) {
    if (host.isStopping) return;
    // Always mirror graph-committed status into the reactive store so
    // observers (StateObserver, MultiPortBuilder, whenActive) see every
    // transition — including the transient `.pending` for loader UI.
    host.runtimeOf(feature).updateStatusStore(host.statusOf(feature));
    if (newStatus == GraphNodeStatus.pending) return;
    host.emitFeatureStatusChanged(feature);
    // Snapshot the port set before iterating.
    for (final port in feature.config.ports.toList(growable: false)) {
      host.emitPortChanged(port);
    }
  }

  @override
  void onError(AnyFeature feature, Object error, StackTrace stackTrace) {
    host.reportError(
      feature: feature,
      error: HandlerError.wrap(feature.name, error, stackTrace: stackTrace),
    );
  }

  // === internals ===

  Graph<AnyFeature> _buildGraph() {
    final g = Graph<AnyFeature>(
      nodeValues: _features,
      visitor: this,
      activationConcurrency: host.options?.maxResolveConcurrency,
    );
    // Wire per-feature handles (toggle + lifetime cleanup bag) on each
    // feature's runtime for this container. Called exactly once per
    // container lifecycle.
    for (final feature in g.topologicalOrder()) {
      final runtime = host.runtimeOf(feature);
      runtime.toggle = (state) => _onToggle(feature, state);
      runtime.lifetimeCleanup = CleanupBag(
        onError: (e, st) => host.reportError(
          feature: feature,
          error: HandlerError.wrap(
            feature.name,
            e,
            source: '<lifetime-cleanup>',
            stackTrace: st,
          ),
        ),
      );
    }
    return g;
  }

  /// External entry point mirroring the `toggle` callable passed into
  /// activation setups.
  @internal
  Future<void> toggleFeature(AnyFeature feature, ToggleState state) =>
      _onToggle(feature, state);

  Future<void> _onToggle(AnyFeature feature, ToggleState state) {
    if (host.isStopping) return Future.value();
    final runtime = host.runtimeOf(feature);
    final active = state == ToggleState.active;
    if (runtime.ownActive == active) return Future.value();
    runtime.ownActive = active;
    if (_inSetupPhase) return Future.value();

    final completer = Completer<void>();
    _pendingToggles.add(_PendingToggle(feature, completer));

    if (!_draining) {
      _draining = true;
      scheduleMicrotask(() => unawaited(_drainPendingToggles()));
    }
    return completer.future;
  }

  Future<void> _drainPendingToggles() async {
    try {
      while (_pendingToggles.isNotEmpty) {
        if (host.isStopping) {
          while (_pendingToggles.isNotEmpty) {
            _pendingToggles.removeFirst().completer.complete();
          }
          return;
        }
        final next = _pendingToggles.removeFirst();
        try {
          await graph.recompute(next.feature);
          next.completer.complete();
        } on Object catch (e, st) {
          next.completer.completeError(e, st);
        }
      }
    } finally {
      _draining = false;
    }
  }

  Future<void> _runActivationSetups(Graph<AnyFeature> g) async {
    final pending = <Future<void>>[];
    for (final f in g.topologicalOrder()) {
      if (host.isStopping) return;
      final config = f.config;
      final setup = config.activationSetup;
      if (setup == null) continue;
      final runtime = host.runtimeOf(f);

      pending.add(() async {
        try {
          await runAsUserCallback(
            () =>
                setup(runtime.parent, runtime.toggle, runtime.lifetimeCleanup),
          );
        } on Object catch (e, st) {
          host.reportError(
            feature: f,
            error: HandlerError.wrap(
              f.name,
              e,
              source: '<activation-setup>',
              stackTrace: st,
            ),
          );
        }
      }());
    }
    if (pending.isNotEmpty) {
      await Future.wait(pending, eagerError: false);
    }
  }
}

class _PendingToggle {
  final AnyFeature feature;
  final Completer<void> completer;
  _PendingToggle(this.feature, this.completer);
}
