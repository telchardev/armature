import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import 'examples_tree.dart';

class ExamplesSidebar extends StatelessWidget {
  const ExamplesSidebar({super.key, required this.activeSlug, this.onNavigate});

  final String activeSlug;
  final VoidCallback? onNavigate;

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 24, 16, 32),
      children: [
        for (final section in examplesTree) ...[
          _SectionHeader(title: section.title),
          for (final entry in section.entries)
            _EntryTile(
              entry: entry,
              selected: entry.slug == activeSlug,
              onTap: () {
                context.go('/examples/${entry.slug}');
                onNavigate?.call();
              },
            ),
          const SizedBox(height: 20),
        ],
      ],
    );
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({required this.title});

  final String title;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 6),
      child: Text(
        title.toUpperCase(),
        style: Theme.of(context).textTheme.labelSmall?.copyWith(
          letterSpacing: 1.2,
          fontWeight: FontWeight.w700,
          color: Theme.of(context).colorScheme.onSurfaceVariant,
        ),
      ),
    );
  }
}

class _EntryTile extends StatelessWidget {
  const _EntryTile({
    required this.entry,
    required this.selected,
    required this.onTap,
  });

  final ExampleEntry entry;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Material(
      color: selected ? scheme.secondaryContainer : Colors.transparent,
      borderRadius: BorderRadius.circular(8),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          child: Text(
            entry.title,
            style: TextStyle(
              color: selected ? scheme.onSecondaryContainer : scheme.onSurface,
              fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
            ),
          ),
        ),
      ),
    );
  }
}
