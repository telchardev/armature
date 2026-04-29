/// Base class for every error the framework produces.
///
/// The `on ArmatureError` clause catches every typed error surfaced by
/// `armature` — whether it's a misuse of the API, a resolution failure,
/// or a user-callback failure reported through a
/// [ContainerErrorHandler].
///
/// The hierarchy is split across four broad groups:
///
/// * **Lifecycle errors** (thrown when an operation is invoked in the
///   wrong container state): [ContainerError].
/// * **Programming errors** (thrown synchronously, must be fixed in
///   code): [TaskError], [FeatureConfigurationError],
///   [ContainerUsageError], [PortError], [StoreLookupError].
/// * **Resolution failures** (thrown by `AppContainer.start()` when the
///   graph or a stores factory can't be brought up):
///   [FeatureResolutionError] with a [FeatureResolutionReason].
/// * **Recoverable runtime errors** (reported to
///   [ContainerErrorHandler], never thrown out of the framework):
///   [HandlerError], [ListenerError], [RenderError].
///
/// **Stack traces.** Every [ArmatureError] carries an optional
/// [stackTrace] — either captured explicitly at a `catch` site
/// (passed into the constructor / `wrap` factory), or the VM-attached
/// trace from a `throw`. Consumers of [ContainerErrorHandler] can
/// rely on `error.stackTrace` for diagnostics without any extra
/// plumbing.
sealed class ArmatureError extends Error {
  final String message;
  final StackTrace? _stackTrace;

  ArmatureError(this.message, {StackTrace? stackTrace})
    : _stackTrace = stackTrace;

  /// Captured stack trace — either passed into the constructor (e.g.
  /// threaded through `wrap(..., stackTrace: st)` at a `catch` site)
  /// or, failing that, the trace the VM attached when this error was
  /// thrown. `null` only if the error was never thrown and no trace
  /// was supplied.
  @override
  StackTrace? get stackTrace => _stackTrace ?? super.stackTrace;

  @override
  String toString() => message;
}

/// Thrown when an [AppContainer] operation is invoked in the wrong
/// lifecycle state — e.g. double `start()` without an intervening
/// `stop()`, `apply()` before `start()`.
final class ContainerError extends ArmatureError {
  ContainerError(super.message, {super.stackTrace});

  @override
  String toString() => 'ContainerError: $message';
}

/// Thrown when [AppContainer] is used in a way that can only be a bug
/// in calling code: `stop()` from inside a user callback (would
/// self-deadlock), reaching into orchestrator internals before `start()`,
/// etc.
final class ContainerUsageError extends ArmatureError {
  ContainerUsageError(super.message, {super.stackTrace});

  @override
  String toString() => 'ContainerUsageError: $message';
}

/// Thrown when a [Feature] is misconfigured: `activation()` / `onStart()`
/// called more than once, a duplicate [Store] registered under the same
/// runtime type inside the same feature, or a feature's scope API
/// accessed before its construct phase.
final class FeatureConfigurationError extends ArmatureError {
  /// Name of the affected feature when one is in scope. `null` for
  /// errors raised from contexts without feature attribution (e.g.
  /// duplicate [Store] detection inside [Store.track]).
  final String? featureName;

  FeatureConfigurationError(
    super.message, {
    this.featureName,
    super.stackTrace,
  });

  @override
  String toString() => featureName != null
      ? 'FeatureConfigurationError($featureName): $message'
      : 'FeatureConfigurationError: $message';
}

/// Thrown when a [Task] is called after it — or the owning [Store] —
/// has been disposed, or surfaced through a pending future when
/// `Task.reset()` cancels coalesced callers from `.latest`,
/// `.debounce`, or `.throttle(trailing)`.
final class TaskError extends ArmatureError {
  TaskError(super.message, {super.stackTrace});

  @override
  String toString() => 'TaskError: $message';
}

/// Reason classification for [FeatureResolutionError]. Lets callers
/// distinguish configuration errors (e.g. missing parent) from runtime
/// failures (e.g. stores factory threw) without parsing the message.
enum FeatureResolutionReason {
  /// A declared parent feature is missing from the `AppContainer.features`
  /// list (originally surfaces as `GraphNodeNotFoundError`).
  missingParent,

  /// `api.of(feature)` was called with a feature that is not in the
  /// caller's declared parents (neither required nor optional).
  notDeclaredParent,

  /// The user-supplied `stores` factory threw during the container's
  /// eager construct phase. `AppContainer.start()` aborts fail-fast
  /// and rolls back to `.idle`.
  storesFactoryFailed,

  /// A cycle exists in the feature dependency graph (originally surfaces
  /// as `GraphCycleError`).
  cycle,

  /// `Feature.useStores(factory)` was called after the feature's scope
  /// API had already been built (or attempted).
  storesAlreadyInitialised,

  /// Catch-all for less-specific framework errors that still belong to
  /// the feature-resolution family.
  other,
}

