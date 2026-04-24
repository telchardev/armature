// Core AppContainer lifecycle: dependency resolution, start /
// dispose, reentrance, and port apply. Rollback + error recovery
// + listener errors live in their own files.

import 'dart:async';

import 'package:armature/armature.dart';
import 'package:test/test.dart';

import '_helpers.dart';

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

      test('dispose clears the container port handler map', () async {
        final shared = createPipe<int>(name: "shared");
        final holder = createFeature(name: "holder")
          ..usePipe(shared, (v, _) => v + 1);
        final container = AppContainer(features: [holder]);
        await container.start();
        expect(container.handlersOf(shared).length, equals(1));

        await container.dispose();

        // Per-container map is wiped on dispose — another container built
        // from the same top-level `shared` + `holder` pair allocates its
        // own fresh handler map.
        expect(
          container.handlersOf(shared),
          isEmpty,
          reason:
              'dispose clears the container-scoped handler map; '
              'handlers on other containers are unaffected',
        );
      });
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
  });
}
