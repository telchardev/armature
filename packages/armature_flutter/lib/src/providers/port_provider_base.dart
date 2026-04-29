import 'package:armature/advanced.dart' show PortSubscription;
import 'package:armature/armature.dart' show RenderError;
import 'package:flutter/widgets.dart' show State, StatefulWidget;

import '../contexts/container_context.dart' show ContainerContext;
import '../contexts/feature_context.dart' show FeatureContext;
import '../stores/safe_set_state_mixin.dart' show SafeSetStateMixin;

/// Shared [State] base for the built-in port providers
/// ([PipeProvider], [BehaviorProvider], [SingleSlotProvider],
/// [MultiSlotProvider]).
///
/// Owns one [PortSubscription] per mounted widget and forwards
/// rebuilds to the framework via [safeSetState]. Subclasses implement
/// [createSubscription] to call `container.observe(...)` with the
/// correct typed arguments, and expose a [fallbackValue] to render
/// when the subscription fails to initialise (mis-scoped apply) or a
/// handler throws. The container routes throws through its
/// `errorHandler` as [RenderError] and the subscription falls back to
/// the port's `initialValue` for that apply; the provider surfaces
/// [fallbackValue] externally so the rest of the widget tree keeps
/// working instead of tripping Flutter's build error boundary.
///
/// Intended to be subclassed only within this package — user code
/// composes the concrete providers directly.
abstract class PortProviderState<TValue, TInputData, W extends StatefulWidget>
    extends State<W>
    with SafeSetStateMixin {
  PortSubscription<TValue, TInputData>? _sub;

  /// Current reactive value, or [fallbackValue] if the subscription
  /// failed to initialise.
  TValue get value => _sub?.value ?? fallbackValue;

  /// The active subscription, or `null` if initialisation failed.
  /// Subclasses use this from `didUpdateWidget` to forward
  /// [PortSubscription.reapply] when only the port's inputs
  /// (`initialValue` / `data`) changed — that's cheaper than
  /// [resubscribe] which allocates a fresh [PortSubscription].
  PortSubscription<TValue, TInputData>? get subscription => _sub;

  /// Creates a reactive subscription to the current port with the
  /// typed arguments the subclass knows about. Subclasses typically
  /// return `container.observe(...)` with `onChanged: safeSetState`.
  PortSubscription<TValue, TInputData> createSubscription();

  /// Value to surface when the subscription failed at construction
  /// (mis-scoped apply) or was disposed. Subclasses return something
  /// the builder can render without a feature-specific handler (e.g.
  /// `widget.initialValue`, `null`, or `const []`).
  TValue get fallbackValue;

  /// Ensures a live subscription exists. Called from
  /// [didChangeDependencies] on first build and whenever an ancestor
  /// inherited widget changes. Idempotent: a non-null subscription
  /// is reused.
  void _ensureSubscribed() {
    if (_sub != null) return;
    try {
      _sub = createSubscription();
    } on Object catch (e, st) {
      _reportInitError(e, st);
    }
  }

  /// Disposes the current subscription (if any) and creates a fresh
  /// one. Subclasses call this from [didUpdateWidget] when the **port**
  /// itself changes — a new subscription is needed because the old
  /// one is tied to the previous port's handler set. For input-only
  /// changes (same port, new `initialValue` / `data`), call
  /// [PortSubscription.reapply] via [subscription] instead, which
  /// reuses the existing [Reaction] and handler-set listener.
  void resubscribe() {
    _sub?.dispose();
    _sub = null;
    try {
      _sub = createSubscription();
    } on Object catch (e, st) {
      _reportInitError(e, st);
    }
    if (mounted) setState(() {});
  }

  void _reportInitError(Object e, StackTrace st) {
    try {
      final container = ContainerContext.of(context).container;
      final feature = FeatureContext.of(context).feature;
      container.reportError(
        feature: feature,
        error: RenderError.wrap(feature.name, e, stackTrace: st),
      );
    } on Object {
      // We're on the build path and contexts might be unavailable.
      // Swallow — falling back below is still correct.
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _ensureSubscribed();
  }

  @override
  void dispose() {
    _sub?.dispose();
    super.dispose();
  }
}
