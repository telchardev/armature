import 'package:armature/armature.dart';
import 'package:mockito/mockito.dart';
import 'package:test/test.dart';

import '_helpers.dart';
import 'feature_listeners.mocks.dart';

typedef CounterState = ({int counter});
typedef UserState = ({int id, String name});

class CounterStore extends Store<CounterState> {
  CounterStore({required super.state});

  void increment() {
    update((state) => (counter: state.counter + 1));
  }
}

class UserStore extends Store<UserState> {
  UserStore({required super.state});
}

class TestRepositories {
  final int firstRepository;

  TestRepositories(this.firstRepository);
}

class FirstStores {
  final CounterStore counter;
  final UserStore user;

  FirstStores({required this.counter, required this.user});
}

class SecondStores {
  final CounterStore counter;

  SecondStores({required this.counter});
}

class _TestStore extends Store<int> {
  _TestStore() : super(state: 0);

  void setValue(int value) {
    state = value;
  }
}

typedef _ParentStores = ({CounterStore counter});

void main() {
  group('stores factory', () {
    test('typed storesFactory returns a concrete record', () async {
      var counter = CounterStore(state: (counter: 0));
      var user = UserStore(state: (id: 1, name: "Test user"));

      final firstFeature = createFeature(
        name: "firstFeature",
        stores: (parentApi) {
          return FirstStores(counter: counter, user: user);
        },
        exports: (api) => api.own,
      );

      final container = AppContainer(features: [firstFeature]);
      addTearDown(container.stop);
      await container.start();

      final stores =
          container.runtimeOf(firstFeature).scopeApi.stores as FirstStores;
      expect(stores.counter, equals(counter));
      expect(stores.user, equals(user));
    });

    test('stores factory can construct repositories in closure', () async {
      final repositories = TestRepositories(0);
      TestRepositories? factoredRepositories;

      final firstFeature = createFeature(
        name: "firstFeature",
        stores: (parentApi) {
          factoredRepositories = repositories;
          return null;
        },
        exports: (api) => api.own,
      );

      var container = AppContainer(features: [firstFeature]);
      addTearDown(container.stop);
      await container.start();

      expect(factoredRepositories, equals(repositories));
    });

    test('feature without storesFactory has null stores', () async {
      final feature = createFeature(name: "bare");
      final container = AppContainer(features: [feature]);
      addTearDown(container.stop);
      await container.start();

      expect(container.runtimeOf(feature).scopeApi.stores, isNull);
    });

    test('duplicate Store of same runtime type throws', () async {
      final feature = createFeature(
        name: "dup",
        stores: (parentApi) {
          CounterStore(state: (counter: 0));
          return CounterStore(state: (counter: 1));
        },
        exports: (api) => api.own,
      );

      final container = AppContainer(
        features: [feature],
        options: silentOptions(),
      );
      addTearDown(container.stop);

      // Factory throws during tracking → fail-fast aborts start().
      await expectLater(
        container.start,
        throwsA(isA<FeatureResolutionError>()),
      );
    });
  });

  group('parent API (api.of / activation)', () {
    test('parentApi.of() provides typed access to parent stores', () async {
      var userStore = UserStore(state: (id: 1, name: "Test user"));

      final firstFeature = createFeature(
        name: "firstFeature",
        stores: (parentApi) {
          return FirstStores(
            counter: CounterStore(state: (counter: 0)),
            user: userStore,
          );
        },
        exports: (api) => api.own,
      );

      final secondFeature =
          createFeature(name: "secondFeature", dependsOn: [firstFeature])
            ..activation((parentApi, toggle, _) {
              final parentStores = parentApi.of(firstFeature);
              expect(parentStores.user, equals(userStore));
              toggle(ToggleState.active);
            });

      final container = AppContainer(features: [firstFeature, secondFeature]);
      addTearDown(container.stop);
      await container.start();
    });

    test(
      'parentApi.of() throws FeatureResolutionError on non-parent feature',
      () async {
        final featureA = createFeature(name: "a");
        final featureB = createFeature(name: "b");

        final child = createFeature(name: "child", dependsOn: [featureA])
          ..activation((parentApi, toggle, _) {
            expect(
              () => parentApi.of(featureB),
              throwsA(isA<FeatureResolutionError>()),
            );
            toggle(ToggleState.active);
          });

        final container = AppContainer(features: [featureA, featureB, child]);
        addTearDown(container.stop);
        await container.start();
      },
    );

    test(
      'parentApi.of() throws notDeclaredParent when feature is not a parent',
      () async {
        final stranger = createFeature(name: "stranger");
        Object? thrown;
        final child = createFeature(name: "child")
          ..activation((parentApi, toggle, _) {
            try {
              parentApi.of(stranger);
            } on Object catch (e) {
              thrown = e;
            }
            toggle(ToggleState.active);
          });

        final container = AppContainer(features: [stranger, child]);
        addTearDown(container.stop);
        await container.start();

        expect(thrown, isA<FeatureResolutionError>());
        expect(
          (thrown! as FeatureResolutionError).reason,
          equals(FeatureResolutionReason.notDeclaredParent),
        );
      },
    );

    test(
      'parentApi.of() provides typed access to an optional parent',
      () async {
        final optional = createFeature(
          name: "optional",
          stores: (parentApi) => FirstStores(
            counter: CounterStore(state: (counter: 0)),
            user: UserStore(state: (id: 7, name: "opt")),
          ),
          exports: (api) => api.own,
        );

        UserStore? seenUser;
        final child =
            createFeature(name: "child", optionalDependsOn: [optional])
              ..activation((parentApi, toggle, _) {
                seenUser = parentApi.of(optional).user;
                toggle(ToggleState.active);
              });

        final container = AppContainer(features: [optional, child]);
        addTearDown(container.stop);
        await container.start();

        expect(seenUser, isNotNull);
        expect(seenUser!.state.id, equals(7));
      },
    );

    test('activation setup can access typed parent stores', () async {
      final parent = createFeature(
        name: "parent",
        stores: (parentApi) {
          return FirstStores(
            counter: CounterStore(state: (counter: 0)),
            user: UserStore(state: (id: 1, name: "Test")),
          );
        },
        exports: (api) => api.own,
      );

      var parentAccessWorked = false;

      final child = createFeature(name: "child", dependsOn: [parent])
        ..activation((parentApi, toggle, _) {
          final stores = parentApi.of(parent);
          expect(stores, isA<FirstStores>());
          parentAccessWorked = true;
          toggle(ToggleState.active);
        });

      final container = AppContainer(features: [parent, child]);
      addTearDown(container.stop);
      await container.start();

      expect(parentAccessWorked, isTrue);
    });

    test('feature with no dependsOn resolves as root', () async {
      final feature = createFeature(name: "standalone");
      final container = AppContainer(features: [feature]);
      addTearDown(container.stop);
      await container.start();

      expect(container.statusOf(feature) == FeatureStatus.active, isTrue);
    });
  });

  group('useStores override', () {
    test('useStores overrides stores factory before start', () async {
      final repositories = TestRepositories(0);
      final newRepositories = TestRepositories(1);
      TestRepositories? factoredRepositories;

      final firstFeature = createFeature(
        name: "firstFeature",
        stores: (parentApi) {
          factoredRepositories = repositories;
          return null;
        },
        exports: (api) => api.own,
      );

      var container = AppContainer(
        features: [
          firstFeature..useStores((parentApi) {
            factoredRepositories = newRepositories;
            return null;
          }),
        ],
      );
      addTearDown(container.stop);

      await container.start();

      expect(factoredRepositories, equals(newRepositories));
    });

    test('useStores after start throws FeatureResolutionError', () async {
      final feature = createFeature(
        name: "late-override",
        stores: (parentApi) => null,
        exports: (api) => api.own,
      );

      final container = AppContainer(features: [feature]);
      addTearDown(container.stop);
      await container.start();

      expect(
        () => feature.useStores((_) => null),
        throwsA(isA<FeatureResolutionError>()),
      );
    });
  });

  group('configuration errors', () {
    test('activation() called twice throws FeatureConfigurationError', () {
      final feature = createFeature(name: "f");
      feature.activation((_, _, _) {});

      expect(
        () => feature.activation((_, _, _) {}),
        throwsA(isA<FeatureConfigurationError>()),
      );
    });

    test('onStart() called twice throws FeatureConfigurationError', () {
      final feature = createFeature(name: "f");
      feature.onStart((_, _) {});

      expect(
        () => feature.onStart((_, _) {}),
        throwsA(isA<FeatureConfigurationError>()),
      );
    });
  });

  group('construct phase — fail-fast & ordering', () {
    test(
      'factory throw aborts start() fail-fast and rolls back to idle',
      () async {
        var calls = 0;
        final feature = createFeature<void, void, void>(
          name: "bad-factory",
          stores: (_) {
            calls++;
            throw StateError('factory failed');
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
        expect(calls, equals(1));
        expect(container.status, equals(ContainerStatus.idle));

        // A retry should re-invoke the factory fresh — the polished
        // rollback cleared the cached `_scopeApi`/state.
        await expectLater(
          container.start,
          throwsA(isA<FeatureResolutionError>()),
        );
        expect(calls, equals(2));
      },
    );

    test(
      'stores factory can call parentApi.of(requiredParent) directly',
      () async {
        final parentStore = CounterStore(state: (counter: 42));
        final parent = createFeature<_ParentStores, _ParentStores, void>(
          name: "eager-parent",
          stores: (_) => (counter: parentStore),
          exports: (api) => api.own,
        );

        CounterStore? capturedInChildFactory;
        final child = createFeature(
          name: "eager-child",
          dependsOn: [parent],
          stores: (parentApi) {
            // Eager construct runs parents first in topo order, so
            // `of(parent)` works right inside the child's factory.
            capturedInChildFactory = parentApi.of(parent).counter;
            return null;
          },
          exports: (api) => api.own,
        );

        final container = AppContainer(features: [parent, child]);
        addTearDown(container.stop);
        await container.start();

        expect(capturedInChildFactory, same(parentStore));
      },
    );

    test(
      'factory throw in parent aborts start() before child factory runs',
      () async {
        var childFactoryCalled = false;
        final parent = createFeature(
          name: "bad-parent",
          stores: (_) => throw StateError('parent factory boom'),
          exports: (api) => api.own,
        );
        final child = createFeature(
          name: "closed-child",
          dependsOn: [parent],
          stores: (_) {
            childFactoryCalled = true;
            return null;
          },
          exports: (api) => api.own,
        );

        final container = AppContainer(
          features: [parent, child],
          options: silentOptions(),
        );
        addTearDown(container.stop);

        // Fail-fast on the parent factory throw — child factory never
        // runs because the construct phase bails on the first error.
        await expectLater(
          container.start,
          throwsA(isA<FeatureResolutionError>()),
        );
        expect(childFactoryCalled, isFalse);
        expect(container.status, equals(ContainerStatus.idle));
      },
    );

    test(
      'factory throw in optional parent still aborts start() fail-fast',
      () async {
        final optionalParent = createFeature(
          name: "opt-parent",
          stores: (_) => throw StateError('opt factory boom'),
          exports: (api) => api.own,
        );

        final child = createFeature(
          name: "opt-child",
          optionalDependsOn: [optionalParent],
          stores: (_) => null,
          exports: (api) => api.own,
        );

        final container = AppContainer(
          features: [optionalParent, child],
          options: silentOptions(),
        );
        addTearDown(container.stop);

        // Optional vs required parent only differs at cascade time
        // (activation / deactivation). Factory failures are binary:
        // if any declared feature fails to construct, the whole
        // container can't start. Users who want resilience should
        // wrap the factory in try/catch and return a null / fallback
        // stores value.
        await expectLater(
          container.start,
          throwsA(isA<FeatureResolutionError>()),
        );
        expect(container.status, equals(ContainerStatus.idle));
      },
    );
  });

  group('port subscriptions & onPortChanged', () {
    test('observe tracks store state mutations; onPortChanged is '
        'handler-set only', () async {
      final listeners = MockListeners();
      final pipeFeature = createFeature(name: "pipeFeature");
      final intPipe = createPipe<int>(name: "one", feature: pipeFeature);

      final counter = CounterStore(state: (counter: 0));

      final feature = createFeature(
        name: "feature",
        dependsOn: [pipeFeature],
        stores: (parentApi) {
          return SecondStores(counter: counter);
        },
        exports: (api) => api.own,
      );

      feature.usePipe(intPipe, (value, api) {
        return value + api.own.counter.state.counter;
      });

      var container = AppContainer(features: [pipeFeature, feature]);
      addTearDown(container.stop);

      container.onPortChanged(port: intPipe, callback: listeners.onPortChanged);

      await container.start();

      // Activation cascade emits one portChanged per port-using feature.
      verify(listeners.onPortChanged()).called(1);

      // observe() is the reactive path: its per-subscriber Reaction
      // tracks atoms the handler reads, so state mutations update the
      // value through `onChanged` WITHOUT emitting portChanged.
      // `onPortChanged` is now a pure handler-set stream — it does NOT
      // fire on atom-driven re-applies.
      var observerChanges = 0;
      final sub = container.observe(
        rootFeature: pipeFeature,
        port: intPipe,
        initialValue: 0,
        data: null,
        onChanged: () => observerChanges++,
      );
      addTearDown(sub.dispose);

      expect(sub.value, equals(0));

      counter.increment();
      counter.increment();

      expect(observerChanges, equals(2));
      expect(sub.value, equals(2));
      // No more portChanged emits — state mutation is a reactive
      // event, not a handler-set event.
      verifyNoMoreInteractions(listeners);
    });
  });

  group('store dispose', () {
    test('Store.dispose() clears all listeners', () {
      final store = _TestStore();
      var callCount = 0;

      store.subscribe((_, _) {
        callCount++;
      });

      store.setValue(1);
      expect(callCount, equals(1));

      store.dispose();

      store.setValue(2);
      expect(callCount, equals(1));
    });
  });
}
