import 'dart:async' show Zone;
import 'dart:collection' show UnmodifiableMapView;

import 'package:armature_graph/armature_graph.dart'
    show
        Graph,
        GraphCycleError,
        GraphError,
        GraphFixedPointError,
        GraphNodeNotFoundError;
import "package:armature_reactive/armature_reactive.dart" show Reaction;
import "package:meta/meta.dart";

import '../errors.dart'
    show
        ArmatureError,
        ContainerError,
        ContainerUsageError,
        FeatureResolutionError,
        FeatureResolutionReason,
        HandlerError,
        ListenerError,
        RenderError;
import '../feature/feature.dart' show AnyFeature, Feature;
import '../feature/feature_api.dart' show FeatureHandlerContext;
import '../feature/feature_status.dart' show FeatureStatus, ToggleState;
import '../logger/logger.dart' show LogLevel, Logger;
import '../logger/null_logger.dart' show NullLogger;
import '../port/port.dart' show Port, AnyPort;
import '../user_callback_zone.dart' show userCallbackZoneKey;
import './events.dart' show Events;
import './feature_orchestrator.dart' show FeatureOrchestrator;
import './port_subscription.dart' show PortSubscription;

/// Lifecycle status of a [AppContainer].
enum ContainerStatus { idle, starting, working, disposed }

/// Error handler callback for recoverable feature errors.
///
/// [source] is the attribution label — the feature name for feature-
/// scoped errors, or one of the sentinels `'<container>'` (container-
/// lifecycle throws such as `onDispose`) / `'<events>'` (throws from
/// listeners on port-level events where no feature subscribed directly).
/// The domain feature name (when known) is also carried on the
/// [ArmatureError] subtype via its own `featureName` field; use that
/// when the caller specifically wants "the feature this error is about"
/// rather than "what triggered this callback".
typedef ContainerErrorHandler =
    void Function({
      required String source,
      required ArmatureError error,
      required Map<String, String> meta,
    });

/// Configuration options for an [AppContainer].
///
/// ```dart
/// AppContainer(
///   features: [...],
///   options: ContainerOptions(
///     errorHandler: ({required source, required error, required meta}) {
///       debugPrint('[$source] $error');
///     },
///     maxResolveConcurrency: 4, // cap parallel onStart work
///   ),
/// );
/// ```
class ContainerOptions {
  /// Sink for every **recoverable** error the container observes at
  /// runtime. Everything user-actionable lands here:
  ///
  /// * `activation` setup throws → [HandlerError]
  /// * `onStart` throws → [HandlerError] (the feature settles
  ///   `.disabled`; required descendants cascade closed)
  /// * Store `dispose()` throws during teardown → [HandlerError]
  /// * Lifetime cleanup disposer throws → [HandlerError]
  /// * `onDispose` container-callback throws → [HandlerError]
  ///   (feature name `'<container>'`)
  /// * Listener throws from [AppContainer.onFeatureStatusChanged] /
  ///   [AppContainer.onPortChanged] → [ListenerError]
  /// * Apply-time [PortError] (wrong owner) → [PortError] (slot falls
  ///   back to `initialValue`)
  /// * Slot widget `build` throws → [RenderError] (slot renders
  ///   fallback widget)
  ///
  /// The handler gets the attribution `source` (a feature name, or
  /// one of the sentinels `'<container>'` / `'<events>'`), the
  /// framework [ArmatureError] subtype (which carries its own domain
  /// `featureName` when the error is feature-scoped), and a string-
  /// keyed metadata map with extra context (e.g.
  /// `{'event': 'portChanged', 'port': portName}`).
  ///
  /// A handler throw is caught and logged via the container's [Logger]
  /// — one bad handler never blocks another error from being
  /// processed. The [Logger], in contrast to `errorHandler`, is only
  /// used for framework-internal diagnostics; user-actionable errors
  /// always surface here.
  final ContainerErrorHandler errorHandler;

  /// Max concurrent `onActivate` / `onStart` invocations during the
  /// graph cascade. Forwarded to the underlying [Graph]'s activation
  /// semaphore. `null` means no limit (default). Lifecycle setups run
  /// unconditionally in parallel — they're expected to be lightweight
  /// (handler registration + toggle); heavy async work belongs in
  /// `onStart`, which this option throttles.
  final int? maxResolveConcurrency;

