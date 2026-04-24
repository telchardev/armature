import 'package:flutter/material.dart';

import '../../widgets/code_block.dart';
import '../doc_typography.dart';

class FeaturesContent extends StatelessWidget {
  const FeaturesContent({super.key});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const DocTitle('Features'),
        const DocParagraph(
          'A feature is a module that owns a slice of the app. It declares '
          'what it depends on, holds its own reactive stores, exposes a '
          'typed surface to descendants, and registers handlers on ports '
          'from ancestors. Features are the unit of composition in '
          'Armature — you build an app by listing them, and the framework '
          'resolves the rest.',
        ),
        const DocHeading('createFeature signature'),
        const DocParagraph(
          'Every feature is created through createFeature. The function '
          'takes a name, an optional dependency list, optional port and '
          'store factories, and an exports factory that defines what '
          'descendants see:',
        ),
        const CodeBlock(code: _signatureSource, language: 'dart'),
        const DocParagraph(
          'Six named parameters cover every case. Stateless features (a '
          'pure port extension, for example) can omit stores and exports '
          'entirely. Features that own stores must also provide exports — '
          'the framework refuses the configuration otherwise.',
        ),
        const DocHeading('Dependencies'),
        const DocParagraph(
          'dependsOn lists the ancestors the feature needs. The framework '
          'activates dependencies first, so by the time this feature runs, '
          'all of them are already available through api.of(...).',
        ),
        const DocParagraph(
          'optionalDependsOn marks ancestors that may be absent. A feature '
          'can register handlers on ports from optional parents, but if '
          'the parent is not in the container, those handlers are silently '
          'skipped. Use this to ship plugins that light up only when a '
          'host feature is present.',
        ),
        const CodeBlock(code: _depsSource, language: 'dart'),
        const DocHeading('Stores and exports'),
        const DocParagraph(
          'The stores factory returns a record of Store instances. The '
          'framework tracks them via a zone-scoped marker, so the factory '
          'must be synchronous. Each store is keyed by its runtime type — '
          'two stores of the same type in one feature throws at '
          'construction.',
        ),
        const DocParagraph(
          'The exports factory returns whatever descendants should see. '
          'Most features pass through own stores with exports: (api) => '
          'api.own; a feature that wants to narrow the surface can return '
          'a smaller record:',
        ),
        const CodeBlock(code: _storesSource, language: 'dart'),
        const DocParagraph(
          'Inside stores and exports the api argument gives access to '
          'parent features. api.own is not available in the stores factory '
          '(stores are being constructed), but api.of(someParent) is.',
        ),
        const DocHeading('Ports'),
        const DocParagraph(
          'The ports parameter is a record of port instances — the typed '
          'extension points this feature exposes. Port instances are '
          'usually declared in a sibling file and wired in directly:',
        ),
        const CodeBlock(code: _portsSource, language: 'dart'),
        const DocParagraph(
          'See the Ports page for how pipes, behaviors, and slots behave '
          'and how descendants contribute handlers.',
        ),
        const DocHeading('Lifecycle hooks'),
        const DocParagraph(
          'Two hooks control when and how a feature runs. Both are chained '
          'on the feature with cascade syntax.',
        ),
        Text.rich(
          TextSpan(
            children: [
              const TextSpan(text: 'Without '),
              inlineCode('activation', context),
              const TextSpan(
                text:
                    ', a feature auto-activates when the container starts. '
                    'Pass a setup callback to gate activation behind a toggle '
                    '— the framework wires stores eagerly but holds the '
                    'feature in an inactive state until your setup turns it '
                    'on. Register teardown via ',
              ),
              inlineCode('cleanup.add(disposer)', context),
              const TextSpan(
                text: '; the bag runs LIFO on the next deactivation.',
              ),
            ],
          ),
          style: Theme.of(context).textTheme.bodyLarge?.copyWith(height: 1.6),
        ),
        const SizedBox(height: 16),
        Text.rich(
          TextSpan(
            children: [
              inlineCode('onStart', context),
              const TextSpan(
                text:
                    ' fires on every inactive → active transition. Stores '
                    'are already built at this point. If the callback '
                    'throws, the feature settles in disabled state and its '
                    'required descendants cascade closed. For best-effort '
                    'work whose failure should not disable the feature, '
                    'wrap the call in local try/catch.',
              ),
            ],
          ),
          style: Theme.of(context).textTheme.bodyLarge?.copyWith(height: 1.6),
        ),
        const SizedBox(height: 16),
        const CodeBlock(code: _lifecycleSource, language: 'dart'),
        const DocHeading('Putting it together'),
        const DocParagraph(
          'A typical feature file is short. Here is a counter feature that '
          'reads a flag from a toggle parent, adds a tab to a layout '
          'parent, and exposes its store to everyone downstream:',
        ),
        const CodeBlock(code: _togetherSource, language: 'dart'),
        const DocHeading('What is next?'),
        const DocBullet(
          'Dependency graph — how dependsOn resolves at runtime, cycle '
          'detection, and activation order.',
        ),
        const DocBullet(
          'Stores — the reactive state features own, with tasks for '
          'async side effects.',
        ),
        const DocBullet('Ports — pipes, behaviors, and slots in detail.'),
      ],
    );
  }
}

