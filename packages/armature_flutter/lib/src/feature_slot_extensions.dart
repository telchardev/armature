import 'package:armature/armature.dart'
    show Feature, FeatureHandlerContext, FeatureScopeApi;
import 'package:flutter/widgets.dart' show Widget;

import './ports/multi_slot.dart'
    show MultiSlot, MultiSlotDescriptor, MultiSlotHandler;
import './ports/single_slot.dart'
    show SingleSlot, SingleSlotDescriptor, SingleSlotHandler;
import './ports/slot_descriptor.dart' show SlotLoaderBuilder;

/// User-facing extensions for registering slot handlers from a
/// [Feature]. Handlers return a plain `Widget?` — the extension wraps
/// the widget into the framework-internal descriptor under the hood,
/// so user code never types [SingleSlotDescriptor] /
/// [MultiSlotDescriptor] explicitly.
///
/// Registration records the `(port, handler)` pairing into the
/// feature's config. The actual installation into a container's port
/// handler map happens during that container's `start()` —
/// `FeatureOrchestrator` iterates each feature's `portBindings` and
/// calls `container.addPortHandler(...)`.
extension FeatureSlotExtensions<TStores> on Feature<TStores, dynamic, dynamic> {
  /// Registers [handler] against a parent's [SingleSlot].
  ///
  /// [handler] receives the slot's `data` payload and a typed
  /// [FeatureScopeApi] scoped to this feature (`api.own` for own
  /// stores, `api.of(parent)` for parent exports). Return `null` to
  /// abstain for that particular `data` payload; return a [Widget]
  /// to contribute it — the widget wins the slot if its [priority] is
  /// the highest among active contributors (ties go to the
  /// first-registered handler).
  ///
  /// [loader] overrides the renderer's default loader while this
  /// feature is `.pending` during a rebuild that would have selected
  /// this handler.
  void useSingleSlot<TInputData>(
    SingleSlot<TInputData, SingleSlotHandler<TInputData>> slot,
    Widget? Function(TInputData data, FeatureScopeApi<TStores> api) handler, {
    int priority = 1,
    SlotLoaderBuilder? loader,
  }) {
    SingleSlotDescriptor? wrappedHandler(
      TInputData data,
      FeatureHandlerContext ctx,
    ) {
      final widget = handler(data, ctx as FeatureScopeApi<TStores>);
      if (widget == null) return null;
      return SingleSlotDescriptor(
        widget: widget,
        priority: priority,
        loader: loader,
      );
    }

    recordPortBinding(slot, wrappedHandler);
  }

  /// Registers [handler] against a parent's [MultiSlot].
  ///
  /// [handler] receives the slot's `data` payload and a typed
  /// [FeatureScopeApi] scoped to this feature. Return `null` to skip
  /// rendering for that `data`; return a [Widget] to contribute it —
  /// all active contributions are included in the slot's output,
  /// sorted by [order] according to the slot's
  /// [MultiSlot.orderDirection] (ascending or descending). Ties keep
  /// registration order because Dart's `List.sort` is stable.
  ///
  /// [loader] overrides the renderer's default loader while this
  /// feature is `.pending`.
  void useMultiSlot<TInputData>(
    MultiSlot<TInputData, MultiSlotHandler<TInputData>> slot,
    Widget? Function(TInputData data, FeatureScopeApi<TStores> api) handler, {
    int order = 1,
    SlotLoaderBuilder? loader,
  }) {
    MultiSlotDescriptor? wrappedHandler(
      TInputData data,
      FeatureHandlerContext ctx,
    ) {
      final widget = handler(data, ctx as FeatureScopeApi<TStores>);
      if (widget == null) return null;
      return MultiSlotDescriptor(widget: widget, order: order, loader: loader);
    }

    recordPortBinding(slot, wrappedHandler);
  }
}
