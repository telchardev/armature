import 'package:flutter/material.dart';

import '../doc_typography.dart';

class GlossaryContent extends StatelessWidget {
  const GlossaryContent({super.key});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const DocTitle('Glossary'),
        const DocParagraph(
          'A reference card for the vocabulary armature introduces. Each '
          'entry is one or two sentences plus the API entry point — for '
          'the long version, follow the link in the sidebar.',
        ),
        const DocHeading('Runtime'),
        _term(
          'AppContainer',
          'Runtime root of an armature app. Owns the dependency graph, '
              'lifecycle, error handler, and logger. One per app (or per '
              'test). API: AppContainer, ContainerOptions.',
        ),
        _term(
          'ArmatureApp',
          'Bootstrap widget. Takes the feature list, builds the '
              'AppContainer, installs ContainerContext, and renders your '
              'tree. API: ArmatureApp.',
        ),
        const DocHeading('Composition'),
        _term(
          'Feature',
          'Isolated module that declares dependencies (dependsOn / '
              'optionalDependsOn), owns stores, and may declare and/or use '
              'ports. The unit of composition. API: createFeature(...).',
        ),
        _term(
          'exports',
          'Typed API a feature publishes to its dependents — read by '
              'them via api.of(parent). Required whenever stores: is '
              'declared (use exports: (api) => api.own for full '
              'passthrough, or narrow it to hide internal stores). API: '
              'createFeature(exports: ...), api.of(parent).',
        ),
        _term(
          'createFeatureRoot',
          'Binds a feature to a root widget. The returned builder mounts '
              'that feature in the widget tree. API: createFeatureRoot(...).',
        ),
        const DocHeading('State'),
        _term(
          'Store',
          'Observable state holder. Reads from .state inside a tracked '
              'scope auto-subscribe; mutations go through update(...). API: '
              'Store<T>.',
        ),
        _term(
          'StoreBuilder',
          'Flutter widget that rebuilds whenever any .state read inside '
              'its builder changes. API: StoreBuilder<T>.',
        ),
        _term(
          'StoreSelector',
          'Like StoreBuilder, but rebuilds only when a derived value '
              '(select: ...) changes by ==. API: StoreSelector<V>.',
        ),
        const DocHeading('Async work'),
        _term(
          'Task',
          'Strategy-aware async operation owned by a store. Observable '
              'lifecycle via Task.state — TaskIdle, TaskPending, TaskDone, '
              'TaskFailed. API: Store.createTask(...), Store.createVoidTask(...).',
        ),
        _term(
          'TaskStrategy',
          'Concurrency policy for a task: .once (cache-and-share), '
              '.queue (FIFO serialise), .latest (supersede in-flight), '
              '.debounce(d) (coalesce burst), .throttle(d) (rate-limit). '
              'API: TaskStrategy.',
        ),
        const DocHeading('Composition between features'),
        _term(
          'Port',
          'Typed extension point declared by one feature, used by '
              'others. Three shapes: pipe, behavior, slot. The only contract '
              'between features besides dependsOn.',
        ),
        _term(
          'Pipe',
          'Sequential transformation port — handlers chain like '
              'middleware over a value. API: createPipe<T>(...).',
        ),
        _term(
          'Behavior',
          'Priority-based selection port — the highest-priority handler '
              'wins. API: createBehavior<TBranch, TPayload>(...).',
        ),
        _term(
          'Slot',
          'Widget-injection port. Single slot picks one widget by '
              'priority; multi slot renders an ordered list. Keyed variants '
              'partition by a key. API: createKeyedSingleSlot, '
              'createMultiSlot, KeyedSingleSlot, KeyedMultiSlot.',
        ),
        const DocHeading('Lifecycle'),
        _term(
          'FeatureStatus',
          'Current lifecycle state of a feature: disabled, pending, '
              'active. API: FeatureStatus.',
        ),
        _term(
          'Activation',
          'Optional setup that gates when a feature becomes '
              'FeatureStatus.active. Without it, the feature auto-activates '
              'at container start. API: feature.activation(...), whenActive, '
              'whenInactive, whenAllActive, whenStoreState, manualActivation.',
        ),
        _term(
          'Toggle',
          'The ToggleState.active / ToggleState.inactive signal an '
              'activation setup emits to flip a feature on or off. API: '
              'ToggleState, container.toggleFeature(...).',
        ),
        _term(
          'Cleanup',
          'Per-activation disposer registry. Sugar methods: '
              'cleanup.subscribe(store, fn), cleanup.periodic(d, fn), '
              'cleanup.listen(stream, fn). API: Cleanup (passed to '
              'activation setup and onStart).',
        ),
        const DocHeading('Under the hood'),
        _term(
          'Reactive primitive',
          'The low-level Atom / Reaction / Context that powers tracked '
              'reads. You rarely touch these — stores, ports, and '
              'StoreBuilder use them under the hood. API: armature_reactive.',
        ),
        const DocHeading('What is next?'),
        const DocBullet(
          'Installation — pick the packages that match your project.',
        ),
        const DocBullet(
          'Introduction — see these terms in real code via a Notes/Todo '
          'app that the rest of the docs build on.',
        ),
        const DocBullet(
          'Features — the createFeature signature in depth, with the '
          'Notes feature as the running example.',
        ),
      ],
    );
  }

  static Widget _term(String name, String body) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [DocSubheading(name), DocParagraph(body)],
      ),
    );
  }
}
