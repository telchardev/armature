import 'package:meta/meta.dart' show internal;

import './logger.dart' show Logger, LogLevel, LoggerDebugInfo;

/// No-op [Logger] used by `AppContainer` when the caller doesn't
/// supply one. Every [log] call is silently discarded, avoiding
/// conditional null-checks on every framework diagnostic.
///
/// Framework-internal — not exported from the public barrel. Consumers
/// that want to disable logging simply omit the `logger:` parameter.
@internal
class NullLogger implements Logger {
  const NullLogger();

  @override
  void log({
    required LogLevel level,
    required String message,
    LoggerDebugInfo? info,
  }) {}
}
