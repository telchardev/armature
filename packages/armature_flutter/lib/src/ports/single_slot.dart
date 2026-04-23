import 'package:armature/armature.dart'
    show
        AppContainer,
        Feature,
        FeatureHandlerContext,
        FeatureStatus,
        Port,
        PortType;
import 'package:flutter/widgets.dart' show Widget;
import 'package:meta/meta.dart' show internal;

import '../renderer/renderer_context.dart' show rendererContext;
import './slot_descriptor.dart' show SlotDescriptor;

/// Framework-internal descriptor returned by a [SingleSlot] handler —
/// carries the widget to render plus a [priority] used to pick a
/// winner when several features contribute to the same slot.
///
/// User code doesn't construct this directly; the
/// `feature.useSingleSlot(port, (data, api) => widget, priority: N)`
/// extension wraps user-returned widgets into descriptors.
@internal
class SingleSlotDescriptor extends SlotDescriptor {
  /// Selection weight — **higher wins**. Default `1`; set higher to
  /// override lower-priority contributors (e.g. a premium feature
  /// overriding a default view). On equal priority the **first
  /// registered** handler's descriptor wins (see [SingleSlot.apply]).
  final int priority;

  @internal
  SingleSlotDescriptor({
    this.priority = 1,
    required super.widget,
    super.loader,
  });
}

/// Handler registered via `feature.useSingleSlot(port, ...)`. Returns
/// the descriptor this feature wants to contribute, or `null` to
/// abstain for this particular `data` payload.
typedef SingleSlotHandler<TInputData> =
    SingleSlotDescriptor? Function(TInputData data, FeatureHandlerContext ctx);

/// Port that selects the highest-priority descriptor among active
/// contributors and renders **one** widget.
///
/// `apply` walks every registered handler in registration order,
/// skipping handlers from inactive features and handlers that return
/// `null`. Among the remaining descriptors the one with the strictly
/// greatest [SingleSlotDescriptor.priority] wins; ties are broken by
/// registration order — the **first registered** handler keeps its
/// descriptor. If no handler produces a descriptor, `apply` returns
/// `null`, which the provider materialises as an empty slot.
class SingleSlot<
  TInputData extends Object?,
  THandler extends SingleSlotHandler<TInputData>
>
    extends Port<Widget?, TInputData, THandler> {
  @internal
  SingleSlot({required super.name, super.owner})
    : super(type: PortType.singleSlot);

  @internal
  @override
  Widget? apply({
    required Widget? initialValue,
    required AppContainer container,
    required TInputData data,
  }) {
    SingleSlotDescriptor? resultDescriptor;
    Feature? resultFeature;

    for (final MapEntry(:key, :value) in handlers.entries) {
      if (container.statusOf(key) != FeatureStatus.active) continue;

      final descriptor = value(data, container.handlerContextFor(key));
      if (descriptor == null) continue;

      if (resultDescriptor != null &&
          descriptor.priority <= resultDescriptor.priority) {
        continue;
      }

      resultDescriptor = descriptor;
      resultFeature = key;
    }

    if (resultDescriptor != null && resultFeature != null) {
      Map<String, String>? debugInfo;

      assert(() {
        debugInfo = this.debugInfo;
        return true;
      }());

      return rendererContext.renderer.renderSlot(
        container: container,
        feature: resultFeature,
        descriptor: resultDescriptor,
        data: data,
        debugInfo: debugInfo,
      );
    }

    return null;
  }
}

/// Creates a [SingleSlot], optionally owned by [feature]. Call this
/// at top-level and reference the returned instance from child
/// features' `useSingleSlot(...)` handlers.
SingleSlot<TInputData, SingleSlotHandler<TInputData>> createSingleSlot<
  TInputData extends Object?
>({required String name, Feature? feature}) {
  return SingleSlot(name: name, owner: feature);
}
