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

/// Sort direction for [MultiSlot] contributions, keyed off
/// [MultiSlotDescriptor.order].
enum MultiSlotOrderDirection {
  /// Smaller `order` values come first — e.g. `1` renders before `2`.
  asc,

  /// Larger `order` values come first — e.g. `2` renders before `1`.
  desc,
}

/// Framework-internal descriptor returned by a [MultiSlot] handler —
/// carries the widget plus an [order] used to sort contributions.
///
/// User code doesn't construct this directly; the
/// `feature.useMultiSlot(port, (data, api) => widget, order: N)`
/// extension wraps user-returned widgets into descriptors.
@internal
class MultiSlotDescriptor extends SlotDescriptor {
  /// Sort key. Interpretation depends on [MultiSlot.orderDirection]:
  /// smaller first (`asc`) or larger first (`desc`). Entries with
  /// equal [order] keep registration order relative to each other
  /// because Dart's `List.sort` is stable.
  final int order;

  @internal
  MultiSlotDescriptor({this.order = 1, required super.widget, super.loader});
}

/// Handler registered via `feature.useMultiSlot(port, ...)`. Returns
/// the descriptor this feature wants to contribute, or `null` to
/// abstain for this particular `data` payload.
typedef MultiSlotHandler<TInputData> =
    MultiSlotDescriptor? Function(TInputData data, FeatureHandlerContext ctx);

/// Port that collects contributions from every active feature and
/// renders **all** of them as a list, sorted by
/// [MultiSlotDescriptor.order] in [orderDirection].
///
/// `apply` walks every registered handler in registration order,
/// skipping handlers from inactive features and handlers that return
/// `null`. The surviving descriptors are rendered and their widgets
/// sorted in place; the final list is returned as the slot's value
/// (appended to `initialValue`, so the caller can seed a header /
/// placeholder widget).
class MultiSlot<
  TInputData extends Object?,
  THandler extends MultiSlotHandler<TInputData>
>
    extends Port<List<Widget>, TInputData, THandler> {
  final MultiSlotOrderDirection orderDirection;

  @internal
  MultiSlot({required this.orderDirection, required super.name, super.owner})
    : super(type: PortType.multiSlot);

  @internal
  @override
  List<Widget> apply({
    required List<Widget> initialValue,
    required AppContainer container,
    required TInputData data,
  }) {
    // Accumulate as `(order, widget)` records, sort in place, then
    // append to a single growable List. Avoids the previous tuple
    // list + spread+map literal, which allocated two lists per apply.
    final entries = <({int order, Widget widget})>[];

    for (final MapEntry(:key, :value) in handlers.entries) {
      if (container.statusOf(key) != FeatureStatus.active) continue;

      final descriptor = value(data, container.handlerContextFor(key));
      if (descriptor == null) continue;

      Map<String, String>? debugInfo;

      assert(() {
        debugInfo = this.debugInfo;
        return true;
      }());

      final widget = rendererContext.renderer.renderSlot(
        container: container,
        feature: key,
        descriptor: descriptor,
        data: data,
        debugInfo: debugInfo,
      );

      entries.add((order: descriptor.order, widget: widget));
    }

    if (entries.length > 1) {
      entries.sort(
        (a, b) => orderDirection == MultiSlotOrderDirection.asc
            ? a.order - b.order
            : b.order - a.order,
      );
    }

    final result = List<Widget>.of(initialValue, growable: true);
    for (final e in entries) {
      result.add(e.widget);
    }
    return result;
  }
}

/// Creates a [MultiSlot], optionally owned by [feature]. Call this at
/// top-level and reference the returned instance from child features'
/// `useMultiSlot(...)` handlers.
MultiSlot<TInputData, MultiSlotHandler<TInputData>>
createMultiSlot<TInputData extends Object?>({
  required String name,
  Feature? feature,
  required MultiSlotOrderDirection orderDirection,
}) {
  return MultiSlot(orderDirection: orderDirection, name: name, owner: feature);
}
