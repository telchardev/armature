import 'package:flutter/material.dart';

// Deferred so the 6 live Armature demos (≈hundreds of KB of compiled
// Dart) are only downloaded when the user actually navigates to
// `/examples/*`. Docs-only visits never load them.
import 'examples_registry.dart' deferred as examples_content;
import 'examples_sidebar.dart';
import 'examples_tree.dart';

/// Sidebar + content layout for example pages.
///
/// Mirrors [DocsShell] but without prev/next navigation — examples are
/// browsed non-sequentially.
class ExamplesShell extends StatelessWidget {
  const ExamplesShell({super.key, required this.slug});

  final String slug;

  static const double _breakpoint = 900;
  static const double _sidebarWidth = 260;
  static const double _contentMaxWidth = 960;

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
                  child: ExamplesSidebar(activeSlug: slug),
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
    final entry = findExample(slug);
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
            icon: const Icon(Icons.apps_outlined),
            label: const Text('Browse examples'),
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
        child: ExamplesSidebar(
          activeSlug: slug,
          onNavigate: () => Navigator.of(sheetContext).pop(),
        ),
      ),
    );
  }
}

class _Content extends StatefulWidget {
  const _Content({required this.slug});

  final String slug;

  @override
  State<_Content> createState() => _ContentState();
}

class _ContentState extends State<_Content> {
  // `loadLibrary()` is idempotent — after the first call it returns a
  // cached future, so navigating between examples after the initial
  // load resolves immediately.
  late final Future<void> _load = examples_content.loadLibrary();

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<void>(
      future: _load,
      builder: (context, snapshot) {
        final Widget child;
        if (snapshot.hasError) {
          child = Padding(
            padding: const EdgeInsets.all(48),
            child: Text(
              'Failed to load example: ${snapshot.error}',
              style: Theme.of(context).textTheme.bodyMedium,
            ),
          );
        } else if (snapshot.connectionState != ConnectionState.done) {
          child = const Padding(
            padding: EdgeInsets.all(48),
            child: Center(child: CircularProgressIndicator()),
          );
        } else {
          child = examples_content.resolveExampleContent(widget.slug);
        }
        return SingleChildScrollView(
          // Reset scroll to top when navigating between examples — the
          // key forces a fresh ScrollController per slug.
          key: ValueKey('examples:${widget.slug}'),
          padding: const EdgeInsets.symmetric(horizontal: 40, vertical: 56),
          child: Align(
            alignment: Alignment.topLeft,
            child: ConstrainedBox(
              constraints: const BoxConstraints(
                maxWidth: ExamplesShell._contentMaxWidth,
              ),
              child: child,
            ),
          ),
        );
      },
    );
  }
}
