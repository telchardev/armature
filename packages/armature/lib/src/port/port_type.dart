/// Categorisation of [Port] subclasses. Used for debug tooling, logging,
/// and the `debugInfo` map. Framework-level: extending with new kinds
/// requires a new enum value.
enum PortType {
  /// [Pipe] — chains handlers to sequentially transform a value.
  pipe,

  /// [Behavior] — selects the highest-priority handler descriptor.
  behavior,

  /// `SingleSlot` — renders one widget from the highest-priority handler.
  singleSlot,

  /// `MultiSlot` — renders a collection of widgets, one per handler.
  multiSlot,
}
