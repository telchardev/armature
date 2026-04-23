import 'dart:async';

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
///   * [shouldBeActive] — the feature's own preference (`ownActive`
///     flag). Graph cascades `disabled` down required-parent chains.
///   * [onActivate] — fresh per-activation [CleanupBag], awaited
///     `onStart` callback, and per-feature port emission.
///   * [onDeactivate] — per-activation cleanup bag run, port emission.
///   * [onError] — forwards caught visitor exceptions to the host.
///
/// Owns startup-time orchestration: builds the underlying [Graph] on
/// first [start] (eagerly constructing every feature's stores in
/// topological order), wires per-feature toggles + lifetime cleanup,
/// then runs `activation` setups followed by a single resolve cascade.
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

  /// Populated on first successful [start] and cleared by the
  /// polished-rollback teardown path (`resetForRestart: true`).
  /// Accessing before then throws via [graph]; [statusOf] degrades to
  /// `FeatureStatus.disabled` gracefully.
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
  ///
  /// Released **before** the single resolve so that `onStart` callbacks
  /// running inside the cascade can trigger real recomputes — the
  /// graph's tail-await drains them before [start] returns.
  bool _inSetupPhase = false;

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
  /// 1. **Construct phase** — run every feature's stores factory in
  ///    topological order. Parents are built before children, so
  ///    `parentApi.of(parent)` inside factories and setups always sees
  ///    real stores. Factory throw aborts `start()` fail-fast
  ///    (polished rollback then disposes stores built so far).
  /// 2. **Setup phase** — run user [activationSetup]s. Their `toggle(...)`
  ///    calls just flip `ownActive`; the cascade is deferred via
  ///    [_inSetupPhase].
  /// 3. **Resolve phase** — single `graph.resolve()` applies every
  ///    toggle in one cascade. `onStart` callbacks running inside the
  ///    cascade can themselves trigger recomputes; the graph's
  ///    tail-await drains them before returning.
  ///
  /// Port-changed events are emitted per-feature as each activates —
  /// subscribers (widgets / reactions) re-read port values incrementally
  /// rather than waiting for the slowest `onStart` to settle the whole
  /// start. This matters when one feature has a long-running `onStart`:
  /// widgets that depend on faster siblings' ports shouldn't block on it.
  ///
  /// Throws [GraphNodeNotFoundError] / [GraphCycleError] /
  /// [GraphFixedPointError] / [FeatureResolutionError] (factory
  /// failure) if the feature list is malformed or a factory threw;
  /// the caller ([AppContainer.start]) handles rollback.
  Future<void> start() async {
    final g = _graph ??= _buildGraph();

    // Phase 1: eager construct. First factory throw aborts start.
    _runConstructPhase(g);
    if (host.isDisposed) return;

    // Phase 2: user setups. Batched toggles, no cascade.
    _inSetupPhase = true;
    try {
      await _runActivationSetups(g);
    } finally {
      _inSetupPhase = false;
    }
    if (host.isDisposed) return;

    // Phase 3: one cascade (tail-awaits any nested recomputes). Port
    // emits fire per feature as it activates — see [onActivate].
    await g.resolve();
  }

  /// Constructs every feature's stores in topological order.
  ///
  /// Fail-fast: the first factory throw propagates out of this loop,
  /// bubbles through [start] and [AppContainer.start], and triggers
  /// polished rollback. Features whose factory hadn't run yet stay
  /// un-constructed; features already built get disposed by the
  /// rollback path.
  void _runConstructPhase(Graph<AnyFeature> g) {
    for (final f in g.topologicalOrder()) {
      if (host.isDisposed) return;
      f.internal.construct();
    }
  }

  /// Teardown: deactivate all active features (graph handles ordering,
  /// awaiting per-feature `onDeactivate`), then have each feature
  /// dispose its own lifetime resources sequentially. No-op if the
  /// graph was never built (container disposed before first [start]).
  ///
  /// When [resetForRestart] is true, also resets each feature's
  /// internal state and discards the graph so a subsequent [start] can
  /// rebuild from scratch. Used by the polished-rollback path.
  Future<void> teardown({bool resetForRestart = false}) async {
    final g = _graph;
    if (g == null) return;
    await g.shutdown();
    for (final f in g.topologicalOrder()) {
      await f.internal.teardown(
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

      if (resetForRestart) {
        f.internal.resetForRestart();
      }
    }
    if (resetForRestart) {
      // Drop the graph so the next start rebuilds it (and re-wires
      // toggle + lifetimeCleanup for every feature).
      _graph = null;
    }
  }

  // === GraphVisitor<AnyFeature> ===

  /// Feature should be active iff its `ownActive` flag is set. After
  /// a successful construct phase every feature has a valid
  /// `scopeApi` (fail-fast aborts start otherwise), so no extra check
  /// is needed here.
  @override
  bool shouldBeActive(AnyFeature feature) => feature.internal.ownActive;

  @override
  Future<void> onActivate(AnyFeature feature) async {
    final stopwatch = Stopwatch()..start();
    // Graph throttles parallel `onActivate` invocations via its own
    // semaphore when the container's `maxResolveConcurrency` is set —
    // no extra wrapper needed here.
    //
    // An `onStart` failure propagates out of
    // [feature.internal.activate] as a `HandlerError(source:'onStart')`
    // — the graph catches it, settles the node `.disabled`, and calls
    // [onError] below, which forwards the error to the user's
    // `errorHandler`. Status-store / event emission for `.pending` and
    // `.active` is handled uniformly via [onStatusChanged] — this
    // method only runs the work + records timing.
    await feature.internal.activate(
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
    await feature.internal.deactivate();
  }

  /// Single post-commit notification dispatcher. Graph fires this hook
  /// on every status transition (`.pending`, `.active`, `.disabled`);
  /// routing logic:
  ///
  /// * `.pending` — update the feature's status store only. Transient
  ///   state; subscribers to `onFeatureStatusChanged` don't see it to
  ///   preserve the "one event per settled status" contract.
  /// * `.active` / `.disabled` — update the store, fire the public
  ///   event, and fan out `portChanged` for every port the feature
  ///   registered a handler with (the port's effective value may have
  ///   flipped now that the handler set changed).
  @override
  void onStatusChanged(AnyFeature feature, GraphNodeStatus newStatus) {
    if (host.isDisposed) return;
    // Always mirror graph-committed status into the reactive store so
    // observers (StateObserver, MultiPortBuilder, whenActive) see every
    // transition — including the transient `.pending` for loader UI.
    feature.internal.updateStatusStore(host.statusOf(feature));
    if (newStatus == GraphNodeStatus.pending) return;
    host.emitFeatureStatusChanged(feature);
    // Snapshot the port set before iterating — `emitPortChanged` fans
    // out to user listeners whose bodies, in pathological cases, could
    // mutate the underlying set. A fixed list defuses ConcurrentModi-
    // ficationError for no measurable cost (port counts stay small).
    for (final port in feature.internal.ports.toList(growable: false)) {
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
    // Wire per-feature handles (toggle + lifetime cleanup bag) exactly
    // once. User code only reaches them through the `activation` setup
    // callback, which runs inside [start]; before that there's no way
    // to invoke them, so wiring after graph construction is safe.
    for (final feature in g.topologicalOrder()) {
      feature.internal.toggle = (state) => _onToggle(feature, state);
      feature.internal.lifetimeCleanup = CleanupBag(
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
  /// activation setups. Allows `AppContainer.toggleFeature` to flip a
  /// feature's `ownActive` flag without reaching through a saved
  /// callable reference.
  @internal
  Future<void> toggleFeature(AnyFeature feature, ToggleState state) =>
      _onToggle(feature, state);

  Future<void> _onToggle(AnyFeature feature, ToggleState state) {
    if (host.isDisposed) return Future.value();
    final active = state == ToggleState.active;
    if (feature.internal.ownActive == active) return Future.value();
    feature.internal.ownActive = active;
    // During the setup phase, toggles just flip `ownActive`. The single
    // `graph.resolve()` at the end of [start] applies them in one
    // consolidated cascade. Outside the setup phase (e.g. from
    // `onStart`, external `toggleFeature`, or runtime port handlers),
    // toggles trigger an immediate recompute.
    if (_inSetupPhase) return Future.value();
    return graph.recompute(feature);
  }

  /// Runs every feature's activation setup in topological order.
  /// Setups execute concurrently via `Future.wait`; they're typically
  /// lightweight (registering handlers, toggles, captures) so no
  /// concurrency limit is applied. Heavy-async work belongs in
  /// `onStart`, which the graph throttles via its activation
  /// semaphore.
  Future<void> _runActivationSetups(Graph<AnyFeature> g) async {
    final pending = <Future<void>>[];
    for (final f in g.topologicalOrder()) {
      if (host.isDisposed) return;
      final internal = f.internal;
      final setup = internal.activationSetup;
      if (setup == null) continue;

      pending.add(() async {
        try {
          await runAsUserCallback(
            () => setup(
              internal.parent,
              internal.toggle,
              internal.lifetimeCleanup,
            ),
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