  /// Throws `AssertionError` if [maxResolveConcurrency] is `<= 0`
  /// (use `null` for unbounded parallelism instead of zero).
  ContainerOptions({required this.errorHandler, this.maxResolveConcurrency})
    : assert(
        maxResolveConcurrency == null || maxResolveConcurrency > 0,
        'maxResolveConcurrency must be > 0 or null (unbounded).',
      );
}

/// Manages feature lifecycle, dependency resolution, and port application.
///
/// ```dart
/// final container = AppContainer(features: [layoutFeature, authFeature]);
/// await container.start();
/// ```
final class AppContainer {
  /// Debug-only finalizer that warns when an [AppContainer] is
  /// garbage-collected without ever being disposed. Catches forgotten
  /// `dispose()` calls in tests and hot-reload scenarios where
  /// lingering timers / stream subscriptions / port handler entries
  /// would otherwise leak silently.
  ///
  /// Attached in debug builds only (via `assert`), so production
  /// behaviour is unchanged.
  static final Finalizer<String> _debugFinalizer = Finalizer((name) {
    // ignore: avoid_print
    print(
      'WARN: $name was garbage-collected without dispose(). This may '
      'indicate leaked timers, stream subscriptions, or stale port '
      'handlers. Call `container.dispose()` when done.',
    );
  });

  /// Dependency graph. Used internally by debug overlay.
  @internal
  Graph<AnyFeature> get graph => _orchestrator.graph;

  late final Events _events;

  /// Deduplicated features in the caller's declaration order.
  final List<AnyFeature> _features;

  final Map<String, Duration> _resolveTimes = {};

  /// Feature resolve durations, populated after [start]. Read-only view.
  Map<String, Duration> get resolveTimes => UnmodifiableMapView(_resolveTimes);

  final Logger _logger;

  final ContainerOptions? _options;

  late final FeatureOrchestrator _orchestrator;

  ContainerStatus _status = ContainerStatus.idle;

  /// In-flight `start()` future, tracked so `dispose()` can await it
  /// before tearing down. `null` outside of a `start()` call.
  Future<void>? _startFuture;

  ContainerStatus get status {
    return _status;
  }

  AppContainer({
    List<AnyFeature> features = const [],
    ContainerOptions? options,
    Logger? logger,
  }) : _features = features.toSet().toList(growable: false),
       _options = options,
       _logger = logger ?? NullLogger() {
    _events = Events(reportListenerError: _reportListenerError);
    _orchestrator = FeatureOrchestrator(host: this, features: _features);
    assert(() {
      _debugFinalizer.attach(
        this,
        'AppContainer#${identityHashCode(this)}',
        detach: this,
      );
      return true;
    }());
  }

  /// Guard: fail if the container has already been disposed. Used by
  /// every public operation that must not run after teardown.
  void _checkNotDisposed() {
    if (_status == ContainerStatus.disposed) {
      throw ContainerError('AppContainer is disposed.');
    }
  }

  /// Guard: fail unless the container is in the fully-started
  /// `.working` state. [op] is a short description of the attempted
  /// operation used in the error message (e.g. `'toggle a feature'`).
  void _requireWorking(String op) {
    _checkNotDisposed();
    if (_status != ContainerStatus.working) {
      throw ContainerError('AppContainer must be started to $op.');
    }
  }

  /// Disposes the container, awaiting per-feature cleanup (which may be
  /// async if any disposer returns a `Future`), then tears down event
  /// buses and reaction tracking.
  ///
  /// Idempotent: subsequent calls return the same in-flight future.
  Future<void> dispose() {
    return _disposing ??= _runDispose();
  }

  Future<void>? _disposing;

  final List<void Function()> _disposeCallbacks = [];

  /// Registers [callback] to run at the tail of [dispose] (after feature
  /// teardown and internal cleanup). Use to release resources owned
  /// externally that reference the container — e.g. the
  /// `armature_flutter` renderer global.
  ///
  /// Callbacks are invoked once, in registration order. Throws are
  /// swallowed and logged so one misbehaving callback doesn't block the
  /// others.
  @internal
  void onDispose(void Function() callback) {
    _disposeCallbacks.add(callback);
  }

