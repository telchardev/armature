import 'dart:async';
import 'dart:collection';

/// Caps the number of concurrent in-flight invocations of [run].
///
/// Package-private (not re-exported from `armature_graph.dart`): the
/// graph exposes its concurrency cap through the `activationConcurrency`
/// parameter on [Graph], not via a direct Semaphore reference.
///
/// When [_max] tasks are running, new callers wait (approximately FIFO)
/// until a running task finishes. A waiter re-checks the gate after
/// waking because another caller may have taken the freed slot in
/// between.
///
/// [drain] wakes every waiter and sets a shutdown flag, letting them pass
/// the gate without a real slot — their `fn` is expected to observe the
/// shutdown signal (e.g. graph status) and bail out quickly.
///
/// **Re-entrancy is unsupported.** Calling [run] recursively from
/// inside an `fn` already holding a slot on the *same* Semaphore
/// deadlocks once the cap fills: the inner call parks on a waiter,
/// the outer call cannot finish (waiting on the inner), and the
/// holder never releases. Do not nest `run()` on a single instance.
class Semaphore {
  /// Creates a Semaphore that admits up to [_max] concurrent
  /// invocations of [run]. Throws [ArgumentError] if `max <= 0`.
  Semaphore(this._max) {
    if (_max <= 0) {
      throw ArgumentError.value(_max, 'max', 'must be > 0');
    }
  }

  final int _max;
  int _inFlight = 0;
  bool _draining = false;
  final Queue<Completer<void>> _waiters = Queue();

  /// Runs [fn] under the concurrency cap.
  ///
  /// If fewer than [_max] invocations are in flight, [fn] starts
  /// immediately; otherwise the caller parks on a FIFO waiter queue
  /// and wakes when a running invocation releases its slot (or when
  /// [drain] is called — see class docs). The returned future
  /// completes with `fn`'s result; exceptions thrown by `fn` propagate
  /// through after releasing the slot.
  Future<T> run<T>(Future<T> Function() fn) async {
    while (_inFlight >= _max && !_draining) {
      final waiter = Completer<void>();
      _waiters.add(waiter);
      await waiter.future;
    }
    _inFlight++;
    try {
      return await fn();
    } finally {
      _inFlight--;
      if (!_draining && _waiters.isNotEmpty) {
        _waiters.removeFirst().complete();
      }
    }
  }

  /// Releases every queued waiter. Used by [Graph.shutdown] so pending
  /// activation work doesn't hang forever; waiters wake, observe the
  /// shutdown signal, and return.
  ///
  /// After [drain], the Semaphore no longer enforces a cap — subsequent
  /// [run] calls bypass the gate unconditionally. The Semaphore is not
  /// reusable; create a new instance if you need renewed limiting.
  void drain() {
    _draining = true;
    while (_waiters.isNotEmpty) {
      _waiters.removeFirst().complete();
    }
  }
}
