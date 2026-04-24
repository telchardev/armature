import 'package:flutter/material.dart';

import '../../widgets/code_block.dart';
import '../doc_typography.dart';

class GettingStartedContent extends StatelessWidget {
  const GettingStartedContent({super.key});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const DocTitle('Getting started'),
        const DocParagraph(
          'Armature is a feature-based framework for Flutter and pure Dart '
          'applications. You compose your app from self-contained features, '
          'each declaring its dependencies, stores, and typed ports. The '
          'framework resolves the graph, wires everything together, and hands '
          'you back a reactive runtime.',
        ),
        const DocParagraph(
          'This page walks you from installation to your first working '
          'feature. It should take about five minutes.',
        ),
        const DocHeading('Install'),
        const DocParagraph('Add the core package and the Flutter integration:'),
        const CodeBlock(
          code: 'flutter pub add armature armature_flutter',
          language: 'bash',
        ),
        const DocParagraph(
          'For pure Dart apps, drop armature_flutter. If you only need the '
          'reactive primitives, armature_reactive stands on its own.',
        ),
        const DocHeading('What is a feature?'),
        const DocParagraph(
          'A feature is a module that owns a slice of your app — its stores, '
          'its UI, and the contracts it exposes to others. Features declare '
          'what they depend on; Armature resolves the init order and '
          'activates them in topological sequence.',
        ),
        Text.rich(
          TextSpan(
            children: [
              const TextSpan(text: 'Each feature is created with '),
              inlineCode('createFeature', context),
              const TextSpan(
                text:
                    ' and lives in its own directory — typically a config '
                    'file, one or more stores, and a UI folder.',
              ),
            ],
          ),
          style: Theme.of(context).textTheme.bodyLarge?.copyWith(height: 1.6),
        ),
        const SizedBox(height: 16),
        const DocHeading('Define your first feature'),
        const DocParagraph(
          'Here is a counter feature that attaches a tab and a FAB to a '
          'host layout feature:',
        ),
        const CodeBlock(code: _counterFeatureCode, language: 'dart'),
        const DocParagraph(
          'Three things to notice. First, the feature declares dependsOn — '
          'Armature will activate layoutFeature before counterFeature. '
          'Second, stores is a record; each store is keyed by name and '
          'available later via api.own. Third, usePipe and useSingleSlot '
          'bind into typed ports exposed by the host feature.',
        ),
        const DocHeading('Bootstrap the app'),
        const DocParagraph(
          'List your features in ArmatureApp. The framework resolves the '
          'graph, activates each feature, and renders the root widget:',
        ),
        const CodeBlock(code: _bootstrapCode, language: 'dart'),
        const DocParagraph(
          'That is the whole loop: declare features, list them, run. As the '
          'app grows you add more features, wire them through ports, and '
          'never touch the bootstrap code again.',
        ),
        const DocHeading('What is next?'),
        const DocBullet(
          'Installation — the full per-package breakdown (armature, '
          'armature_flutter, armature_reactive, armature_graph) and SDK '
          'requirements.',
        ),
        const DocBullet(
          'Features — the createFeature signature covered in depth, '
          'plus lifecycle hooks.',
        ),
      ],
    );
  }
}

const _counterFeatureCode = '''final counterFeature = createFeature(
  name: 'Counter',
  dependsOn: [layoutFeature],
  stores: (_) => (counter: CounterStore()),
  exports: (api) => api.own,
)
  ..usePipe(layoutFeature.ports.tabsPipe, (tabs, _) => [
        ...tabs,
        (id: 'counter', label: 'Counter', icon: Icons.add_circle_outline),
      ])
  ..useSingleSlot(layoutFeature.ports.bodyKeyedSlot('counter'),
      (mode, api) => CounterTab(store: api.own.counter, mode: mode))
  ..useMultiSlot(layoutFeature.ports.fabSlot, (_, api) {
    if (api.of(layoutFeature).activeTab.state != 'counter') return null;
    return FloatingActionButton(
      onPressed: () => api.own.counter.increment(),
      child: const Icon(Icons.add),
    );
  });''';

const _bootstrapCode = '''void main() {
  runApp(
    ArmatureApp(
      features: [
        layoutFeature,
        counterFeature,
        historyFeature,
      ],
      child: layoutRoot(data: null),
    ),
  );
}''';
