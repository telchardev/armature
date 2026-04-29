import 'dart:async' show scheduleMicrotask;

import 'package:flutter/widgets.dart' show State, StatefulWidget, VoidCallback;

/// Defers [setState] to the next microtask and no-ops if the widget
/// has been unmounted in the meantime. Guards against build-phase and
/// post-dispose calls from reactive listeners.
mixin SafeSetStateMixin<T extends StatefulWidget> on State<T> {
  void safeSetState([VoidCallback? fn]) {
    scheduleMicrotask(() {
      if (!mounted) return;
      setState(fn ?? () {});
    });
  }
}
