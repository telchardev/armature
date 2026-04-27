import 'package:armature/armature.dart';
import 'package:test/test.dart';

void main() {
  group('Port metadata', () {
    test(
      'handler set for a port is populated in the container map after start',
      () async {
        final owner = createFeature(name: "owner");
        final pipe = createPipe<int>(name: "p", feature: owner);
        final child1 = createFeature(name: "c1", dependsOn: [owner])
          ..usePipe(pipe, (v, _) => v + 1);
        final child2 = createFeature(name: "c2", dependsOn: [owner])
          ..usePipe(pipe, (v, _) => v + 2);

        final container = AppContainer(features: [owner, child1, child2]);
        addTearDown(container.stop);
        await container.start();

        final handlers = container.handlersOf(pipe);
        expect(handlers.length, equals(2));
        expect(
          handlers.keys.map((f) => f.name).toSet(),
          equals({child1.name, child2.name}),
        );
      },
    );

    test('debugInfo exposes name, type, and owner', () {
      final owner = createFeature(name: "owner");
      final pipe = createPipe<int>(name: "metric", feature: owner);

      expect(
        pipe.debugInfo,
        equals({'name': 'metric', 'type': 'pipe', 'owner': 'owner'}),
      );
    });

    test('debugInfo reports "unbound" owner for lazy-bound ports', () {
      final pipe = createPipe<int>(name: "lazy");
      expect(pipe.debugInfo['owner'], equals('unbound'));
    });
  });

  group('Port validation', () {
    test('port used in its owner feature throws PortError', () {
      final owner = createFeature(name: "owner");
      final pipe = createPipe<int>(name: "p", feature: owner);

      expect(
        () => owner.usePipe(pipe, (v, _) => v + 1),
        throwsA(isA<PortError>()),
      );
    });

    test('port used in a non-child feature throws PortError', () {
      final owner = createFeature(name: "owner");
      final pipe = createPipe<int>(name: "p", feature: owner);
      final unrelated = createFeature(name: "unrelated");

      expect(
        () => unrelated.usePipe(pipe, (v, _) => v + 1),
        throwsA(isA<PortError>()),
      );
    });

    test('port registered twice from the same feature throws PortError', () {
      final owner = createFeature(name: "owner");
      final pipe = createPipe<int>(name: "p", feature: owner);
      final child = createFeature(name: "child", dependsOn: [owner]);

      child.usePipe(pipe, (v, _) => v + 1);

      expect(
        () => child.usePipe(pipe, (v, _) => v + 2),
        throwsA(isA<PortError>()),
      );
    });

    test(
      'port used in a feature with owner as optional parent is allowed',
      () async {
        final owner = createFeature(name: "owner");
        final pipe = createPipe<int>(name: "p", feature: owner);
        final child = createFeature(name: "child", optionalDependsOn: [owner])
          ..usePipe(pipe, (v, _) => v + 10);

        final container = AppContainer(features: [owner, child]);
        addTearDown(container.stop);
        await container.start();

        final result = container.apply(
          rootFeature: owner,
          port: pipe,
          initialValue: 0,
          data: null,
        );
        expect(result, equals(10));
      },
    );

    test('port with lazy owner binds on first apply', () async {
      // createPipe without an explicit feature.
      final pipe = createPipe<int>(name: "lazy");

      final owner = createFeature(name: "owner");
      final child = createFeature(name: "child", dependsOn: [owner])
        ..usePipe(pipe, (v, _) => v + 1);

      final container = AppContainer(features: [owner, child]);
      addTearDown(container.stop);
      await container.start();

      final result = container.apply(
        rootFeature: owner,
        port: pipe,
        initialValue: 5,
        data: null,
      );
      expect(result, equals(6));
    });

    test(
      'lazy port with misconfigured pre-registered handler returns PortError '
      'on apply, keeps owner unbound, and re-reports on every retry',
      () async {
        // Port constructed without a feature: handlers added while owner is
        // unbound skip validation. When the owner finally applies, the port
        // retroactively validates — and if a pre-registered handler violates
        // the parent contract, the port stays in lazy mode so the next
        // apply repeats validation (observable-broken until source is fixed).
        final pipe = createPipe<int>(name: "lazy");
        final owner = createFeature(name: "owner");
        // `unrelated` has no `dependsOn: [owner]` — adding a handler now is
        // accepted (owner is null), but validation will fail on apply.
        final unrelated = createFeature(name: "unrelated")
          ..usePipe(pipe, (v, _) => v + 100);

        final errors = <ArmatureError>[];
        final container = AppContainer(
          features: [owner, unrelated],
          options: ContainerOptions(
            errorHandler: ({required source, required error, required meta}) {
              errors.add(error);
            },
          ),
        );
        addTearDown(container.stop);
        await container.start();

        final r1 = container.apply(
          rootFeature: owner,
          port: pipe,
          initialValue: 7,
          data: null,
        );
        expect(r1, equals(7));
        expect(errors, hasLength(1));
        expect(errors.single, isA<PortError>());
        expect(pipe.debugInfo['owner'], equals('unbound'));

        final r2 = container.apply(
          rootFeature: owner,
          port: pipe,
          initialValue: 7,
          data: null,
        );
        expect(r2, equals(7));
        expect(errors, hasLength(2));
        expect(pipe.debugInfo['owner'], equals('unbound'));
      },
    );

    test(
      'apply from a non-owner feature returns initialValue and invokes errorHandler',
      () async {
        final owner = createFeature(name: "owner");
        final pipe = createPipe<int>(name: "p", feature: owner);
        final other = createFeature(name: "other");

        ArmatureError? captured;
        final container = AppContainer(
          features: [owner, other],
          options: ContainerOptions(
            errorHandler: ({required source, required error, required meta}) {
              captured = error;
            },
          ),
        );
        addTearDown(container.stop);
        await container.start();

        final result = container.apply(
          rootFeature: other,
          port: pipe,
          initialValue: 42,
          data: null,
        );

        expect(result, equals(42));
        expect(captured, isA<PortError>());
      },
    );
  });
}
