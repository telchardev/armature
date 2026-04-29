import 'dart:async';

import 'package:armature/advanced.dart' show LoggerDebugInfo;
import 'package:armature/armature.dart';
import 'package:armature/src/logger/null_logger.dart';
import 'package:test/test.dart';

class _DebugInfo implements LoggerDebugInfo {
  @override
  final Map<String, String> debugInfo;

  const _DebugInfo(this.debugInfo);
}

List<String> _capture(void Function() fn) {
  final output = <String>[];
  runZoned(
    fn,
    zoneSpecification: ZoneSpecification(
      print: (_, _, _, msg) => output.add(msg),
    ),
  );
  return output;
}

void main() {
  group('NullLogger', () {
    test('log does nothing and does not throw', () {
      const logger = NullLogger();
      final output = _capture(
        () => logger.log(level: LogLevel.error, message: 'x'),
      );
      expect(output, isEmpty);
    });
  });

  group('PrintLogger', () {
    test('prints at or above minLevel', () {
      final logger = PrintLogger(minLevel: LogLevel.info);
      final output = _capture(() {
        logger.log(level: LogLevel.debug, message: 'dbg');
        logger.log(level: LogLevel.info, message: 'info');
        logger.log(level: LogLevel.warning, message: 'warn');
        logger.log(level: LogLevel.error, message: 'err');
      });
      expect(output, hasLength(3));
      expect(output[0], contains('INFO'));
      expect(output[0], contains('info'));
      expect(output[1], contains('WARNING'));
      expect(output[2], contains('ERROR'));
    });

    test('defaults to LogLevel.debug (all levels pass)', () {
      final logger = PrintLogger();
      final output = _capture(() {
        logger.log(level: LogLevel.debug, message: 'dbg');
        logger.log(level: LogLevel.error, message: 'err');
      });
      expect(output, hasLength(2));
    });

    test('prefixes message with bracketed uppercase level name', () {
      final logger = PrintLogger();
      final output = _capture(
        () => logger.log(level: LogLevel.warning, message: 'hello'),
      );
      expect(output.single, contains('[WARNING]'));
      expect(output.single, contains('hello'));
    });

    test('includes debugInfo JSON when info is provided', () {
      final logger = PrintLogger();
      final output = _capture(
        () => logger.log(
          level: LogLevel.debug,
          message: 'msg',
          info: const _DebugInfo({'k': 'v', 'name': 'x'}),
        ),
      );
      expect(output.single, contains('msg'));
      expect(output.single, contains('"k":"v"'));
      expect(output.single, contains('"name":"x"'));
    });

    test('omits JSON when info is null', () {
      final logger = PrintLogger();
      final output = _capture(
        () => logger.log(level: LogLevel.info, message: 'plain'),
      );
      expect(output.single, contains('plain'));
      expect(output.single, isNot(contains('=>')));
    });

    test('falls back to toString() when debugInfo is not JSON-encodable', () {
      // The map ostensibly types as Map<String, String> but the value
      // is a custom non-encodable object cast in via dynamic. The
      // logger must not crash — we want the original message visible
      // plus a hint about the encoding failure.
      final notEncodable = const _DebugInfo({
        'good': 'fine',
        'bad': '<unencodable>',
      });
      final logger = PrintLogger();
      // Sanity-check: encoding the cleanup map directly succeeds —
      // we exercise the real failure path by passing a self-cycle.
      final cyclic = <String, dynamic>{};
      cyclic['self'] = cyclic;
      final cyclicInfo = _CyclicDebugInfo(cyclic);

      final output = _capture(
        () =>
            logger.log(level: LogLevel.error, message: 'msg', info: cyclicInfo),
      );
      expect(output, hasLength(1));
      expect(output.single, contains('msg'));
      expect(output.single, contains('json encoding failed'));

      // Sanity: a normal info still uses JSON encoding.
      final ok = _capture(
        () => logger.log(
          level: LogLevel.error,
          message: 'ok',
          info: notEncodable,
        ),
      );
      expect(ok.single, contains('"good":"fine"'));
    });
  });
}

class _CyclicDebugInfo implements LoggerDebugInfo {
  final Map<String, dynamic> _raw;
  const _CyclicDebugInfo(this._raw);

  // [LoggerDebugInfo.debugInfo] is typed as `Map<String, String>` —
  // we deliberately violate that contract via a dynamic-cast view to
  // exercise the encoder's failure path.
  @override
  Map<String, String> get debugInfo => _raw.cast<String, String>();
}
