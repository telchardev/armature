import 'package:armature/armature.dart';
import 'package:armature_flutter/armature_flutter.dart';
import 'package:armature_flutter/test_utils.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

class _CounterStore extends Store<int> {
  _CounterStore() : super(state: 0);

  void increment() => state = state + 1;
}

enum _TestBranch { a, b }

void main() {
  group('PipeProvider', () {
    testWidgets('renders pipe value', (tester) async {
      final rootFeature = createFeature(name: "root");
      final pipe = createPipe<List<String>>(name: "tabs", feature: rootFeature);

      final childFeature = createFeature(
        name: "child",
        dependsOn: [rootFeature],
      )..usePipe(pipe, (tabs, api) => [...tabs, 'home', 'settings']);

      final container = await startedContainer(
        features: [rootFeature, childFeature],
      );

      await pumpFeature(
        tester,
        container: container,
        feature: rootFeature,
        child: PipeProvider(
          pipe: pipe,
          initialValue: <String>[],
          builder: (tabs, _) => Text(tabs.join(', ')),
        ),
      );

      expect(find.text('home, settings'), findsOneWidget);
    });

    testWidgets('rebuilds when reactive state changes', (tester) async {
      final rootFeature = createFeature(
        name: "root",
        stores: (_) => (counter: _CounterStore()),
        exports: (api) => api.own,
      );
      final pipe = createPipe<int>(name: "sum", feature: rootFeature);

      final childFeature =
          createFeature(name: "child", dependsOn: [rootFeature])
            ..usePipe(pipe, (value, api) {
              return value + api.of(rootFeature).counter.state;
            });

      final container = await startedContainer(
        features: [rootFeature, childFeature],
      );
      final counterStore = rootFeature.storeOf<_CounterStore>(container);

      await pumpFeature(
        tester,
        container: container,
        feature: rootFeature,
        child: PipeProvider(
          pipe: pipe,
          initialValue: 0,
          builder: (value, _) => Text('$value'),
        ),
      );

      expect(find.text('0'), findsOneWidget);

      counterStore.increment();
      await tester.pumpAndSettle();

      expect(find.text('1'), findsOneWidget);
    });

    testWidgets('collects handlers from multiple features', (tester) async {
      final rootFeature = createFeature(name: "root");
      final pipe = createPipe<List<String>>(
        name: "multi",
        feature: rootFeature,
      );

      final featureA = createFeature(name: "a", dependsOn: [rootFeature])
        ..usePipe(pipe, (list, api) => [...list, 'A']);

      final featureB = createFeature(name: "b", dependsOn: [rootFeature])
        ..usePipe(pipe, (list, api) => [...list, 'B']);

      final container = await startedContainer(
        features: [rootFeature, featureA, featureB],
      );

      await pumpFeature(
        tester,
        container: container,
        feature: rootFeature,
        child: PipeProvider(
          pipe: pipe,
          initialValue: <String>[],
          builder: (list, _) => Text(list.join(', ')),
        ),
      );

      expect(find.text('A, B'), findsOneWidget);
    });
  });

  group('SingleSlotProvider', () {
    testWidgets('renders slot widget', (tester) async {
      final rootFeature = createFeature(name: "root");
      final slot = createSingleSlot<Null>(name: "title", feature: rootFeature);

      final childFeature = createFeature(
        name: "child",
        dependsOn: [rootFeature],
      )..useSingleSlot(slot, (_, api) => const Text('Hello'));

      final container = await startedContainer(
        features: [rootFeature, childFeature],
      );

      await pumpFeature(
        tester,
        container: container,
        feature: rootFeature,
        child: SingleSlotProvider(
          slot: slot,
          data: null,
          builder: (child, _) => child ?? const Text('fallback'),
        ),
      );

      expect(find.text('fallback'), findsNothing);
      expect(find.byType(Text), findsOneWidget);
    });

    testWidgets('renders fallback when no handlers', (tester) async {
      final rootFeature = createFeature(name: "root");
      final slot = createSingleSlot<Null>(name: "empty", feature: rootFeature);

      final container = await startedContainer(features: [rootFeature]);

      await pumpFeature(
        tester,
        container: container,
        feature: rootFeature,
        child: SingleSlotProvider(
          slot: slot,
          data: null,
          builder: (child, _) => child ?? const Text('fallback'),
        ),
      );

      expect(find.text('fallback'), findsOneWidget);
    });

    testWidgets('renders fallback when handler returns null', (tester) async {
      final rootFeature = createFeature(name: "root");
      final slot = createSingleSlot<Null>(
        name: "nullable",
        feature: rootFeature,
      );

      final childFeature = createFeature(
        name: "child",
        dependsOn: [rootFeature],
      )..useSingleSlot(slot, (_, api) => null);

      final container = await startedContainer(
        features: [rootFeature, childFeature],
      );

      await pumpFeature(
        tester,
        container: container,
        feature: rootFeature,
        child: SingleSlotProvider(
          slot: slot,
          data: null,
          builder: (child, _) => child ?? const Text('fallback'),
        ),
      );

      expect(find.text('fallback'), findsOneWidget);
    });

    testWidgets('rebuilds when reactive state changes', (tester) async {
      final rootFeature = createFeature(
        name: "root",
        stores: (_) => (counter: _CounterStore()),
        exports: (api) => api.own,
      );
      final slot = createSingleSlot<Null>(
        name: "reactive",
        feature: rootFeature,
      );

      final childFeature =
          createFeature(name: "child", dependsOn: [rootFeature])
            ..useSingleSlot(slot, (_, api) {
              return Text('count: ${api.of(rootFeature).counter.state}');
            });

      final container = await startedContainer(
        features: [rootFeature, childFeature],
      );
      final counterStore = rootFeature.storeOf<_CounterStore>(container);

      await pumpFeature(
        tester,
        container: container,
        feature: rootFeature,
        child: SingleSlotProvider(
          slot: slot,
          data: null,
          builder: (child, _) => child ?? const SizedBox.shrink(),
        ),
      );

      counterStore.increment();
      await tester.pumpAndSettle();

      counterStore.increment();
      await tester.pumpAndSettle();
    });
  });

  group('MultiSlotProvider', () {
    testWidgets('collects widgets from multiple features', (tester) async {
      final rootFeature = createFeature(name: "root");
      final slot = createMultiSlot<Null>(
        name: "actions",
        feature: rootFeature,
        orderDirection: MultiSlotOrderDirection.asc,
      );

      final featureA = createFeature(name: "a", dependsOn: [rootFeature])
        ..useMultiSlot(slot, (_, api) => const Text('A'), order: 1);

      final featureB = createFeature(name: "b", dependsOn: [rootFeature])
        ..useMultiSlot(slot, (_, api) => const Text('B'), order: 2);

      final container = await startedContainer(
        features: [rootFeature, featureA, featureB],
      );

      await pumpFeature(
        tester,
        container: container,
        feature: rootFeature,
        child: MultiSlotProvider(
          slot: slot,
          data: null,
          builder: (children, _) =>
              Column(mainAxisSize: MainAxisSize.min, children: children),
        ),
      );

      expect(find.byType(Text), findsWidgets);
    });

    testWidgets('renders empty when no handlers', (tester) async {
      final rootFeature = createFeature(name: "root");
      final slot = createMultiSlot<Null>(
        name: "empty_multi",
        feature: rootFeature,
        orderDirection: MultiSlotOrderDirection.asc,
      );

      final container = await startedContainer(features: [rootFeature]);

      await pumpFeature(
        tester,
        container: container,
        feature: rootFeature,
        child: MultiSlotProvider(
          slot: slot,
          data: null,
          builder: (children, _) {
            if (children.isEmpty) return const Text('empty');
            return Column(mainAxisSize: MainAxisSize.min, children: children);
          },
        ),
      );

      expect(find.text('empty'), findsOneWidget);
    });

    testWidgets('skips handlers returning null', (tester) async {
      final rootFeature = createFeature(name: "root");
      final slot = createMultiSlot<Null>(
        name: "partial",
        feature: rootFeature,
        orderDirection: MultiSlotOrderDirection.asc,
      );

      final visibleFeature = createFeature(
        name: "visible",
        dependsOn: [rootFeature],
      )..useMultiSlot(slot, (_, api) => const Text('visible'), order: 1);

      final hiddenFeature = createFeature(
        name: "hidden",
        dependsOn: [rootFeature],
      )..useMultiSlot(slot, (_, api) => null, order: 2);

      final container = await startedContainer(
        features: [rootFeature, visibleFeature, hiddenFeature],
      );

      await pumpFeature(
        tester,
        container: container,
        feature: rootFeature,
        child: MultiSlotProvider(
          slot: slot,
          data: null,
          builder: (children, _) =>
              Column(mainAxisSize: MainAxisSize.min, children: children),
        ),
      );

      expect(find.text('visible'), findsOneWidget);
    });
  });

  group('BehaviorProvider', () {
    testWidgets('renders behavior value', (tester) async {
      final rootFeature = createFeature(name: "root");
      final behavior = createBehavior<_TestBranch, String>(
        name: "test",
        feature: rootFeature,
      );

      final childFeature =
          createFeature(name: "child", dependsOn: [rootFeature])
            ..useBehavior(behavior, (api) {
              return (branch: _TestBranch.b, payload: 'overridden');
            });

      final container = await startedContainer(
        features: [rootFeature, childFeature],
      );

      await pumpFeature(
        tester,
        container: container,
        feature: rootFeature,
        child: BehaviorProvider(
          behavior: behavior,
          initialValue: BehaviorDescriptor(
            branch: _TestBranch.a,
            payload: 'default',
          ),
          builder: (result, _) => Text('${result.branch}: ${result.payload}'),
        ),
      );

      expect(find.text('_TestBranch.b: overridden'), findsOneWidget);
    });

    testWidgets('uses initialValue when no handlers', (tester) async {
      final rootFeature = createFeature(name: "root");
      final behavior = createBehavior<_TestBranch, String>(
        name: "empty",
        feature: rootFeature,
      );

      final container = await startedContainer(features: [rootFeature]);

      await pumpFeature(
        tester,
        container: container,
        feature: rootFeature,
        child: BehaviorProvider(
          behavior: behavior,
          initialValue: BehaviorDescriptor(
            branch: _TestBranch.a,
            payload: 'default',
          ),
          builder: (result, _) => Text(result.payload),
        ),
      );

      expect(find.text('default'), findsOneWidget);
    });

    testWidgets('selects highest priority handler', (tester) async {
      final rootFeature = createFeature(name: "root");
      final behavior = createBehavior<_TestBranch, String>(
        name: "priority",
        feature: rootFeature,
      );

      final lowFeature = createFeature(name: "low", dependsOn: [rootFeature])
        ..useBehavior(behavior, (api) {
          return (branch: _TestBranch.a, payload: 'low');
        }, priority: 1);

      final highFeature = createFeature(name: "high", dependsOn: [rootFeature])
        ..useBehavior(behavior, (api) {
          return (branch: _TestBranch.b, payload: 'high');
        }, priority: 10);

      final container = await startedContainer(
        features: [rootFeature, lowFeature, highFeature],
      );

      await pumpFeature(
        tester,
        container: container,
        feature: rootFeature,
        child: BehaviorProvider(
          behavior: behavior,
          initialValue: BehaviorDescriptor(
            branch: _TestBranch.a,
            payload: 'default',
          ),
          builder: (result, _) => Text(result.payload),
        ),
      );

      expect(find.text('high'), findsOneWidget);
    });
  });
}
