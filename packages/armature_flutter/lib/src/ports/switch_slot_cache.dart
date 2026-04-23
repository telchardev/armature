/// Returns a function that caches a built slot per route. Used by
/// `createSingleSwitchSlot` and `createMultiSwitchSlot` to share the
/// per-route memoization logic.
TSlot Function(String route) memoizedSlotFactory<TSlot>({
  required String name,
  required TSlot Function(String slotName) build,
}) {
  final cache = <String, TSlot>{};
  return (String route) {
    final slotName = "$name/$route";
    return cache[slotName] ??= build(slotName);
  };
}
