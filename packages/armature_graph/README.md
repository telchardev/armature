# armature_graph

Directed-acyclic-graph resolver with topological ordering and
visitor-based activation cascade. **Pure Dart.** Consumed by
[`armature`](https://pub.dev/packages/armature) to resolve feature
dependencies at container startup; usable standalone for any task that
needs cycle detection + topologically-ordered lifecycle hooks.

## Concepts

- **`Graph<T>`** — a DAG of nodes where each node has a `T` payload
  with its own declared `parents` / `optionalParents`.
- **`GraphNodeStatus`** — `.disabled` / `.pending` / `.active`.
- **`GraphVisitor<T>`** — user-supplied hooks:
  - `shouldBeActive(node)` — the node's own preference.
  - `onActivate(node)` / `onDeactivate(node)` — called when the node
    enters / leaves `.active`.
  - `onStatusChanged(node, status)` — fires for every settled
    transition.
  - `onError(node, error, st)` — receives caught visitor throws.

## Usage

```dart
import 'package:armature_graph/armature_graph.dart';

class Node extends GraphNodeValue {
  @override final String name;
  @override final List<GraphNodeValue> parents;
  @override final List<GraphNodeValue> optionalParents = const [];
  Node(this.name, [this.parents = const []]);
}

class PrintVisitor implements GraphVisitor<Node> {
  @override bool shouldBeActive(Node n) => true;
  @override Future<void> onActivate(Node n) async => print('+ ${n.name}');
  @override Future<void> onDeactivate(Node n) async => print('- ${n.name}');
  @override void onStatusChanged(Node n, GraphNodeStatus s) {}
  @override void onError(Node n, Object e, StackTrace st) {
    print('! ${n.name}: $e');
  }
}

Future<void> main() async {
  final a = Node('a');
  final b = Node('b', [a]);
  final c = Node('c', [b]);

  final graph = Graph(nodeValues: [a, b, c], visitor: PrintVisitor());
  await graph.resolve();
  // prints: + a, + b, + c  — topological order
}
```

### Cascade semantics

- `resolve()` walks the graph to a fixed point — each pass checks every
  node's preferred status (`shouldBeActive`) plus required-parent
  status, activates / deactivates as needed, and drains nested
  recomputes before returning.
- `GraphFixedPointError` surfaces if the cascade fails to stabilise in
  `drainIterationLimit` passes (default 100) — indicates a toggle loop
  in the user's visitor.
- `GraphCycleError` / `GraphNodeNotFoundError` catch malformed inputs
  at construction.

### Throttling

Pass `activationConcurrency: N` to cap parallel `onActivate` calls via
an internal semaphore. `null` means unbounded.

## Install

```yaml
dependencies:
  armature_graph: ^0.1.0
```

## Learn more

- [`armature`](https://pub.dev/packages/armature) — the feature
  framework that uses this graph for dependency resolution.
- [Monorepo README](https://github.com/telchardev/armature) — full
  architecture and examples.

## License

MIT — see [LICENSE](LICENSE).
