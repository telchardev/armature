import 'dart:async' show unawaited;

import 'package:armature/armature.dart'
    show AnyFeature, AppContainer, ContainerOptions, Logger;
import 'package:flutter/widgets.dart' as flutter;

import './_start_failure.dart' show reportStartFailure;
import './renderer/flutter_renderer.dart'
    show FlutterRenderer, FlutterRendererOptions;
import './renderer/renderer.dart' show Renderer;
import './renderer/renderer_context.dart' show rendererContext;

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
/// over that lifecycle, e.g.:
///   * wiring the container into a widget tree whose root isn't a
///     Flutter widget you own (`runApp(MyApp(...))` style where `MyApp`
///     isn't [ArmatureApp]);
///   * driving the container from a test harness that wants to inspect
///     it before any widget is built;
///   * sharing one container across multiple top-level widgets.
///
/// `start()` is kicked off fire-and-forget; if it throws, the error is
/// routed through `containerOptions.errorHandler` (if supplied) with
/// `source: '<app-container>'`, otherwise logged via [logger]. The
/// returned [AppContainer] is usable as soon as a slot apply reaches a
/// `.working` status — earlier calls surface via the container's own
/// starting-state guards.
///
/// ```dart
/// final bootstrap = await bootstrap(features: [layoutFeature]);
/// runApp(bootstrap.render(child: const MyApp()));
/// // ... later: await bootstrap.container.dispose();
/// ```
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

  rendererContext.renderer =
      customRenderer ??
      FlutterRenderer(options: renderOptions ?? FlutterRendererOptions());
  container.onDispose(rendererContext.reset);

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

  var renderContent = rendererContext.renderer.renderRoot(container: container);

  flutter.Widget render({required flutter.Widget child}) {
    return renderContent(child: child);
  }

  return (container: container, render: render);
}
