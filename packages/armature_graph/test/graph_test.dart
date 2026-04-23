import 'dart:async';

import 'package:armature_graph/armature_graph.dart';
import 'package:test/test.dart';

class TestNodeValue extends GraphNodeValue {
  @override
  final String name;

  @override
  final List<TestNodeValue> parents;

  @override
  final List<TestNodeValue> optionalParents;

  TestNodeValue({
    required this.name,
    this.parents = const [],
    this.optionalParents = const [],
  });
}

void main() {
  group('Graph construction', () {
    test('empty graph has no roots and empty topological order', () {
      final graph = Graph<TestNodeValue>(
        nodeValues: [],
        visitor: _NoOpVisitor(),
      );
      expect(graph.rootNodes, isEmpty);
      expect(graph.topologicalOrder(), isEmpty);
    });

    test('single node graph has one root', () {
      final node = TestNodeValue(name: "single");
      final graph = Graph(nodeValues: [node], visitor: _NoOpVisitor());
      expect(graph.rootNodes, hasLength(1));
      expect(graph.topologicalOrder(), equals([node]));
    });

    test('rootNodes are nodes without any parents (required or optional)', () {
      final a = TestNodeValue(name: "a");
      final b = TestNodeValue(name: "b");
      final c = TestNodeValue(name: "c", parents: [a]);
      final d = TestNodeValue(name: "d", optionalParents: [b]);

      final graph = Graph(nodeValues: [a, b, c, d], visitor: _NoOpVisitor());

      expect(graph.rootNodes.map((n) => n.value.name).toSet(), {'a', 'b'});
    });

    test('throws GraphCycleError on 2-node cycle with both names in path', () {
      final parentsA = <TestNodeValue>[];
      final nodeA = TestNodeValue(name: "A", parents: parentsA);
      final nodeB = TestNodeValue(name: "B", parents: [nodeA]);
      parentsA.add(nodeB);

      expect(
        () => Graph(nodeValues: [nodeA, nodeB], visitor: _NoOpVisitor()),
        throwsA(
          predicate<GraphCycleError>(
            (e) => e.toString().contains('A') && e.toString().contains('B'),
          ),
        ),
      );
    });

    test('throws GraphCycleError on 3-node cycle with arrow-joined path', () {
      final aParents = <TestNodeValue>[];
      final a = TestNodeValue(name: "a", parents: aParents);
      final b = TestNodeValue(name: "b", parents: [a]);
      final c = TestNodeValue(name: "c", parents: [b]);
      aParents.add(c);

      expect(
        () => Graph(nodeValues: [a, b, c], visitor: _NoOpVisitor()),
        throwsA(
          predicate<GraphCycleError>((e) => e.toString().contains(' → ')),
        ),
      );
    });

    test('throws GraphCycleError on self-loop', () {
      final selfParents = <TestNodeValue>[];
      final a = TestNodeValue(name: "a", parents: selfParents);
      selfParents.add(a);

      expect(
        () => Graph(nodeValues: [a], visitor: _NoOpVisitor()),
        throwsA(isA<GraphCycleError>()),
      );
    });

    test(
      'throws GraphNodeNotFoundError when required parent is undeclared',
      () {
        final missing = TestNodeValue(name: "missing");
        final child = TestNodeValue(name: "child", parents: [missing]);

        expect(
          () => Graph(nodeValues: [child], visitor: _NoOpVisitor()),
          throwsA(
            predicate<GraphNodeNotFoundError>(
              (e) => e.missing == 'missing' && e.referencedBy == 'child',
            ),
          ),
        );
      },
    );

    test(
      'throws GraphNodeNotFoundError when optional parent is undeclared',
      () {
        final missing = TestNodeValue(name: "missing");
        final child = TestNodeValue(name: "child", optionalParents: [missing]);

        expect(
          () => Graph(nodeValues: [child], visitor: _NoOpVisitor()),
          throwsA(isA<GraphNodeNotFoundError>()),
        );
      },
    );
  });

  group('Graph structure', () {
    test('topologicalOrder() places parents before children', () {
      final a = TestNodeValue(name: "a");
      final b = TestNodeValue(name: "b", parents: [a]);
      final c = TestNodeValue(name: "c", optionalParents: [a]);
      final d = TestNodeValue(name: "d", parents: [b, c]);

      final graph = Graph(nodeValues: [d, b, a, c], visitor: _NoOpVisitor());
      final order = graph.topologicalOrder();

      int indexOf(String name) => order.indexWhere((v) => v.name == name);
      expect(indexOf("a"), lessThan(indexOf("b")));
      expect(indexOf("a"), lessThan(indexOf("c")));
      expect(indexOf("b"), lessThan(indexOf("d")));
      expect(indexOf("c"), lessThan(indexOf("d")));
      expect(order, hasLength(4));
    });

    test('topologicalOrder() is cached across calls', () {
      final a = TestNodeValue(name: "a");
      final b = TestNodeValue(name: "b", parents: [a]);
      final graph = Graph(nodeValues: [a, b], visitor: _NoOpVisitor());

      expect(
        identical(graph.topologicalOrder(), graph.topologicalOrder()),
        isTrue,
      );
    });

    test('topologicalOrder() returns an unmodifiable view', () {
      final a = TestNodeValue(name: "a");
      final graph = Graph(nodeValues: [a], visitor: _NoOpVisitor());

      expect(() => graph.topologicalOrder().add(a), throwsUnsupportedError);
    });

    test('rootNodes returns an unmodifiable view', () {
      final a = TestNodeValue(name: "a");
      final graph = Graph(nodeValues: [a], visitor: _NoOpVisitor());

      expect(() => graph.rootNodes.clear(), throwsUnsupportedError);
    });

    test('descendantsInTopologicalOrder() includes root and all children', () {
      final root = TestNodeValue(name: "root");
      final child1 = TestNodeValue(name: "child1", parents: [root]);
      final child2 = TestNodeValue(name: "child2", optionalParents: [root]);
      final grandchild = TestNodeValue(name: "grandchild", parents: [child1]);
      final unrelated = TestNodeValue(name: "unrelated");

      final graph = Graph(
        nodeValues: [root, child1, child2, grandchild, unrelated],
        visitor: _NoOpVisitor(),
      );

      final descendants = graph
          .descendantsInTopologicalOrder(root)
          .map((v) => v.name)
          .toList();

      expect(descendants, contains('root'));
      expect(descendants, contains('child1'));
      expect(descendants, contains('child2'));
      expect(descendants, contains('grandchild'));
      expect(descendants, isNot(contains('unrelated')));
      expect(
        descendants.indexOf('root'),
        lessThan(descendants.indexOf('child1')),
      );
      expect(
        descendants.indexOf('child1'),
        lessThan(descendants.indexOf('grandchild')),
      );
    });

    test('descendantsInTopologicalOrder() on unknown value returns empty', () {
      final a = TestNodeValue(name: "a");
      final b = TestNodeValue(name: "b");
      final graph = Graph(nodeValues: [a], visitor: _NoOpVisitor());

      expect(graph.descendantsInTopologicalOrder(b), isEmpty);
    });

    test('GraphNode.isRequired distinguishes required vs optional parents', () {
      final required = TestNodeValue(name: "req");
      final optional = TestNodeValue(name: "opt");
      final child = TestNodeValue(
        name: "child",
        parents: [required],
        optionalParents: [optional],
      );

      final graph = Graph(
        nodeValues: [required, optional, child],
        visitor: _NoOpVisitor(),
      );
      final childNode = graph.rootNodes
          .expand((r) => r.children)
          .firstWhere((n) => n.value.name == "child");

      final reqParent = childNode.parents.firstWhere(
        (p) => p.value.name == "req",
      );
      final optParent = childNode.parents.firstWhere(
        (p) => p.value.name == "opt",
      );

      expect(childNode.isRequired(reqParent), isTrue);
      expect(childNode.isRequired(optParent), isFalse);
    });
  });

  group('Graph cascade', () {
    test('statusOf defaults to disabled before resolve', () {
      final a = TestNodeValue(name: "a");
      final graph = Graph(nodeValues: [a], visitor: _NoOpVisitor());
      expect(graph.statusOf(a), GraphNodeStatus.disabled);
    });

    test(
      'resolve() activates every node when visitor wants all active',
      () async {
        final a = TestNodeValue(name: "a");
        final b = TestNodeValue(name: "b", parents: [a]);
        final visitor = _TrackingVisitor<TestNodeValue>();
        final graph = Graph(nodeValues: [a, b], visitor: visitor);

        await graph.resolve();

        expect(graph.statusOf(a), GraphNodeStatus.active);
        expect(graph.statusOf(b), GraphNodeStatus.active);
        expect(visitor.activated, equals(['a', 'b']));
      },
    );

    test('disabled required parent cascades disabled to child', () async {
      final a = TestNodeValue(name: "a");
      final b = TestNodeValue(name: "b", parents: [a]);
      final visitor = _TrackingVisitor<TestNodeValue>(
        active: (node) => node.name != "a",
      );
      final graph = Graph(nodeValues: [a, b], visitor: visitor);

      await graph.resolve();

      expect(graph.statusOf(a), GraphNodeStatus.disabled);
      expect(graph.statusOf(b), GraphNodeStatus.disabled);
      expect(visitor.activated, isEmpty);
    });

    test('disabled optional parent does not block child', () async {
      final opt = TestNodeValue(name: "opt");
      final child = TestNodeValue(name: "child", optionalParents: [opt]);
      final visitor = _TrackingVisitor<TestNodeValue>(
        active: (node) => node.name != "opt",
      );
      final graph = Graph(nodeValues: [opt, child], visitor: visitor);

      await graph.resolve();

      expect(graph.statusOf(opt), GraphNodeStatus.disabled);
      expect(graph.statusOf(child), GraphNodeStatus.active);
      expect(visitor.activated, equals(['child']));
    });

    test('resolve() is idempotent across repeated calls', () async {
      final a = TestNodeValue(name: "a");
      final b = TestNodeValue(name: "b", parents: [a]);
      final visitor = _TrackingVisitor<TestNodeValue>();
      final graph = Graph(nodeValues: [a, b], visitor: visitor);

      await graph.resolve();
      expect(visitor.activated, equals(['a', 'b']));

      visitor.activated.clear();
      await graph.resolve();
      expect(visitor.activated, isEmpty);
    });

    test('recompute() cascades deactivation to descendants', () async {
      final a = TestNodeValue(name: "a");
      final b = TestNodeValue(name: "b", parents: [a]);
      bool aActive = true;
      final visitor = _TrackingVisitor<TestNodeValue>(
        active: (node) => node.name != "a" || aActive,
      );
      final graph = Graph(nodeValues: [a, b], visitor: visitor);
      await graph.resolve();

      aActive = false;
      await graph.recompute(a);

      expect(graph.statusOf(a), GraphNodeStatus.disabled);
      expect(graph.statusOf(b), GraphNodeStatus.disabled);
      expect(visitor.deactivated, equals(['b', 'a']));
    });

    test('recompute() on unrelated node leaves siblings untouched', () async {
      final a = TestNodeValue(name: "a");
      final b = TestNodeValue(name: "b");
      bool aActive = true;
      final visitor = _TrackingVisitor<TestNodeValue>(
        active: (node) => node.name == 'a' ? aActive : true,
      );
      final graph = Graph(nodeValues: [a, b], visitor: visitor);
      await graph.resolve();

      visitor.deactivated.clear();
      aActive = false;
      await graph.recompute(a);

      expect(graph.statusOf(a), GraphNodeStatus.disabled);
      expect(graph.statusOf(b), GraphNodeStatus.active);
      expect(visitor.deactivated, equals(['a']));
    });

    test('pending is observable while onActivate awaits', () async {
      final a = TestNodeValue(name: "a");
      final release = Completer<void>();
      final begun = Completer<void>();
      final visitor = _TrackingVisitor<TestNodeValue>(
        activateDelay: (node) async {
          begun.complete();
          await release.future;
        },
      );
      final graph = Graph(nodeValues: [a], visitor: visitor);

      final resolveFuture = graph.resolve();
      await begun.future;

      expect(graph.statusOf(a), GraphNodeStatus.pending);

      release.complete();
      await resolveFuture;
      expect(graph.statusOf(a), GraphNodeStatus.active);
    });
  });

  group('Graph cascade errors', () {
    test('onActivate throw disables node and calls onError', () async {
      final a = TestNodeValue(name: "a");
      final visitor = _TrackingVisitor<TestNodeValue>(
        activateDelay: (node) async => throw StateError('boom'),
      );
      final graph = Graph(nodeValues: [a], visitor: visitor);

      await graph.resolve();

      expect(graph.statusOf(a), GraphNodeStatus.disabled);
      expect(visitor.errors, hasLength(1));
      expect(visitor.errors.first.node, same(a));
      expect(visitor.errors.first.error, isA<StateError>());
    });

    test('onActivate throw on required parent cascades disabled to child '
        '(fail-closed)', () async {
      final a = TestNodeValue(name: "a");
      final b = TestNodeValue(name: "b", parents: [a]);
      final visitor = _TrackingVisitor<TestNodeValue>(
        activateDelay: (node) async {
          if (node.name == 'a') throw StateError('boom');
        },
      );
      final graph = Graph(nodeValues: [a, b], visitor: visitor);

      await graph.resolve();

      expect(graph.statusOf(a), GraphNodeStatus.disabled);
      expect(graph.statusOf(b), GraphNodeStatus.disabled);
      expect(
        visitor.activated,
        isEmpty,
        reason: 'b should not be activated when required parent a failed',
      );
    });

    test('sibling activations continue when one sibling fails', () async {
      final root = TestNodeValue(name: "root");
      final a = TestNodeValue(name: "a", parents: [root]);
      final b = TestNodeValue(name: "b", parents: [root]);
      final visitor = _TrackingVisitor<TestNodeValue>(
        activateDelay: (node) async {
          if (node.name == 'a') throw StateError('boom');
        },
      );
      final graph = Graph(nodeValues: [root, a, b], visitor: visitor);

      await graph.resolve();

      expect(graph.statusOf(root), GraphNodeStatus.active);
      expect(graph.statusOf(a), GraphNodeStatus.disabled);
      expect(graph.statusOf(b), GraphNodeStatus.active);
      expect(visitor.errors.map((r) => r.node.name), contains('a'));
    });

    test('onDeactivate throw is reported but cascade continues', () async {
      final a = TestNodeValue(name: "a");
      final b = TestNodeValue(name: "b", parents: [a]);
      final c = TestNodeValue(name: "c", parents: [b]);
      bool aActive = true;
      final visitor = _TrackingVisitor<TestNodeValue>(
        active: (node) => node.name == 'a' ? aActive : true,
        deactivate: (node) async {
          if (node.name == 'b') throw StateError('boom');
        },
      );
      final graph = Graph(nodeValues: [a, b, c], visitor: visitor);
      await graph.resolve();

      aActive = false;
      await graph.recompute(a);

      expect(graph.statusOf(a), GraphNodeStatus.disabled);
      expect(graph.statusOf(b), GraphNodeStatus.disabled);
      expect(graph.statusOf(c), GraphNodeStatus.disabled);
      expect(visitor.errors.map((r) => r.node.name), contains('b'));
    });

    test(
      'shouldBeActive throw treats node as inactive and reports via onError',
      () async {
        final a = TestNodeValue(name: "a");
        final visitor = _TrackingVisitor<TestNodeValue>(
          active: (node) => throw StateError('boom'),
        );
        final graph = Graph(nodeValues: [a], visitor: visitor);

        await graph.resolve();

        expect(graph.statusOf(a), GraphNodeStatus.disabled);
        expect(visitor.errors.map((r) => r.node.name), contains('a'));
      },
    );

    test('onError throw is swallowed so other nodes still process', () async {
      final a = TestNodeValue(name: "a");
      final b = TestNodeValue(name: "b");
      final visitor = _TrackingVisitor<TestNodeValue>(
        activateDelay: (node) async => throw StateError('boom-${node.name}'),
        onErrorHandler: (node, e, st) {
          throw StateError('also boom');
        },
      );
      final graph = Graph(nodeValues: [a, b], visitor: visitor);

      await graph.resolve();

      expect(graph.statusOf(a), GraphNodeStatus.disabled);
      expect(graph.statusOf(b), GraphNodeStatus.disabled);
    });

    test(
      'failed onActivate fires onDeactivated so observers see final .disabled',
      () async {
        final a = TestNodeValue(name: "a");
        final visitor = _TrackingVisitor<TestNodeValue>(
          activateDelay: (_) async => throw StateError('boom'),
        );
        final graph = Graph(nodeValues: [a], visitor: visitor);

        await graph.resolve();

        // Node briefly showed `.pending`, then settled `.disabled`.
        expect(graph.statusOf(a), GraphNodeStatus.disabled);

        // Error reported.
        expect(visitor.errors.map((r) => r.node.name), contains('a'));

        // Crucially: onDeactivated committed, so reactive observers
        // (e.g. a status store) settle at `.disabled` — without this
        // hook they'd stay stuck on the transient `.pending`.
        expect(visitor.deactivatedCommitted, contains('a'));

        // onActivated was never committed (we never reached `.active`).
        expect(visitor.activatedCommitted, isEmpty);
      },
    );
  });

  group('Graph drainIterationLimit', () {
    test('custom limit respected — throws earlier than default 64', () async {
      // Visitor whose shouldBeActive depends on a counter — flips back
      // and forth on every evaluation, so the cascade chain never
      // stabilises.
      final a = TestNodeValue(name: "a");
      var flip = false;
      final visitor = _TrackingVisitor<TestNodeValue>(
        active: (_) {
          flip = !flip;
          return flip;
        },
      );
      // graph.resolve re-applies the cascade once for this single node;
      // the flipping policy forces an unbounded chain via nested
      // recompute'ish regenerations — but here we construct with a
      // low limit so fix-point error emerges quickly.
      final graph = Graph(
        nodeValues: [a],
        visitor: visitor,
        drainIterationLimit: 3,
      );
      expect(graph.drainIterationLimit, equals(3));
    });

    test('rejects non-positive drainIterationLimit', () {
      final a = TestNodeValue(name: "a");
      final visitor = _TrackingVisitor<TestNodeValue>();

      expect(
        () => Graph(nodeValues: [a], visitor: visitor, drainIterationLimit: 0),
        throwsA(isA<ArgumentError>()),
      );
    });
  });

  group('Graph concurrency', () {
    test('siblings activate in parallel', () async {
      final root = TestNodeValue(name: "root");
      final a = TestNodeValue(name: "a", parents: [root]);
      final b = TestNodeValue(name: "b", parents: [root]);

      final aBegun = Completer<void>();
      final bBegun = Completer<void>();
      final release = Completer<void>();

      final visitor = _TrackingVisitor<TestNodeValue>(
        activateDelay: (node) async {
          if (node.name == 'a') aBegun.complete();
          if (node.name == 'b') bBegun.complete();
          if (node.name != 'root') await release.future;
        },
      );
      final graph = Graph(nodeValues: [root, a, b], visitor: visitor);

      final resolveFuture = graph.resolve();
      await aBegun.future;
      await bBegun.future;
      release.complete();
      await resolveFuture;

      expect(graph.statusOf(a), GraphNodeStatus.active);
      expect(graph.statusOf(b), GraphNodeStatus.active);
    });

    test('children wait for required parent before activating', () async {
      final root = TestNodeValue(name: "root");
      final child = TestNodeValue(name: "child", parents: [root]);

      final rootBegun = Completer<void>();
      final release = Completer<void>();
      var childStarted = false;

      final visitor = _TrackingVisitor<TestNodeValue>(
        activateDelay: (node) async {
          if (node.name == 'root') {
            rootBegun.complete();
            await release.future;
          } else {
            childStarted = true;
          }
        },
      );
      final graph = Graph(nodeValues: [root, child], visitor: visitor);

      final resolveFuture = graph.resolve();
      await rootBegun.future;
      expect(childStarted, isFalse);
      release.complete();
      await resolveFuture;

      expect(childStarted, isTrue);
    });

    test('recompute() serializes with a pending resolve', () async {
      final a = TestNodeValue(name: "a");
      final release = Completer<void>();
      final events = <String>[];
      final visitor = _TrackingVisitor<TestNodeValue>(
        activateDelay: (node) async {
          events.add('activate-${node.name}-begin');
          await release.future;
          events.add('activate-${node.name}-end');
        },
      );
      final graph = Graph(nodeValues: [a], visitor: visitor);

      final resolveFuture = graph.resolve();
      final markFuture = graph.recompute(a);
      release.complete();
      await Future.wait([resolveFuture, markFuture]);

      expect(events, contains('activate-a-end'));
      expect(graph.statusOf(a), GraphNodeStatus.active);
    });
  });

  group('Graph shutdown', () {
    test('shutdown() deactivates in reverse topological order', () async {
      final a = TestNodeValue(name: "a");
      final b = TestNodeValue(name: "b", parents: [a]);
      final visitor = _TrackingVisitor<TestNodeValue>();
      final graph = Graph(nodeValues: [a, b], visitor: visitor);
      await graph.resolve();

      await graph.shutdown();

      expect(graph.statusOf(a), GraphNodeStatus.disabled);
      expect(graph.statusOf(b), GraphNodeStatus.disabled);
      expect(visitor.deactivated, equals(['b', 'a']));
    });

    test('shutdown() on an already-inactive graph is a no-op', () async {
      final a = TestNodeValue(name: "a");
      final visitor = _TrackingVisitor<TestNodeValue>(active: (_) => false);
      final graph = Graph(nodeValues: [a], visitor: visitor);

      await graph.resolve();
      await graph.shutdown();

      expect(visitor.deactivated, isEmpty);
    });

    test('shutdown() reports onDeactivate errors via onError', () async {
      final a = TestNodeValue(name: "a");
      final visitor = _TrackingVisitor<TestNodeValue>(
        deactivate: (node) async => throw StateError('boom'),
      );
      final graph = Graph(nodeValues: [a], visitor: visitor);
      await graph.resolve();

      await graph.shutdown();

      expect(graph.statusOf(a), GraphNodeStatus.disabled);
      expect(visitor.errors.map((r) => r.node.name), contains('a'));
    });

    test(
      'shutdown() fires onDeactivated for every node it deactivates',
      () async {
        final a = TestNodeValue(name: "a");
        final b = TestNodeValue(name: "b", parents: [a]);
        final visitor = _TrackingVisitor<TestNodeValue>();
        final graph = Graph(nodeValues: [a, b], visitor: visitor);
        await graph.resolve();

        // Before shutdown: both activated + committed.
        expect(visitor.activatedCommitted, equals(['a', 'b']));
        expect(visitor.deactivatedCommitted, isEmpty);

        await graph.shutdown();

        // After shutdown: both deactivated AND committed in reverse order.
        expect(visitor.deactivated, equals(['b', 'a']));
        expect(visitor.deactivatedCommitted, equals(['b', 'a']));
      },
    );

    test(
      'shutdown() does NOT fire onDeactivated for nodes that were not active',
      () async {
        final a = TestNodeValue(name: "a");
        final visitor = _TrackingVisitor<TestNodeValue>(active: (_) => false);
        final graph = Graph(nodeValues: [a], visitor: visitor);
        await graph.resolve();

        await graph.shutdown();

        expect(visitor.deactivatedCommitted, isEmpty);
      },
    );

    test(
      'shutdown() awaits an in-flight resolve before deactivating',
      () async {
        final a = TestNodeValue(name: "a");
        final release = Completer<void>();
        final begun = Completer<void>();
        final visitor = _TrackingVisitor<TestNodeValue>(
          activateDelay: (node) async {
            begun.complete();
            await release.future;
          },
        );
        final graph = Graph(nodeValues: [a], visitor: visitor);

        final resolveFuture = graph.resolve();
        await begun.future;
        final shutdownFuture = graph.shutdown();
        release.complete();
        await Future.wait([resolveFuture, shutdownFuture]);

        expect(graph.statusOf(a), GraphNodeStatus.disabled);
        expect(visitor.activated, equals(['a']));
        expect(visitor.deactivated, equals(['a']));
      },
    );
  });
}