/// Thrown when a feature fails to resolve during `AppContainer.start()`.
/// The [reason] field pins down which kind of failure this is;
/// [message] has the human-readable details.
final class FeatureResolutionError extends ArmatureError {
  final String featureName;
  final FeatureResolutionReason reason;

  FeatureResolutionError(
    this.featureName,
    String message, {
    this.reason = FeatureResolutionReason.other,
    StackTrace? stackTrace,
  }) : super(message, stackTrace: stackTrace);

  @override
  String toString() =>
      'FeatureResolutionError($featureName, ${reason.name}): $message';
}

/// Thrown when a port is used incorrectly — duplicate handler from the
/// same feature, handler registered by the owner, handler registered by
/// a feature that didn't declare the owner as a parent.
///
/// At *apply-time* (inside `port.apply()` / `AppContainer.apply()`) the
/// same condition is **returned** rather than thrown — see `Port.check`
/// — so a mis-scoped apply degrades gracefully (returns `initialValue`)
/// instead of crashing the render.
final class PortError extends ArmatureError {
  final String portName;

  PortError(this.portName, String message, {StackTrace? stackTrace})
    : super(message, stackTrace: stackTrace);

  @override
  String toString() => 'PortError($portName): $message';
}

/// Thrown when [FeatureHandlerContext.store] cannot find a store by
/// type.
final class StoreLookupError extends ArmatureError {
  final Type storeType;

  StoreLookupError(this.storeType, String message, {StackTrace? stackTrace})
    : super(message, stackTrace: stackTrace);

  @override
  String toString() => 'StoreLookupError($storeType): $message';
}

/// Reported to [ContainerErrorHandler] when a user-supplied **handler**
/// — an activation `setup`, `onStart`, or a port handler (`usePipe` /
/// `useBehavior` / `useSingleSlot` / `useMultiSlot`) — throws.
///
/// Never thrown back out of the framework: it's always the payload of
/// an `errorHandler` callback, so the container remains usable.
final class HandlerError extends ArmatureError {
  /// Name of the feature that owns the throwing handler.
  final String featureName;

  HandlerError(this.featureName, super.message, {super.stackTrace});

  /// Wraps a raw throw from a handler into a typed [HandlerError].
  ///
  /// * If [error] is already an [ArmatureError], it is returned unchanged
  ///   — framework errors pass through without re-wrapping.
  /// * Otherwise a new [HandlerError] is built with a message
  ///   optionally prefixed by [source] (e.g. `'onStart'`,
  ///   `'Store dispose'`). The caller's [stackTrace] is preserved on
  ///   the resulting error for diagnostics.
  static ArmatureError wrap(
    String featureName,
    Object error, {
    String? source,
    StackTrace? stackTrace,
  }) {
    if (error is ArmatureError) return error;
    final message = source != null ? '$source threw: $error' : error.toString();
    return HandlerError(featureName, message, stackTrace: stackTrace);
  }

  @override
  String toString() => 'HandlerError($featureName): $message';
}

/// Reported to [ContainerErrorHandler] when a user-supplied event
/// listener registered via [AppContainer.onFeatureStatusChanged] or
/// [AppContainer.onPortChanged] throws. Never thrown directly — one
/// misbehaving listener never breaks siblings or bubbles up into
/// framework code.
final class ListenerError extends ArmatureError {
  /// For `featureStatusChanged` listeners — the feature's name. For
  /// `portChanged` listeners — the port's name.
  final String source;

  ListenerError(this.source, super.message, {super.stackTrace});

  /// Wraps a raw throw from a listener into a typed [ListenerError].
  /// Passes [error] through unchanged when it's already an
  /// [ArmatureError]; otherwise attaches the provided [stackTrace] for
  /// diagnostics.
  static ArmatureError wrap(
    String source,
    Object error, {
    StackTrace? stackTrace,
  }) {
    if (error is ArmatureError) return error;
    return ListenerError(
      source,
      'Listener threw: $error',
      stackTrace: stackTrace,
    );
  }

  @override
  String toString() => 'ListenerError($source): $message';
}

/// Reported to [ContainerErrorHandler] when a slot widget's `build`
/// throws. Never thrown directly — the slot renders a fallback widget
/// (or the application's `errorBuilder`) instead.
final class RenderError extends ArmatureError {
  /// Name of the feature whose slot widget threw during build.
  final String featureName;

  RenderError(this.featureName, super.message, {super.stackTrace});

  /// Wraps a raw throw from a slot build into a typed [RenderError].
  /// Passes [error] through unchanged when it's already an
  /// [ArmatureError]; otherwise attaches the provided [stackTrace] for
  /// diagnostics.
  static ArmatureError wrap(
    String featureName,
    Object error, {
    StackTrace? stackTrace,
  }) {
    if (error is ArmatureError) return error;
    return RenderError(
      featureName,
      'Render threw: $error',
      stackTrace: stackTrace,
    );
  }

  @override
  String toString() => 'RenderError($featureName): $message';
}
