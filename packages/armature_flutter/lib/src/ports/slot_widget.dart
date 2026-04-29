import 'package:armature/armature.dart'
    show AppContainer, Feature, FeatureStatus, RenderError;
import 'package:flutter/foundation.dart'
    show DiagnosticPropertiesBuilder, StringProperty;
import 'package:flutter/widgets.dart'
    show Widget, StatefulWidget, BuildContext, SizedBox, Text, State;

import '../contexts/feature_context.dart' show FeatureContext;
import '../stores/safe_set_state_mixin.dart' show SafeSetStateMixin;
import './slot_descriptor.dart' show SlotDescriptor;

/// Builder that returns the loader widget shown while the hosting
/// feature is `.pending`. `null` falls through to the descriptor's own
/// loader (when provided) or an empty space.
typedef SlotWidgetLoaderBuilder = Widget? Function();

/// Builder that returns the widget shown when the slot's child build
/// throws. `null` falls through to the framework's plain-text fallback
/// (`Text("Error in \"<feature\>\" feature: ...")`).
typedef SlotWidgetErrorBuilder =
    Widget? Function({
      required String errorMessage,
      required String featureName,
    });

/// Mount point for one of the slot-family ports — wraps the descriptor
/// widget in a [FeatureContext] scope, surfaces the loader widget
/// while the owning feature is `.pending`, and catches child build
/// throws into a [RenderError] reported through the container's
/// `errorHandler`.
///
/// Application code rarely constructs [SlotWidget] directly; it's
/// produced by [FlutterRenderer.renderSlot] for every slot port. Only
/// custom [Renderer] implementations need to build it manually.
class SlotWidget<TInputData, TSlotDescriptor extends SlotDescriptor>
    extends StatefulWidget {
  final AppContainer container;

  final TInputData data;

  final Map<String, String>? debugInfo;

  final TSlotDescriptor descriptor;

  final SlotWidgetErrorBuilder? errorBuilder;

  final Feature feature;

  final SlotWidgetLoaderBuilder? loaderBuilder;

  const SlotWidget({
    super.key,
    required this.container,
    required this.feature,
    required this.data,
    required this.descriptor,
    required this.errorBuilder,
    required this.loaderBuilder,
    this.debugInfo,
  });

  @override
  State<SlotWidget<TInputData, TSlotDescriptor>> createState() =>
      _SlotWidgetState<TInputData, TSlotDescriptor>();

  @override
  void debugFillProperties(DiagnosticPropertiesBuilder properties) {
    super.debugFillProperties(properties);
    if (debugInfo case final info?) {
      for (final MapEntry(:key, :value) in info.entries) {
        properties.add(StringProperty(key, value));
      }
    }
  }
}

class _SlotWidgetState<TInputData, TSlotDescriptor extends SlotDescriptor>
    extends State<SlotWidget<TInputData, TSlotDescriptor>>
    with SafeSetStateMixin {
  late final void Function() _disposer;

  @override
  void initState() {
    super.initState();
    _disposer = widget.container.onFeatureStatusChanged(
      feature: widget.feature,
      callback: safeSetState,
    );
  }

  Widget _renderError(Object error, StackTrace stackTrace) {
    final featureName = widget.feature.name;

    // Wrap as RenderError so errorHandler can distinguish render
    // failures from handler / listener ones.
    widget.container.reportError(
      feature: widget.feature,
      error: RenderError.wrap(featureName, error, stackTrace: stackTrace),
    );

    return widget.errorBuilder?.call(
          errorMessage: error.toString(),
          featureName: featureName,
        ) ??
        Text("Error in \"$featureName\" feature: $error");
  }

  Widget? _renderLoader() {
    return widget.descriptor.loader?.call() ?? widget.loaderBuilder?.call();
  }

  @override
  void dispose() {
    _disposer();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    try {
      if (widget.container.statusOf(widget.feature) == FeatureStatus.pending) {
        return FeatureContext(
          feature: widget.feature,
          child: _renderLoader() ?? const SizedBox.shrink(),
        );
      }

      return FeatureContext(
        feature: widget.feature,
        child: widget.descriptor.widget,
      );
    } on Object catch (error, stackTrace) {
      return _renderError(error, stackTrace);
    }
  }
}
