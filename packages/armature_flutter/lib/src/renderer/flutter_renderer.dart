import 'package:armature/armature.dart' show AppContainer, Feature;
import 'package:flutter/widgets.dart' show Widget;

import '../contexts/container_context.dart' show ContainerContext;
import '../ports/slot_descriptor.dart' show SlotDescriptor;
import '../ports/slot_widget.dart' show SlotWidget;
import './renderer.dart' show Renderer, RenderRootResult;

/// Widget-builder for a feature-scoped render error — surfaced by
/// [SlotWidget] when a slot's build throws, falling back to the string
/// message for display. Configured via [FlutterRendererOptions].
typedef FlutterRendererErrorBuilder =
    Widget Function({
      required String featureName,
      required String errorMessage,
    });

/// Widget-builder for the "slot is loading" state (feature is
/// `.pending` or the container hasn't settled yet). Configured via
/// [FlutterRendererOptions].
typedef FlutterRendererLoaderBuilder = Widget Function();

/// Optional per-app hooks for the default [FlutterRenderer] — lets the
/// caller override how error and loader states render inside slots.
/// Supply instances of this type via
/// [ArmatureApp.renderOptions] / `bootstrap(renderOptions: ...)`.
class FlutterRendererOptions {
  /// Called whenever a slot's child `build` throws. `null` renders
  /// the default fallback (`Text("Error in \"<feature\>\" feature: ...")`).
  final FlutterRendererErrorBuilder? errorBuilder;

  /// Called whenever a slot is in the loading state (feature `.pending`,
  /// or container still `.starting`). `null` renders nothing
  /// (`SizedBox.shrink()`).
  final FlutterRendererLoaderBuilder? loaderBuilder;

  FlutterRendererOptions({this.errorBuilder, this.loaderBuilder});
}

/// Default [Renderer] implementation — wires [AppContainer] through
/// [ContainerContext] and renders each slot with [SlotWidget]. Most
/// apps never see this class directly; supply a custom [Renderer] to
/// [ArmatureApp] / `bootstrap()` only when you need to intercept the
/// widget build path (e.g. for debug instrumentation or alternative
/// shells).
class FlutterRenderer implements Renderer {
  final FlutterRendererOptions options;

  FlutterRenderer({required this.options});

  @override
  Widget? renderError({
    required String featureName,
    required String errorMessage,
  }) {
    return options.errorBuilder?.call(
      featureName: featureName,
      errorMessage: errorMessage,
    );
  }

  @override
  Widget? renderLoader() {
    return options.loaderBuilder?.call();
  }

  @override
  RenderRootResult renderRoot({required AppContainer container}) {
    return ({required Widget child}) {
      return ContainerContext(container: container, child: child);
    };
  }

  @override
  Widget renderSlot<
    TFeature extends Feature,
    TSlotInputData,
    TSlotDescriptor extends SlotDescriptor
  >({
    required AppContainer container,
    required TFeature feature,
    required TSlotDescriptor descriptor,
    required TSlotInputData data,
    Map<String, String>? debugInfo,
  }) {
    return SlotWidget(
      container: container,
      feature: feature,
      data: data,
      descriptor: descriptor,
      errorBuilder: options.errorBuilder,
      loaderBuilder: options.loaderBuilder,
      debugInfo: debugInfo,
    );
  }
}