const _signatureSource = '''Feature<TStores, TExports, TPorts> createFeature<
  TStores extends Object?,
  TExports extends Object?,
  TPorts extends Object?
>({
  required String name,
  List<AnyFeature> dependsOn,
  List<AnyFeature> optionalDependsOn,
  TPorts? ports,
  StoresFactory<TStores>? stores,
  ExportsFactory<TStores, TExports>? exports,
})''';

const _depsSource = '''final counterFeature = createFeature(
  name: 'Counter',
  dependsOn: [layoutFeature],
  optionalDependsOn: [featureTogglesFeature],
  stores: (_) => (counter: CounterStore()),
  exports: (api) => api.own,
);''';

const _storesSource = '''final authFeature = createFeature(
  name: 'Auth',
  stores: (_) => (
    session: SessionStore(),
    prefs: PrefsStore(),
  ),
  // Hide PrefsStore from descendants — they only see session.
  exports: (api) => (session: api.own.session),
);''';

const _portsSource = '''// layout/ports.dart
final tabsPipe = createPipe<List<TabSpec>>(name: 'layout.tabs');
final fabSlot = createMultiSlot<LayoutMode>(name: 'layout.fab');

// layout/config.dart
final layoutFeature = createFeature(
  name: 'Layout',
  ports: (tabsPipe: tabsPipe, fabSlot: fabSlot),
  stores: (_) => (activeTab: ActiveTabStore()),
  exports: (api) => api.own,
);''';

const _lifecycleSource = '''final adminFeature = createFeature(
  name: 'Admin',
  dependsOn: [authFeature],
  stores: (_) => (panel: AdminPanelStore()),
  exports: (api) => api.own,
)
  ..activation((parentApi, toggle, cleanup) {
    // Gate on the session role — flip active/inactive as it changes.
    final disposer = parentApi.of(authFeature).session.subscribe(
      (_, current) => toggle(
        current.role == Role.admin
            ? ToggleState.active
            : ToggleState.inactive,
      ),
      fireImmediately: true,
    );
    cleanup.add(disposer);
  })
  ..onStart((api, cleanup) {
    api.own.panel.loadInitialData();
  });''';

const _togetherSource = '''final counterFeature = createFeature(
  name: 'Counter',
  dependsOn: [layoutFeature],
  optionalDependsOn: [featureTogglesFeature],
  stores: (_) => (counter: CounterStore()),
  exports: (api) => api.own,
)
  ..usePipe(layoutFeature.ports.tabsPipe, (tabs, _) => [
        ...tabs,
        (id: 'counter', label: 'Counter', icon: Icons.add),
      ])
  ..useSingleSlot(
    layoutFeature.ports.bodyKeyedSlot('counter'),
    (mode, api) => CounterTab(store: api.own.counter, mode: mode),
  );''';
