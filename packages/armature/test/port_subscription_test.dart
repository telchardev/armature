import 'package:armature/armature.dart';
import 'package:armature/src/store/state.dart';
import 'package:test/test.dart';

/// Regression test for the former shared-per-port Reaction bug.
///
/// Under the old design, `AppContainer.apply` reused a single `Reaction`
/// per port across every caller. Each `reaction.track` call cleared
/// `_newAtoms` on entry and replaced `_atoms` on exit, so a second
/// apply with a handler that read a different atom replaced the first
/// apply's dep set — the first subscriber then stopped receiving
/// `portChanged` events for its own reactive reads.
///
/// The fix moves reactivity into per-subscriber [PortSubscription]s
/// via [AppContainer.observe]. Each subscription owns its own
/// `Reaction`, so subscribers tracking different atoms no longer
/// overwrite each other.
void main() {
  test('per-subscriber reactions: divergent atom reads do not overwrite each '
      'other', () async {
    late State<int> stateX;
    late State<int> stateY;

    final owner = createFeature(name: 'owner');
    final pipe = createPipe<int>(name: 'pipe', feature: owner);
    final child = createFeature(name: 'child', dependsOn: [owner]);

    // Handler reads exactly one of the two reactive stores, chosen by
    // the threaded `value`. Reading `.state` calls `Atom.reportObserved`
    // so whichever store the handler touches becomes a dep of the
    // ambient reaction.
    child.usePipe<int>(pipe, (value, api) {
      return value == 1 ? stateX.state : stateY.state;
    });

    stateX = State<int>(state: 100);
    stateY = State<int>(state: 200);
    addTearDown(() {
      stateX.dispose();
      stateY.dispose();
    });

    final container = AppContainer(features: [owner, child]);
    addTearDown(container.stop);
    await container.start();

    var subAChanges = 0;
    var subBChanges = 0;

    // "Widget A" subscribes with initialValue=1 → handler reads stateX.
    final subA = container.observe(
      rootFeature: owner,
      port: pipe,
      initialValue: 1,
      data: null,
      onChanged: () => subAChanges++,
    );
    addTearDown(subA.dispose);

    // "Widget B" subscribes with initialValue=2 → handler reads stateY.
    // With per-subscriber reactions, subA's tracking of stateX is
    // preserved independently of subB.
    final subB = container.observe(
      rootFeature: owner,
      port: pipe,
      initialValue: 2,
      data: null,
      onChanged: () => subBChanges++,
    );
    addTearDown(subB.dispose);

    // Mutating stateX must invalidate subA but not subB.
    stateX.state = 101;
    await Future<void>.delayed(Duration.zero);

    expect(subAChanges, equals(1), reason: 'subA tracks stateX');
    expect(subBChanges, equals(0), reason: 'subB tracks stateY, not stateX');
    expect(subA.value, equals(101));
    expect(subB.value, equals(200));

    // Mutating stateY must invalidate subB but not subA.
    stateY.state = 201;
    await Future<void>.delayed(Duration.zero);

    expect(subAChanges, equals(1), reason: 'stateY is not a subA dep');
    expect(subBChanges, equals(1), reason: 'subB tracks stateY');
    expect(subA.value, equals(101));
    expect(subB.value, equals(201));
  });

  test(
    'observe re-applies when a feature owning a handler toggles active',
    () async {
      final owner = createFeature(name: 'owner');
      final pipe = createPipe<int>(name: 'pipe', feature: owner);

      final toggleable = createFeature(name: 'toggleable', dependsOn: [owner])
        ..usePipe<int>(pipe, (value, api) => value + 10);

      // Gated by activation setup → starts inactive; test flips it
      // active later.
      toggleable.activation((_, _, _) {});

      final container = AppContainer(features: [owner, toggleable]);
      addTearDown(container.stop);
      await container.start();

      var changes = 0;
      final sub = container.observe(
        rootFeature: owner,
        port: pipe,
        initialValue: 0,
        data: null,
        onChanged: () => changes++,
      );
      addTearDown(sub.dispose);

      // `toggleable` is inactive → handler skipped → initialValue through.
      expect(sub.value, equals(0));

      await container.toggleFeature(toggleable, ToggleState.active);

      expect(sub.value, equals(10), reason: 'activation must re-apply');
      expect(changes, greaterThanOrEqualTo(1));

      await container.toggleFeature(toggleable, ToggleState.inactive);

      expect(sub.value, equals(0), reason: 'deactivation must re-apply');
    },
  );
}