  Future<void> _runDispose() async {
    // Forbid dispose invoked from within a feature lifecycle callback
    // (setup / onStart). Awaiting `_startFuture` from inside such a
    // callback would self-deadlock; throwing gives a clearer signal
    // for the bug. Detected via a zone marker installed by
    // [runAsUserCallback] around user-supplied callbacks — this does
    // NOT fire for `dispose()` called from outside `start()` while a
    // start is merely in flight in the background.
    //
    // Yield one microtask first so that the synchronous reject flows
    // naturally through the awaiting user code via the returned
    // Future (pre-await sync throws in async functions settle the
    // returned Future after the caller's frame has unwound).
    await null;
    if (Zone.current[userCallbackZoneKey] == true) {
      // Clear the cached future so a later, legitimate dispose() call
      // from outside the user callback can run instead of replaying
      // this rejection.
      _disposing = null;
      throw ContainerUsageError(
        'AppContainer.dispose() cannot be called from within a feature '
        'lifecycle callback. Schedule the dispose outside of it '
        '(e.g. unawaited(Future.microtask(container.dispose))).',
      );
    }

    // Claim the `.disposed` status immediately — external observers
    // (SlotWidget, listener callbacks) should see the transition as
    // soon as dispose is initiated, even if the actual teardown has
    // to wait for an in-flight start to settle below.
    _status = ContainerStatus.disposed;

    // Detach the debug finalizer — from here on, GC-without-dispose is
    // no longer a concern.
    assert(() {
      _debugFinalizer.detach(this);
      return true;
    }());

    // Wait for any in-flight start() to settle before tearing down.
    // Otherwise teardown races with feature resolution and leaves
    // handler registrations + partially-initialised stores behind.
    final pendingStart = _startFuture;
    if (pendingStart != null) {
      try {
        await pendingStart;
      } on Object {
        // start() failed; `_rollback()` already ran. We still proceed
        // with teardown below.
      }
    }

    await _teardownFeatures(resetForRestart: false);

    for (final cb in _disposeCallbacks) {
      try {
        cb();
      } on Object catch (e, st) {
        _reportContainerError(
          error: e,
          stackTrace: st,
          operation: 'onDispose callback',
          meta: const {'event': 'onDispose'},
        );
      }
    }
    _disposeCallbacks.clear();
  }

  /// Shared teardown path used by both [_runDispose] and [_rollback].
  ///
  /// Tears down every feature via the lifecycle layer (which handles
  /// graph shutdown — including draining its activation-concurrency
  /// semaphore — and per-feature store cleanup), clears reaction
  /// tracking, and clears resolve-time stats.
  ///
  /// When [resetForRestart] is `true`:
  ///   * Per-feature internal state is reset and the graph is discarded
  ///     so a subsequent [start] builds everything fresh.
  ///   * Port handlers registered statically at feature-construction
  ///     time (via `usePipe`, `useBehavior`, …) are **kept** — a retry
  ///     needs them in place, since `usePipe` isn't re-invoked.
  ///   * Events stay alive (no `dispose()`), since the container is
  ///     still usable.
  ///
  /// When [resetForRestart] is `false` (full dispose):
  ///   * Port handlers are deregistered so top-level ports shared
  ///     across container instances don't accumulate stale entries.
  ///   * Events are disposed.
  Future<void> _teardownFeatures({required bool resetForRestart}) async {
    await _orchestrator.teardown(resetForRestart: resetForRestart);

    if (!resetForRestart) {
      for (final feature in _features) {
        for (final port in feature.internal.ports) {
          port.removeHandler(feature: feature);
        }
      }
    }

    _resolveTimes.clear();

    if (!resetForRestart) {
      _events.dispose();
    }
  }

