import 'dart:async';

import 'package:armature/armature.dart'
    show AnyFeature, AppContainer, ContainerOptions, Logger;
import 'package:flutter/widgets.dart';

import './_start_failure.dart' show reportStartFailure;
import './renderer/flutter_renderer.dart'
    show FlutterRenderer, FlutterRendererOptions;
import './renderer/renderer.dart' show Renderer;
import './renderer/renderer_context.dart' show ContainerRenderer;

/// Top-level widget that bootstraps the armature container and provides
/// it to the widget tree.
///
/// Replaces the manual `bootstrap()` + `runApp()` pattern:
///
/// ```dart
/// runApp(ArmatureApp(
///   features: [layoutFeature, authFeature, ...],
///   child: layoutRoot(data: null),
/// ));
/// ```
///
/// The renderer is installed on the specific container this widget
/// owns — so two `ArmatureApp`s living sibling-by-sibling (or mounting
/// / unmounting in rapid succession) each carry their own renderer and
/// feature runtime state without stomping on each other.
class ArmatureApp extends StatefulWidget {
  final Widget child;
  final ContainerOptions? containerOptions;
  final Renderer? customRenderer;
  final List<AnyFeature> features;
  final Logger? logger;
  final FlutterRendererOptions? renderOptions;

  const ArmatureApp({
    super.key,
    required this.features,
    required this.child,
    this.containerOptions,
    this.customRenderer,
    this.renderOptions,
    this.logger,
  });

  @override
  State<ArmatureApp> createState() => _ArmatureAppState();
}

class _ArmatureAppState extends State<ArmatureApp> {
  late final AppContainer _container;

  @override
  void initState() {
    super.initState();

    _container = AppContainer(
      features: widget.features,
      options: widget.containerOptions,
      logger: widget.logger,
    );
    _container.setRenderer(
      widget.customRenderer ??
          FlutterRenderer(
            options: widget.renderOptions ?? FlutterRendererOptions(),
          ),
    );

    unawaited(
      _container.start().catchError(
        (Object error, StackTrace stackTrace) => reportStartFailure(
          error,
          stackTrace,
          logger: widget.logger,
          options: widget.containerOptions,
        ),
      ),
    );
  }

  @override
  void dispose() {
    // AppContainer.dispose() is async (cleanup bags may have async
    // disposers). Flutter's State.dispose() is sync, so we fire-and-
    // forget — teardown completes after the widget tree is gone. The
    // container carries its own renderer + feature runtime state, so
    // late teardown side effects can't corrupt any concurrent
    // ArmatureApp.
    unawaited(_container.dispose());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final renderRoot = _container.renderer.renderRoot(container: _container);
    return renderRoot(child: widget.child);
  }
}
