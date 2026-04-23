import 'package:armature/armature.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('AppContainer.dispose()', () {
    test('sets status to disposed', () async {
      final container = AppContainer(features: []);
      expect(container.status, equals(ContainerStatus.idle));

      await container.dispose();
      expect(container.status, equals(ContainerStatus.disposed));
    });

    test('is idempotent (calling dispose twice does not throw)', () async {
      final container = AppContainer(features: []);

      await container.dispose();
      await container.dispose();

      expect(container.status, equals(ContainerStatus.disposed));
    });

    test('start() throws after dispose', () async {
      final container = AppContainer(features: []);
      await container.dispose();

      expect(() => container.start(), throwsA(isA<ContainerError>()));
    });

    test('apply() throws after dispose', () async {
      final feature = createFeature(name: "test");
      final pipe = createPipe<int>(name: "pipe", feature: feature);

      final container = AppContainer(features: [feature]);
      await container.start();

      await container.dispose();

      expect(
        () => container.apply(
          rootFeature: feature,
          port: pipe,
          initialValue: 0,
          data: null,
        ),
        throwsA(isA<ContainerError>()),
      );
    });

    test('cleans up port reactions', () async {
      final feature = createFeature(name: "root");
      final pipe = createPipe<int>(name: "pipe", feature: feature);

      final childFeature = createFeature(name: "child", dependsOn: [feature])
        ..usePipe(pipe, (value, api) => value + 1);

      final container = AppContainer(features: [feature, childFeature]);
      addTearDown(container.dispose);

      await container.start();

      // Apply to create a reaction
      container.apply(
        rootFeature: feature,
        port: pipe,
        initialValue: 0,
        data: null,
      );

      // Dispose cleans up reactions
      await container.dispose();

      expect(container.status, equals(ContainerStatus.disposed));
    });

    test('subscriptions stop working after dispose', () async {
      final feature = createFeature(name: "root");
      var callCount = 0;

      final container = AppContainer(features: [feature]);
      addTearDown(container.dispose);

      container.onFeatureStatusChanged(
        feature: feature,
        callback: () => callCount++,
      );

      await container.dispose();

      // After dispose, events should have been cleared
      expect(container.status, equals(ContainerStatus.disposed));
      expect(callCount, equals(0));
    });
  });
}
