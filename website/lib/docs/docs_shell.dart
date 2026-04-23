import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import 'docs_registry.dart';
import 'docs_sidebar.dart';
import 'docs_tree.dart';

/// Sidebar + content layout for doc pages.
///
/// Wide layouts show the sidebar permanently on the left. Narrow layouts
/// replace it with a "Browse docs" button that opens the sidebar in a modal
/// bottom sheet.
class DocsShell extends StatelessWidget {
  const DocsShell({super.key, required this.slug});

  final String slug;

  static const double _breakpoint = 900;
  static const double _sidebarWidth = 260;
  static const double _contentMaxWidth = 780;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final isWide = constraints.maxWidth >= _breakpoint;
        if (isWide) {
          return Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SizedBox(
                width: _sidebarWidth,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    border: Border(
                      right: BorderSide(
                        color: Theme.of(context).colorScheme.outlineVariant,
                      ),
                    ),
                  ),
                  child: DocsSidebar(activeSlug: slug),
                ),
              ),
              Expanded(child: _Content(slug: slug)),
            ],
          );
        }
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _NarrowTopBar(slug: slug),
            Expanded(child: _Content(slug: slug)),
          ],
        );
      },
    );
  }
}

class _NarrowTopBar extends StatelessWidget {
  const _NarrowTopBar({required this.slug});

  final String slug;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final entry = findEntry(slug);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerLow,
        border: Border(bottom: BorderSide(color: scheme.outlineVariant)),
      ),
      child: Row(
        children: [
          TextButton.icon(
            onPressed: () => _openSheet(context),
            icon: const Icon(Icons.menu_book_outlined),
            label: const Text('Browse docs'),
          ),
          const Spacer(),
          if (entry != null)
            Text(
              entry.title,
              style: Theme.of(
                context,
              ).textTheme.bodyMedium?.copyWith(color: scheme.onSurfaceVariant),
            ),
        ],
      ),
    );
  }

  void _openSheet(BuildContext context) {
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (sheetContext) => FractionallySizedBox(
        heightFactor: 0.85,
        child: DocsSidebar(
          activeSlug: slug,
          onNavigate: () => Navigator.of(sheetContext).pop(),
        ),
      ),
    );
  }
}

class _Content extends StatelessWidget {
  const _Content({required this.slug});

  final String slug;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      // Reset scroll to top when navigating between doc pages — the
      // key forces a fresh ScrollController per slug.
      key: ValueKey('docs:$slug'),
      padding: const EdgeInsets.symmetric(horizontal: 40, vertical: 56),
      child: Align(
        alignment: Alignment.topLeft,
        child: ConstrainedBox(
          constraints: const BoxConstraints(
            maxWidth: DocsShell._contentMaxWidth,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              resolveDocContent(slug),
              const SizedBox(height: 56),
              _PrevNextNav(slug: slug),
            ],
          ),
        ),
      ),
    );
  }
}

class _PrevNextNav extends StatelessWidget {
  const _PrevNextNav({required this.slug});

  final String slug;

  @override
  Widget build(BuildContext context) {
    final prev = previousEntry(slug);
    final next = nextEntry(slug);
    if (prev == null && next == null) {
      return const SizedBox.shrink();
    }
    return Padding(
      padding: const EdgeInsets.only(top: 16),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (prev != null)
            Expanded(child: _NavCard(entry: prev, isNext: false))
          else
            const Spacer(),
          const SizedBox(width: 16),
          if (next != null)
            Expanded(child: _NavCard(entry: next, isNext: true))
          else
            const Spacer(),
        ],
      ),
    );
  }
}

class _NavCard extends StatelessWidget {
  const _NavCard({required this.entry, required this.isNext});

  final DocEntry entry;
  final bool isNext;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    return InkWell(
      onTap: () => context.go('/docs/${entry.slug}'),
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: scheme.outlineVariant),
        ),
        child: Column(
          crossAxisAlignment: isNext
              ? CrossAxisAlignment.end
              : CrossAxisAlignment.start,
          children: [
            Text(
              isNext ? 'Next →' : '← Previous',
              style: textTheme.labelMedium?.copyWith(
                color: scheme.onSurfaceVariant,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              entry.title,
              style: textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
