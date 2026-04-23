/// Provides structured debug metadata for logging.
///
/// Implementors expose a map of key-value pairs via [debugInfo] that
/// loggers can serialise alongside the primary message (e.g. feature
/// name + port name + event kind). Keep values small and serialisable
/// — [Logger] implementations may render them as JSON, so complex
/// objects are formatted via their `toString()`.
abstract class LoggerDebugInfo {
  /// Key-value pairs describing this object for debug output.
  Map<String, String> get debugInfo;
}

/// Severity levels for log messages, ordered from least to most severe.
/// Loggers compare by [LogLevel.index] to implement minimum-level
/// filtering.
enum LogLevel { debug, info, warning, error }

/// Interface for logging framework events.
///
/// Framework-internal diagnostics only — never the channel through
/// which user-actionable errors surface (those go through
/// `ContainerOptions.errorHandler` as typed `ArmatureError`s). Swap the
/// default via `ArmatureApp(logger: ...)` to integrate with your app's
/// logging infrastructure.
abstract class Logger {
  /// Emits a log message.
  ///
  /// * [level] — severity; loggers gate output on this value
  ///   (typically by comparing against a configured `minLevel`).
  /// * [message] — the primary human-readable line.
  /// * [info] — optional structured key/value metadata; when present
  ///   the logger renders it after [message] (implementation-defined
  ///   format — [PrintLogger] uses JSON).
  void log({
    required LogLevel level,
    required String message,
    LoggerDebugInfo? info,
  });
}
