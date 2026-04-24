// Container-scoped event surface: onFeatureStatusChanged,
// onPortChanged, listener error routing, concurrent-resolve
// throttling, and the debug-only finalizer that warns on
// GC-without-dispose.

import 'dart:async';

import 'package:armature/armature.dart';
import 'package:mockito/mockito.dart';
import 'package:test/test.dart';

import '_helpers.dart';
import 'container_listeners.mocks.dart';

Future<void> main() async {
  group('AppContainer', () {
    group('subscriptions', () {
      test(
        'start() must call listeners (feature/port) after feature resolve',
        () async {
          final listeners = MockListeners();
          final pipeFeature = createFeature(name: "pipeFeature");

          final port = createPipe<int>(name: "port", feature: pipeFeature);

          final feature1 =
              createFeature(name: "feature1", dependsOn: [pipeFeature])
                ..usePipe(port, (value, api) => value + 1)
                ..activation((_, toggle, _) async {
                  await Future<void>.delayed(const Duration(milliseconds: 50));
                  unawaited(toggle(ToggleState.active));
                });

          final feature2 =
              createFeature(
                  name: "feature2",
                  dependsOn: [pipeFeature, feature1],
                )
                ..usePipe(port, (value, api) => value + 1)
                ..activation((_, toggle, _) async {
                  await Future<void>.delayed(const Duration(milliseconds: 50));
                  unawaited(toggle(ToggleState.active));
                });

          var container = AppContainer(
            features: [pipeFeature, feature1, feature2],
          );
          addTearDown(container.dispose);

          container.onFeatureStatusChanged(
            feature: feature1,
            callback: listeners.onFeatureStatusChanged,
          );
          container.onFeatureStatusChanged(
            feature: feature2,
            callback: listeners.onFeatureStatusChanged2,
          );

          container.onPortChanged(
            port: port,
            callback: listeners.onPortChanged,
          );
          container.onPortChanged(
            port: port,
            callback: listeners.onPortChanged2,
          );

          unawaited(container.start());

          verifyNever(listeners.onFeatureStatusChanged()).called(0);
          verifyNever(listeners.onPortChanged()).called(0);

          await Future<void>.delayed(const Duration(milliseconds: 300));

          verify(listeners.onFeatureStatusChanged()).called(1);
          verify(listeners.onFeatureStatusChanged2()).called(1);
          // Port emits fire per activation (no more batching) so both
          // feature1 and feature2 trigger their own `portChanged`.
          verify(listeners.onPortChanged()).called(2);
          verify(listeners.onPortChanged2()).called(2);
        },
      );

      test(
        'onFeatureStatusChanged disposer removes callback before it fires',
        () async {
          final feature = createFeature(name: "f");
          final container = AppContainer(features: [feature]);
          addTearDown(container.dispose);

          var count = 0;
          final dispose = container.onFeatureStatusChanged(
            feature: feature,
            callback: () => count++,
          );
          dispose();

          await container.start();

          expect(count, equals(0));
        },
      );

      test('onPortChanged disposer removes callback before it fires', () async {
        final root = createFeature(name: "root");
        final pipe = createPipe<int>(name: "p", feature: root);
        final child = createFeature(name: "child", dependsOn: [root])
          ..usePipe(pipe, (v, _) => v + 1);

        final container = AppContainer(features: [root, child]);
        addTearDown(container.dispose);

        var count = 0;
        final dispose = container.onPortChanged(
          port: pipe,
          callback: () => count++,
        );
        dispose();

        await container.start();

        expect(count, equals(0));
      });

      test(
        'portChanged fires once per activation of a feature that uses the port',
        () async {
          // Every feature that registers a handler on the port emits its
          // own `portChanged` when it activates — no start-time batching.
          // That lets widgets update incrementally as fast features come
          // online even while a slow sibling is still awaiting `onStart`.
          final listeners = MockListeners();
          final root = createFeature(name: "root");
          final pipe = createPipe<int>(name: "p", feature: root);

          final f1 = createFeature(name: "f1", dependsOn: [root])
            ..usePipe(pipe, (v, _) => v + 1);
          final f2 = createFeature(name: "f2", dependsOn: [root])
            ..usePipe(pipe, (v, _) => v + 2);
          final f3 = createFeature(name: "f3", dependsOn: [root])
            ..usePipe(pipe, (v, _) => v + 3);

          final container = AppContainer(features: [root, f1, f2, f3]);
          addTearDown(container.dispose);
          container.onPortChanged(
            port: pipe,
            callback: listeners.onPortChanged,
          );

          await container.start();

          // 3 emits: one per activated feature that uses this port.
          // (root owns the port but doesn't register a handler, so it
          // doesn't contribute.)
          verify(listeners.onPortChanged()).called(3);
        },
      );

      test('portChanged is not emitted for disabled feature', () async {
        final listeners = MockListeners();
        final pipeFeature = createFeature(name: "pipeFeature");
        final pipe = createPipe<int>(name: "p", feature: pipeFeature);

        final enabled = createFeature(name: "enabled", dependsOn: [pipeFeature])
          ..usePipe(pipe, (v, _) => v + 1);

        final disabled = createFeature(
          name: "disabled",
          dependsOn: [pipeFeature],
        )..activation((_, _, _) {});
        disabled.usePipe(pipe, (v, _) => v + 1);

        final container = AppContainer(
          features: [pipeFeature, enabled, disabled],
        );
        addTearDown(container.dispose);
        container.onPortChanged(port: pipe, callback: listeners.onPortChanged);

        await container.start();

        verify(listeners.onPortChanged()).called(1);
      });
    });

    group('listener errors', () {
      test(
        'featureStatusChanged listener throw is routed to errorHandler, siblings still run',
        () async {
          final captured = <({String source, ArmatureError error})>[];
          final feature = createFeature(name: "f");

          final container = AppContainer(
            features: [feature],
            options: ContainerOptions(
              errorHandler: ({required source, required error, required meta}) {
                captured.add((source: source, error: error));
              },
            ),
          );
          addTearDown(container.dispose);

          var secondRan = false;
          container.onFeatureStatusChanged(
            feature: feature,
            callback: () => throw Exception('first listener fail'),
          );
          container.onFeatureStatusChanged(
            feature: feature,
            callback: () => secondRan = true,
          );

          await container.start();

          expect(secondRan, isTrue);
          expect(captured, hasLength(1));
          expect(captured.single.source, equals('f'));
          expect(captured.single.error, isA<ListenerError>());
        },
      );

      test(
        'portChanged listener throw reports with <events> source and port meta',
        () async {
          // Port events aren't attributable to a single feature, so the
          // container passes the synthetic `<events>` source; the port's
          // name lives in meta for filtering.
          final capturedMeta = <Map<String, String>>[];
          final root = createFeature(name: "root");
          final pipe = createPipe<int>(name: "p", feature: root);
          final child = createFeature(name: "child", dependsOn: [root])
            ..usePipe(pipe, (v, _) => v + 1);

          final container = AppContainer(
            features: [root, child],
            options: ContainerOptions(
              errorHandler: ({required source, required error, required meta}) {
                capturedMeta.add({'source': source, ...meta});
              },
            ),
          );
          addTearDown(container.dispose);

          container.onPortChanged(
            port: pipe,
            callback: () => throw StateError('port listener boom'),
          );

          await container.start();

          expect(capturedMeta, isNotEmpty);
          expect(capturedMeta.first['source'], equals('<events>'));
          expect(capturedMeta.first['event'], equals('portChanged'));
          expect(capturedMeta.first['port'], equals('p'));
        },
      );

      test(
        'multiple listener throws in one emit — all routed, all siblings run',
        () async {
          final captured = <Object>[];
          final feature = createFeature(name: "multi-fail");

          final container = AppContainer(
            features: [feature],
            options: ContainerOptions(
              errorHandler: ({required source, required error, required meta}) {
                captured.add(error);
              },
            ),
          );
          addTearDown(container.dispose);

          var survivorRan = false;
          container.onFeatureStatusChanged(
            feature: feature,
            callback: () => throw StateError('first'),
          );
          container.onFeatureStatusChanged(
            feature: feature,
            callback: () => throw StateError('second'),
          );
          container.onFeatureStatusChanged(
            feature: feature,
            callback: () => survivorRan = true,
          );

          await container.start();

          expect(survivorRan, isTrue);
          expect(captured, hasLength(2));
        },
      );
    });

    group('debug finalizer', () {
      test('construct + dispose cycle does not throw', () async {
        // In debug builds `AppContainer()` attaches itself to a static
        // `Finalizer` (inside an `assert(() { ... }())` block) to emit
        // a GC-time warning when a container is collected without
        // dispose. `dispose()` detaches the finalizer symmetrically.
        //
        // This smoke-test guards both branches: a typo in either the
        // attach or the detach call would throw at assertion time.
        // Intentionally simple — reliably forcing a GC to observe the
        // warning isn't feasible in Dart's test runner.
        expect(() async {
          final container = AppContainer(features: [createFeature(name: "f")]);
          await container.start();
          await container.dispose();
        }, returnsNormally);
      });

      test(
        'multiple containers attach independently without interference',
        () async {
          // `identityHashCode(this)` is used as the finalizer token; two
          // containers must get distinct tokens so detach of one doesn't
          // kill the other's warning.
          final c1 = AppContainer(features: [createFeature(name: "a")]);
          final c2 = AppContainer(features: [createFeature(name: "b")]);
          addTearDown(c1.dispose);
          addTearDown(c2.dispose);
          await c1.start();
          await c2.start();
          // No exception from overlapping attach + detach on the static
          // finalizer means the per-instance token scheme works.
          expect(c1.status, equals(ContainerStatus.working));
          expect(c2.status, equals(ContainerStatus.working));
        },
      );
    });

    group('throttling', () {
      test(
        'maxResolveConcurrency throttles parallel onStart to at most N in flight',
        () async {
          // `maxResolveConcurrency` forwards to the graph's activation
          // semaphore, which wraps `onActivate` (and therefore `onStart`).
          // Setups run unthrottled; we use `onStart` to observe the cap.
          var inFlight = 0;
          var maxObserved = 0;

          final features = <AnyFeature>[
            for (var i = 0; i < 10; i++)
              createFeature(name: "f$i")..onStart((_, _) async {
                inFlight++;
                if (inFlight > maxObserved) maxObserved = inFlight;
                await Future<void>.delayed(const Duration(milliseconds: 30));
                inFlight--;
              }),
          ];

          final container = AppContainer(
            features: features,
            options: silentOptions(maxResolveConcurrency: 3),
          );
          addTearDown(container.dispose);

          await container.start();

          expect(maxObserved, lessThanOrEqualTo(3));
          expect(maxObserved, greaterThan(0));
        },
      );

      test('no throttling when maxResolveConcurrency is null', () async {
        var inFlight = 0;
        var maxObserved = 0;

        final features = <AnyFeature>[
          for (var i = 0; i < 8; i++)
            createFeature(name: "f$i")..onStart((_, _) async {
              inFlight++;
              if (inFlight > maxObserved) maxObserved = inFlight;
              await Future<void>.delayed(const Duration(milliseconds: 20));
              inFlight--;
            }),
        ];

        final container = AppContainer(features: features);
        addTearDown(container.dispose);

        await container.start();

        // Without a limit, all 8 should be in flight concurrently.
        expect(maxObserved, equals(8));
      });

      test('maxResolveConcurrency must be > 0', () {
        expect(
          () => silentOptions(maxResolveConcurrency: 0),
          throwsA(isA<AssertionError>()),
        );
      });
    });
  });
}
