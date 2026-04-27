import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../code_block.dart';
import '../external_links.dart';
import '../max_width.dart';

const _sampleCode = '''final notesFeature = createFeature(
  name: 'Notes',
  dependsOn: [layoutFeature],
  stores: (_) => (notes: NotesStore()),
  exports: (api) => api.own,
)
  ..usePipe(layoutFeature.ports.tabs, (tabs, _) => [
        ...tabs,
        (id: 'notes', label: 'Notes', icon: Icons.note),
      ])
  ..useSingleSlot(layoutFeature.ports.body('notes'),
      (_, api) => NotesTab(store: api.own.notes));

// Search auto-activates only when notes is non-empty.
final searchFeature = createFeature(
  name: 'Search',
  dependsOn: [notesFeature],
)..activation(whenStoreState(
  feature: notesFeature,
  store: (e) => e.notes,
  predicate: (s) => s.items.isNotEmpty,
));''';

class HeroSection extends StatelessWidget {
  const HeroSection({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 72),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            theme.colorScheme.primaryContainer.withValues(alpha: 0.25),
            theme.colorScheme.surface,
          ],
        ),
      ),
      child: MaxWidth(
        child: LayoutBuilder(
          builder: (context, constraints) {
            final isWide = constraints.maxWidth >= 900;
            if (isWide) {
              return const Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Expanded(flex: 5, child: _HeroText()),
                  SizedBox(width: 48),
                  Expanded(flex: 6, child: _HeroCode()),
                ],
              );
            }
            return const Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [_HeroText(), SizedBox(height: 48), _HeroCode()],
            );
          },
        ),
      ),
    );
  }
}

class _HeroText extends StatelessWidget {
  const _HeroText();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'FLUTTER FRAMEWORK',
          style: theme.textTheme.labelMedium?.copyWith(
            letterSpacing: 1.5,
            color: theme.colorScheme.primary,
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 16),
        Text(
          'Feature-based architecture\nfor Flutter.',
          style: theme.textTheme.displayMedium?.copyWith(
            fontWeight: FontWeight.w700,
            height: 1.1,
          ),
        ),
        const SizedBox(height: 24),
        Text(
          'Organize code by vertical features. Armature resolves '
          'initialization order from a dependency graph, wires features '
          'together through typed ports, and gives you MobX-style reactive '
          'stores out of the box.',
          style: theme.textTheme.bodyLarge?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
            height: 1.5,
          ),
        ),
        const SizedBox(height: 32),
        Wrap(
          spacing: 12,
          runSpacing: 12,
          children: [
            FilledButton.icon(
              onPressed: () => context.go('/docs/quickstart'),
              icon: const Icon(Icons.rocket_launch_outlined),
              label: const Text('Get started'),
              style: FilledButton.styleFrom(
                padding: const EdgeInsets.symmetric(
                  horizontal: 24,
                  vertical: 16,
                ),
              ),
            ),
            OutlinedButton.icon(
              onPressed: () => openExternal(kGitHubUrl),
              icon: const Icon(Icons.code),
              label: const Text('GitHub'),
              style: OutlinedButton.styleFrom(
                padding: const EdgeInsets.symmetric(
                  horizontal: 24,
                  vertical: 16,
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class _HeroCode extends StatelessWidget {
  const _HeroCode();

  @override
  Widget build(BuildContext context) {
    return const CodeBlock(code: _sampleCode, language: 'dart');
  }
}
