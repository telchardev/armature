import 'package:meta/meta.dart' show internal;

/// Listener signature registered via [Emitter.add] — the emitter fires
/// the callback without any arguments; event attribution comes from the
/// key passed to [Emitter.add].
typedef VoidEventListener = void Function();

/// Called when a listener registered with [Emitter.emit] throws.
/// Receives the original event key, the error, and the stack trace so
/// the owning container can route the failure through its
/// `ContainerErrorHandler`.
typedef EmitterErrorHandler<TEvent> =
    void Function(TEvent event, Object error, StackTrace stackTrace);

/// Framework-internal fan-out primitive for keyed event notifications.
///
/// Each [TEvent] key can carry any number of [VoidEventListener]s;
/// [emit] fires them in insertion order with exception isolation — a
/// throwing listener is reported through [onListenerError] and the
/// remaining listeners still run. Safe to add or remove listeners
/// during a listener's own invocation: [emit] iterates a defensive
/// copy so subscribers can't trip `ConcurrentModificationError`.
///
/// Not exported from the public API — application code interacts with
/// the container's higher-level subscriptions (`onFeatureStatusChanged`,
/// `onPortChanged`) which delegate here.
@internal
class Emitter<TEvent> {
  final Map<TEvent, Set<VoidEventListener>> _listeners = {};

  /// Handler for exceptions thrown from listeners. Each listener's
  /// throw is caught, reported through this handler, and the remaining
  /// listeners still run. The owning container wires this to its
  /// `ContainerErrorHandler` so listener failures surface through the
  /// same channel as other recoverable errors.
  final EmitterErrorHandler<TEvent> onListenerError;

  /// Creates an emitter whose listener throws route through
  /// [onListenerError].
  Emitter({required this.onListenerError});

  /// Subscribes [listener] to [event]. Duplicate subscriptions (same
  /// listener instance for the same event) are silently deduped — the
  /// underlying set keeps a single entry.
  void add(TEvent event, VoidEventListener listener) {
    _listeners.putIfAbsent(event, () => {}).add(listener);
  }

  /// Fires [event] to every currently-registered listener.
  ///
  /// Allocation policy: single-listener events skip the defensive
  /// snapshot and call the listener directly. Multi-listener events
  /// iterate a snapshot so listeners are free to [add] or [remove]
  /// subscribers for the same [event] during their own invocation
  /// (classic one-shot-listener pattern — "fire, then remove myself").
  /// Idle events allocate nothing.
  ///
  /// A listener throw is caught and forwarded to [onListenerError];
  /// siblings still run.
  void emit(TEvent event) {
    final eventListeners = _listeners[event];
    if (eventListeners == null) return;
    final count = eventListeners.length;
    if (count == 0) return;
    if (count == 1) {
      try {
        eventListeners.first();
      } on Object catch (e, st) {
        onListenerError(event, e, st);
      }
      return;
    }
    for (final listener in eventListeners.toList(growable: false)) {
      try {
        listener();
      } on Object catch (e, st) {
        onListenerError(event, e, st);
      }
    }
  }

  /// Unsubscribes [listener] from [event]. No-op if not previously
  /// registered. When the last listener for an event is removed, the
  /// event's bucket is dropped from the internal map to keep memory
  /// bounded by the live-listener count, not the historical total.
  void remove(TEvent event, VoidEventListener listener) {
    final set = _listeners[event];
    if (set == null) return;
    set.remove(listener);
    if (set.isEmpty) {
      _listeners.remove(event);
    }
  }

  /// Drops every registered listener. Idempotent. Subsequent [emit]
  /// calls are no-ops.
  void dispose() {
    _listeners.clear();
  }
}
