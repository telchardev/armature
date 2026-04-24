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
/// Ports are **stateless across containers**. Handler registration,
/// deregistration, and invocation all go through per-container maps
/// owned by [AppContainer] (via `container.handlersOf<THandler>(port)`,
/// `container.addPortHandler(...)`, etc.). The only mutable field on a
/// port itself is [_owner], which is set once (either up front via the
/// `feature:` constructor argument or lazily on the first apply) and
/// never cleared — the ownership of a port is a property of the feature
/// that declared it in `ports:`, stable for the lifetime of the process.
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

  @internal
  Port({required this.name, required this.type, AnyFeature? owner})
    : _owner = owner;

  /// Applies this port against the handler set registered in [container]
  /// for this port. Subclasses iterate `container.handlersOf<THandler>(this)`
  /// to get the live map.
  @internal
  TValue apply({
    required TValue initialValue,
    required AppContainer container,
    required TInputData data,
  });

  /// Validates that [applyingFeature] is allowed to apply this port
  /// against [container]'s handler registry.
  ///
  /// **Always returns, never throws.** Apply-time validation runs on
  /// every render (potentially per-frame), so a mis-scoped apply is
  /// surfaced as a value — callers route the returned [PortError] through
  /// the container's `errorHandler` and fall back to `initialValue`
  /// instead of crashing the build. Registration-time validation
  /// ([validateOwnership]) *throws* [PortError] from
  /// [AppContainer.addPortHandler] — those are programming errors that
  /// fire once, during container construction / feature start.
  ///
  /// **Side effect**: the first successful call binds this port's
  /// owner to [applyingFeature] (when the port was constructed without
  /// an explicit `feature:` argument). Subsequent calls must use the
  /// same feature; otherwise a [PortError] is returned. Use
  /// constructors with an explicit `feature:` to avoid relying on lazy
  /// binding.
  ///
  /// **Deferred validation.** During the owner-binding step, every
  /// handler already registered against [container] for this port is
  /// revalidated against the candidate owner. If any pre-registered
  /// handler violates the owner/parent contract, this method returns
  /// that [PortError] **without binding the owner** — the port stays
  /// in lazy-bind mode so the next apply repeats validation from
  /// scratch.
  @internal
  PortError? check({
    required AppContainer container,
    required AnyFeature applyingFeature,
  }) {
    if (_owner == null) {
      final handlers = container.handlersOf(this);
      for (final feature in handlers.keys) {
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

  /// Validates a feature for registration of a handler on this port.
  /// Returns `null` when the registration is legal, otherwise a
  /// [PortError] the caller can throw or route through `errorHandler`.
  ///
  /// Used by [AppContainer.addPortHandler] at feature-start time.
  @internal
  PortError? validateOwnership({required AnyFeature applyingFeature}) {
    if (_owner == null) return null; // lazy-bind mode; check at apply time.
    return _validateHandler(applyingFeature, candidateOwner: _owner!);
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

  /// Pure validator — returns the [PortError] that would be raised for
  /// [feature] against [candidateOwner], or `null` if the pairing is
  /// legal.
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
