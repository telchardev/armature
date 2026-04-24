import 'package:armature/armature.dart' show Feature;

import './keyed_slot_cache.dart' show memoizedKeyedSlot;
import './multi_slot.dart'
    show MultiSlot, MultiSlotHandler, MultiSlotOrderDirection, createMultiSlot;

/// A family of [MultiSlot]s indexed by a string key.
///
/// Call the returned function with a key to obtain (or create) the
/// slot bound to that key. Slots are memoized per key — the same key
/// always yields the same [MultiSlot] instance within a single
/// `createKeyedMultiSlot` factory.
typedef KeyedMultiSlot<TInputData> =
    MultiSlot<TInputData, MultiSlotHandler<TInputData>> Function(String key);

/// Builds a memoized factory that creates or reuses a [MultiSlot] per
/// string key. Slots share `feature` ownership; `name` is namespaced
/// per key (`"$name/$key"`).
///
/// [orderDirection] defaults to [MultiSlotOrderDirection.asc].
KeyedMultiSlot<TInputData> createKeyedMultiSlot<TInputData extends Object?>({
  required String name,
  Feature? feature,
  MultiSlotOrderDirection orderDirection = MultiSlotOrderDirection.asc,
}) {
  return memoizedKeyedSlot<MultiSlot<TInputData, MultiSlotHandler<TInputData>>>(
    name: name,
    build: (slotName) => createMultiSlot<TInputData>(
      name: slotName,
      feature: feature,
      orderDirection: orderDirection,
    ),
  );
}
