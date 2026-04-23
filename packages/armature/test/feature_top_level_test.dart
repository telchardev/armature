import 'package:armature/armature.dart';
import 'package:test/test.dart';

class _Svc extends Store<int> {
  _Svc() : super(state: 0);
}

final _topLevelBlockBody =
    createFeature(
      name: "topLevelBlockBody",
      stores: (_) => (svc: _Svc()),
      exports: (api) => api.own,
    )..onStart((api, cleanup) {
      // block body returns Null — previously broke the runtime cast.
      final _ = api.own.svc;
    });

final _topLevelArrowNull = createFeature(
  name: "topLevelArrowNull",
  stores: (_) => (svc: _Svc()),
  exports: (api) => api.own,
)..onStart((_, _) => null);

final _topLevelActivationBlock =
    createFeature(
      name: "topLevelActivationBlock",
      stores: (_) => (svc: _Svc()),
      exports: (api) => api.own,
    )..activation((_, toggle, _) {
      toggle(ToggleState.active);
    });

// --- Reuse-across-containers scenario ---
//
// Canonical Armature idiom: features are declared as top-level `final`s,
// ports live next to them. A parent StatefulWidget (like `ArmatureApp`)
// mounts a container from that feature list; on remount a *new* container
// is built with the *same* top-level feature instances. This suite pins
// down the contract that the pipe contributions survive that cycle.

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
  group('top-level feature cascades', () {
    test('onStart with 2-param block body activates cleanly', () async {
      final c = AppContainer(features: [_topLevelBlockBody]);
      await c.start();
      expect(c.statusOf(_topLevelBlockBody) == FeatureStatus.active, isTrue);
      await c.dispose();
    });

    test('onStart with (_, _) => null arrow activates cleanly', () async {
      final c = AppContainer(features: [_topLevelArrowNull]);
      await c.start();
      expect(c.statusOf(_topLevelArrowNull) == FeatureStatus.active, isTrue);
      await c.dispose();
    });

    test('activation with 3-param block body activates cleanly', () async {
      final c = AppContainer(features: [_topLevelActivationBlock]);
      await c.start();
      expect(
        c.statusOf(_topLevelActivationBlock) == FeatureStatus.active,
        isTrue,
      );
      await c.dispose();
    });
  });

  group('top-level feature reuse across container lifecycles', () {
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
        final s1 = feature.internal.scopeApi.own;
        expect(factoryInvocations, equals(1));
        await c1.dispose();

        final c2 = AppContainer(features: [feature]);
        await c2.start();
        final s2 = feature.internal.scopeApi.own;
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
      // disposer. Before the fix this would accumulate a listener that
      // fires on every subsequent container's activation writes.
      final s1 = feature.internal.statusStore;
      final transitions = <FeatureStatus>[];
      s1.subscribe((_, next) => transitions.add(next));

      await c1.dispose();
      final snapshot = transitions.length;

      final c2 = AppContainer(features: [feature]);
      await c2.start();

      // c2's activation writes land on a *new* statusStore, not s1,
      // because teardown disposed and replaced it.
      expect(transitions.length, equals(snapshot));
      expect(identical(feature.internal.statusStore, s1), isFalse);
      expect(c2.statusOf(feature), equals(FeatureStatus.active));
      await c2.dispose();
    });
  });
}
