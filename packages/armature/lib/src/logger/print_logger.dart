import 'dart:convert';

import './logger.dart' show Logger, LogLevel, LoggerDebugInfo;

/// [Logger] that routes messages to `print` (the Dart / Flutter
/// console). Suitable for local development; consider a structured
/// logger (or your observability stack's adapter) for production.
///
/// Each line is prefixed with the level (e.g. `[DEBUG]`). When
/// [LoggerDebugInfo] is supplied its map is appended as JSON after a
/// `=>` separator so grepping on a key/value pair stays easy.
class PrintLogger implements Logger {
  static const _jsonEncoder = JsonEncoder();

  /// Lowest [LogLevel] that will actually be printed; messages strictly
  /// below this severity are dropped.
  final LogLevel minLevel;

  /// Creates a logger that only prints entries at or above [minLevel]
  /// (default: [LogLevel.debug] — everything through).
  const PrintLogger({this.minLevel = LogLevel.debug});

  @override
  void log({
    required LogLevel level,
    required String message,
    LoggerDebugInfo? info,
  }) {
    if (level.index < minLevel.index) {
      return;
    }

    final prefix = '[${level.name.toUpperCase()}]';
    if (info != null) {
      print('$prefix $message => ${_jsonEncoder.convert(info.debugInfo)}');
    } else {
      print('$prefix $message');
    }
  }
}
