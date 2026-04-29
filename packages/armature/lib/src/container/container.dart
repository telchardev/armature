import 'dart:async' show Zone;
import 'dart:collection' show UnmodifiableMapView;
import 'dart:developer' show log;

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
        PortError,
        RenderError;
import '../feature/feature.dart' show AnyFeature, Feature;
import '../feature/feature_api.dart' show FeatureHandlerContext;
import '../feature/feature_runtime.dart' show FeatureRuntime;
import '../feature/feature_status.dart' show FeatureStatus, ToggleState;
import '../logger/logger.dart' show LogLevel, Logger;
import '../logger/null_logger.dart' show NullLogger;
import '../port/port.dart' show Port, AnyPort;
import '../user_callback_zone.dart' show userCallbackZoneKey;
import './events.dart' show Events;
import './feature_orchestrator.dart' show FeatureOrchestrator;
import './port_subscription.dart' show PortSubscription;

/// Lifecycle status of a [AppContainer].
enum ContainerStatus {
  /// Constructed but `start()` has not been called yet — features are
  /// declared, no resolution or activation has happened. Also the
  /// resting state after [AppContainer.stop] returns.
  idle,

  /// `start()` is in progress: the dependency graph is being built and
  /// the initial activation cascade is running.
  starting,

  /// `start()` finished successfully; features can be toggled, ports
  /// invoked, and tasks dispatched.
  working,
}

/// Error handler callback for recoverable feature errors.
///
/// [source] is the attribution label — the feature name for feature-
/// scoped errors, or one of the sentinels `'<container>'` (container-
/// lifecycle throws) / `'<events>'` (throws from listeners on port-
/// level events where no feature subscribed directly). The domain
/// feature name (when known) is also carried on the [ArmatureError]
/// subtype via its own `featureName` field; use that when the caller
/// specifically wants "the feature this error is about" rather than
/// "what triggered this callback".
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
/// // ...
/// await container.stop(); // tears down; can call start() again later
/// ```
final class AppContainer {
  /// Debug-only finalizer that warns when an [AppContainer] is
  /// garbage-collected while still active (i.e. without a matching
  /// [stop]). Catches forgotten `stop()` calls in tests and hot-reload
  /// scenarios where lingering timers / stream subscriptions / port
  /// handler entries would otherwise leak silently.
  ///
  /// Attached on each [start] (debug builds only, via `assert`),
  /// detached when [stop] completes — so a container that was
  /// constructed but never started raises no warning, and a container
  /// that was cleanly stopped raises no warning either.
  static final Finalizer<String> _debugFinalizer = Finalizer((name) {
    log(
      '$name was garbage-collected while still active. This may '
      'indicate leaked timers, stream subscriptions, or stale port '
      'handlers. Call `container.stop()` when done.',
      name: 'armature.AppContainer',
      level: 900, // WARNING per dart:developer convention.
    );
  });

  /// Raw dependency graph backing this container. Exposed for
  /// framework-internal consumers (notably `ContainerDebugExtensions.debug`)
  /// — application code should read through `debug` instead.
  @internal
  Graph<AnyFeature> get graph => _orchestrator.graph;

  late final Events _events;

  /// Deduplicated features in the caller's declaration order.
  final List<AnyFeature> _features;

  /// Per-container feature runtime state. Populated at construction —
  /// one fresh [FeatureRuntime] per declared feature per container —
  /// and reused across start/stop cycles (the runtime resets its own
  /// per-cycle state in `teardown`). Two containers that share the
  /// same top-level `final` feature instance hold independent entries
  /// here, so async teardown of one cannot corrupt the other's state.
  final Map<AnyFeature, FeatureRuntime> _runtimes = {};

  /// Per-container port handler registry. Keyed by `port` → `feature`
  /// → wrapped handler (erased to [Function]; concrete types are
  /// reconstituted inside each [Port] subclass via a per-entry cast).
  /// Cleared on every [stop] — no cross-cycle handler leakage.
  final Map<AnyPort, Map<AnyFeature, Function>> _portHandlers = {};

  final Map<String, Duration> _resolveTimes = {};

  /// Feature resolve durations, populated after [start]. Read-only view.
  Map<String, Duration> get resolveTimes => UnmodifiableMapView(_resolveTimes);

  final Logger _logger;

  final ContainerOptions? _options;

  late final FeatureOrchestrator _orchestrator;

  ContainerStatus _status = ContainerStatus.idle;

  /// In-flight `start()` future, tracked so [stop] can await it before
  /// tearing down. `null` outside of a `start()` call.
  Future<void>? _startFuture;

