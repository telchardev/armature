import 'dart:async' show unawaited;

import 'package:armature/armature.dart'
    show AnyFeature, AppContainer, ContainerOptions, Logger;
import 'package:flutter/widgets.dart' as flutter;

import './_start_failure.dart' show reportStartFailure;
import './renderer/flutter_renderer.dart'
    show FlutterRenderer, FlutterRendererOptions;
import './renderer/renderer.dart' show Renderer;
import './renderer/renderer_context.dart' show ContainerRenderer;

/// Widget-tree wrapper installed by [bootstrap] — runs the returned
/// `render` with any child to mount the armature provider stack above it.
typedef Render = flutter.Widget Function({required flutter.Widget child});

/// Result of [bootstrap]: the live [AppContainer] and a [Render] that
/// produces the provider-wrapped widget tree for the caller to hand to
/// `runApp` (or further wrap).
typedef BootstrapResult = ({AppContainer container, Render render});

/// Manually bootstraps an [AppContainer] and its renderer, returning
/// both the container handle and a [Render] that wraps a child widget
/// with the provider stack.
///
/// **Prefer [ArmatureApp]** for typical apps — it manages the container's
/// full widget-mounted lifecycle (create on `initState`, dispose on
/// `dispose`). Reach for [bootstrap] only when you need manual control
/// over that lifecycle.
///
/// The renderer is stored on the container itself — no global singleton
/// — so multiple bootstraps with different renderers coexist cleanly.
Future<BootstrapResult> bootstrap({
  required List<AnyFeature> features,
  Renderer? customRenderer,
  ContainerOptions? containerOptions,
  FlutterRendererOptions? renderOptions,
  Logger? logger,
}) async {
  final container = AppContainer(
    features: features,
    options: containerOptions,
    logger: logger,
  );

  container.setRenderer(
    customRenderer ??
        FlutterRenderer(options: renderOptions ?? FlutterRendererOptions()),
  );

  unawaited(
    container.start().catchError(
      (Object error, StackTrace stackTrace) => reportStartFailure(
        error,
        stackTrace,
        logger: logger,
        options: containerOptions,
      ),
    ),
  );

  var renderContent = container.renderer.renderRoot(container: container);

  flutter.Widget render({required flutter.Widget child}) {
    return renderContent(child: child);
  }

  return (container: container, render: render);
}
