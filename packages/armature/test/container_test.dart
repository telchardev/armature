import 'dart:async';

import 'package:armature/armature.dart';
import 'package:mockito/mockito.dart';
import 'package:test/test.dart';

import '_helpers.dart';
import 'container_listeners.mocks.dart';

/// Store that increments a counter on dispose — used to verify that
/// eager-constructed stores of OTHER features are disposed when the
/// construct phase aborts fail-fast partway through.
class _DisposeCounter extends Store<int> {
  int disposeCount;
  _DisposeCounter() : disposeCount = 0, super(state: 0);

  @override
  void dispose() {
    disposeCount++;
    super.dispose();
  }
}

Future<void> main() async {
  group('AppContainer', () {
    group('dependencies & resolve', () {
      test(
        'start() should check dependencies and start running features',
        () async {
          final firstFeature = createFeature(name: "firstFeature");

          final secondFeature = createFeature(
            name: "secondFeature",
            dependsOn: [firstFeature],
          );

          var container = AppContainer(features: [secondFeature]);
          addTearDown(container.dispose);

          await expectLater(container.start, throwsA(isA<ArmatureError>()));
        },
      );

      test('start() complex feature graph', () async {
        final feature1 = createFeature(name: "feature1");

        final feature2 = createFeature(name: "feature2", dependsOn: [feature1])
          ..activation((_, _, _) {});

        final feature3 = createFeature(name: "feature3", dependsOn: [feature2]);

        final feature4 = createFeature(
          name: "feature4",
          dependsOn: [feature1],
          optionalDependsOn: [feature3],
        );

        final feature5 = createFeature(name: "feature5", dependsOn: [feature3]);

        final feature6 = createFeature(
          name: "feature6",
          optionalDependsOn: [feature5],
        );

        final feature7 = createFeature(name: "feature7");

        final feature8 = createFeature(
          name: "feature8",
          optionalDependsOn: [feature7],
        );

        final feature9 = createFeature(name: "feature9", dependsOn: [feature8])
          ..activation((_, _, _) {});

        final feature10 = createFeature(
          name: "feature10",
          dependsOn: [feature8],
        );

        final feature11 = createFeature(
          name: "feature11",
          dependsOn: [feature1],
          optionalDependsOn: [feature9],
        );

        final feature12 = createFeature(
          name: "feature12",
          dependsOn: [feature11, feature6],
          optionalDependsOn: [feature5],
        );

        final feature13 = createFeature(
          name: "feature13",
          dependsOn: [feature12],
        );

        final feature14 = createFeature(
          name: "feature14",
          dependsOn: [feature5, feature13],
        );

        final feature15 = createFeature(
          name: "feature15",
          dependsOn: [feature14],
        );

        var container = AppContainer(
          features: [
            feature1,
            feature2,
            feature3,
            feature4,
            feature5,
            feature6,
            feature7,
            feature8,
            feature9,
            feature10,
            feature11,
            feature12,
            feature13,
            feature14,
            feature15,
          ],
        );
        addTearDown(container.dispose);

        await container.start();

        expect(container.statusOf(feature1) == FeatureStatus.active, isTrue);
        expect(container.statusOf(feature15) == FeatureStatus.active, isFalse);
      });

      test('should handle async activation setup that never starts', () async {
        final feature = createFeature(name: "asyncDisabled")
          ..activation((_, _, _) async {
            await Future<void>.delayed(const Duration(milliseconds: 10));
            // Never calls ctrl.start — feature stays inactive.
          });

        final container = AppContainer(features: [feature]);
        addTearDown(container.dispose);
        await container.start();

        expect(container.statusOf(feature) == FeatureStatus.active, isFalse);
      });
    });

    group('start / dispose lifecycle', () {
      test('transitions to .working after successful start', () async {
        final feature = createFeature(name: "root");
        final container = AppContainer(features: [feature]);
        addTearDown(container.dispose);

        expect(container.status, equals(ContainerStatus.idle));

        await container.start();

        expect(container.status, equals(ContainerStatus.working));
      });

      test('should throw when called twice on working container', () async {
        final container = AppContainer(features: [createFeature(name: "f")]);
        addTearDown(container.dispose);
        await container.start();

        await expectLater(container.start, throwsA(isA<ContainerError>()));
      });

      test('should throw when called concurrently', () async {
        final feature = createFeature(name: "slow")
          ..activation((_, toggle, _) async {
            await Future<void>.delayed(const Duration(milliseconds: 100));
            unawaited(toggle(ToggleState.active));
          });

        final container = AppContainer(features: [feature]);
        addTearDown(container.dispose);
        final firstStart = container.start();

        await expectLater(container.start, throwsA(isA<ContainerError>()));

        await firstStart;
      });

      test('start() after dispose throws ContainerError', () async {
        final feature = createFeature(name: "f");
        final container = AppContainer(features: [feature]);
        await container.start();
        await container.dispose();

        await expectLater(container.start, throwsA(isA<ContainerError>()));
      });

      test('dispose() is idempotent', () async {
        final feature = createFeature(name: "f");
        final container = AppContainer(features: [feature]);
        await container.start();

        await container.dispose();
        await container.dispose();
        expect(container.status, equals(ContainerStatus.disposed));
      });

      test('dispose() clears features and resolveTimes', () async {
        final feature = createFeature(name: "f");
        final container = AppContainer(features: [feature]);
        await container.start();

        expect(container.resolveTimes, isNotEmpty);

        await container.dispose();

        expect(container.resolveTimes, isEmpty);
      });

      test('dispose during throttled resolve does not hang', () async {
        final features = <AnyFeature>[
          for (var i = 0; i < 10; i++)
            createFeature(name: "f$i")..activation((_, toggle, _) async {
              await Future<void>.delayed(const Duration(milliseconds: 100));
              unawaited(toggle(ToggleState.active));
            }),
        ];

        final container = AppContainer(
          features: features,
          options: silentOptions(maxResolveConcurrency: 2),
        );

        final startFuture = container.start();
        await Future<void>.delayed(const Duration(milliseconds: 10));
        unawaited(container.dispose());

        // start() must complete in reasonable time — not hang forever.
        await startFuture.timeout(const Duration(seconds: 2));
        expect(container.status, equals(ContainerStatus.disposed));
      });

      test(
        'dispose removes port handlers from shared top-level port',
        () async {
          final shared = createPipe<int>(name: "shared");
          final holder = createFeature(name: "holder")
            ..usePipe(shared, (v, _) => v + 1);
          final container = AppContainer(features: [holder]);
          await container.start();
          expect(shared.handlerCount, equals(1));

          await container.dispose();

          expect(
            shared.handlerCount,
            equals(0),
            reason:
                'dispose deregisters handlers to prevent leaks across '
                'container instances',
          );
        },
      );
    });

    group('rollback', () {
      test('rolls back to .idle on missing-dependency error', () async {
        final parent = createFeature(name: "parent");
        final child = createFeature(name: "child", dependsOn: [parent]);

        // child depends on parent, but parent is not added
        final container = AppContainer(features: [child]);
        addTearDown(container.dispose);

        expect(container.status, equals(ContainerStatus.idle));

        await expectLater(
          container.start,
          throwsA(isA<FeatureResolutionError>()),
        );

        expect(container.status, equals(ContainerStatus.idle));
      });

      test('can retry start() after rolled-back error', () async {
        final parent = createFeature(name: "parent");
        final child = createFeature(name: "child", dependsOn: [parent]);

        final container = AppContainer(features: [child]);
        addTearDown(container.dispose);

        // First attempt fails.
        await expectLater(
          container.start,
          throwsA(isA<FeatureResolutionError>()),
        );
        expect(container.status, equals(ContainerStatus.idle));

        // Second attempt is allowed — rollback cleared `.starting`.
        await expectLater(
          container.start,
          throwsA(isA<FeatureResolutionError>()),
        );
      });

      test('failed start rolls back resolveTimes to empty', () async {
        final container = AppContainer(
          features: [
            createFeature(
              name: "orphan",
              dependsOn: [createFeature(name: "missing")],
            ),
          ],
        );
        addTearDown(container.dispose);

        await expectLater(
          container.start,
          throwsA(isA<FeatureResolutionError>()),
        );
        // Polished rollback wipes per-attempt telemetry so a retry sees
        // a clean slate.
        expect(container.resolveTimes, isEmpty);
        expect(container.status, equals(ContainerStatus.idle));
      });

      test('failed start resets feature.ownActive to default', () async {
        // Feature with an activation setup defaults to ownActive=false.
        // If something else in the same start attempt fails, the
        // polished rollback should restore that default so a retry
        // doesn't pick up a half-toggled flag.
        final setupFeature = createFeature(name: "setup-feature")
          ..activation((_, toggle, _) async {
            await toggle(ToggleState.active);
          });
        final orphan = createFeature(
          name: "orphan",
          dependsOn: [createFeature(name: "never-registered")],
        );

        final container = AppContainer(features: [setupFeature, orphan]);
        addTearDown(container.dispose);

        await expectLater(
          container.start,
          throwsA(isA<FeatureResolutionError>()),
        );
        expect(container.status, equals(ContainerStatus.idle));
        expect(setupFeature.internal.ownActive, isFalse);
      });

      test('failed start preserves port handlers for retry', () async {
        // Handlers are registered statically at feature-creation via
        // `usePipe` (before any container). Rollback must NOT strip
        // them — a retry reuses the same feature instances and expects
        // their handlers to still be attached.
        final shared = createPipe<int>(name: "shared");
        final healthy = createFeature(name: "healthy")
          ..usePipe(shared, (v, _) => v + 1);
        final orphan = createFeature(
          name: "orphan",
          dependsOn: [createFeature(name: "missing")],
        );

        final container = AppContainer(
          features: [healthy, orphan],
          options: silentOptions(),
        );
        addTearDown(container.dispose);

        await expectLater(
          container.start,
          throwsA(isA<FeatureResolutionError>()),
        );

        expect(
          shared.handlerCount,
          equals(1),
          reason: 'rollback must keep handlers so retry sees them',
        );
      });

      test(
        'failed start disposes services built before the failing factory',
        () async {
          _DisposeCounter? disposeCounter;
          final healthy = createFeature(
            name: "healthy",
            stores: (_) {
              // Construct the service INSIDE the factory so
              // `Store.track` picks it up and the orchestrator-layer
              // teardown can dispose it.
              disposeCounter = _DisposeCounter();
              return (counter: disposeCounter!);
            },
            exports: (api) => api.own,
          );
          final bad = createFeature(
            name: "bad",
            dependsOn: [healthy],
            stores: (_) => throw StateError('boom'),
            exports: (api) => api.own,
          );

          final container = AppContainer(
            features: [healthy, bad],
            options: silentOptions(),
          );
          addTearDown(container.dispose);

          await expectLater(
            container.start,
            throwsA(isA<FeatureResolutionError>()),
          );

          expect(
            disposeCounter?.disposeCount,
            equals(1),
            reason:
                'services built before the failing factory must be '
                'disposed by the rollback path',
          );
        },
      );

      test(
        'useStores allows re-override after a rolled-back failed start',
        () async {
          var useBadFactory = true;
          final feature = createFeature<void, void, void>(
            name: "badServices",
            stores: (_) {
              if (useBadFactory) throw Exception('services factory failed');
            },
            exports: (api) => api.own,
          );

          final container = AppContainer(
            features: [feature],
            options: silentOptions(),
          );
          addTearDown(container.dispose);

          // First start fails fail-fast; polished rollback clears the
          // cached `_scopeApi`, so a subsequent `useStores` override
          // is allowed and the next start can succeed.
          await expectLater(
            container.start,
            throwsA(isA<FeatureResolutionError>()),
          );
          expect(container.status, equals(ContainerStatus.idle));

          useBadFactory = false;
          feature.useStores((_) {});

          await container.start();
          expect(container.status, equals(ContainerStatus.working));
        },
      );
    });

    group('reentrance', () {
      test(
        'dispose() called from within an activation setup rejects with ContainerUsageError',
        () async {
          late AppContainer container;
          Object? capturedError;
          final feature = createFeature(name: "self-dispose-setup")
            ..activation((_, _, _) async {
              try {
                await container.dispose();
              } on Object catch (e) {
                capturedError = e;
              }
            });

          container = AppContainer(features: [feature]);
          await container.start().timeout(const Duration(seconds: 2));

          expect(capturedError, isA<ContainerUsageError>());
          expect(container.status, equals(ContainerStatus.working));
          await container.dispose();
          expect(container.status, equals(ContainerStatus.disposed));
        },
      );

      test(
        'dispose() called from within onStart rejects with ContainerUsageError',
        () async {
          late AppContainer container;
          Object? capturedError;
          final feature = createFeature(name: "self-dispose-onStart")
            ..onStart((_, _) async {
              try {
                await container.dispose();
              } on Object catch (e) {
                capturedError = e;
              }
            });

          container = AppContainer(features: [feature]);
          await container.start().timeout(const Duration(seconds: 2));

          expect(capturedError, isA<ContainerUsageError>());
          expect(container.status, equals(ContainerStatus.working));
          await container.dispose();
          expect(container.status, equals(ContainerStatus.disposed));
        },
      );

      test(
        'concurrent dispose() calls during in-flight start collapse to same future',
        () async {
          final slow = createFeature(name: "slow")
            ..activation((_, toggle, _) async {
              await Future<void>.delayed(const Duration(milliseconds: 80));
              unawaited(toggle(ToggleState.active));
            });
          final container = AppContainer(features: [slow]);

          final startFuture = container.start();
          await Future<void>.delayed(const Duration(milliseconds: 20));

          final d1 = container.dispose();
          final d2 = container.dispose();
          expect(
            identical(d1, d2),
            isTrue,
            reason: 'dispose() is idempotent — two calls share one future',
          );

          await startFuture.timeout(const Duration(seconds: 2));
          await Future.wait([d1, d2]).timeout(const Duration(seconds: 2));
          expect(container.status, equals(ContainerStatus.disposed));
        },
      );
    });

    group('apply', () {
      test('apply should throw when called before start', () async {
        final root = createFeature(name: "root");
        final pipe = createPipe<int>(name: "p", feature: root);

        final child = createFeature(name: "child", dependsOn: [root]);
        child.usePipe(pipe, (value, api) => value + 1);

        final container = AppContainer(features: [root, child]);
        addTearDown(container.dispose);

        expect(
          () => container.apply(
            rootFeature: root,
            port: pipe,
            initialValue: 0,
            data: null,
          ),
          throwsA(isA<ContainerError>()),
        );
      });

      test('apply() after dispose throws ContainerError', () async {
        final feature = createFeature(name: "f");
        final pipe = createPipe<int>(name: "p", feature: feature);
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

      test(
        'apply() during .starting returns partial snapshot without throwing',
        () async {
          // R4 is intentionally not fixed: apply() during .starting keeps
          // working on the currently-resolved subset of features. This
          // test locks the behavior in — the snapshot reflects only
          // handlers of features that are already active at the call
          // site (none here, because the single feature sits behind an
          // async activation setup delay).
          final root = createFeature(name: "root");
          final pipe = createPipe<int>(name: "p", feature: root);
          final child = createFeature(name: "child", dependsOn: [root])
            ..usePipe(pipe, (v, _) => v + 10)
            ..activation((_, toggle, _) async {
              await Future<void>.delayed(const Duration(milliseconds: 80));
              unawaited(toggle(ToggleState.active));
            });
          final container = AppContainer(features: [root, child]);

          final startFuture = container.start();
          await Future<void>.delayed(const Duration(milliseconds: 10));
          expect(container.status, equals(ContainerStatus.starting));

          final partial = container.apply(
            rootFeature: root,
            port: pipe,
            initialValue: 0,
            data: null,
          );
          // Neither feature has run its handler contribution yet (root
          // has no handler; child is inactive); partial == initialValue.
          expect(partial, equals(0));

          await startFuture;
          await container.dispose();
        },
      );
    });

    group('error recovery', () {
      test('should recover when activation setup throws', () async {
        final feature = createFeature(name: "failing")
          ..activation((_, _, _) => throw Exception('setup failed'));

        final container = AppContainer(features: [feature]);
        addTearDown(container.dispose);
        await container.start();

        expect(container.statusOf(feature) == FeatureStatus.active, isFalse);
        expect(container.status, equals(ContainerStatus.working));
      });

      test(
        'services factory throw aborts start() fail-fast (no partial container)',
        () async {
          final feature = createFeature(
            name: "badFactory",
            stores: (parentApi) {
              throw Exception('factory failed');
            },
            exports: (api) => api.own,
          );

          final container = AppContainer(
            features: [feature],
            options: silentOptions(),
          );
          addTearDown(container.dispose);

          await expectLater(
            container.start,
            throwsA(
              isA<FeatureResolutionError>().having(
                (e) => e.reason,
                'reason',
                FeatureResolutionReason.storesFactoryFailed,
              ),
            ),
          );
          expect(container.status, equals(ContainerStatus.idle));
        },
      );

      test('should recover when onStart throws', () async {
        final feature = createFeature(name: "badStart")
          ..onStart((_, _) => throw Exception('onStart failed'));

        final container = AppContainer(features: [feature]);
        addTearDown(container.dispose);
        await container.start();

        expect(container.status, equals(ContainerStatus.working));
      });

      test('onStart throw: feature settles disabled, descendants cascade '
          'closed, errorHandler gets HandlerError', () async {
        final captured = <ArmatureError>[];
        final parent = createFeature(name: "parent")
          ..onStart((_, _) => throw Exception('onStart boom'));
        final child = createFeature(name: "child", dependsOn: [parent]);

        final container = AppContainer(
          features: [parent, child],
          options: ContainerOptions(
            errorHandler: ({required source, required error, required meta}) {
              captured.add(error);
            },
          ),
        );
        addTearDown(container.dispose);
        await container.start();

        expect(container.statusOf(parent), equals(FeatureStatus.disabled));
        expect(container.statusOf(child), equals(FeatureStatus.disabled));
        expect(captured, hasLength(1));
        expect(captured.single, isA<HandlerError>());
        expect((captured.single as HandlerError).featureName, equals('parent'));
      });

      test('errorHandler receives failing feature\'s name and error', () async {
        final captured = <({String source, ArmatureError error})>[];
        final f1 = createFeature(name: "alpha")
          ..activation((_, _, _) => throw Exception('alpha bad'));
        final f2 = createFeature(name: "beta")
          ..activation((_, _, _) => throw Exception('beta bad'));

        final container = AppContainer(
          features: [f1, f2],
          options: ContainerOptions(
            errorHandler: ({required source, required error, required meta}) {
              captured.add((source: source, error: error));
            },
          ),
        );
        addTearDown(container.dispose);
        await container.start();

        final names = captured.map((e) => e.source).toSet();
        expect(names, equals({'alpha', 'beta'}));
        for (final entry in captured) {
          expect(entry.error, isA<HandlerError>());
        }
      });

      test('container survives errorHandler that throws', () async {
        final failing = createFeature(name: "failing")
          ..activation((_, _, _) => throw Exception('setup failed'));

        final container = AppContainer(
          features: [failing],
          options: ContainerOptions(
            errorHandler: ({required source, required error, required meta}) {
              throw Exception('handler exploded');
            },
          ),
        );
        addTearDown(container.dispose);

        await container.start();

        expect(container.status, equals(ContainerStatus.working));
        expect(container.statusOf(failing) == FeatureStatus.active, isFalse);
      });
    });

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
