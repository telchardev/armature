import 'dart:collection' show UnmodifiableSetView;

import 'package:meta/meta.dart' show internal;

/// Protocol implemented by values carried in a [Graph]. Defines the DAG
/// edges (required [parents] and [optionalParents]) used for cycle
/// detection and topological traversal.
///
/// Each distinct [GraphNodeValue] instance corresponds to at most one
/// node inside a single [Graph]; identity equality is used throughout.
abstract class GraphNodeValue {
  /// Human-readable identifier for this node. Used in error messages,
  /// Graphviz exports, and debug logs. Must be stable for the lifetime
  /// of the node.
  String get name;

  /// Values that this node depends on **softly**. The graph still
  /// traverses them for construct-phase ordering, but they do not
  /// participate in the required-parent activation cascade — an
  /// optional parent staying `disabled` does not force this node
  /// `disabled`.
  List<GraphNodeValue> get optionalParents;

  /// Values that this node depends on **strictly**. The graph orders
  /// construction so each listed parent is built before this node, and
  /// cascades activation: this node can be `active` only while every
  /// required parent is `active`.
  List<GraphNodeValue> get parents;
}

/// Internal node wrapper that records the parent/child edges used for
/// traversal. [requiredParents] is the subset of [parents] that came
/// from [GraphNodeValue.parents] (as opposed to
/// [GraphNodeValue.optionalParents]) — consumers can distinguish
/// required vs optional edges when visualising the graph.
///
/// Constructed only by the [Graph] while building its internal topology.
/// External code receives node instances through Graph's visitor hooks
/// and debug APIs; treat every set (`parents`, `requiredParents`,
/// `children`) as read-only — mutations would break cycle detection
/// and cascade invariants. The getters expose
/// [UnmodifiableSetView]s; the constructor is [internal].
class GraphNode<TValue extends GraphNodeValue> {
  final Set<GraphNode<TValue>> _children = {};
  final Set<GraphNode<TValue>> _parents;
  final Set<GraphNode<TValue>> _requiredParents;

  /// Payload value this node wraps.
  final TValue value;

  @internal
  GraphNode({
    required this.value,
    required Set<GraphNode<TValue>> parents,
    required Set<GraphNode<TValue>> requiredParents,
  }) : _parents = parents,
       _requiredParents = requiredParents;

  /// Read-only view of this node's children (nodes that declared
  /// `this.value` as a parent via either
  /// [GraphNodeValue.parents] or [GraphNodeValue.optionalParents]).
  late final Set<GraphNode<TValue>> children = UnmodifiableSetView(_children);

  /// Read-only view of every parent — the union of [requiredParents]
  /// and the optional-parent set.
  late final Set<GraphNode<TValue>> parents = UnmodifiableSetView(_parents);

  /// Read-only view of the required-parent subset. Drives the
  /// activation cascade — this node's target status is downgraded to
  /// `disabled` whenever any entry here is not `active`.
  late final Set<GraphNode<TValue>> requiredParents = UnmodifiableSetView(
    _requiredParents,
  );

  /// Whether [parent] is a required (not optional) parent of this node.
  bool isRequired(GraphNode<TValue> parent) =>
      _requiredParents.contains(parent);

  /// Framework-internal back-edge wiring — called by [Graph] once per
  /// child during graph construction. Never invoke from user code.
  @internal
  void addChild(GraphNode<TValue> child) {
    _children.add(child);
  }

  @override
  String toString() => 'GraphNode(${value.name})';
}
