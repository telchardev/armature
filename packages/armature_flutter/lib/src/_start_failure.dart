import 'package:armature/armature.dart'
    show ArmatureError, ContainerError, ContainerOptions, LogLevel, Logger;
import 'package:meta/meta.dart' show internal;

/// Attribution label for throws that escape [AppContainer.start] when
/// called from [bootstrap] / `ArmatureApp` — the error isn't attributable
/// to a single feature, so this synthetic `source` stands in.
const _appContainerSource = '<app-container>';

/// Shared routing for a throw escaping [AppContainer.start] in the
/// fire-and-forget path used by `bootstrap()` and `ArmatureApp`.
///
/// If [options] provides an `errorHandler`, the failure is wrapped into
/// an [ArmatureError] (pass-through if already one, or [ContainerError]
/// otherwise — preserving [stackTrace]) and reported with
/// `source: '<app-container>'`. Otherwise falls back to [logger] at
/// `LogLevel.error`.
@internal
void reportStartFailure(
  Object error,
  StackTrace stackTrace, {
  Logger? logger,
  ContainerOptions? options,
}) {
  final handler = options?.errorHandler;
  if (handler != null) {
    handler(
      source: _appContainerSource,
      error: error is ArmatureError
          ? error
          : ContainerError(error.toString(), stackTrace: stackTrace),
      meta: const {},
    );
  } else {
    logger?.log(
      level: LogLevel.error,
      message: 'AppContainer.start() failed: $error\n$stackTrace',
    );
  }
}