  /// In-flight `stop()` future, tracked so concurrent `stop()` calls
  /// coalesce and so the orchestrator can detect "stop requested" via
  /// [isStopping]. `null` outside of a `stop()` call.
  Future<void>? _stopping;

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
    // Allocate a fresh runtime for every feature this container owns.
    // The next container built with the same features gets its own
    // independent set of runtimes.
    for (final f in _features) {
      _runtimes[f] = FeatureRuntime(feature: f, container: this);
    }
  }

  /// Guard: fail unless the container is in the fully-started
  /// `.working` state. [op] is a short description of the attempted
  /// operation used in the error message (e.g. `'toggle a feature'`).
  void _requireWorking(String op) {
    if (_status != ContainerStatus.working) {
      throw ContainerError('AppContainer must be started to $op.');
    }
  }

  /// Stops the container: deactivates every feature (LIFO), runs
  /// per-feature lifetime cleanup, disposes the per-cycle stores and
  /// status stores, clears port handlers, and drops every registered
  /// event listener. The container then returns to
  /// [ContainerStatus.idle] and [start] can be called again to spin up
  /// a fresh cycle (with new store instances).
  ///
  /// **No-op when already `.idle`.** Concurrent calls coalesce into the
  /// same in-flight future.
  ///
  /// **Cannot be called from a feature lifecycle callback** (`setup`,
  /// `onStart`, port handlers) — throws [ContainerUsageError]. Schedule
  /// the stop outside the callback if you need to.
  ///
  /// **References to stores / exports / handler context obtained from
  /// the previous cycle are stale after stop.** The underlying objects
  /// were disposed; re-fetch through `use(...)` / `useStore(...)` after
  /// the next [start]. Widget consumers using `WatchPort` /
  /// `useFeature` re-resolve through the container on rebuild.
  ///
  /// **Event listeners registered via [onFeatureStatusChanged] /
  /// [onPortChanged] are dropped.** Re-subscribe after the next [start]
  /// if you want to keep observing.
  ///
  /// Per-cycle resources (a websocket, a database handle, a telemetry
  /// session) belong inside a feature's `setup` / `onStart` and its
  /// `cleanup` bag — not at the container level. The cleanup bag
  /// drains automatically on stop, then a fresh one is allocated for
  /// the next cycle.
  Future<void> stop() {
    return _stopping ??= _runStop();
  }

  Future<void> _runStop() async {
    // Yield one microtask first so the synchronous reject below flows
    // naturally through awaiting user code via the returned Future
    // (pre-await sync throws in async functions settle the returned
    // Future after the caller's frame has unwound).
    await null;
    _assertNotInUserCallback();

    // Already idle — nothing to tear down. Clear the cached future so
    // a subsequent stop() after a new start() runs fresh.
    if (_status == ContainerStatus.idle) {
      _stopping = null;
      return;
    }

    await _awaitInFlightStart();
    await _teardownFeatures();
    _events.clearListeners();

    _status = ContainerStatus.idle;
    _stopping = null;

    assert(() {
      _debugFinalizer.detach(this);
      return true;
    }());
  }

  /// Rejects `stop()` calls from inside a feature lifecycle callback
  /// (setup / `onStart`); awaiting `_startFuture` from there would
  /// self-deadlock. Detected via the zone marker installed by
  /// [runAsUserCallback].
  void _assertNotInUserCallback() {
    if (Zone.current[userCallbackZoneKey] == true) {
      _stopping = null;
      throw ContainerUsageError(
        'AppContainer.stop() cannot be called from within a feature '
        'lifecycle callback. Schedule the stop outside of it '
        '(e.g. unawaited(Future.microtask(container.stop))).',
      );
    }
  }

  /// Waits for an in-flight `start()` to settle before teardown so
  /// handler registrations and partially-initialised stores aren't
  /// orphaned. Errors from the awaited start are swallowed —
  /// `_rollback()` already ran on its failure path; teardown still
  /// proceeds for safety.
  Future<void> _awaitInFlightStart() async {
    if (_status != ContainerStatus.starting) return;
    final pendingStart = _startFuture;
    if (pendingStart == null) return;
    try {
      await pendingStart;
    } on Object {
      // Already rolled back by _runStart's catch; keep going.
    }
  }

  /// Whether a [stop] is in progress. Internal signal for the
  /// orchestrator and emit gates so they can short-circuit work that
  /// would otherwise race with teardown.
  @internal
  bool get isStopping => _stopping != null;

  /// Shared teardown path used by both [_runStop] and [_rollback].
  ///
  /// Tears down every feature via the lifecycle layer (which handles
  /// graph shutdown — including draining its activation-concurrency
  /// semaphore — and per-feature store cleanup), clears the port
  /// handler map and resolve-time stats. Feature internal state is
  /// always restored to the freshly-constructed baseline inside
  /// [FeatureRuntime.teardown] so the same runtime can be reused in
  /// the next start cycle on this same container.
  Future<void> _teardownFeatures() async {
    await _orchestrator.teardown();

    // Drop every handler contributed to any port this container
    // installed. Since `_portHandlers` is container-scoped, other
    // containers sharing the same top-level ports are unaffected.
    // The next start() re-installs handlers from each feature's
    // recorded `portBindings` via the orchestrator's install-port-
    // handlers step.
    _portHandlers.clear();

    _resolveTimes.clear();
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
    if (_status == ContainerStatus.idle) {
      throw ContainerError(
        'AppContainer is not started. Call start() before apply().',
      );
    }

    final error = port.check(container: this, applyingFeature: rootFeature);

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
    if (_status == ContainerStatus.idle) {
      throw ContainerError(
        'AppContainer is not started. Call start() before observe().',
      );
    }

    final error = port.check(container: this, applyingFeature: rootFeature);
    if (error != null) {
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
    // Silently skip events while a stop is in progress: teardown runs
    // onDeactivate for every feature, which would otherwise notify
    // subscribers who then re-enter `apply()` / `statusOf()` on a
    // container that's tearing down. Subscribers don't need per-
    // feature deactivation events during stop — the whole container
    // is going idle.
    if (isStopping) return;
    _events.portChanged.emit(port);
  }

  /// Fires the public `featureStatusChanged` event. The orchestrator
  /// calls this for settled states (`.active` / `.disabled`) — transient
  /// `.pending` transitions update status stores directly without going
  /// through the event emitter, so legacy listeners keep seeing one
  /// event per activation cycle.
  @internal
  void emitFeatureStatusChanged(AnyFeature feature) {
    if (isStopping) return;
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
    return runtimeOf(feature).scopeApi;
  }

  /// Returns this container's [FeatureRuntime] for [feature]. Throws
  /// [ContainerUsageError] if the feature was not registered on this
  /// container.
  @internal
  FeatureRuntime runtimeOf(AnyFeature feature) {
    final r = _runtimes[feature];
    if (r == null) {
      throw ContainerUsageError(
        'Feature "${feature.name}" is not registered on this AppContainer.',
      );
    }
    return r;
  }

  /// Returns the map of (feature → handler) for [port] as seen by this
  /// container. Handlers are erased to [Function]; concrete port
  /// subclasses cast per-entry at the call site (cheaper than a
  /// map-level `.cast()` wrapper, which re-checks types on every
  /// read). Returns an empty const map when no handler is installed.
  /// Callers must not mutate — use [addPortHandler] / [removePortHandler].
  @internal
  Map<AnyFeature, Function> handlersOf(AnyPort port) {
    return _portHandlers[port] ?? const {};
  }

  /// Installs [handler] for [feature] on [port] in this container's
  /// handler map. Throws [PortError] if [feature] already has a handler
  /// on [port] in this container.
  @internal
  void addPortHandler({
    required AnyPort port,
    required AnyFeature feature,
    required Function handler,
  }) {
    final map = _portHandlers.putIfAbsent(port, () => {});
    if (map.containsKey(feature)) {
      throw PortError(
        port.name,
        'Port "${port.name}" already used in "${feature.name}" feature',
      );
    }
    final error = port.validateOwnership(applyingFeature: feature);
    if (error != null) throw error;
    map[feature] = handler;
  }

  /// Removes [feature]'s handler from [port] in this container's
  /// handler map. No-op if no such handler is installed.
  @internal
  void removePortHandler({required AnyPort port, required AnyFeature feature}) {
    final map = _portHandlers[port];
    if (map == null) return;
    map.remove(feature);
    if (map.isEmpty) _portHandlers.remove(port);
  }

  /// Whether [feature] has a handler installed on [port] in this
  /// container.
  @internal
  bool hasPortHandlerFor({required AnyPort port, required AnyFeature feature}) {
    return _portHandlers[port]?.containsKey(feature) ?? false;
  }

  /// Sets [feature]'s own activation preference from outside an
  /// activation setup. Equivalent to calling the `toggle` callable exposed
  /// inside [Feature.activation]; prefer this over the saved-reference
  /// pattern in tests and external controllers.
  ///
  /// Idempotent: setting the current state is a no-op and resolves with
  /// a completed future. Throws [ContainerError] if the container is not
  /// `.working` (i.e. before [start] has succeeded or while a [stop] is
  /// in progress).
  Future<void> toggleFeature(Feature feature, ToggleState state) {
    _requireWorking('toggle a feature');
    return _orchestrator.toggleFeature(feature, state);
  }

  /// Resolves all features in dependency order and starts the container.
  ///
  /// Idempotent and queue-friendly with [stop]:
  /// * Calling [start] while a [start] is already in flight returns the
  ///   same future (concurrent calls coalesce).
  /// * Calling [start] when the container is already in
  ///   [ContainerStatus.working] (and no stop is pending) is a no-op.
  /// * Calling [start] while a [stop] is in flight queues the start —
  ///   it begins after the stop completes, on the next cycle's fresh
  ///   stores.
  ///
  /// Throws [ContainerUsageError] if invoked from within a feature
  /// lifecycle callback (would self-deadlock).
  Future<void> start() {
    // Re-entrance guard runs first — before coalesce — because the
    // in-flight start IS the caller (a feature callback re-entering
    // start()). Coalescing onto the in-flight future would have the
    // callback await its own parent and deadlock.
    if (Zone.current[userCallbackZoneKey] == true) {
      return Future.error(
        ContainerUsageError(
          'AppContainer.start() cannot be called from within a feature '
          'lifecycle callback. Schedule the start outside of it '
          '(e.g. unawaited(Future.microtask(container.start))).',
        ),
      );
    }

    // Coalesce: an in-flight (or queued-after-stop) start returns the
    // same future. Two consecutive `container.start()` calls share one
    // result — the second doesn't kick off a second cycle.
    final inFlight = _startFuture;
    if (inFlight != null) return inFlight;

    // No-op: container is already up and no stop is tearing it down.
    // Returns an already-completed future so callers can `await` without
    // ceremony.
    if (_status == ContainerStatus.working && _stopping == null) {
      return Future.value();
    }

    assert(() {
      // Re-attach the debug finalizer for this cycle. `detach` first
      // is defensive — if a previous cycle didn't detach (e.g. because
      // it was never stopped), we'd otherwise stack attach calls.
      _debugFinalizer.detach(this);
      _debugFinalizer.attach(
        this,
        'AppContainer#${identityHashCode(this)}',
        detach: this,
      );
      return true;
    }());
    return _startFuture = _runStart();
  }

  Future<void> _runStart() async {
    // Mutual await: if a stop is in flight, queue after it. The stop
    // returns the container to `.idle`; this start then runs fresh on
    // the next cycle's stores. Stop's failures don't block us — we
    // proceed regardless and surface our own outcome.
    final pendingStop = _stopping;
    if (pendingStop != null) {
      try {
        await pendingStop;
      } on Object {
        // Swallowed — this start's outcome stands on its own.
      }
    }

    _status = ContainerStatus.starting;
    try {
      await _orchestrator.start();
      // Don't flip to .working if a stop has been requested mid-start
      // — `_runStop` is awaiting our completion and will set `.idle`
      // after teardown.
      if (!isStopping) {
        _status = ContainerStatus.working;
      }
      // ignore: avoid_catching_errors
    } on GraphError catch (e) {
      await _rollback();
      throw _wrapGraphError(e);
    } on Object {
      await _rollback();
      rethrow;
    } finally {
      _startFuture = null;
    }
  }

  /// Re-wraps a sealed [GraphError] variant into the public
  /// [FeatureResolutionError] family so callers match a single
  /// framework type for every resolution failure. `GraphFixedPointError`
  /// — triggered by a toggle cycle in activation setups that never
  /// stabilises — shares the `cycle` reason with structural cycle
  /// detection.
  FeatureResolutionError _wrapGraphError(GraphError e) {
    return switch (e) {
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
  }

  /// Reverts a failed `start()`: tears down features, clears event
  /// listeners (so observers don't see partial state on the retry),
  /// and returns the container to `.idle`.
  Future<void> _rollback() async {
    await _teardownFeatures();
    _events.clearListeners();
    _status = ContainerStatus.idle;
  }

  /// Subscribes to feature status-change events (any transition among
  /// `disabled` / `pending` / `active`). Returns a disposer.
  ///
  /// Listeners are dropped on [stop]; re-subscribe after the next
  /// [start] if you want to keep observing.
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
  ///
  /// Listeners are dropped on [stop]; re-subscribe after the next
  /// [start] if you want to keep observing.
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
