import 'dart:async';

import 'package:meta/meta.dart';

import '../store/state.dart' show StateChangeListener;
import '../store/store.dart' show Store;

/// Bag of cleanup callbacks collected during `onStart`, executed in LIFO
/// order on feature deactivation.
///
/// Disposers may be sync or async (`FutureOr<void> Function()`). Async
/// disposers are awaited before the next one runs, so cleanup ordering
/// is preserved.
///
/// ```dart
/// feature.onStart((api, cleanup) {
///   // The verbose form — works for any disposer:
///   cleanup.add(api.of(other).store.subscribe(listener));
///
///   final ws = WebSocket.connect(url);
///   cleanup.add(ws.close);             // async disposer (Future<void>)
///
///   // For common patterns, prefer the typed helpers:
///   cleanup.subscribe(api.own.counter, (prev, next) => /* ... */);
///   cleanup.periodic(Duration(seconds: 30), () => api.own.data.refresh());
///   cleanup.listen(eventStream, (event) => /* ... */);
/// });
/// ```
///
/// After deactivation the bag is sealed: subsequent `add` calls invoke
/// the disposer immediately, which makes async `onStart` that races with
/// deactivation safe by default. Late-added async disposers are
/// fire-and-forget — `add` itself stays sync.
abstract class Cleanup {
  /// Registers a disposer to run on deactivation (LIFO order).
  ///
  /// The disposer may be sync (`void`) or async (`Future<void>`). Async
  /// disposers are awaited inside `runAll` to preserve LIFO ordering.
  ///
  /// If the feature has already been deactivated (e.g. the bag was
  /// sealed while an async `onStart` was still awaiting), the disposer
  /// is invoked immediately. Late-add of an async disposer is
  /// fire-and-forget (the result is not awaited).
  void add(FutureOr<void> Function() disposer);

  /// Subscribes [listener] to [store] and registers the cancel disposer
  /// on this bag. Sugar for the common pattern
  /// `cleanup.add(store.subscribe(listener, ...))`.
  ///
  /// [fireImmediately] forwards to [Store.subscribe]: when `true`, the
  /// listener fires once during `subscribe` with `(current, current)` so
  /// the caller can seed its side effect.
  void subscribe<T>(
    Store<T> store,
    StateChangeListener<T> listener, {
    bool fireImmediately = false,
  }) {
    add(store.subscribe(listener, fireImmediately: fireImmediately));
  }

  /// Schedules [callback] to fire every [duration] until the bag runs.
  /// Wraps [Timer.periodic] and registers `timer.cancel` on this bag —
  /// the timer is cancelled automatically on deactivation.
  ///
  /// Sugar for
  /// `cleanup.add(Timer.periodic(duration, (_) => callback()).cancel)`.
  /// For the rare case where the [Timer] argument is needed inside the
  /// callback, drop to that verbose form.
  void periodic(Duration duration, void Function() callback) {
    final timer = Timer.periodic(duration, (_) => callback());
    add(timer.cancel);
  }

  /// Subscribes to [stream] and registers the subscription's `cancel`
  /// disposer on this bag. Every parameter mirrors [Stream.listen].
  ///
  /// Sugar for
  /// `cleanup.add(stream.listen(onData, onError: ..., onDone: ..., cancelOnError: ...).cancel)`.
  void listen<T>(
    Stream<T> stream,
    void Function(T data) onData, {
    Function? onError,
    void Function()? onDone,
    bool? cancelOnError,
  }) {
    final subscription = stream.listen(
      onData,
      onError: onError,
      onDone: onDone,
      cancelOnError: cancelOnError,
    );
    add(subscription.cancel);
  }
}

/// Default [Cleanup] implementation used by the framework.
@internal
final class CleanupBag extends Cleanup {
  final List<FutureOr<void> Function()> _disposers = [];
  bool _sealed = false;
  final void Function(Object error, StackTrace stack)? _onError;

  CleanupBag({required void Function(Object error, StackTrace stack) onError})
    : _onError = onError;

  /// Creates an already-sealed empty bag. Used as a non-null default for
  /// lifecycle state slots that should behave as "no-op" until a real
  /// bag is installed: [add] runs disposers immediately, [runAll] is a
  /// no-op. If [onError] is supplied, late-`add` failures (sync or
  /// async) route through it — the framework plumbs the same sink the
  /// live bag used, so races between an async `onStart` and
  /// deactivation surface errors through the container's
  /// `errorHandler` rather than silently vanishing.
  CleanupBag.sealed({void Function(Object error, StackTrace stack)? onError})
    : _sealed = true,
      _onError = onError;

  /// Runs all registered disposers in LIFO order and seals the bag. Safe
  /// to call multiple times — subsequent calls resolve to a no-op.
  ///
  /// Async disposers are awaited sequentially, so a disposer's effects
  /// land before the next one starts. Exceptions thrown (sync) or future
  /// rejections (async) are passed to [onError] (if provided) and do not
  /// prevent the remaining disposers from running.
  Future<void> runAll() async {
    if (_sealed) return;
    _sealed = true;
    for (final disposer in _disposers.reversed) {
      try {
        await disposer();
      } on Object catch (e, st) {
        _onError?.call(e, st);
      }
    }
    _disposers.clear();
  }

  @override
  void add(FutureOr<void> Function() disposer) {
    if (_sealed) {
      // Late registration (async `onStart` raced with deactivation).
      // Run the disposer immediately. Async results are fire-and-forget
      // because `add` is sync; any rejection is reported through the
      // bag's onError if one is set, otherwise silently swallowed.
      try {
        final result = disposer();
        if (result is Future<void>) {
          result.catchError((Object e, StackTrace st) {
            _onError?.call(e, st);
          });
        }
      } on Object catch (e, st) {
        _onError?.call(e, st);
      }
      return;
    }
    _disposers.add(disposer);
  }
}
