import 'dart:async' show FutureOr, runZoned;

import 'package:meta/meta.dart' show internal;

/// Zone key used to mark that we're currently executing a
/// user-supplied lifecycle callback (activation `setup` or `onStart`).
///
/// Framework code consults `Zone.current[userCallbackZoneKey]` to reject
/// operations that would self-deadlock when invoked from inside such
/// a callback — notably `AppContainer.stop()` awaiting the same
/// `start()` future whose user callback called it.
@internal
const Symbol userCallbackZoneKey = #appKitInsideUserCallback;

/// Runs [body] inside a zone that marks it as user callback code. Use
/// to wrap every invocation of a user-supplied lifecycle callback so
/// the in-call detection works transitively through async gaps.
///
/// Accepts `FutureOr` so sync and async callbacks both work without
/// boilerplate at the call site.
///
/// **Caveat — late-fired callbacks inherit the zone.** Dart zones
/// capture any asynchronous primitive scheduled inside them: a
/// `Timer`, `Stream.listen`, or `scheduleMicrotask` registered from
/// [body] will fire with `userCallbackZoneKey` still set, even after
/// [runAsUserCallback] has returned. In practice this can produce a
/// false positive — e.g. a `Timer` registered inside `onStart` that
/// later calls `container.stop()` will be rejected as "called
/// from a user callback" even though the original `start()` future
/// has long since settled. The detection is aimed at **synchronous**
/// self-recursion; treat it as a best-effort guard for detached
/// callbacks.
@internal
Future<void> runAsUserCallback(FutureOr<void> Function() body) {
  return runZoned(() async {
    final result = body();
    if (result is Future) await result;
  }, zoneValues: {userCallbackZoneKey: true});
}
