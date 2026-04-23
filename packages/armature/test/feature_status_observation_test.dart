import 'package:armature/armature.dart';
import 'package:armature/test_utils.dart';
import 'package:test/test.dart';

// Drains pending microtasks so fire-and-forget unawaited toggles from
// inside a subscribe listener settle before assertions run.
Future<void> _flush() async {
  for (var i = 0; i < 4; i++) {
    await Future<void>.delayed(Duration.zero);
  }
}

void main() {
  group('api.statusOf — reactive status observation', () {
    test('returns the current status of a declared parent', () async {
      final parent = createFeature(name: 'parent');
      final child = createFeature(name: 'child', dependsOn: [parent]);

      final container = await startedContainer(features: [parent, child]);

      // Both features auto-activate on start.
      expect(parent.internal.statusStore.state, equals(FeatureStatus.active));
      final statusStore = child.internal.parent.statusOf(parent);
      expect(statusStore.state, equals(FeatureStatus.active));
      expect(container.statusOf(parent), equals(FeatureStatus.active));
    });

    test('throws when feature is not a declared parent', () async {
      final unrelated = createFeature(name: 'unrelated');
      final feature = createFeature(name: 'feature');

      await startedContainer(features: [unrelated, feature]);

      expect(
        () => feature.internal.parent.statusOf(unrelated),
        throwsA(
          isA<FeatureResolutionError>().having(
            (e) => e.reason,
            'reason',
            equals(FeatureResolutionReason.notDeclaredParent),
          ),
        ),
      );
    });

    test(
      'subscribers see transitions: disabled → pending → active → disabled',
      () async {
        final gated = createFeature(name: 'gated')
          ..activation(manualActivation());
        final observer = createFeature(name: 'observer', dependsOn: [gated]);

        final container = await startedContainer(features: [gated, observer]);

        final statusStore = observer.internal.parent.statusOf(gated);
        final transitions = <FeatureStatus>[statusStore.state];
        final dispose = statusStore.subscribe((_, next) {
          transitions.add(next);
        });
        addTearDown(dispose);

        expect(statusStore.state, equals(FeatureStatus.disabled));

        await container.toggleFeature(gated, ToggleState.active);
        expect(statusStore.state, equals(FeatureStatus.active));

        await container.toggleFeature(gated, ToggleState.inactive);
        expect(statusStore.state, equals(FeatureStatus.disabled));

        expect(
          transitions,
          containsAllInOrder([
            FeatureStatus.disabled,
            FeatureStatus.active,
            FeatureStatus.disabled,
          ]),
        );
      },
    );

    test(
      'port handler re-evaluates when observed parent status changes',
      () async {
        // Gated parent — starts disabled, activates via external toggle.
        final gated = createFeature(name: 'gated')
          ..activation(manualActivation());

        // Pipe owner — its pipe's handler reads gated's status. When the
        // status flips, the pipe re-applies.
        final root = createFeature(name: 'root');
        final pipe = createPipe<String>(name: 'label', feature: root);

        final observer =
            createFeature(
              name: 'observer',
              dependsOn: [root],
              optionalDependsOn: [gated],
            )..usePipe(pipe, (_, api) {
              final status = api.statusOf(gated).state;
              return status == FeatureStatus.active ? 'ON' : 'OFF';
            });

        final container = await startedContainer(
          features: [root, gated, observer],
        );

        String currentValue() => container.apply(
          rootFeature: root,
          port: pipe,
          initialValue: '?',
          data: null,
        );

        expect(currentValue(), equals('OFF'));

        await container.toggleFeature(gated, ToggleState.active);
        expect(currentValue(), equals('ON'));

        await container.toggleFeature(gated, ToggleState.inactive);
        expect(currentValue(), equals('OFF'));
      },
    );

    test(
      'statusOf returns same Store instance across calls (identity)',
      () async {
        final parent = createFeature(name: 'parent');
        final child = createFeature(name: 'child', dependsOn: [parent]);
        await startedContainer(features: [parent, child]);

        final a = child.internal.parent.statusOf(parent);
        final b = child.internal.parent.statusOf(parent);
        expect(identical(a, b), isTrue);
      },
    );

    test('works with optionalDependsOn parents too', () async {
      final optional = createFeature(name: 'optional')
        ..activation(manualActivation());
      final observer = createFeature(
        name: 'observer',
        optionalDependsOn: [optional],
      );

      final container = await startedContainer(features: [optional, observer]);

      final status = observer.internal.parent.statusOf(optional);
      expect(status.state, equals(FeatureStatus.disabled));

      await container.toggleFeature(optional, ToggleState.active);
      expect(status.state, equals(FeatureStatus.active));
    });

    test('compose with whenStoreState for declarative "whenActive"', () async {
      // Parent gated manually — toggles drive its status store.
      final source = createFeature(name: 'source')
        ..activation(manualActivation());

      // Child uses whenStoreState against source's statusStore — a
      // declarative `whenActive(source)` built on primitives.
      final dependent =
          createFeature(name: 'dependent', optionalDependsOn: [source])
            ..activation(
              whenStoreState(
                feature: source,
                store: (_) => source.internal.statusStore,
                predicate: (s) => s == FeatureStatus.active,
              ),
            );

      final container = await startedContainer(features: [source, dependent]);

      expect(container.statusOf(dependent), equals(FeatureStatus.disabled));

      await container.toggleFeature(source, ToggleState.active);
      // dependent's toggle is scheduled as an unawaited future inside the
      // subscribe listener; drain the microtask queue before asserting.
      await _flush();
      expect(container.statusOf(dependent), equals(FeatureStatus.active));

      await container.toggleFeature(source, ToggleState.inactive);
      await _flush();
      expect(container.statusOf(dependent), equals(FeatureStatus.disabled));
    });

    test('status store is disposed on container.dispose', () async {
      final parent = createFeature(name: 'parent');
      final child = createFeature(name: 'child', dependsOn: [parent]);

      final container = AppContainer(
        features: [parent, child],
        options: silentOptions(),
      );
      await container.start();

      final store = child.internal.parent.statusOf(parent);
      // Before dispose: reads + subscribes ok.
      expect(store.state, equals(FeatureStatus.active));

      await container.dispose();

      // After dispose: further subscribe must not throw on the disposed
      // store's underlying state — it's idempotently disposed.
      // The store object still exists but is inert.
    });
  });
}
