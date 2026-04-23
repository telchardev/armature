import 'package:armature/armature.dart' show Feature;

import './multi_slot.dart'
    show MultiSlot, MultiSlotHandler, MultiSlotOrderDirection, createMultiSlot;
import './switch_slot_cache.dart' show memoizedSlotFactory;

typedef MultiSlotFactory<TInputData> =
    MultiSlot<TInputData, MultiSlotHandler<TInputData>> Function(String route);

/// Builds a memoized factory that creates or reuses a [MultiSlot] per
/// `route`. Slots share `feature` ownership; `name` is namespaced per
/// route (`"$name/$route"`).
MultiSlotFactory<TInputData> createMultiSwitchSlot<TInputData extends Object?>({
  required String name,
  Feature? feature,
  required MultiSlotOrderDirection orderDirection,
}) {
  return memoizedSlotFactory<
    MultiSlot<TInputData, MultiSlotHandler<TInputData>>
  >(
    name: name,
    build: (slotName) => createMultiSlot<TInputData>(
      name: slotName,
      feature: feature,
      orderDirection: orderDirection,
    ),
  );
}
