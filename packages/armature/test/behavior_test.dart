import 'package:armature/armature.dart';
import 'package:test/test.dart';

enum TestFeatureBranches { first, second, third }

void main() {
  group('Behavior', () {
    test('apply() should override behavior from a dependent feature', () async {
      final behaviorFeature = createFeature(name: "behaviorFeature");

      final behavior = createBehavior<TestFeatureBranches, Null>(
        name: "behavior",
        feature: behaviorFeature,
      );

      final firstFeature = createFeature(
        name: "firstFeature",
        dependsOn: [behaviorFeature],
      );

      firstFeature.useBehavior(behavior, (api) {
        return (branch: TestFeatureBranches.second, payload: null);
      });

      final container = AppContainer(features: [behaviorFeature, firstFeature]);
      addTearDown(container.dispose);
      await container.start();

      final result = container.apply(
        rootFeature: behaviorFeature,
        port: behavior,
        initialValue: BehaviorDescriptor(
          branch: TestFeatureBranches.first,
          payload: null,
        ),
        data: null,
      );

      expect(result.branch, equals(TestFeatureBranches.second));
    });

    test(
      'apply() should override behavior from dependent features by priority',
      () async {
        final behaviorFeature = createFeature(name: "behaviorFeature");

        final behavior = createBehavior<TestFeatureBranches, Null>(
          name: "behavior",
          feature: behaviorFeature,
        );

        final firstFeature = createFeature(
          name: "firstFeature",
          dependsOn: [behaviorFeature],
        );

        firstFeature.useBehavior(behavior, (api) {
          return (branch: TestFeatureBranches.second, payload: null);
        }, priority: 1);

        final secondFeature = createFeature(
          name: "secondFeature",
          dependsOn: [behaviorFeature],
        );

        secondFeature.useBehavior(behavior, (api) {
          return (branch: TestFeatureBranches.third, payload: null);
        }, priority: 2);

        final container = AppContainer(
          features: [behaviorFeature, firstFeature, secondFeature],
        );
        addTearDown(container.dispose);
        await container.start();

        final result = container.apply(
          rootFeature: behaviorFeature,
          port: behavior,
          initialValue: BehaviorDescriptor(
            branch: TestFeatureBranches.first,
            payload: null,
          ),
          data: null,
        );

        expect(result.branch, equals(TestFeatureBranches.third));
      },
    );

    test('should return initialValue when no handlers', () async {
      final root = createFeature(name: "root");
      final behavior = createBehavior<TestFeatureBranches, Null>(
        name: "empty",
        feature: root,
      );
      final container = AppContainer(features: [root]);
      addTearDown(container.dispose);
      await container.start();

      final initial = BehaviorDescriptor(
        branch: TestFeatureBranches.first,
        payload: null,
      );

      final result = container.apply(
        rootFeature: root,
        port: behavior,
        initialValue: initial,
        data: null,
      );

      expect(result, same(initial));
    });

    test('first handler wins on equal priority', () async {
      final root = createFeature(name: "root");
      final behavior = createBehavior<TestFeatureBranches, Null>(
        name: "tied",
        feature: root,
      );

      final feature1 = createFeature(name: "f1", dependsOn: [root]);
      feature1.useBehavior(behavior, (api) {
        return (branch: TestFeatureBranches.second, payload: null);
      }, priority: 1);

      final feature2 = createFeature(name: "f2", dependsOn: [root]);
      feature2.useBehavior(behavior, (api) {
        return (branch: TestFeatureBranches.third, payload: null);
      }, priority: 1);

      final container = AppContainer(features: [root, feature1, feature2]);
      addTearDown(container.dispose);
      await container.start();

      final result = container.apply(
        rootFeature: root,
        port: behavior,
        initialValue: BehaviorDescriptor(
          branch: TestFeatureBranches.first,
          payload: null,
        ),
        data: null,
      );

      expect(result.branch, equals(TestFeatureBranches.second));
    });

    test('all handlers returning null falls back to initialValue', () async {
      final root = createFeature(name: "root");
      final behavior = createBehavior<TestFeatureBranches, Null>(
        name: "all-null",
        feature: root,
      );

      final f1 = createFeature(name: "f1", dependsOn: [root]);
      f1.useBehavior(behavior, (_) => null);
      final f2 = createFeature(name: "f2", dependsOn: [root]);
      f2.useBehavior(behavior, (_) => null);

      final container = AppContainer(features: [root, f1, f2]);
      addTearDown(container.dispose);
      await container.start();

      final initial = BehaviorDescriptor(
        branch: TestFeatureBranches.first,
        payload: null,
      );
      final result = container.apply(
        rootFeature: root,
        port: behavior,
        initialValue: initial,
        data: null,
      );
      expect(result, same(initial));
    });

    test('disabled handler feature is skipped', () async {
      final root = createFeature(name: "root");
      final behavior = createBehavior<TestFeatureBranches, Null>(
        name: "skip-disabled",
        feature: root,
      );

      final enabled = createFeature(name: "on", dependsOn: [root])
        ..useBehavior(
          behavior,
          (_) => (branch: TestFeatureBranches.second, payload: null),
          priority: 1,
        );
      final gated = createFeature(name: "off", dependsOn: [root])
        ..activation((_, _, _) {}); // never activates
      gated.useBehavior(
        behavior,
        (_) => (branch: TestFeatureBranches.third, payload: null),
        priority: 10,
      );

      final container = AppContainer(features: [root, enabled, gated]);
      addTearDown(container.dispose);
      await container.start();

      final result = container.apply(
        rootFeature: root,
        port: behavior,
        initialValue: BehaviorDescriptor(
          branch: TestFeatureBranches.first,
          payload: null,
        ),
        data: null,
      );
      // gated is disabled — high-priority handler ignored.
      expect(result.branch, equals(TestFeatureBranches.second));
    });

    test('handler returning null is skipped', () async {
      final root = createFeature(name: "root");
      final behavior = createBehavior<TestFeatureBranches, Null>(
        name: "nullable",
        feature: root,
      );

      final feature1 = createFeature(name: "f1", dependsOn: [root]);
      feature1.useBehavior(behavior, (api) {
        return null;
      });

      final container = AppContainer(features: [root, feature1]);
      addTearDown(container.dispose);
      await container.start();

      final initial = BehaviorDescriptor(
        branch: TestFeatureBranches.first,
        payload: null,
      );

      final result = container.apply(
        rootFeature: root,
        port: behavior,
        initialValue: initial,
        data: null,
      );

      expect(result, same(initial));
    });
  });
}