  /// Applies a [port] within the scope of [rootFeature] as a one-shot,
  /// non-reactive read.
  ///
  /// Handlers that read reactive [State] / [Atom] during [apply] do **not**
  /// register the caller for future invalidations. Callers who need to
  /// rebuild when the port's dependencies change should use [observe]
  /// instead — it wraps each subscription in its own [Reaction] so
  /// subscribers' dep sets no longer stomp on each other's tracking.
  TValue apply<TValue, TInputData, THandler extends Function>({
    required Feature rootFeature,
    required Port<TValue, TInputData, THandler> port,
    required TValue initialValue,
    required TInputData data,
  }) {
    _checkNotDisposed();
    if (_status == ContainerStatus.idle) {
      throw ContainerError(
        'AppContainer is not started. Call start() before apply().',
      );
    }

    final error = port.check(applyingFeature: rootFeature);

    if (error != null) {
      _callErrorHandler(source: rootFeature.name, error: error, meta: {});
      return initialValue;
    }

    _logger.log(level: LogLevel.debug, message: "Port applying", info: port);

    return port.apply(initialValue: initialValue, data: data, container: this);
  }

  /// Creates a reactive [PortSubscription] that re-applies [port]
  /// whenever any atom its handlers read changes. The returned
  /// subscription owns its own [Reaction], so two subscribers of the
  /// same port that read different atoms no longer overwrite each
  /// other's dep sets.
  ///
  /// [onChanged] fires after [PortSubscription.value] is updated.
  /// Widgets typically pass `safeSetState` so the rebuild runs with a
  /// fresh value.
  ///
  /// Errors thrown by port handlers (at first apply or during any
  /// re-apply) are routed through the container's [errorHandler] as
  /// [RenderError]; the subscription falls back to [initialValue] for
  /// that apply, and stays live for future re-tries.
  ///
  /// Observe also wakes on `portChanged` — emitted from the feature-
  /// lifecycle cascade — so the subscription re-applies when a
  /// handler's owning feature activates or deactivates. Reactive atom
  /// changes drive re-apply through the subscription's own
  /// [Reaction], **without** re-emitting `portChanged` (that would
  /// wake unrelated subscribers and defeat per-subscriber isolation).
  /// Call [PortSubscription.dispose] when the subscription is no
  /// longer needed.
  PortSubscription<TValue, TInputData>
  observe<TValue, TInputData, THandler extends Function>({
    required Feature rootFeature,
    required Port<TValue, TInputData, THandler> port,
    required TValue initialValue,
    required TInputData data,
    required void Function() onChanged,
  }) {
    _checkNotDisposed();
    if (_status == ContainerStatus.idle) {
      throw ContainerError(
        'AppContainer is not started. Call start() before observe().',
      );
    }

    final error = port.check(applyingFeature: rootFeature);
    if (error != null) {
      // Mis-scoped apply: report the error and return a "dead"
      // subscription pinned at [initialValue]. The port's owner never
      // changes, so no atom could un-break this — skip allocating a
      // Reaction + event listener entirely.
      _callErrorHandler(source: rootFeature.name, error: error, meta: {});
      return PortSubscription.disabled(initialValue);
    }

    _logger.log(level: LogLevel.debug, message: "Port observing", info: port);

    return PortSubscription.live(
      container: this,
      rootFeature: rootFeature,
      port: port,
      initialValue: initialValue,
      data: data,
      onChanged: onChanged,
    );
  }

  @internal
  Logger get logger => _logger;

  @internal
  ContainerOptions? get options => _options;

  @internal
  bool get isDisposed => _status == ContainerStatus.disposed;

  /// Fires `portChanged` for [port]. Called by the orchestrator's
  /// post-activation / post-deactivation hooks when a feature owning a
  /// handler on the port transitions active ↔ disabled — the handler
  /// set affects `port.apply` output even when no reactive atom
  /// changed, so live [PortSubscription]s must re-apply.
  ///
  /// Reactive atom changes do NOT go through this channel — they
  /// drive re-apply through each subscription's own [Reaction]. That
  /// keeps per-subscriber atom-tracking isolated (subA's atom change
  /// can't wake subB) and silences debug tooling for routine state
  /// mutations.
  @internal
  void emitPortChanged(AnyPort port) {
    // Silently skip events after dispose: teardown runs onDeactivate
    // for every feature, which would otherwise notify subscribers who
    // then re-enter `apply()` / `statusOf()` on the already-disposed
    // container. Subscribers don't need per-feature deactivation
    // events during container dispose — the whole container is going
    // away.
    if (_status == ContainerStatus.disposed) return;
    _events.portChanged.emit(port);
  }

