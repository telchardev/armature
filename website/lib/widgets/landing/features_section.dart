import 'package:flutter/material.dart';

import '../max_width.dart';

class FeaturesSection extends StatelessWidget {
  const FeaturesSection({super.key});

  static const _items = <_FeatureData>[
    _FeatureData(
      icon: Icons.widgets_outlined,
      title: 'Feature-based modules',
      body:
          'Organize code by vertical features. Each feature declares its own '
          'stores, ports, and wiring to the rest of the app.',
    ),
    _FeatureData(
      icon: Icons.account_tree_outlined,
      title: 'Dependency graph',
      body:
          'Init order is resolved from a declared `dependsOn` graph via '
          'topological sort. No manual bootstrap sequencing.',
    ),
    _FeatureData(
      icon: Icons.bolt_outlined,
      title: 'Reactive primitives',
      body:
          'MobX-style Atoms and Reactions with automatic dependency tracking. '
          'Works with plain Dart — no codegen required.',
    ),
    _FeatureData(
      icon: Icons.link_outlined,
      title: 'Typed ports',
      body:
          'Pipes, behaviors, and slots as typed contracts between features. '
          'Features stay decoupled without losing type safety.',
    ),
  ];

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 72),
      child: MaxWidth(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'What you get',
              style: theme.textTheme.headlineMedium?.copyWith(
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Four primitives that compose into a complete app architecture.',
              style: theme.textTheme.bodyLarge?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 40),
            LayoutBuilder(
              builder: (context, constraints) {
                final columns = constraints.maxWidth >= 900 ? 2 : 1;
                return _Grid(columns: columns, items: _items);
              },
            ),
          ],
        ),
      ),
    );
  }
}

class _FeatureData {
  const _FeatureData({
    required this.icon,
    required this.title,
    required this.body,
  });

  final IconData icon;
  final String title;
  final String body;
}

class _Grid extends StatelessWidget {
  const _Grid({required this.columns, required this.items});

  final int columns;
  final List<_FeatureData> items;

  @override
  Widget build(BuildContext context) {
    const gap = 20.0;
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = (constraints.maxWidth - gap * (columns - 1)) / columns;
        return Wrap(
          spacing: gap,
          runSpacing: gap,
          children: [
            for (final item in items)
              SizedBox(
                width: width,
                child: _FeatureCard(data: item),
              ),
          ],
        );
      },
    );
  }
}

class _FeatureCard extends StatelessWidget {
  const _FeatureCard({required this.data});

  final _FeatureData data;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Container(
      padding: const EdgeInsets.all(28),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: scheme.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: scheme.primaryContainer,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(data.icon, color: scheme.onPrimaryContainer, size: 24),
          ),
          const SizedBox(height: 20),
          Text(
            data.title,
            style: theme.textTheme.titleLarge?.copyWith(
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 10),
          Text(
            data.body,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: scheme.onSurfaceVariant,
              height: 1.5,
            ),
          ),
        ],
      ),
    );
  }
}
