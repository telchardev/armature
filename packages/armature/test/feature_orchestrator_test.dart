import 'dart:async';

import 'package:armature/armature.dart';
import 'package:test/test.dart';

import '_helpers.dart';

class _Counter extends Store<int> {
  _Counter() : super(state: 0);

  void bump() => update((s) => s + 1);
}

void main() {
  group('Feature activation', () {
    test(
      'feature without activation setup auto-activates at AppContainer.start',
      () async {
        final feature = createFeature(name: "auto");
        final container = AppContainer(features: [feature]);
        addTearDown(container.stop);
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
        addTearDown(container.stop);
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
        addTearDown(container.stop);
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
        addTearDown(container.stop);
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
        addTearDown(container.stop);

        expect(
          () => container.toggleFeature(feature, ToggleState.active),
          throwsA(isA<ContainerError>()),
        );

        await container.start();
        await container.stop();

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
        addTearDown(container.stop);
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
      addTearDown(container.stop);
      await container.start();

      expect(startCalls, equals(1));
    });

    test('toggleFeature(.active) cascades activation to descendants', () async {
      final parent = createFeature(name: "parent")..activation((_, _, _) {});
      final child = createFeature(name: "child", dependsOn: [parent]);

      final container = AppContainer(features: [parent, child]);
      addTearDown(container.stop);
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
        addTearDown(container.stop);
        await container.start();

        expect(container.statusOf(child) == FeatureStatus.active, isTrue);

        await container.toggleFeature(parent, ToggleState.inactive);
        expect(container.statusOf(parent) == FeatureStatus.active, isFalse);
        expect(container.statusOf(child) == FeatureStatus.active, isFalse);
      },
    );

    test(
      'stores are eagerly constructed at start and reused across toggles',
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
        addTearDown(container.stop);
        await container.start();

        // Eager construct: factory runs once at start, even though the
        // feature is initially inactive (activation setup never toggled
        // it).
        expect(factoryCalls, equals(1));

        await container.toggleFeature(feature, ToggleState.active);
        await container.toggleFeature(feature, ToggleState.inactive);
        await container.toggleFeature(feature, ToggleState.active);
        // Stores are cached — factory is never re-invoked.
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
      addTearDown(container.stop);
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
      addTearDown(container.stop);
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
        addTearDown(container.stop);
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
        addTearDown(container.stop);
        await container.start();

        await container.toggleFeature(feature, ToggleState.inactive);
        // Bag is now sealed. Late add should run disposer synchronously.
        savedCleanup.add(() => lateCalled = true);
        expect(lateCalled, isTrue);
      },
    );

    test('lifetime cleanup bag runs on AppContainer.stop', () async {
      var disposed = false;
      final feature = createFeature(name: "bag")
        ..activation((_, _, cleanup) {
          cleanup.add(() => disposed = true);
        });

      final container = AppContainer(features: [feature]);
      addTearDown(container.stop);
      await container.start();

      expect(disposed, isFalse);
      await container.stop();
      expect(disposed, isTrue);
    });

    test('async setup activates after delay', () async {
      final feature = createFeature(name: "async")
        ..activation((_, toggle, _) async {
          await Future<void>.delayed(const Duration(milliseconds: 20));
          unawaited(toggle(ToggleState.active));
        });

      final container = AppContainer(features: [feature]);
      addTearDown(container.stop);
      await container.start();

      // container.start() awaits all setups — feature should be active now.
      expect(container.statusOf(feature) == FeatureStatus.active, isTrue);
    });

    test('sync onStart does not expose pending state', () async {
      final feature = createFeature(name: "sync-onstart")..onStart((_, _) {});

      final container = AppContainer(features: [feature]);
      addTearDown(container.stop);
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
      addTearDown(container.stop);
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
      addTearDown(container.stop);
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
        addTearDown(container.stop);
        await container.start();

        expect(container.statusOf(feature) == FeatureStatus.active, isFalse);
        expect(captured, equals(['bad-setup']));
      },
    );

    group('chained toggles', () {
      test(
        'onStart-triggered cascade drains before start() returns: A→B→C',
        () async {
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
          addTearDown(container.stop);
          await container.start();

          expect(container.statusOf(a) == FeatureStatus.active, isTrue);
          expect(container.statusOf(b) == FeatureStatus.active, isTrue);
          expect(container.statusOf(c) == FeatureStatus.active, isTrue);
        },
      );
    });

    group('re-entrancy: toggle from inside lifecycle callback', () {
      test('toggleFeature from a post-start onStart with concurrency=1 '
          'completes without deadlock', () async {
        late AppContainer container;
        final c = createFeature(name: 'c')..activation((_, _, _) {});
        final b = createFeature(name: 'b')
          ..activation((_, _, _) {})
          ..onStart((_, _) async {
            unawaited(container.toggleFeature(c, ToggleState.active));
          });

        container = AppContainer(
          features: [b, c],
          options: ContainerOptions(
            errorHandler: ({required source, required error, required meta}) {},
            maxResolveConcurrency: 1,
          ),
        );
        addTearDown(container.stop);
        await container.start();
        await container
            .toggleFeature(b, ToggleState.active)
            .timeout(const Duration(seconds: 5));
        await Future<void>.delayed(const Duration(milliseconds: 50));

        expect(container.statusOf(b), FeatureStatus.active);
        expect(container.statusOf(c), FeatureStatus.active);
      });

      test('reactive subscription that toggles in response to a mid-cascade '
          'state change does not trip GraphFixedPointError', () async {
        final counter = _Counter();
        addTearDown(counter.dispose);

        final a = createFeature(name: 'a')
          ..activation((_, toggle, cleanup) {
            cleanup.add(
              counter.subscribe((_, next) {
                unawaited(
                  toggle(
                    next.isEven ? ToggleState.active : ToggleState.inactive,
                  ),
                );
              }, fireImmediately: true),
            );
          });
        final b = createFeature(name: 'b')
          ..onStart((_, _) async {
            // Mid-cascade mutation that fires A's listener.
            counter.bump();
          });

        final container = AppContainer(
          features: [a, b],
          options: ContainerOptions(
            errorHandler: ({required source, required error, required meta}) {},
          ),
        );
        addTearDown(container.stop);

        await container.start().timeout(const Duration(seconds: 5));
        expect(container.status, ContainerStatus.working);
        expect(container.statusOf(b), FeatureStatus.active);
        // Let any queued toggles from B's onStart settle.
        await Future<void>.delayed(const Duration(milliseconds: 50));
        // After bump (counter=1, odd), A flipped to .inactive via the
        // queued recompute — proving the cycle was broken.
        expect(container.statusOf(a), FeatureStatus.disabled);
      });
    });

    group('partial activation on cascade failure', () {
      test('failing onStart leaves siblings active and required descendants '
          'fail-closed (degraded mode)', () async {
        // Topology:
        //   parent   (auto-active)
        //     ├── a  (auto-active, succeeds)
        //     ├── b  (auto-active, onStart throws)
        //     └── c  (depends on a + b → fail-closed when b fails)
        //
        // Per the documented `_applyCascade` contract: a stays
        // `.active`, b lands `.disabled`, c never runs onActivate
        // and settles `.disabled` because one required parent isn't
        // active.
        final errors = <ArmatureError>[];
        final parent = createFeature(name: 'parent');
        final a = createFeature(name: 'a', dependsOn: [parent]);
        final b = createFeature(name: 'b', dependsOn: [parent])
          ..onStart((_, _) => throw StateError('b boom'));
        final c = createFeature(name: 'c', dependsOn: [parent, a, b]);

        final container = AppContainer(
          features: [parent, a, b, c],
          options: ContainerOptions(
            errorHandler: ({required source, required error, required meta}) {
              errors.add(error);
            },
          ),
        );
        addTearDown(container.stop);
        await container.start();

        expect(container.statusOf(parent), FeatureStatus.active);
        expect(
          container.statusOf(a),
          FeatureStatus.active,
          reason: 'sibling that activated successfully stays active',
        );
        expect(
          container.statusOf(b),
          FeatureStatus.disabled,
          reason: 'failed onStart settles .disabled',
        );
        expect(
          container.statusOf(c),
          FeatureStatus.disabled,
          reason: 'required descendant of b fails closed',
        );
        // The failure surfaces through `errorHandler`.
        expect(errors, isNotEmpty);
        expect(errors.first, isA<HandlerError>());
      });
    });
  });
}
