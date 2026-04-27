// Core AppContainer lifecycle: dependency resolution, start /
// stop, reentrance, and port apply. Rollback + error recovery
// + listener errors live in their own files.

import 'dart:async';

import 'package:armature/armature.dart';
import 'package:test/test.dart';

import '_helpers.dart';

class _Counter extends Store<int> {
  _Counter() : super(state: 0);
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
          addTearDown(container.stop);

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
        addTearDown(container.stop);

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
        addTearDown(container.stop);
        await container.start();

        expect(container.statusOf(feature) == FeatureStatus.active, isFalse);
      });
    });

    group('start / stop lifecycle', () {
      test('transitions to .working after successful start', () async {
        final feature = createFeature(name: "root");
        final container = AppContainer(features: [feature]);
        addTearDown(container.stop);

        expect(container.status, equals(ContainerStatus.idle));

        await container.start();

        expect(container.status, equals(ContainerStatus.working));
      });

      test('start() while already .working is a no-op', () async {
        final container = AppContainer(features: [createFeature(name: "f")]);
        addTearDown(container.stop);
        await container.start();

        // Second start on a working container completes immediately,
        // doesn't run a fresh cycle.
        await container.start();
        expect(container.status, equals(ContainerStatus.working));
      });

      test(
        'concurrent start() calls coalesce on the in-flight future',
        () async {
          final feature = createFeature(name: "slow")
            ..activation((_, toggle, _) async {
              await Future<void>.delayed(const Duration(milliseconds: 60));
              unawaited(toggle(ToggleState.active));
            });

          final container = AppContainer(features: [feature]);
          addTearDown(container.stop);

          final f1 = container.start();
          final f2 = container.start();
          expect(
            identical(f1, f2),
            isTrue,
            reason: 'two concurrent start() calls share one future',
          );

          await f1;
          expect(container.status, equals(ContainerStatus.working));
        },
      );

      test('start() after stop succeeds (container is reusable)', () async {
        final feature = createFeature(name: "f");
        final container = AppContainer(features: [feature]);
        await container.start();
        await container.stop();
        expect(container.status, equals(ContainerStatus.idle));

        // Stop returns the container to .idle; the next start() rebuilds
        // a fresh cycle without throwing.
        await container.start();
        expect(container.status, equals(ContainerStatus.working));

        await container.stop();
      });

      test('stop() is idempotent', () async {
        final feature = createFeature(name: "f");
        final container = AppContainer(features: [feature]);
        await container.start();

        await container.stop();
        await container.stop();
        expect(container.status, equals(ContainerStatus.idle));
      });

      test('stop() clears resolveTimes', () async {
        final feature = createFeature(name: "f");
        final container = AppContainer(features: [feature]);
        await container.start();

        expect(container.resolveTimes, isNotEmpty);

        await container.stop();

        expect(container.resolveTimes, isEmpty);
      });

      test('stop during throttled resolve does not hang', () async {
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
        final stopFuture = container.stop();

        // Both start() and stop() must complete in reasonable time —
        // stop awaits the in-flight start before tearing down, so a
        // hung start would also hang stop.
        await Future.wait([
          startFuture,
          stopFuture,
        ]).timeout(const Duration(seconds: 2));
        expect(container.status, equals(ContainerStatus.idle));
      });

      test('stop clears the container port handler map', () async {
        final shared = createPipe<int>(name: "shared");
        final holder = createFeature(name: "holder")
          ..usePipe(shared, (v, _) => v + 1);
        final container = AppContainer(features: [holder]);
        await container.start();
        expect(container.handlersOf(shared).length, equals(1));

        await container.stop();

        // Per-container map is wiped on stop — the next start() (or
        // another container built from the same top-level `shared` +
        // `holder` pair) re-installs a fresh handler set.
        expect(
          container.handlersOf(shared),
          isEmpty,
          reason:
              'stop clears the container-scoped handler map; '
              'handlers on other containers are unaffected',
        );
      });
    });

    // Restart-friendly contract: the parts that are unique to reusing
    // the *same* container across start/stop cycles. Cross-container
    // reuse (one container.stop() → fresh container with the same
    // features) lives in container_reuse_test.dart.
    group('restart cycle', () {
      test('next start() builds fresh stores (identity changes)', () async {
        final feature = createFeature(
          name: "fresh-stores",
          stores: (_) => (counter: _Counter()),
          exports: (api) => api.own,
        );

        final container = AppContainer(features: [feature]);
        addTearDown(container.stop);

        await container.start();
        final firstStores = container.runtimeOf(feature).scopeApi.stores;

        await container.stop();
        await container.start();

        final secondStores = container.runtimeOf(feature).scopeApi.stores;
        expect(
          identical(firstStores, secondStores),
          isFalse,
          reason: 'each start() cycle constructs a fresh stores record',
        );
      });

      test('statusStore identity is fresh on the second cycle', () async {
        final feature = createFeature(name: "status-fresh");
        final container = AppContainer(features: [feature]);
        addTearDown(container.stop);

        await container.start();
        final firstStatus = container.runtimeOf(feature).statusStore;

        await container.stop();
        await container.start();

        final secondStatus = container.runtimeOf(feature).statusStore;
        expect(
          identical(firstStatus, secondStatus),
          isFalse,
          reason:
              'statusStore is recreated in teardown so the next cycle '
              'lands writes on an undisposed instance',
        );
      });

      test('lifetimeCleanup re-arms across cycles', () async {
        var firstCycleCleanup = 0;
        var secondCycleCleanup = 0;
        var cycleIndex = 0;
        final feature = createFeature(name: "lifetime-rearm")
          ..activation((_, _, cleanup) {
            final witness = cycleIndex;
            cleanup.add(() {
              if (witness == 0) {
                firstCycleCleanup++;
              } else {
                secondCycleCleanup++;
              }
            });
          });

        final container = AppContainer(features: [feature]);
        addTearDown(container.stop);

        await container.start();
        await container.stop();
        expect(firstCycleCleanup, equals(1));
        expect(secondCycleCleanup, equals(0));

        cycleIndex = 1;
        await container.start();
        await container.stop();
        expect(firstCycleCleanup, equals(1));
        expect(
          secondCycleCleanup,
          equals(1),
          reason:
              'second cycle gets its own lifetimeCleanup bag, the disposer '
              'registered in the second activation runs only on the second stop',
        );
      });

      test('event listeners are cleared after stop', () async {
        final root = createFeature(name: "root");
        final container = AppContainer(features: [root]);
        addTearDown(container.stop);

        await container.start();

        var notifications = 0;
        container.onFeatureStatusChanged(
          feature: root,
          callback: () => notifications++,
        );

        await container.stop();
        // Subscriber is gone — re-running the cycle must not wake the
        // previously-registered listener. Cycle 2 brings the feature
        // back to .active during start, which would normally emit one
        // featureStatusChanged.
        await container.start();

        expect(
          notifications,
          equals(0),
          reason: 'listeners registered before stop() must not fire after stop',
        );
      });

      test(
        'start() during in-flight stop queues — runs after stop completes',
        () async {
          final slow = createFeature(name: "slow")
            ..activation((_, _, cleanup) {
              // Async cleanup so stop() spends real time tearing down,
              // giving start() a window to land while it's still in flight.
              cleanup.add(
                () => Future<void>.delayed(const Duration(milliseconds: 60)),
              );
            });

          final container = AppContainer(features: [slow]);
          addTearDown(container.stop);
          await container.start();

          final stopFuture = container.stop();
          // start() during stop must NOT throw — it queues behind stop.
          final startFuture = container.start();

          await Future.wait([stopFuture, startFuture]);
          expect(
            container.status,
            equals(ContainerStatus.working),
            reason:
                'queued start ran after stop and brought the container '
                'back up on the next cycle',
          );
        },
      );

      test('start() from within a feature callback throws', () async {
        late AppContainer container;
        Object? capturedError;
        final feature = createFeature(name: "self-start")
          ..onStart((_, _) async {
            try {
              await container.start();
            } on Object catch (e) {
              capturedError = e;
            }
          });

        container = AppContainer(features: [feature]);
        addTearDown(container.stop);

        await container.start().timeout(const Duration(seconds: 2));
        expect(capturedError, isA<ContainerUsageError>());
        expect(container.status, equals(ContainerStatus.working));
      });

      test('ownActive resets to its construction default after stop', () async {
        var setupCount = 0;
        final feature = createFeature(name: "needs-toggle")
          ..activation((_, toggle, _) async {
            setupCount++;
            // Setup runs twice; first cycle activates, second leaves disabled.
            if (setupCount == 1) {
              await toggle(ToggleState.active);
            }
          });

        final container = AppContainer(features: [feature]);
        addTearDown(container.stop);

        await container.start();
        expect(container.statusOf(feature), equals(FeatureStatus.active));

        await container.stop();
        await container.start();

        // Without ownActive reset, the first cycle's `toggle(.active)`
        // would persist and the feature would re-activate without setup
        // running through its non-activating branch. Reset puts it back
        // to the construction default
        // (`activationSetup != null ⇒ false`).
        expect(container.statusOf(feature), equals(FeatureStatus.disabled));
      });
    });

    group('reentrance', () {
      test(
        'stop() called from within an activation setup rejects with ContainerUsageError',
        () async {
          late AppContainer container;
          Object? capturedError;
          final feature = createFeature(name: "self-stop-setup")
            ..activation((_, _, _) async {
              try {
                await container.stop();
              } on Object catch (e) {
                capturedError = e;
              }
            });

          container = AppContainer(features: [feature]);
          await container.start().timeout(const Duration(seconds: 2));

          expect(capturedError, isA<ContainerUsageError>());
          expect(container.status, equals(ContainerStatus.working));
          await container.stop();
          expect(container.status, equals(ContainerStatus.idle));
        },
      );

      test(
        'stop() called from within onStart rejects with ContainerUsageError',
        () async {
          late AppContainer container;
          Object? capturedError;
          final feature = createFeature(name: "self-stop-onStart")
            ..onStart((_, _) async {
              try {
                await container.stop();
              } on Object catch (e) {
                capturedError = e;
              }
            });

          container = AppContainer(features: [feature]);
          await container.start().timeout(const Duration(seconds: 2));

          expect(capturedError, isA<ContainerUsageError>());
          expect(container.status, equals(ContainerStatus.working));
          await container.stop();
          expect(container.status, equals(ContainerStatus.idle));
        },
      );

      test(
        'concurrent stop() calls during in-flight start collapse to same future',
        () async {
          final slow = createFeature(name: "slow")
            ..activation((_, toggle, _) async {
              await Future<void>.delayed(const Duration(milliseconds: 80));
              unawaited(toggle(ToggleState.active));
            });
          final container = AppContainer(features: [slow]);

          final startFuture = container.start();
          await Future<void>.delayed(const Duration(milliseconds: 20));

          final d1 = container.stop();
          final d2 = container.stop();
          expect(
            identical(d1, d2),
            isTrue,
            reason: 'stop() is idempotent — two calls share one future',
          );

          await startFuture.timeout(const Duration(seconds: 2));
          await Future.wait([d1, d2]).timeout(const Duration(seconds: 2));
          expect(container.status, equals(ContainerStatus.idle));
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
        addTearDown(container.stop);

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

      test('apply() after stop throws ContainerError', () async {
        final feature = createFeature(name: "f");
        final pipe = createPipe<int>(name: "p", feature: feature);
        final container = AppContainer(features: [feature]);
        await container.start();

        await container.stop();

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
          await container.stop();
        },
      );
    });
  });
}
