import 'package:armature/armature.dart';
import 'package:test/test.dart';

void main() {
  group('Pipe', () {
    test('apply', () async {
      final pipeFeature = createFeature(name: "pipeFeature");

      final intPipe = createPipe<int>(name: "one", feature: pipeFeature);

      final firstFeature = createFeature(
        name: "firstFeature",
        dependsOn: [pipeFeature],
      );

      firstFeature.usePipe(intPipe, (value, api) {
        return value + 1;
      });

      final secondFeature = createFeature(
        name: "secondFeature",
        dependsOn: [firstFeature, pipeFeature],
      );

      secondFeature.usePipe(intPipe, (value, api) {
        return value + 1;
      });

      var container = AppContainer(
        features: [pipeFeature, firstFeature, secondFeature],
      );
      addTearDown(container.stop);

      await container.start();

      expect(
        container.apply(
          rootFeature: pipeFeature,
          port: intPipe,
          initialValue: 0,
          data: null,
        ),
        equals(2),
      );
    });

    test('apply should skip disabled features', () async {
      final pipeFeature = createFeature(name: "pipeFeature");

      final intPipe = createPipe<int>(name: "one", feature: pipeFeature);

      final firstFeature = createFeature(
        name: "firstFeature",
        dependsOn: [pipeFeature],
      );

      firstFeature.usePipe(intPipe, (value, api) {
        return value + 1;
      });

      final secondFeature = createFeature(
        name: "secondFeature",
        dependsOn: [firstFeature, pipeFeature],
      )..activation((_, _, _) {});

      secondFeature.usePipe(intPipe, (value, api) {
        return value + 1;
      });

      var container = AppContainer(
        features: [pipeFeature, firstFeature, secondFeature],
      );
      addTearDown(container.stop);

      await container.start();

      expect(
        container.apply(
          rootFeature: pipeFeature,
          port: intPipe,
          initialValue: 0,
          data: null,
        ),
        equals(1),
      );
    });

    test('handlers are applied in registration order', () async {
      final root = createFeature(name: "root");
      final pipe = createPipe<int>(name: "order", feature: root);

      final a = createFeature(name: "a", dependsOn: [root])
        ..usePipe(pipe, (v, _) => v * 2);
      final b = createFeature(name: "b", dependsOn: [root])
        ..usePipe(pipe, (v, _) => v + 5);

      final container = AppContainer(features: [root, a, b]);
      addTearDown(container.stop);
      await container.start();

      // (1 * 2) + 5 == 7.
      expect(
        container.apply(
          rootFeature: root,
          port: pipe,
          initialValue: 1,
          data: null,
        ),
        equals(7),
      );
    });

    test('should return initialValue when no handlers registered', () async {
      final root = createFeature(name: "root");
      final pipe = createPipe<int>(name: "empty", feature: root);
      final container = AppContainer(features: [root]);
      addTearDown(container.stop);
      await container.start();

      final result = container.apply(
        rootFeature: root,
        port: pipe,
        initialValue: 42,
        data: null,
      );

      expect(result, equals(42));
    });
  });
}
