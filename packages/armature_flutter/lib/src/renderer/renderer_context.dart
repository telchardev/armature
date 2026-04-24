import 'package:armature/armature.dart' show AppContainer;
import 'package:flutter/widgets.dart' show FlutterError;
import 'package:meta/meta.dart' show internal;

import './renderer.dart' show Renderer;

/// Per-[AppContainer] renderer binding.
///
/// Uses an [Expando] to attach the active renderer to a specific
/// [AppContainer] instance without the core `armature` package needing
/// any knowledge of Flutter or rendering. When the container is
/// garbage-collected the Expando entry clears automatically — no
/// disposer needed.
///
/// Two concurrent [AppContainer] instances hold independent renderers
/// — disposing one does not touch the other's binding.
final Expando<Renderer> _rendererForContainer = Expando<Renderer>(
  'armature_flutter.renderer',
);

/// Typed accessor for the per-container renderer.
extension ContainerRenderer on AppContainer {
  /// Returns the [Renderer] bound to this container. Throws when the
  /// container was never bootstrapped by [ArmatureApp] or `bootstrap()`.
  Renderer get renderer {
    final r = _rendererForContainer[this];
    if (r == null) {
      throw FlutterError(
        'Renderer not initialized for this AppContainer. '
        'Did you bootstrap via ArmatureApp or bootstrap()?',
      );
    }
    return r;
  }

  /// Binds [renderer] to this container. Idempotent — the last setter
  /// wins, so re-calling with a different renderer hot-swaps the
  /// binding (but this is an unusual pattern; typically called once
  /// from `ArmatureApp.initState` or `bootstrap()`).
  void setRenderer(Renderer renderer) {
    _rendererForContainer[this] = renderer;
  }

  /// Framework-internal probe: returns the bound [Renderer] or `null`
  /// when nothing is bound. Used by `pumpFeature` in tests to install
  /// a default renderer only when the caller hasn't provided one.
  @internal
  Renderer? get maybeRenderer => _rendererForContainer[this];
}
