import 'package:armature/armature.dart' show Feature;

import './keyed_slot_cache.dart' show memoizedKeyedSlot;
import './single_slot.dart'
    show SingleSlot, SingleSlotHandler, createSingleSlot;

/// A family of [SingleSlot]s indexed by a string key.
///
/// Call the returned function with a key to obtain (or create) the
/// slot bound to that key. Slots are memoized per key — the same key
/// always yields the same [SingleSlot] instance within a single
/// `createKeyedSingleSlot` factory.
typedef KeyedSingleSlot<TInputData> =
    SingleSlot<TInputData, SingleSlotHandler<TInputData>> Function(String key);

/// Builds a memoized factory that creates or reuses a [SingleSlot] per
/// string key. Slots share `feature` ownership; `name` is namespaced per
/// key (`"$name/$key"`).
KeyedSingleSlot<TInputData> createKeyedSingleSlot<TInputData extends Object?>({
  required String name,
  Feature? feature,
}) {
  return memoizedKeyedSlot<
    SingleSlot<TInputData, SingleSlotHandler<TInputData>>
  >(
    name: name,
    build: (slotName) =>
        createSingleSlot<TInputData>(name: slotName, feature: feature),
  );
}
