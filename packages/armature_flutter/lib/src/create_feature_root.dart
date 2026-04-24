import 'package:armature/armature.dart' as armature;
import 'package:flutter/widgets.dart'
    show Widget, StatelessWidget, BuildContext;
import 'package:meta/meta.dart' show internal;

import './contexts/container_context.dart' show ContainerContext;
import './ports/slot_descriptor.dart' show SlotDescriptor, SlotLoaderBuilder;
import './renderer/renderer_context.dart' show ContainerRenderer;

/// Widget that mounts [feature] as a top-level root inside the
/// container: looks up the live [AppContainer] via [ContainerContext]
/// and hands it (plus the widget + optional loader + `data`) to the
/// active renderer.
///
/// Most apps don't instantiate this directly — [createFeatureRoot]
/// returns a typed builder that does.
class FeatureRoot<TInputData extends Object?> extends StatelessWidget {
  final TInputData data;

  /// Widget to render once [feature] is active.
  final Widget widget;

  /// Optional loader shown while [feature] is still `.pending`.
  final SlotLoaderBuilder? loader;

  final armature.Feature feature;

  const FeatureRoot({
    super.key,
    required this.feature,
    required this.data,
    required this.widget,
    this.loader,
  });

  Map<String, String> get _debugInfo {
    return {"type": "feature_root", "owner": feature.name};
  }

  /// Internal: projects the root's widget + loader onto a
  /// [SlotDescriptor] for the renderer's typed slot pipeline.
  @internal
  SlotDescriptor get descriptor =>
      SlotDescriptor(widget: widget, loader: loader);

  @override
  Widget build(BuildContext context) {
    var container = ContainerContext.of(context).container;

    Map<String, String>? debugInfo;

    assert(() {
      debugInfo = _debugInfo;
      return true;
    }());

    return container.renderer.renderSlot(
      container: container,
      feature: feature,
      descriptor: descriptor,
      data: data,
      debugInfo: debugInfo,
    );
  }
}

/// Typed builder returned by [createFeatureRoot] — call it with the
/// per-render `data` payload to produce the [FeatureRoot] widget.
typedef FeatureRootBuilder<TInputData> =
    Widget Function({required TInputData data});

/// Binds [feature] and its root [widget] (plus optional [loader]) into
/// a reusable [FeatureRootBuilder].
FeatureRootBuilder<TInputData> createFeatureRoot<TInputData extends Object?>({
  required armature.Feature feature,
  required Widget widget,
  SlotLoaderBuilder? loader,
}) {
  return ({required TInputData data}) {
    return FeatureRoot(
      feature: feature,
      data: data,
      widget: widget,
      loader: loader,
    );
  };
}
