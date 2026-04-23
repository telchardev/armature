import 'package:armature/armature.dart';
import 'package:test/test.dart';

import '_helpers.dart';

void main() {
  group('ContainerDebug', () {
    test('debug snapshot mirrors live graph after start', () async {
      final parent = createFeature(name: "parent");
      final child = createFeature(name: "child", dependsOn: [parent]);
      final container = await startedContainer(features: [parent, child]);

      final snapshot = container.debug;

      expect(snapshot.features.map((f) => f.name), equals(['parent', 'child']));
      expect(
        snapshot.features.first.dependencies,
        isEmpty,
        reason: 'parent has no deps',
      );
      expect(
        snapshot.features.last.dependencies.map((d) => d.featureName),
        equals(['parent']),
      );
    });

    test('debug throws ContainerUsageError before start', () {
      final container = AppContainer(features: [createFeature(name: "f")]);
      addTearDown(container.dispose);

      // Graph is not built yet — the underlying `graph` getter surfaces
      // the same ContainerUsageError; debug extension is transparent.
      expect(() => container.debug, throwsA(isA<ContainerUsageError>()));
    });

    test('debug throws ContainerUsageError after dispose', () async {
      // After dispose, the internal graph reference is kept (only
      // `resetForRestart: true` drops it), so we need an explicit guard
      // — otherwise `debug` would return a stale snapshot of a torn-down
      // container. This test pins the explicit-throw behaviour.
      final container = await startedContainer(
        features: [createFeature(name: "f")],
      );
      await container.dispose();

      expect(() => container.debug, throwsA(isA<ContainerUsageError>()));
    });
  });
}
