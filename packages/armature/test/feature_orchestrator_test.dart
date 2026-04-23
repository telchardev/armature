import 'dart:async';

import 'package:armature/armature.dart';
import 'package:test/test.dart';

import '_helpers.dart';

class _Counter extends Store<int> {
  _Counter() : super(state: 0);
}

void main() {
  group('Feature activation', () {
    test(
      'feature without activation setup auto-activates at AppContainer.start',
      () async {
        final feature = createFeature(name: "auto");
        final container = AppContainer(features: [feature]);
        addTearDown(container.dispose);
        await container.start();

        expect(container.statusOf(feature) == FeatureStatus.active, isTrue);
      },
    );

    test(
      'feature with activation setup starts inactive until toggle(ToggleState.active)',
      () async {
        final feature = createFeature(name: "gated")
          ..activation((_, _, _) {}); // never starts

        final container = AppContainer(features: [feature]);
        addTearDown(container.dispose);
        await container.start();

        expect(container.statusOf(feature) == FeatureStatus.active, isFalse);
      },
    );

    test(
      'toggle(ToggleState.active) during setup activates the feature',
      () async {
        final feature = createFeature(name: "immediate")
          ..activation((_, toggle, _) {
            unawaited(toggle(ToggleState.active));
          });

        final container = AppContainer(features: [feature]);
        addTearDown(container.dispose);
        await container.start();

        expect(container.statusOf(feature) == FeatureStatus.active, isTrue);
      },
    );

    test(
      'container.toggleFeature after start drives activation externally',
      () async {
        final feature = createFeature(name: "deferred")
          ..activation((_, _, _) {}); // deferred — never auto-activates

        final container = AppContainer(features: [feature]);
        addTearDown(container.dispose);
        await container.start();

        expect(container.statusOf(feature) == FeatureStatus.active, isFalse);

        await container.toggleFeature(feature, ToggleState.active);
        expect(container.statusOf(feature) == FeatureStatus.active, isTrue);

        await container.toggleFeature(feature, ToggleState.inactive);
        expect(container.statusOf(feature) == FeatureStatus.active, isFalse);
      },
    );

    test(
      'toggleFeature throws ContainerError when container is not working',
      () async {
        final feature = createFeature(name: "not-started")
          ..activation((_, _, _) {});

        final container = AppContainer(features: [feature]);
        addTearDown(container.dispose);

        expect(
          () => container.toggleFeature(feature, ToggleState.active),
          throwsA(isA<ContainerError>()),
        );

        await container.start();
        await container.dispose();

        expect(
          () => container.toggleFeature(feature, ToggleState.active),
          throwsA(isA<ContainerError>()),
        );
      },
    );

    test(
      'activation toggle callable (native path) still drives activation',
      () async {
        // Keep this as the canonical coverage of the `toggle` callable
        // passed into activation setup — the other tests prefer the
        // newer external path via container.toggleFeature.
        late FeatureToggle savedCtrl;
        final feature = createFeature(name: "native-toggle")
          ..activation((_, toggle, _) {
            savedCtrl = toggle;
          });

        final container = AppContainer(features: [feature]);
        addTearDown(container.dispose);
        await container.start();

        await savedCtrl(ToggleState.active);
        expect(container.statusOf(feature) == FeatureStatus.active, isTrue);
      },
    );

    test('toggle(ToggleState.active)/stop() are idempotent', () async {
      var startCalls = 0;
      final feature = createFeature(name: "idem")
        ..activation((_, toggle, _) {
          unawaited(toggle(ToggleState.active));
          unawaited(toggle(ToggleState.active)); // no-op
        })
        ..onStart((_, _) {
          startCalls++;
        });

      final container = AppContainer(features: [feature]);
      addTearDown(container.dispose);
      await container.start();

      expect(startCalls, equals(1));
    });

    test('toggleFeature(.active) cascades activation to descendants', () async {
      final parent = createFeature(name: "parent")..activation((_, _, _) {});
      final child = createFeature(name: "child", dependsOn: [parent]);

      final container = AppContainer(features: [parent, child]);
      addTearDown(container.dispose);
      await container.start();

      expect(container.statusOf(parent) == FeatureStatus.active, isFalse);
      expect(container.statusOf(child) == FeatureStatus.active, isFalse);

      await container.toggleFeature(parent, ToggleState.active);
      expect(container.statusOf(parent) == FeatureStatus.active, isTrue);
      expect(container.statusOf(child) == FeatureStatus.active, isTrue);
    });

    test(
      'toggleFeature(.inactive) cascades deactivation to descendants',
      () async {
        final parent = createFeature(name: "parent")
          ..activation((_, toggle, _) {
            unawaited(toggle(ToggleState.active));
          });
        final child = createFeature(name: "child", dependsOn: [parent]);

        final container = AppContainer(features: [parent, child]);
        addTearDown(container.dispose);
        await container.start();

        expect(container.statusOf(child) == FeatureStatus.active, isTrue);

        await container.toggleFeature(parent, ToggleState.inactive);
        expect(container.statusOf(parent) == FeatureStatus.active, isFalse);
        expect(container.statusOf(child) == FeatureStatus.active, isFalse);
      },
    );

    test(
      'services are eagerly constructed at start and reused across toggles',
      () async {
        var factoryCalls = 0;
        final feature = createFeature(
          name: "eager",
          stores: (_) {
            factoryCalls++;
            return _Counter();
          },
          exports: (api) => api.own,
        )..activation((_, _, _) {});

        final container = AppContainer(features: [feature]);
        addTearDown(container.dispose);
        await container.start();

        // Eager construct: factory runs once at start, even though the
        // feature is initially inactive (activation setup never toggled
        // it).
        expect(factoryCalls, equals(1));

        await container.toggleFeature(feature, ToggleState.active);
        await container.toggleFeature(feature, ToggleState.inactive);
        await container.toggleFeature(feature, ToggleState.active);
        // Services are cached — factory is never re-invoked.
        expect(factoryCalls, equals(1));
      },
    );

    test('onStart runs on every inactive→active transition', () async {
      var starts = 0;
      final feature = createFeature(name: "count")
        ..activation((_, _, _) {})
        ..onStart((_, _) {
          starts++;
        });

      final container = AppContainer(features: [feature]);
      addTearDown(container.dispose);
      await container.start();

      expect(starts, equals(0));
      await container.toggleFeature(feature, ToggleState.active);
      expect(starts, equals(1));
      await container.toggleFeature(feature, ToggleState.inactive);
      await container.toggleFeature(feature, ToggleState.active);
      expect(starts, equals(2));
    });

    test('cleanup bag runs in LIFO order on deactivation', () async {
      final order = <int>[];
      final feature = createFeature(name: "lifo")
        ..activation((_, toggle, _) {
          unawaited(toggle(ToggleState.active));
        })
        ..onStart((_, cleanup) {
          cleanup.add(() => order.add(1));
          cleanup.add(() => order.add(2));
          cleanup.add(() => order.add(3));
        });

      final container = AppContainer(features: [feature]);
      addTearDown(container.dispose);
      await container.start();

      await container.toggleFeature(feature, ToggleState.inactive);
      expect(order, equals([3, 2, 1]));
    });

    test(
      'cleanup disposer that throws does not prevent later disposers',
      () async {
        final order = <int>[];
        final feature = createFeature(name: "throw-cleanup")
          ..activation((_, toggle, _) {
            toggle(ToggleState.active);
          })
          ..onStart((_, cleanup) {
            cleanup.add(() => order.add(1));
            cleanup.add(() => throw Exception('boom'));
            cleanup.add(() => order.add(3));
          });

        final container = AppContainer(
          features: [feature],
          options: silentOptions(),
        );
        addTearDown(container.dispose);
        await container.start();

        await container.toggleFeature(feature, ToggleState.inactive);
        // LIFO: 3 runs first, then throwing disposer is caught, then 1.
        expect(order, equals([3, 1]));
      },
    );

    test(
      'late cleanup.add after deactivation runs the disposer immediately',
      () async {
        var lateCalled = false;
        late Cleanup savedCleanup;
        final feature = createFeature(name: "late-add")
          ..activation((_, toggle, _) {
            toggle(ToggleState.active);
          })
          ..onStart((_, cleanup) {
            savedCleanup = cleanup;
          });

        final container = AppContainer(features: [feature]);
        addTearDown(container.dispose);
        await container.start();

        await container.toggleFeature(feature, ToggleState.inactive);
        // Bag is now sealed. Late add should run disposer synchronously.
        savedCleanup.add(() => lateCalled = true);
        expect(lateCalled, isTrue);
      },
    );

    test('lifetime cleanup bag runs on AppContainer.dispose', () async {
      var disposed = false;
      final feature = createFeature(name: "bag")
        ..activation((_, _, cleanup) {
          cleanup.add(() => disposed = true);
        });

      final container = AppContainer(features: [feature]);
      addTearDown(container.dispose);
      await container.start();

      expect(disposed, isFalse);
      await container.dispose();
      expect(disposed, isTrue);
    });

    test('async setup activates after delay', () async {
      final feature = createFeature(name: "async")
        ..activation((_, toggle, _) async {
          await Future<void>.delayed(const Duration(milliseconds: 20));
          unawaited(toggle(ToggleState.active));
        });

      final container = AppContainer(features: [feature]);
      addTearDown(container.dispose);
      await container.start();

      // container.start() awaits all setups — feature should be active now.
      expect(container.statusOf(feature) == FeatureStatus.active, isTrue);
    });

    test('sync onStart does not expose pending state', () async {
      final feature = createFeature(name: "sync-onstart")..onStart((_, _) {});

      final container = AppContainer(features: [feature]);
      addTearDown(container.dispose);
      await container.start();

      expect(container.statusOf(feature) == FeatureStatus.pending, isFalse);
      expect(container.statusOf(feature) == FeatureStatus.active, isTrue);
    });

    test('pending is true while async onStart is awaiting', () async {
      final onStartBegun = Completer<void>();
      final releaseOnStart = Completer<void>();
      final feature = createFeature(name: "async-onstart")
        ..onStart((_, _) async {
          onStartBegun.complete();
          await releaseOnStart.future;
        });

      final container = AppContainer(features: [feature]);
      addTearDown(container.dispose);
      final startFuture = container.start();

      // Wait for onStart to actually begin awaiting.
      await onStartBegun.future;

      expect(container.statusOf(feature) == FeatureStatus.pending, isTrue);

      releaseOnStart.complete();
      await startFuture;

      expect(container.statusOf(feature) == FeatureStatus.pending, isFalse);
      expect(container.statusOf(feature) == FeatureStatus.active, isTrue);
    });

    test('child onStart runs after parent onStart completes', () async {
      final events = <String>[];
      final parent = createFeature(name: "parent")
        ..onStart((_, _) async {
          events.add('parent-begin');
          await Future<void>.delayed(const Duration(milliseconds: 30));
          events.add('parent-end');
        });
      final child = createFeature(name: "child", dependsOn: [parent])
        ..onStart((_, _) {
          events.add('child');
        });

      final container = AppContainer(features: [parent, child]);
      addTearDown(container.dispose);
      await container.start();

      expect(events, equals(['parent-begin', 'parent-end', 'child']));
    });

    test(
      'setup that throws leaves feature inactive and reports to errorHandler',
      () async {
        final captured = <String>[];
        final feature = createFeature(name: "bad-setup")
          ..activation((_, _, _) => throw Exception('nope'));

        final container = AppContainer(
          features: [feature],
          options: ContainerOptions(
            errorHandler: ({required source, required error, required meta}) {
              captured.add(source);
            },
          ),
        );
        addTearDown(container.dispose);
        await container.start();

        expect(container.statusOf(feature) == FeatureStatus.active, isFalse);
        expect(captured, equals(['bad-setup']));
      },
    );

    group('chained toggles', () {
      test(
        'onStart-triggered cascade drains before start() returns: A→B→C',
        () async {
          // R7 fix end-to-end: A's onStart toggles B; B's onStart toggles C.
          // Graph's tail-await must drain the nested recomputes before
          // start() completes, so by the time the test sees .working,
          // all three are active.
          //
          // Note: we use onStart (not setup) for the chain because setups
          // run concurrently via Future.wait — their execution order
          // w.r.t. captured-toggle availability isn't guaranteed. onStart
          // runs during the cascade in topological order, so each
          // parent's toggle is captured by its own setup before the
          // child's onStart runs.
          late FeatureToggle toggleB;
          late FeatureToggle toggleC;

          final a = createFeature(name: "a")
            ..onStart((_, _) async {
              unawaited(toggleB(ToggleState.active));
            });
          final b = createFeature(name: "b")
            ..activation((_, toggle, _) {
              toggleB = toggle;
            })
            ..onStart((_, _) async {
              unawaited(toggleC(ToggleState.active));
            });
          final c = createFeature(name: "c")
            ..activation((_, toggle, _) {
              toggleC = toggle;
            });

          final container = AppContainer(features: [a, b, c]);
          addTearDown(container.dispose);
          await container.start();

          expect(container.statusOf(a) == FeatureStatus.active, isTrue);
          expect(container.statusOf(b) == FeatureStatus.active, isTrue);
          expect(container.statusOf(c) == FeatureStatus.active, isTrue);
        },
      );
    });
  });
}
