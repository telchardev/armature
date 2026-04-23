import 'dart:convert' show JsonEncoder;

import 'package:meta/meta.dart' show internal;

const _jsonEncoder = JsonEncoder.withIndent('  ');

/// Formats a store / record / object for display in the debug
/// state inspector. Tries, in order:
/// 1. `toJson()` → pretty-JSON string.
/// 2. `toString()` — if non-default (not `Instance of …`), pretty-
///    indent nested records / lists via [_prettyRecord].
/// 3. Falls back to the runtime type name.
///
/// Framework-internal: consumed by the overlay's state tab only.
@internal
String formatState(dynamic state) {
  if (state == null) return 'null';

  // 1. Try toJson(). The explicit `as dynamic` keeps `avoid_dynamic_calls`
  // honest — the call is deliberately best-effort on an opaque object.
  try {
    final json = (state as dynamic).toJson();
    return _jsonEncoder.convert(json);
  } on Object {
    // no toJson — continue
  }

  // 2. toString() with pretty-printing for records
  try {
    final str = state.toString();
    if (!str.startsWith('Instance of')) return _prettyRecord(str);
  } on Object {
    // continue
  }

  // 3. Fallback
  return '${state.runtimeType}';
}

/// Indents nested `(...)` and `[...]` in record/list toString output.
///
/// Recognises quoted substrings (`'…'` and `"…"` with `\`-escapes) so
/// brackets / commas inside a string literal don't trigger indentation
/// or newlines. That keeps record fields like `(msg: 'hi, there')` on
/// a single line, matching their Dart source.
String _prettyRecord(String input) {
  final buf = StringBuffer();
  var indent = 0;
  var i = 0;
  // 0 = not in string, 39 = inside '…', 34 = inside "…"
  var quote = 0;

  void newLine() {
    buf.writeln();
    buf.write('  ' * indent);
  }

  while (i < input.length) {
    final c = input.codeUnitAt(i);

    if (quote != 0) {
      buf.writeCharCode(c);
      if (c == 0x5C /* \ */ && i + 1 < input.length) {
        // Preserve the escaped char as-is.
        buf.writeCharCode(input.codeUnitAt(i + 1));
        i += 2;
        continue;
      }
      if (c == quote) quote = 0;
      i++;
      continue;
    }

    if (c == 0x27 /* ' */ || c == 0x22 /* " */ ) {
      quote = c;
      buf.writeCharCode(c);
      i++;
    } else if (c == 0x28 /* ( */ || c == 0x5B /* [ */ ) {
      buf.writeCharCode(c);
      indent++;
      newLine();
      i++;
    } else if (c == 0x29 /* ) */ || c == 0x5D /* ] */ ) {
      indent--;
      newLine();
      buf.writeCharCode(c);
      i++;
    } else if (c == 0x2C /* , */ ) {
      buf.write(',');
      if (i + 1 < input.length &&
          input.codeUnitAt(i + 1) == 0x20 /* space */ ) {
        i++;
      }
      newLine();
      i++;
    } else {
      buf.writeCharCode(c);
      i++;
    }
  }

  return buf.toString();
}
