import 'package:armature/armature.dart';
import 'package:armature/test_utils.dart';
import 'package:test/test.dart';

class _ToggleStore extends Store<bool> {
  _ToggleStore({bool initial = false}) : super(state: initial);

  void set(bool value) => state = value;
}

void main() {
  group('manualActivation', () {
    test('feature stays disabled until container.toggleFeature', () async {
      final gated = createFeature(name: 'gated')
        ..activation(manualActivation());

      final container = await startedContainer(features: [gated]);
      expect(container.statusOf(gated), equals(FeatureStatus.disabled));

      await container.toggleFeature(gated, ToggleState.active);
      expect(container.statusOf(gated), equals(FeatureStatus.active));

      await container.toggleFeature(gated, ToggleState.inactive);
      expect(container.statusOf(gated), equals(FeatureStatus.disabled));
    });
  });

  group('whenStoreState', () {
    test(
      'activates when predicate becomes true and deactivates when false',
      () async {
        final parent = createFeature(
          name: 'parent',
          stores: (_) => (toggle: _ToggleStore()),
          exports: (api) => api.own,
        );
        final child = createFeature(name: 'child', dependsOn: [parent])
          ..activation(
            whenStoreState(
              feature: parent,
              store: (e) => e.toggle,
              predicate: (s) => s,
            ),
          );

        final container = await startedContainer(features: [parent, child]);
        final toggleStore = parent.storeOf<_ToggleStore>(container);

        // Initially false → child stays disabled.
        expect(container.statusOf(child), equals(FeatureStatus.disabled));

        // Flip parent state → child activates.
        toggleStore.set(true);
        await Future<void>.delayed(Duration.zero);
        expect(container.statusOf(child), equals(FeatureStatus.active));

        // Flip back → child deactivates.
        toggleStore.set(false);
        await Future<void>.delayed(Duration.zero);
        expect(container.statusOf(child), equals(FeatureStatus.disabled));
      },
    );

    test('fireImmediately applies initial state on start', () async {
      final parent = createFeature(
        name: 'parent',
        stores: (_) => (toggle: _ToggleStore(initial: true)),
        exports: (api) => api.own,
      );
      final child = createFeature(name: 'child', dependsOn: [parent])
        ..activation(
          whenStoreState(
            feature: parent,
            store: (e) => e.toggle,
            predicate: (s) => s,
          ),
        );

      final container = await startedContainer(features: [parent, child]);

      // Initial store state is true → child should already be active.
      expect(container.statusOf(child), equals(FeatureStatus.active));
    });

    test(
      'subscription is disposed on container.stop (no stale toggles)',
      () async {
        final parent = createFeature(
          name: 'parent',
          stores: (_) => (toggle: _ToggleStore()),
          exports: (api) => api.own,
        );
        final child = createFeature(name: 'child', dependsOn: [parent])
          ..activation(
            whenStoreState(
              feature: parent,
              store: (e) => e.toggle,
              predicate: (s) => s,
            ),
          );

        final container = AppContainer(
          features: [parent, child],
          options: silentOptions(),
        );
        await container.start();

        final toggleStore = parent.storeOf<_ToggleStore>(container);
        // Stop — should run cleanup bag, unsubscribing from toggleStore.
        await container.stop();

        // Mutate after stop — must NOT throw or leak. If the
        // subscription is live, any subsequent toggle would hit a
        // stopped container and explode; a sealed container silently
        // ignores.
        toggleStore.set(true);
        // No assertion besides "didn't throw" — a leaked subscription
        // would go via `toggle` into a stopped container.
      },
    );
  });

  group('whenActive', () {
    test(
      'activates when parent becomes active and deactivates when parent goes down',
      () async {
        final source = createFeature(name: 'source')
          ..activation(manualActivation());
        final follower = createFeature(
          name: 'follower',
          optionalDependsOn: [source],
        )..activation(whenActive(source));

        final container = await startedContainer(features: [source, follower]);

        expect(container.statusOf(follower), equals(FeatureStatus.disabled));

        await container.toggleFeature(source, ToggleState.active);
        await _flush();
        expect(container.statusOf(follower), equals(FeatureStatus.active));

        await container.toggleFeature(source, ToggleState.inactive);
        await _flush();
        expect(container.statusOf(follower), equals(FeatureStatus.disabled));
      },
    );

    test(
      'setup of undeclared parent surfaces as a recoverable error',
      () async {
        final unrelated = createFeature(name: 'unrelated');
        final collector = collectErrors();
        final feature = createFeature(name: 'feature')
          ..activation(whenActive(unrelated));

        await startedContainer(
          features: [unrelated, feature],
          options: collector.options,
        );

        // `whenActive(unrelated)` reaches for `parentApi.statusOf(unrelated)`
        // inside the setup — `unrelated` isn't a declared parent, so a
        // `FeatureResolutionError` is raised. The container routes it
        // through `errorHandler` as an activation-setup handler error.
        expect(collector.errors, isNotEmpty);
      },
    );
  });

  group('whenInactive', () {
    test('mirror of whenActive — active while parent is not .active', () async {
      final source = createFeature(name: 'source')
        ..activation(manualActivation());
      final fallback = createFeature(
        name: 'fallback',
        optionalDependsOn: [source],
      )..activation(whenInactive(source));

      final container = await startedContainer(features: [source, fallback]);

      // source disabled → fallback active.
      expect(container.statusOf(fallback), equals(FeatureStatus.active));

      await container.toggleFeature(source, ToggleState.active);
      await _flush();
      expect(container.statusOf(fallback), equals(FeatureStatus.disabled));

      await container.toggleFeature(source, ToggleState.inactive);
      await _flush();
      expect(container.statusOf(fallback), equals(FeatureStatus.active));
    });
  });

  group('whenAllActive', () {
    test(
      'activates when every parent is active; any one going down deactivates',
      () async {
        final a = createFeature(name: 'a')..activation(manualActivation());
        final b = createFeature(name: 'b')..activation(manualActivation());
        final gated = createFeature(name: 'gated', optionalDependsOn: [a, b])
          ..activation(whenAllActive([a, b]));

        final container = await startedContainer(features: [a, b, gated]);

        expect(container.statusOf(gated), equals(FeatureStatus.disabled));

        await container.toggleFeature(a, ToggleState.active);
        await _flush();
        // b still disabled → gated stays disabled.
        expect(container.statusOf(gated), equals(FeatureStatus.disabled));

        await container.toggleFeature(b, ToggleState.active);
        await _flush();
        // Now both active → gated active.
        expect(container.statusOf(gated), equals(FeatureStatus.active));

        await container.toggleFeature(a, ToggleState.inactive);
        await _flush();
        // One of them went down → gated deactivates.
        expect(container.statusOf(gated), equals(FeatureStatus.disabled));

        await container.toggleFeature(a, ToggleState.active);
        await _flush();
        // All active again → gated re-activates.
        expect(container.statusOf(gated), equals(FeatureStatus.active));
      },
    );

    test('empty list → feature is permanently active', () async {
      final feature = createFeature(name: 'always-on')
        ..activation(whenAllActive(const []));

      final container = await startedContainer(features: [feature]);
      await _flush();
      expect(container.statusOf(feature), equals(FeatureStatus.active));
    });
  });
}

Future<void> _flush() async {
  for (var i = 0; i < 4; i++) {
    await Future<void>.delayed(Duration.zero);
  }
}
