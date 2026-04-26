import 'package:armature/armature.dart'
    show AppContainer, ContainerStatus, Feature, FeatureStatus;
import 'package:flutter/widgets.dart' show Widget;

import '../ports/slot_descriptor.dart' show SlotDescriptor;

/// Builder returned by [Renderer.renderRoot] — wraps an arbitrary child
/// widget with the renderer's provider stack (at minimum a
/// [ContainerContext]).
typedef RenderRootResult = Widget Function({required Widget child});

/// Pluggable widget-factory consumed by `bootstrap()` / `ArmatureApp`.
///
/// The default implementation is [FlutterRenderer]. Supply a custom one
/// only when you need to intercept the widget build path — e.g. debug
/// instrumentation that decorates every slot, or a test harness that
/// captures the widget tree without mounting it.
abstract class Renderer {
  /// Widget rendered by a slot when its child build throws. `null`
  /// means "use the built-in textual fallback" (suitable for debug
  /// builds; production apps should return a branded error widget).
  Widget? renderError({
    required String featureName,
    required String errorMessage,
  });

  /// Widget rendered while a slot is in the loading state (owning
  /// feature [FeatureStatus.pending], or container still
  /// [ContainerStatus.starting]). `null` means "render nothing / empty
  /// space".
  Widget? renderLoader();

  /// Builds the root provider stack that should wrap every feature
  /// root. Called once when the container comes up; the returned
  /// callable is invoked with the user's child to produce the final
  /// widget tree.
  RenderRootResult renderRoot({required AppContainer container});

  /// Builds a single feature-root widget. Invoked by [FeatureRoot] —
  /// user code rarely calls this directly. The returned widget hosts
  /// the slot's handler rendering and its own per-feature lifecycle.
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
  });
}
