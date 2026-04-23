import 'dart:async' show scheduleMicrotask;

import 'package:flutter/widgets.dart' show State, StatefulWidget, VoidCallback;

/// Defers [setState] to the next microtask and no-ops if the state has
/// been unmounted in the meantime.
///
/// Graph cascades and port reactions settle on the microtask queue; calling
/// `setState` synchronously from inside a listener can run during a build
/// phase or against a disposed state. This mixin guards both.
///
/// Used by the built-in port providers and [StateObserver]; custom
/// widgets that subscribe to [AppContainer.onFeatureStatusChanged] /
/// [AppContainer.onPortChanged] or drive their own [Reaction] benefit
/// from the same guard.
mixin SafeSetStateMixin<T extends StatefulWidget> on State<T> {
  void safeSetState([VoidCallback? fn]) {
    scheduleMicrotask(() {
      if (!mounted) return;
      setState(fn ?? () {});
    });
  }
}
