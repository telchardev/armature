import 'package:armature/armature.dart' show Feature;

import './single_slot.dart'
    show SingleSlot, SingleSlotHandler, createSingleSlot;
import './switch_slot_cache.dart' show memoizedSlotFactory;

typedef SingleSlotFactory<TInputData> =
    SingleSlot<TInputData, SingleSlotHandler<TInputData>> Function(
      String route,
    );

/// Builds a memoized factory that creates or reuses a [SingleSlot] per
/// `route`. Slots share `feature` ownership; `name` is namespaced per
/// route (`"$name/$route"`).
SingleSlotFactory<TInputData> createSingleSwitchSlot<
  TInputData extends Object?
>({required String name, Feature? feature}) {
  return memoizedSlotFactory<
    SingleSlot<TInputData, SingleSlotHandler<TInputData>>
  >(
    name: name,
    build: (slotName) =>
        createSingleSlot<TInputData>(name: slotName, feature: feature),
  );
}
