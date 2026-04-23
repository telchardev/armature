import 'package:armature_reactive/armature_reactive.dart' show Reaction;
import 'package:meta/meta.dart' show internal;

import '../errors.dart' show RenderError;
import '../feature/feature.dart' show Feature;
import '../port/port.dart' show Port;
import './container.dart' show AppContainer;

/// Reactive subscription to a [Port]'s applied value.
///
/// Created by [AppContainer.observe]. Each subscription owns its own
/// [Reaction], so tracked atoms are isolated per subscriber — unlike
/// the retired shared-reaction model, two subscribers of the same port
/// that read different atoms no longer erase each other's dep sets.
///
/// [value] holds the most recent apply result and is updated before
/// the supplied `onChanged` callback fires. Use [reapply] when the
/// subscription's `initialValue` / `data` change but the port itself
/// stays the same — it re-runs apply without the cost of disposing
/// and re-creating the underlying [Reaction]. Call [dispose] when the
/// subscription is no longer needed so the reaction drops its atom
/// observers.
abstract class PortSubscription<TValue, TInputData> {
  /// Framework-internal: a "dead-on-arrival" subscription used when
  /// [Port.check] fails. [value] is pinned at [initialValue]; [reapply]
  /// and [dispose] are no-ops. No [Reaction], no event subscription —
  /// zero runtime cost beyond the handle itself.
  @internal
  factory PortSubscription.disabled(TValue initialValue) =
      _DisabledPortSubscription<TValue, TInputData>;

  /// Framework-internal: a live subscription that runs the initial
  /// apply, subscribes to the port's handler-set change stream, and
  /// re-applies whenever any tracked atom changes.
  @internal
  factory PortSubscription.live({
    required AppContainer container,
    required Feature rootFeature,
    required Port<TValue, TInputData, Function> port,
    required TValue initialValue,
    required TInputData data,
    required void Function() onChanged,
  }) = _LivePortSubscription<TValue, TInputData>;

  /// Latest apply result. Updated automatically whenever a tracked
  /// atom changes or [reapply] is called. After [dispose], returns the
  /// value at the last successful apply.
  TValue get value;

  /// Whether [dispose] has been called (or whether this is a
  /// [PortSubscription.disabled] handle, in which case always `true`).
  bool get isDisposed;

  /// Updates [initialValue] / [data] and re-runs `port.apply` once.
  ///
  /// The underlying [Reaction] is kept alive — the atom-observer set
  /// is reconciled via the next `track()`'s diff against the previous
  /// dep set, so unchanged deps cost nothing. Use from
  /// `didUpdateWidget` when the subscriber's inputs change but the
  /// port stays the same; that's cheaper than `dispose()` +
  /// [AppContainer.observe] which would allocate a fresh Reaction and
  /// re-subscribe to handler-set events for no gain.
  ///
  /// No-op if disposed.
  void reapply({required TValue initialValue, required TInputData data});

  /// Releases the subscription's reaction and its atom observers. Safe
  /// to call multiple times.
  void dispose();
}

/// Pinned-at-initial-value stub returned when [AppContainer.observe]
/// short-circuits on a port-check failure. Avoids allocating a
/// [Reaction] or subscribing to events only to throw them away.
class _DisabledPortSubscription<TValue, TInputData>
    implements PortSubscription<TValue, TInputData> {
  _DisabledPortSubscription(this._value);

  final TValue _value;

  @override
  TValue get value => _value;

  @override
  bool get isDisposed => true;

  @override
  void reapply({required TValue initialValue, required TInputData data}) {}

  @override
  void dispose() {}
}

/// Live subscription — owns the [Reaction] and the `portChanged`
/// listener. All apply / re-apply logic lives on this class so the
/// container's `observe()` factory stays a thin wrapper.
class _LivePortSubscription<TValue, TInputData>
    implements PortSubscription<TValue, TInputData> {
  _LivePortSubscription({
    required AppContainer container,
    required Feature rootFeature,
    required Port<TValue, TInputData, Function> port,
    required void Function() onChanged,
    required TValue initialValue,
    required TInputData data,
  }) : _container = container,
       _rootFeature = rootFeature,
       _port = port,
       _onChanged = onChanged,
       _value = initialValue,
       _initialValue = initialValue,
       _data = data {
    // `_notify` is stored once so both `Reaction.onInvalidate` and
    // `AppContainer.onPortChanged` hold the same callable identity —
    // important because the portChanged disposer must `remove` the
    // very same instance that was added. Method tear-offs (e.g.
    // `_notify = _reapplyAndNotifyMethod`) are not canonicalised for
    // instance members in Dart; a closure is the safer bet.
    _notify = () {
      if (_disposed) return;
      _runApply();
      _onChanged();
    };
    _reaction = Reaction(onInvalidate: _notify);
    _portChangedDisposer = _container.onPortChanged(
      port: _port,
      callback: _notify,
    );
    // Initial read. Silent — `_runApply` does not call `_onChanged`
    // (only `_notify` does), matching the pre-refactor behaviour
    // where the caller reads the freshly-returned subscription's
    // `value` synchronously without an onChanged fire.
    _runApply();
  }

  final AppContainer _container;
  final Feature _rootFeature;
  final Port<TValue, TInputData, Function> _port;
  final void Function() _onChanged;

  late final Reaction _reaction;
  late final void Function() _notify;
  late final void Function() _portChangedDisposer;

  TValue _value;
  TValue _initialValue;
  TInputData _data;
  bool _disposed = false;

  @override
  TValue get value => _value;

  @override
  bool get isDisposed => _disposed;

  @override
  void reapply({required TValue initialValue, required TInputData data}) {
    if (_disposed) return;
    _initialValue = initialValue;
    _data = data;
    _runApply();
  }

  void _runApply() {
    try {
      late TValue result;
      _reaction.track(() {
        result = _port.apply(
          initialValue: _initialValue,
          data: _data,
          container: _container,
        );
      });
      _value = result;
    } on Object catch (e, st) {
      _container.reportError(
        feature: _rootFeature,
        error: RenderError.wrap(_rootFeature.name, e, stackTrace: st),
      );
      _value = _initialValue;
    }
  }

  @override
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _reaction.clear();
    _portChangedDisposer();
  }
}