  /// Fires the public `featureStatusChanged` event. The orchestrator
  /// calls this for settled states (`.active` / `.disabled`) — transient
  /// `.pending` transitions update status stores directly without going
  /// through the event emitter, so legacy listeners keep seeing one
  /// event per activation cycle.
  @internal
  void emitFeatureStatusChanged(AnyFeature feature) {
    if (_status == ContainerStatus.disposed) return;
    _events.featureStatusChanged.emit(feature);
  }

  @internal
  void recordResolveTime(String featureName, Duration duration) {
    _resolveTimes[featureName] = duration;
  }

  /// Reports a recoverable error against [feature] to the configured
  /// [ContainerErrorHandler]. Callers wrap raw throws into the right
  /// [ArmatureError] subtype — typically [HandlerError] for user-callback
  /// failures — before invoking this method.
  @internal
  void reportError({required Feature feature, required ArmatureError error}) {
    _callErrorHandler(source: feature.name, error: error, meta: {});
  }

  /// Routes a throw from a user-supplied event listener through the
  /// configured [ContainerErrorHandler]. Invoked from [Events] so one
  /// misbehaving listener cannot break siblings.
  void _reportListenerError(
    String source,
    Object error,
    StackTrace stackTrace,
    Map<String, String> meta,
  ) {
    _callErrorHandler(
      source: source,
      error: ListenerError.wrap(source, error, stackTrace: stackTrace),
      meta: meta,
    );
  }

  /// Routes a container-scoped recoverable error (one without feature
  /// attribution — e.g. `onDispose` callback throws) through the
  /// configured [ContainerErrorHandler] using [_containerSentinel] as
  /// the attribution source. [operation] labels the failing operation
  /// for diagnostics (e.g. `'onDispose callback'`) and is threaded into
  /// the wrapped [HandlerError]. [meta] carries the originating event
  /// so handlers can filter.
  void _reportContainerError({
    required Object error,
    required Map<String, String> meta,
    StackTrace? stackTrace,
    String? operation,
  }) {
    _callErrorHandler(
      source: _containerSentinel,
      error: HandlerError.wrap(
        _containerSentinel,
        error,
        source: operation,
        stackTrace: stackTrace,
      ),
      meta: meta,
    );
  }

  /// Synthetic `source` passed to [ContainerErrorHandler] for errors
  /// that originate above the feature layer (e.g. `onDispose`
  /// container-callback throws). Compare with [Events.eventsSentinel],
  /// used for listener errors on container-scoped events.
  static const _containerSentinel = '<container>';

  void _callErrorHandler({
    required String source,
    required ArmatureError error,
    required Map<String, String> meta,
  }) {
    final handler = _options?.errorHandler;
    if (handler == null) {
      _logger.log(level: LogLevel.error, message: "Error: $error in $source");
      return;
    }
    try {
      handler(source: source, error: error, meta: meta);
    } on Object catch (handlerError, stack) {
      _logger.log(
        level: LogLevel.error,
        message:
            'AppContainer errorHandler threw: $handlerError\n'
            'Original error (source=$source): $error\n$stack',
      );
    }
  }

  /// Current lifecycle status of [feature]. Returns
  /// `FeatureStatus.disabled` for unknown features or before
  /// [AppContainer.start] succeeds.
  FeatureStatus statusOf(Feature feature) => _orchestrator.statusOf(feature);

  /// Returns the handler context for [feature] — the value passed as
  /// `ctx` to Pipe / Behavior / Slot handlers. Intended for custom
  /// [Port] implementations that need to invoke handlers without
  /// reaching into `feature.internal`.
  ///
  /// After a successful [AppContainer.start], every registered feature
  /// has a scope API (eager-construct + fail-fast guarantees). Throws
  /// [FeatureConfigurationError] if called before `start()` or after a
  /// rolled-back start.
  @internal
  FeatureHandlerContext handlerContextFor(Feature feature) {
    return feature.internal.scopeApi;
  }