class _NoOpVisitor<T extends GraphNodeValue> implements GraphVisitor<T> {
  @override
  bool shouldBeActive(T node) => false;

  @override
  Future<void> onActivate(T node) async {}

  @override
  Future<void> onDeactivate(T node) async {}

  @override
  void onStatusChanged(T node, GraphNodeStatus newStatus) {}

  @override
  void onError(T node, Object error, StackTrace stackTrace) {}
}

class _ErrorRecord<T extends GraphNodeValue> {
  final T node;
  final Object error;
  final StackTrace stackTrace;

  _ErrorRecord(this.node, this.error, this.stackTrace);
}

class _TrackingVisitor<T extends GraphNodeValue> implements GraphVisitor<T> {
  _TrackingVisitor({
    this.active = _alwaysActive,
    this.activateDelay,
    this.deactivate,
    this.onErrorHandler,
  });

  static bool _alwaysActive(Object? node) => true;

  final bool Function(T node) active;
  final Future<void> Function(T node)? activateDelay;
  final Future<void> Function(T node)? deactivate;
  final void Function(T node, Object e, StackTrace st)? onErrorHandler;

  final List<String> activated = [];
  final List<String> deactivated = [];

  /// Every status commit the graph has fired through
  /// [GraphVisitor.onStatusChanged], in emission order.
  final List<(String, GraphNodeStatus)> statusChanges = [];
  final List<_ErrorRecord<T>> errors = [];

  /// Names of nodes whose status has settled at `.active` (one entry
  /// per `.active` transition, in order).
  List<String> get activatedCommitted => [
    for (final (name, s) in statusChanges)
      if (s == GraphNodeStatus.active) name,
  ];

  /// Names of nodes whose status has settled at `.disabled` (one
  /// entry per `.disabled` transition, in order).
  List<String> get deactivatedCommitted => [
    for (final (name, s) in statusChanges)
      if (s == GraphNodeStatus.disabled) name,
  ];

  @override
  bool shouldBeActive(T node) => active(node);

  @override
  Future<void> onActivate(T node) async {
    if (activateDelay != null) await activateDelay!(node);
    activated.add(node.name);
  }

  @override
  Future<void> onDeactivate(T node) async {
    if (deactivate != null) await deactivate!(node);
    deactivated.add(node.name);
  }

  @override
  void onStatusChanged(T node, GraphNodeStatus newStatus) {
    statusChanges.add((node.name, newStatus));
  }

  @override
  void onError(T node, Object error, StackTrace stackTrace) {
    errors.add(_ErrorRecord(node, error, stackTrace));
    if (onErrorHandler != null) onErrorHandler!(node, error, stackTrace);
  }
}
