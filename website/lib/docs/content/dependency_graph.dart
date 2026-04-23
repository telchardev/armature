import 'package:flutter/material.dart';

import '../../widgets/code_block.dart';
import '../../widgets/dag_diagram.dart';
import '../doc_typography.dart';

class DependencyGraphContent extends StatelessWidget {
  const DependencyGraphContent({super.key});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const DocTitle('Dependency graph'),
        const DocParagraph(
          'Features declare what they need; Armature builds a directed '
          'acyclic graph from those declarations and activates features '
          'in topological order. You never wire a bootstrap sequence by '
          'hand — the graph is the source of truth.',
        ),
        const DocHeading('What the graph looks like'),
        const DocParagraph(
          'Here is a small five-feature app. Arrows point from parent to '
          'child — i.e. from the feature that must be ready to the '
          'feature that needs it:',
        ),
        const _DiagramFrame(
          child: DagDiagram(
            nodes: [
              DagNode(id: 'layout', label: 'layoutFeature'),
              DagNode(id: 'auth', label: 'authFeature'),
              DagNode(
                id: 'counter',
                label: 'counterFeature',
                parentIds: ['layout'],
              ),
              DagNode(
                id: 'history',
                label: 'historyFeature',
                parentIds: ['layout'],
              ),
              DagNode(
                id: 'admin',
                label: 'adminFeature',
                parentIds: ['layout', 'auth'],
              ),
            ],
          ),
        ),
        const DocParagraph(
          'Activation flows downward. layoutFeature and authFeature are '
          'roots, so they start in parallel. counterFeature, '
          'historyFeature, and adminFeature wait for their parents — '
          'adminFeature is last because it needs both.',
        ),
        const DocHeading('Declaring dependencies'),
        const DocParagraph(
          'Two fields on createFeature describe edges. dependsOn lists '
          'required parents; optionalDependsOn lists parents that may or '
          'may not be present in the container.',
        ),
        const CodeBlock(code: _depsSource, language: 'dart'),
        const DocParagraph(
          'Required parents must be in the features list passed to '
          'ArmatureApp — a missing one is a graph construction error. '
          'Optional parents are tolerated: if they are absent, handlers '
          'registered against their ports silently skip.',
        ),
        const DocHeading('Topological activation'),
        const DocParagraph(
          'Siblings (nodes with disjoint ancestor chains) activate in '
          'parallel. Children wait for every required parent to settle '
          'in active state before their own onStart runs. This gives two '
          'guarantees:',
        ),
        const DocBullet(
          'When onStart runs on a feature, api.of(parent) is safe for '
          'every parent — stores are live and onStart finished there.',
        ),
        const DocBullet(
          'When a parent fails, required children cascade to disabled '
          'without their onStart ever firing — fail-closed, no partial '
          'state.',
        ),
        const DocHeading('Deactivation'),
        const DocParagraph(
          'On container disposal the cascade runs in reverse topological '
          'order: children tear down first, then parents. Each feature '
          'drains its cleanup bag (LIFO) before its parents do theirs, '
          'so a child never tries to read a parent store after that '
          'parent has started to dispose.',
        ),
        const DocHeading('Errors at construction'),
        const DocParagraph(
          'The graph detects three failure modes before your app runs:',
        ),
        Text.rich(
          TextSpan(
            children: [
              inlineCode('GraphCycleError', context),
              const TextSpan(
                text:
                    ' — the dependsOn / optionalDependsOn edges form a '
                    'cycle. Thrown at Graph construction; fix the cycle '
                    'and restart.',
              ),
            ],
          ),
          style: Theme.of(context).textTheme.bodyLarge?.copyWith(height: 1.6),
        ),
        const SizedBox(height: 12),
        Text.rich(
          TextSpan(
            children: [
              inlineCode('GraphNodeNotFoundError', context),
              const TextSpan(
                text:
                    ' — a feature lists a parent that is not in the '
                    'features list passed to ArmatureApp. Usually means '
                    'you forgot to add a feature to the container.',
              ),
            ],
          ),
          style: Theme.of(context).textTheme.bodyLarge?.copyWith(height: 1.6),
        ),
        const SizedBox(height: 12),
        Text.rich(
          TextSpan(
            children: [
              inlineCode('GraphFixedPointError', context),
              const TextSpan(
                text:
                    ' — rare; the cascade keeps generating new work past '
                    'the iteration limit. Indicates a visitor callback '
                    'that toggles targets in a cycle that never '
                    'stabilises.',
              ),
            ],
          ),
          style: Theme.of(context).textTheme.bodyLarge?.copyWith(height: 1.6),
        ),
        const SizedBox(height: 24),
        const DocHeading('What is next?'),
        const DocBullet(
          'Stores — the reactive state every feature in the graph owns '
          'and exposes to its descendants.',
        ),
        const DocBullet(
          'Ports — how the graph determines which handlers run when an '
          'owner applies its port.',
        ),
        const DocBullet(
          'Tasks — async work coordinated by stores, with strategies '
          'for concurrent call patterns.',
        ),
      ],
    );
  }
}

class _DiagramFrame extends StatelessWidget {
  const _DiagramFrame({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Container(
        decoration: BoxDecoration(
          color: scheme.surfaceContainerLowest,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: scheme.outlineVariant),
        ),
        padding: const EdgeInsets.all(16),
        child: Center(child: child),
      ),
    );
  }
}

const _depsSource = '''final adminFeature = createFeature(
  name: 'Admin',
  // Required — Armature will error if any is missing.
  dependsOn: [layoutFeature, authFeature],
  // Soft — if featureTogglesFeature is absent, admin still activates
  // and handlers registered on its ports are skipped.
  optionalDependsOn: [featureTogglesFeature],
  stores: (_) => (panel: AdminPanelStore()),
  exports: (api) => api.own,
);''';