  /// Sets [feature]'s own activation preference from outside an
  /// activation setup. Equivalent to calling the `toggle` callable exposed
  /// inside [Feature.activation]; prefer this over the saved-reference
  /// pattern in tests and external controllers.
  ///
  /// Idempotent: setting the current state is a no-op and resolves with
  /// a completed future. Throws [ContainerError] if the container is not
  /// `.working` (i.e. before [start] has succeeded or after [dispose]).
  Future<void> toggleFeature(Feature feature, ToggleState state) {
    _requireWorking('toggle a feature');
    return _orchestrator.toggleFeature(feature, state);
  }

  /// Resolves all features in dependency order and starts the container.
  Future<void> start() {
    if (_status == ContainerStatus.disposed) {
      throw ContainerError('AppContainer is disposed.');
    }
    if (_status == ContainerStatus.working) {
      throw ContainerError('AppContainer is already started.');
    }
    if (_status == ContainerStatus.starting) {
      throw ContainerError('AppContainer is starting.');
    }
    return _startFuture = _runStart();
  }

  Future<void> _runStart() async {
    _status = ContainerStatus.starting;
    try {
      await _orchestrator.start();
      if (_status != ContainerStatus.disposed) {
        _status = ContainerStatus.working;
      }
      // Graph-level misconfiguration surfaces as the sealed [GraphError]
      // family; re-wrap each variant into [FeatureResolutionError] so
      // callers match a single framework type for every resolution
      // failure. `GraphFixedPointError` — triggered by a toggle cycle
      // in activation setups that never stabilises — shares the
      // `cycle` reason with structural cycle detection.
      // ignore: avoid_catching_errors
    } on GraphError catch (e) {
      await _rollback();
      throw switch (e) {
        GraphNodeNotFoundError(:final referencedBy, :final missing) =>
          FeatureResolutionError(
            referencedBy,
            'Feature "$referencedBy" depends on "$missing" which is '
            'not listed in AppContainer.features.',
            reason: FeatureResolutionReason.missingParent,
          ),
        GraphCycleError(:final message) => FeatureResolutionError(
          message,
          message,
          reason: FeatureResolutionReason.cycle,
        ),
        GraphFixedPointError(:final message) => FeatureResolutionError(
          'lifecycle',
          message,
          reason: FeatureResolutionReason.cycle,
        ),
      };
    } on Object {
      await _rollback();
      rethrow;
    } finally {
      _startFuture = null;
    }
  }

  /// Polished rollback: when `start()` fails midway, undo every
  /// side-effect it produced so the container is in a clean `.idle`
  /// state indistinguishable from a freshly-constructed one. A
  /// subsequent `start()` can then run without replaying stale
  /// handlers or partially-initialised stores.
  Future<void> _rollback() async {
    await _teardownFeatures(resetForRestart: true);
    if (_status != ContainerStatus.disposed) _status = ContainerStatus.idle;
  }

  /// Subscribes to feature status-change events (any transition among
  /// `disabled` / `pending` / `active`). Returns a disposer.
  void Function() onFeatureStatusChanged({
    required Feature feature,
    required void Function() callback,
  }) {
    _events.featureStatusChanged.add(feature, callback);

    return () {
      _events.featureStatusChanged.remove(feature, callback);
    };
  }

  /// Subscribes to port handler-set change notifications. Fires when
  /// a feature owning a handler on [port] transitions active ↔
  /// disabled — i.e. whenever the live handler set of the port
  /// structurally changes. Returns a disposer.
  ///
  /// Does NOT fire on reactive atom changes. Callers that need a
  /// rebuild when a tracked atom changes use [observe] instead — each
  /// subscription there owns its own [Reaction] that invalidates
  /// privately, without fanning out to every [onPortChanged]
  /// listener (which would wake unrelated subscribers and regress
  /// per-subscriber isolation).
  void Function() onPortChanged({
    required AnyPort port,
    required void Function() callback,
  }) {
    _events.portChanged.add(port, callback);

    return () {
      _events.portChanged.remove(port, callback);
    };
  }

  @override
  String toString() =>
      'AppContainer(status: ${_status.name}, features: ${_features.length})';
}
