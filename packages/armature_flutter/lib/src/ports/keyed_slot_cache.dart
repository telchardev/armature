/// Returns a function that caches a built slot per key. Used by
/// `createKeyedSingleSlot` and `createKeyedMultiSlot` to share the
/// per-key memoization logic.
TSlot Function(String key) memoizedKeyedSlot<TSlot>({
  required String name,
  required TSlot Function(String slotName) build,
}) {
  final cache = <String, TSlot>{};
  return (String key) {
    final slotName = "$name/$key";
    return cache[slotName] ??= build(slotName);
  };
}
