import 'package:meta/meta.dart';

import '../emitter.dart';
import '../feature/feature.dart';
import '../port/port.dart';

/// Signature for reporting listener errors back to the owning container.
/// [source] is the attribution label passed through to the container's
/// `ContainerErrorHandler` — the feature name for feature-scoped
/// events, or [Events.eventsSentinel] (`'<events>'`) for container-
/// scoped events (e.g. `portChanged`) where no single feature is
/// responsible. [meta] carries event-kind plus additional breadcrumbs
/// (e.g. port name) so handlers can filter.
typedef ListenerErrorReporter =
    void Function(
      String source,
      Object error,
      StackTrace stackTrace,
      Map<String, String> meta,
    );

/// Bundle of container-scoped event emitters. Disposed as a unit by
/// [AppContainer.dispose]. External listeners subscribe through
/// [AppContainer.onFeatureStatusChanged] and [AppContainer.onPortChanged].
///
/// Listener exceptions are captured and forwarded to
/// [reportListenerError] so the container can route them through its
/// `ContainerErrorHandler` — one misbehaving listener no longer
/// blocks siblings or bubbles up into framework code.
@internal
class Events {
  /// Attribution label used as the `source` argument passed to the
  /// container's `ContainerErrorHandler` when a listener on a
  /// container-scoped event (e.g. `portChanged`) throws. These events
  /// aren't attributable to a single feature, so this synthetic label
  /// stands in.
  static const eventsSentinel = '<events>';

  final Emitter<AnyFeature> featureStatusChanged;

  /// Fires when a port's live handler set changes — a feature owning
  /// a handler on the port transitions active ↔ disabled. Consumed
  /// both by external [AppContainer.onPortChanged] subscribers (debug
  /// tooling) and by [PortSubscription] internals so observe subs
  /// re-apply when a new handler joins / leaves the chain.
  ///
  /// Emitted **only** from the feature-lifecycle cascade, never from
  /// `observe`'s reactive invalidations — that keeps per-subscriber
  /// atom-tracking isolated (subA's atom change never wakes subB) and
  /// silences the log for routine state mutations.
  final Emitter<AnyPort> portChanged;

  Events({required ListenerErrorReporter reportListenerError})
    : featureStatusChanged = Emitter<AnyFeature>(
        onListenerError: (feature, error, stackTrace) => reportListenerError(
          feature.name,
          error,
          stackTrace,
          {'event': 'featureStatusChanged'},
        ),
      ),
      portChanged = Emitter<AnyPort>(
        onListenerError: (port, error, stackTrace) => reportListenerError(
          eventsSentinel,
          error,
          stackTrace,
          {'event': 'portChanged', 'port': port.name},
        ),
      );

  void dispose() {
    featureStatusChanged.dispose();
    portChanged.dispose();
  }
}
