import 'package:armature_graph/armature_graph.dart'
    show Graph, GraphNodeStatus, GraphNodeValue, GraphVisitor;

class NodeValue extends GraphNodeValue {
  final String _name;

  NodeValue({required String name}) : _name = name;

  @override
  String get name => _name;

  @override
  List<GraphNodeValue> get optionalParents => [];

  @override
  List<GraphNodeValue> get parents => [];
}

class AlwaysActiveVisitor implements GraphVisitor<NodeValue> {
  @override
  bool shouldBeActive(NodeValue node) => true;

  @override
  Future<void> onActivate(NodeValue node) async {}

  @override
  Future<void> onDeactivate(NodeValue node) async {}

  @override
  void onStatusChanged(NodeValue node, GraphNodeStatus newStatus) {}

  @override
  void onError(NodeValue node, Object error, StackTrace stackTrace) {}
}

Future<void> main() async {
  final graph = Graph(
    nodeValues: [
      NodeValue(name: "one"),
      NodeValue(name: "two"),
      NodeValue(name: "three"),
    ],
    visitor: AlwaysActiveVisitor(),
  );
  await graph.resolve();
}
