// Contract: shared top-level `final feature = createFeature(...)`
// instances are safe to use across multiple [AppContainer] lifetimes,
// sequentially (dispose → start a fresh container) and concurrently
// (two containers alive at once). Per-container runtime state is
// independent in both cases.

import 'package:armature/armature.dart';
import 'package:armature/test_utils.dart';
import 'package:test/test.dart';

class _CounterStore extends Store<int> {
  _CounterStore() : super(state: 0);
  void inc() => state = state + 1;
}

class _Svc extends Store<int> {
  _Svc() : super(state: 0);
}

// Shared top-level features — the canonical Armature idiom.
final _reuseLabelPipe = createPipe<String>(name: 'reuse.label');

final _reuseHost = createFeature(
  name: 'reuseHost',
  ports: (label: _reuseLabelPipe),
);

final _reuseContributor = createFeature(
  name: 'reuseContributor',
  dependsOn: [_reuseHost],
)..usePipe(_reuseLabelPipe, (value, _) => '$value[contrib]');

void main() {
  group('sequential reuse across container lifecycles', () {
    test(
      'pipe contributions survive dispose + fresh container with same features',
      () async {
        // --- First lifecycle ---
        final c1 = AppContainer(features: [_reuseHost, _reuseContributor]);
        await c1.start();
        expect(c1.statusOf(_reuseContributor), equals(FeatureStatus.active));

        final v1 = c1.apply(
          rootFeature: _reuseHost,
          port: _reuseLabelPipe,
          initialValue: 'seed',
          data: null,
        );
        expect(v1, equals('seed[contrib]'));
        await c1.dispose();

        // --- Second lifecycle with the same top-level instances ---
        final c2 = AppContainer(features: [_reuseHost, _reuseContributor]);
        await c2.start();
        expect(c2.statusOf(_reuseContributor), equals(FeatureStatus.active));

        final v2 = c2.apply(
          rootFeature: _reuseHost,
          port: _reuseLabelPipe,
          initialValue: 'seed',
          data: null,
        );
        // Regression guard: before the fix, the contributor's handler was
        // deregistered on c1.dispose() and never re-registered — c2 saw
        // `seed` only.
        expect(v2, equals('seed[contrib]'));
        await c2.dispose();
      },
    );

    test(
      'feature with stores rebuilds a fresh scope on second container start',
      () async {
        int factoryInvocations = 0;

        final feature = createFeature(
          name: 'rebuiltScope',
          stores: (_) {
            factoryInvocations++;
            return (svc: _Svc());
          },
          exports: (api) => api.own,
        );

        final c1 = AppContainer(features: [feature]);
        await c1.start();
        final s1 = feature.storeOf<_Svc>(c1);
        expect(factoryInvocations, equals(1));
        await c1.dispose();

        final c2 = AppContainer(features: [feature]);
        await c2.start();
        final s2 = feature.storeOf<_Svc>(c2);
        expect(factoryInvocations, equals(2));
        // Fresh stores on each start — not the disposed instances from c1.
        expect(identical(s1, s2), isFalse);
        await c2.dispose();
      },
    );

    test(
      'status store emits disabled → active on every container cycle',
      () async {
        final host = createFeature(
          name: 'statusHost',
          ports: (label: createPipe<String>(name: 'statusHost.label')),
        );
        final c1 = AppContainer(features: [host]);
        await c1.start();
        expect(c1.statusOf(host), equals(FeatureStatus.active));
        await c1.dispose();

        final c2 = AppContainer(features: [host]);
        // Before the fix, statusStore was `.dispose()`d on c1 teardown and
        // c2's activation write went to a sealed store — status stayed
        // disabled in c2.
        await c2.start();
        expect(c2.statusOf(host), equals(FeatureStatus.active));
        await c2.dispose();
      },
    );

    test('onStart fires on every container activation', () async {
      int onStartCount = 0;
      final feature =
          createFeature(
            name: 'onStartAcrossContainers',
            stores: (_) => (svc: _Svc()),
            exports: (api) => api.own,
          )..onStart((_, _) {
            onStartCount++;
          });

      final c1 = AppContainer(features: [feature]);
      await c1.start();
      expect(onStartCount, equals(1));
      await c1.dispose();

      final c2 = AppContainer(features: [feature]);
      await c2.start();
      expect(onStartCount, equals(2));
      await c2.dispose();

      final c3 = AppContainer(features: [feature]);
      await c3.start();
      expect(onStartCount, equals(3));
      await c3.dispose();
    });

    test(
      'activation setup re-runs on every container and gates feature status',
      () async {
        int activationCount = 0;
        final feature = createFeature(name: 'activationAcrossContainers')
          ..activation((_, toggle, _) {
            activationCount++;
            toggle(ToggleState.active);
          });

        final c1 = AppContainer(features: [feature]);
        await c1.start();
        expect(activationCount, equals(1));
        expect(c1.statusOf(feature), equals(FeatureStatus.active));
        await c1.dispose();

        final c2 = AppContainer(features: [feature]);
        await c2.start();
        expect(activationCount, equals(2));
        expect(c2.statusOf(feature), equals(FeatureStatus.active));
        await c2.dispose();
      },
    );

    test('statusStore listeners from a disposed container do not leak to '
        'the next container', () async {
      final feature = createFeature(name: 'statusListenerCleanup');
      final c1 = AppContainer(features: [feature]);
      await c1.start();

      // Capture the status store from c1 and subscribe *without* a
      // cleanup bag — simulates a user who forgot to register the
      // disposer.
      final s1 = c1.runtimeOf(feature).statusStore;
      final transitions = <FeatureStatus>[];
      s1.subscribe((_, FeatureStatus next) => transitions.add(next));

      await c1.dispose();
      final snapshot = transitions.length;

      final c2 = AppContainer(features: [feature]);
      await c2.start();

      // c2's runtime holds a *fresh* statusStore, independent from c1's
      // disposed instance. No writes from c2's activation reach s1.
      expect(transitions.length, equals(snapshot));
      expect(identical(c2.runtimeOf(feature).statusStore, s1), isFalse);
      expect(c2.statusOf(feature), equals(FeatureStatus.active));
      await c2.dispose();
    });
  });

  group('concurrent containers sharing top-level features', () {
    test('store instances are independent per container', () async {
      final feature = createFeature(
        name: 'shared',
        stores: (_) => (counter: _CounterStore()),
        exports: (api) => api.own,
      );

      final c1 = AppContainer(features: [feature], options: silentOptions());
      await c1.start();
      final c2 = AppContainer(features: [feature], options: silentOptions());
      await c2.start();
      addTearDown(c1.dispose);
      addTearDown(c2.dispose);

      final s1 = c1.runtimeOf(feature).scopeApi.store<_CounterStore>();
      final s2 = c2.runtimeOf(feature).scopeApi.store<_CounterStore>();

      expect(identical(s1, s2), isFalse);

      s1.inc();
      s1.inc();
      expect(s1.state, equals(2));
      expect(s2.state, equals(0), reason: 'c2 store is untouched');
    });

    test('status stores are independent per container', () async {
      final feature = createFeature(name: 'host');
      final c1 = AppContainer(features: [feature], options: silentOptions());
      await c1.start();
      final c2 = AppContainer(features: [feature], options: silentOptions());
      await c2.start();
      addTearDown(c1.dispose);
      addTearDown(c2.dispose);

      expect(
        identical(
          c1.runtimeOf(feature).statusStore,
          c2.runtimeOf(feature).statusStore,
        ),
        isFalse,
      );
    });

    test('port handlers are isolated per container', () async {
      final owner = createFeature(name: 'owner');
      final pipe = createPipe<int>(name: 'p', feature: owner);
      final contributor = createFeature(name: 'contrib', dependsOn: [owner])
        ..usePipe(pipe, (v, _) => v + 1);

      final c1 = AppContainer(
        features: [owner, contributor],
        options: silentOptions(),
      );
      await c1.start();
      final c2 = AppContainer(
        features: [owner, contributor],
        options: silentOptions(),
      );
      await c2.start();
      addTearDown(c1.dispose);
      addTearDown(c2.dispose);

      final h1 = c1.handlersOf(pipe);
      final h2 = c2.handlersOf(pipe);
      expect(h1.length, equals(1));
      expect(h2.length, equals(1));
      // Maps are identity-distinct.
      expect(identical(h1, h2), isFalse);
    });

    test('async dispose of one container does not touch the other', () async {
      final feature = createFeature(
        name: 'f',
        stores: (_) => (counter: _CounterStore()),
        exports: (api) => api.own,
      );

      final c1 = AppContainer(features: [feature], options: silentOptions());
      await c1.start();
      final c2 = AppContainer(features: [feature], options: silentOptions());
      await c2.start();
      addTearDown(c2.dispose);

      final c2Store = c2.runtimeOf(feature).scopeApi.store<_CounterStore>();
      // Fire-and-forget dispose of c1, then immediately exercise c2.
      // ignore: unawaited_futures
      c1.dispose();

      c2Store.inc();
      expect(c2Store.state, equals(1));
      expect(c2.statusOf(feature), equals(FeatureStatus.active));
    });

    test(
      'disposing one container clears only its own port handler map',
      () async {
        final owner = createFeature(name: 'owner');
        final pipe = createPipe<int>(name: 'p', feature: owner);
        final contributor = createFeature(name: 'contrib', dependsOn: [owner])
          ..usePipe(pipe, (v, _) => v + 1);

        final c1 = AppContainer(
          features: [owner, contributor],
          options: silentOptions(),
        );
        await c1.start();
        final c2 = AppContainer(
          features: [owner, contributor],
          options: silentOptions(),
        );
        await c2.start();
        addTearDown(c2.dispose);

        await c1.dispose();

        // c2 is still fully functional — its handler map survived.
        expect(c2.handlersOf(pipe).length, equals(1));
        expect(
          c2.apply(
            rootFeature: owner,
            port: pipe,
            initialValue: 10,
            data: null,
          ),
          equals(11),
        );
      },
    );
  });

  group('feature config stability across container lifecycles', () {
    test('port bindings survive N dispose/start cycles intact', () async {
      final owner = createFeature(name: 'owner');
      final pipe = createPipe<int>(name: 'p', feature: owner);
      final contributor = createFeature(name: 'contrib', dependsOn: [owner])
        ..usePipe(pipe, (v, _) => v + 1);

      final snapshotCount = contributor.config.portBindings.length;
      expect(snapshotCount, equals(1));

      for (var i = 0; i < 3; i++) {
        final c = AppContainer(
          features: [owner, contributor],
          options: silentOptions(),
        );
        await c.start();
        expect(
          c.handlersOf(pipe).length,
          equals(1),
          reason: 'handler reinstalled in cycle $i',
        );
        await c.dispose();
        // Config is read-only for container lifecycle — must be byte-
        // for-byte the same across cycles.
        expect(contributor.config.portBindings.length, equals(snapshotCount));
      }
    });
  });
}
