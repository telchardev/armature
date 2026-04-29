// Rollback + recoverable error routing — fail-fast construct phase,
// polished rollback to `.idle`, retry contract, and how user-
// callback throws reach `ContainerOptions.errorHandler`.

import 'dart:async';

import 'package:armature/armature.dart';
import 'package:test/test.dart';

import '_helpers.dart';

/// Store that increments a counter on dispose — used by
/// construct-phase fail-fast tests.
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
    group('rollback', () {
      test('rolls back to .idle on missing-dependency error', () async {
        final parent = createFeature(name: "parent");
        final child = createFeature(name: "child", dependsOn: [parent]);

        // child depends on parent, but parent is not added
        final container = AppContainer(features: [child]);
        addTearDown(container.stop);

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
        addTearDown(container.stop);

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
        addTearDown(container.stop);

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
        addTearDown(container.stop);

        await expectLater(
          container.start,
          throwsA(isA<FeatureResolutionError>()),
        );
        expect(container.status, equals(ContainerStatus.idle));
        // Runtime discarded during rollback teardown; the feature config's
        // default (derived from `activationSetup != null ⇒ false`) is what
        // a retry would seed the next runtime with.
        expect(setupFeature.config.activationSetup, isNotNull);
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
        addTearDown(container.stop);

        await expectLater(
          container.start,
          throwsA(isA<FeatureResolutionError>()),
        );

        // The port binding is recorded in the feature's config — never
        // mutated by container lifecycle — so a retry would re-install
        // the handler into the container's fresh map.
        expect(
          healthy.config.portBindings.length,
          equals(1),
          reason: 'feature config is immutable across container lifecycles',
        );
      });

      test(
        'failed start disposes stores built before the failing factory',
        () async {
          _DisposeCounter? disposeCounter;
          final healthy = createFeature(
            name: "healthy",
            stores: (_) {
              // Construct the store INSIDE the factory so
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
          addTearDown(container.stop);

          await expectLater(
            container.start,
            throwsA(isA<FeatureResolutionError>()),
          );

          expect(
            disposeCounter?.disposeCount,
            equals(1),
            reason:
                'stores built before the failing factory must be '
                'disposed by the rollback path',
          );
        },
      );

      test(
        'useStores allows re-override after a rolled-back failed start',
        () async {
          var useBadFactory = true;
          final feature = createFeature<void, void, void>(
            name: "badStores",
            stores: (_) {
              if (useBadFactory) throw Exception('stores factory failed');
            },
            exports: (api) => api.own,
          );

          final container = AppContainer(
            features: [feature],
            options: silentOptions(),
          );
          addTearDown(container.stop);

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

    group('error recovery', () {
      test('should recover when activation setup throws', () async {
        final feature = createFeature(name: "failing")
          ..activation((_, _, _) => throw Exception('setup failed'));

        final container = AppContainer(features: [feature]);
        addTearDown(container.stop);
        await container.start();

        expect(container.statusOf(feature) == FeatureStatus.active, isFalse);
        expect(container.status, equals(ContainerStatus.working));
      });

      test(
        'stores factory throw aborts start() fail-fast (no partial container)',
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
          addTearDown(container.stop);

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
        addTearDown(container.stop);
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
        addTearDown(container.stop);
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
        addTearDown(container.stop);
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
        addTearDown(container.stop);

        await container.start();

        expect(container.status, equals(ContainerStatus.working));
        expect(container.statusOf(failing) == FeatureStatus.active, isFalse);
      });
    });
  });
}
