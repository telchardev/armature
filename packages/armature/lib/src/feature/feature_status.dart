/// Lifecycle state of a feature, as observed from the [AppContainer].
///
/// * [disabled] — not active. The feature is either auto-inactive, its
///   required parent is inactive, or its activation failed. Default state
///   before `AppContainer.start` runs.
/// * [pending] — mid-activation: the feature's stores are constructed
///   and the graph is awaiting the visitor's `onActivate` work to
///   complete. This covers the user's async `onStart` callback plus
///   any framework bookkeeping around it; transitions to `.active`
///   as soon as activation settles successfully, or back to `.disabled`
///   if it throws.
/// * [active] — fully online: stores are live and `onStart` has
///   completed.
enum FeatureStatus { disabled, pending, active }

/// Target state a [FeatureToggle] call sets the feature to.
enum ToggleState { active, inactive }

/// Callable that sets a feature's activation state from user code.
///
/// Passed to the `activation` setup callback. The user wires their own
/// trigger (state subscription, stream, timer, manual) and calls it with
/// the desired [ToggleState]:
///
/// ```dart
/// feature.activation((parentApi, toggle, cleanup) {
///   final sub = someStream.listen((data) {
///     toggle(data.ready ? ToggleState.active : ToggleState.inactive);
///   });
///   cleanup.add(sub.cancel);
/// });
/// ```
///
/// The returned `Future<void>` completes when the cascade finishes
/// (stores initialised, `onStart` awaited, descendants updated).
/// Awaiting is optional — fire-and-forget is fine.
///
/// Calls are idempotent: setting the current state is a no-op.
typedef FeatureToggle = Future<void> Function(ToggleState state);
