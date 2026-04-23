import 'package:meta/meta.dart';

import '../container/container.dart' show AppContainer;
import '../errors.dart' show PortError;
import '../feature/feature.dart' show AnyFeature;
import '../logger/logger.dart' show LoggerDebugInfo;
import './port_type.dart' show PortType;

/// Type alias for a [Port] with type params erased.
typedef AnyPort = Port<dynamic, Object?, Function>;

/// Base class for composable ports (pipes, behaviors, slots).
///
/// A port collects handlers from child features. Subclasses fix
/// `THandler` to their concrete handler-function type via a type-variable
/// bound (`THandler extends PipeHandler<TValue>` etc.), so the handler
/// map stays typed without per-call casts.
///
/// Owner is bound lazily on first [apply] call if not supplied via factory.
///
/// **Handler invariants:**
///
///   * Handlers must be **pure** — no side effects beyond computing
///     the returned value. A handler that throws will break the
///     current [apply] and propagate the exception to the caller (the
///     container's reaction doesn't swallow it).
///   * Handlers can **read** from reactive `State` / `Atom`; reads are
///     tracked automatically for invalidation. They must NOT **write**
///     to reactive state during a handler body — that creates a
///     reaction cycle where the write invalidates the very reaction
///     executing the handler. Schedule writes outside of the handler
///     (e.g. in an `onStart` Future or user-triggered task).
abstract class Port<
  TValue,
  TInputData extends Object?,
  THandler extends Function
>
    implements LoggerDebugInfo {
  final String name;

  final PortType type;

  AnyFeature? _owner;

  final Map<AnyFeature, THandler> _handlers = {};

  @internal
  Port({required this.name, required this.type, AnyFeature? owner})
    : _owner = owner;

  /// Registers a [handler] from [feature] for this port.
  ///
  /// Throws [PortError] immediately if [feature] already has a handler
  /// registered, or — when [_owner] is already bound — if [feature]
  /// violates the owner/parent contract (`feature == _owner`, or the
  /// port's owner is not in [feature]'s `dependsOn` / `optionalDependsOn`).
  ///
  /// When this port was constructed without an explicit `feature:`
  /// argument (lazy-owner mode), owner/parent validation of
  /// pre-registered handlers is **deferred** to the first [check] call;
  /// see there for details.
  @internal
  void addHandler({required THandler handler, required AnyFeature feature}) {
    if (_handlers[feature] != null) {
      throw PortError(
        name,
        "Port \"$name\" already used in \"${feature.name}\" feature",
      );
    }

    if (_owner != null) {
      final error = _validateHandler(feature, candidateOwner: _owner!);
      if (error != null) throw error;
    }

    _handlers[feature] = handler;
  }

  @internal
  TValue apply({
    required TValue initialValue,
    required AppContainer container,
    required TInputData data,
  });

  /// Validates that [applyingFeature] is allowed to apply this port.
  ///
  /// **Always returns, never throws.** Apply-time validation runs on
  /// every render (potentially per-frame), so a mis-scoped apply is
  /// surfaced as a value — `AppContainer.apply` routes the returned
  /// [PortError] through the container's `errorHandler` and falls back
  /// to `initialValue` instead of crashing the build. Registration-time
  /// validation ([addHandler]) still *throws* [PortError] — those are
  /// programming errors that fire once, during feature construction.
  ///
  /// **Side effect**: the first successful call binds this port's
  /// owner to [applyingFeature] (when the port was constructed without
  /// an explicit `feature:` argument). Subsequent calls must use the
  /// same feature; otherwise a [PortError] is returned. Use [Pipe] /
  /// [Behavior] factories with an explicit `feature:` to avoid relying
  /// on lazy binding.
  ///
  /// **Deferred validation.** During the owner-binding step, every
  /// handler that was registered while the owner was still unbound is
  /// revalidated against the candidate owner. If any pre-registered
  /// handler violates the owner/parent contract, this method returns
  /// that [PortError] **without binding the owner** — the port stays
  /// in lazy-bind mode so the next apply repeats validation from
  /// scratch (possibly picking up a fix via hot-reload). The violating
  /// handler is kept in the map but never executes, because `apply`
  /// short-circuits whenever [check] returns a non-null error.
  @internal
  PortError? check({required AnyFeature applyingFeature}) {
    if (_owner == null) {
      // Validate every pre-registered handler against the candidate
      // owner before committing the binding. If any violates, leave
      // `_owner` null so a subsequent apply re-runs validation — this
      // keeps the port observable-broken until the source is fixed,
      // without silently executing misconfigured handlers.
      for (final feature in _handlers.keys) {
        final error = _validateHandler(
          feature,
          candidateOwner: applyingFeature,
        );
        if (error != null) return error;
      }
      _owner = applyingFeature;
      return null;
    }

    return applyingFeature != _owner
        ? PortError(
            name,
            "an attempt to apply a port inside a feature "
            "(\"${applyingFeature.name}\") that is not its owner "
            "(\"${_owner!.name}\")",
          )
        : null;
  }

  @override
  Map<String, String> get debugInfo {
    return {
      "name": name,
      "type": type.name,
      "owner": _owner?.name ?? 'unbound',
    };
  }

  @override
  String toString() => '${type.name}($name)';

  /// Number of features that registered handlers for this port.
  @internal
  int get handlerCount => _handlers.length;

  /// Names of features that registered handlers for this port.
  @internal
  List<String> get handlerFeatureNames =>
      _handlers.keys.map((f) => f.name).toList();

  @protected
  @internal
  Map<AnyFeature, THandler> get handlers => _handlers;

  @internal
  void removeHandler({required AnyFeature feature}) {
    _handlers.remove(feature);
  }

  /// Pure validator — returns the [PortError] that would be raised for
  /// [feature] against [candidateOwner], or `null` if the pairing is
  /// legal. Used by [addHandler] (eager path: wraps the result in a
  /// throw) and [check] (lazy-bind path: returns the result up the
  /// stack without binding the owner).
  PortError? _validateHandler(
    AnyFeature feature, {
    required AnyFeature candidateOwner,
  }) {
    if (feature == candidateOwner) {
      return PortError(
        name,
        "Forbid use \"$name\" port in owner \"${feature.name}\" feature",
      );
    }

    final hasOwnerInParents =
        feature.parents.contains(candidateOwner) ||
        feature.optionalParents.contains(candidateOwner);

    if (!hasOwnerInParents) {
      return PortError(
        name,
        "Not found \"${candidateOwner.name}\" feature in "
        "\"${feature.name}\" feature dependencies",
      );
    }

    return null;
  }
}
