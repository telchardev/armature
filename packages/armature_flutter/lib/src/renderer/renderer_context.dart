import 'package:flutter/widgets.dart' show FlutterError;
import 'package:meta/meta.dart' show internal;

import './renderer.dart' show Renderer;

/// Process-wide holder for the active [Renderer].
///
/// **Multi-container caveat:** This is a global singleton. Running two
/// [AppContainer] instances side-by-side with different renderers is
/// unsupported — whichever one bootstraps last wins, and slot widgets
/// rendered via the earlier container will route through the new
/// renderer. Manage container lifetimes strictly sequentially: dispose
/// the old container (which calls [reset] via `onDispose`) before
/// bootstrapping a new one.
class _RendererContext {
  Renderer? _renderer;

  Renderer get renderer {
    final r = _renderer;
    if (r == null) {
      throw FlutterError(
        'Renderer not initialized. Call bootstrap() before rendering.',
      );
    }
    return r;
  }

  set renderer(Renderer renderer) {
    _renderer = renderer;
  }

  /// Drops the cached renderer. Invoked automatically by
  /// [AppContainer.onDispose] in `bootstrap()` and `ArmatureApp`; tests may
  /// also call it directly in `tearDown`.
  @internal
  void reset() {
    _renderer = null;
  }
}

final rendererContext = _RendererContext();
