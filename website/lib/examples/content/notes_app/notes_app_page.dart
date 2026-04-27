import 'package:armature_flutter/armature_flutter.dart';
import 'package:flutter/material.dart';

import '../../../docs/doc_typography.dart';
import '../../../widgets/external_links.dart';
import '../../../widgets/loaded_code_block.dart';
import 'notes_app_widget.dart';

class NotesAppPage extends StatelessWidget {
  const NotesAppPage({super.key});

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 2,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const DocTitle('Notes app'),
          const DocParagraph(
            'A 5-feature Notes/Todo app — the running example used across '
            'the docs. Layout owns the Scaffold and four ports (tabs '
            'pipe, body keyed slot, fab + actions multi slots); Notes / '
            'Search / Settings each plug a tab; Analytics gates on the '
            'toggle store and renders a note-count chip in the AppBar.',
          ),
          const DocParagraph(
            'Add a note to see Search activate (whenStoreState on '
            'notes.items.isNotEmpty). Open Settings → flip Analytics off '
            'to see the chip disappear via the activation cascade.',
          ),
          const SizedBox(height: 8),
          const _Tabs(),
          const SizedBox(height: 24),
          const SizedBox(
            height: 580,
            child: TabBarView(
              physics: NeverScrollableScrollPhysics(),
              children: [_PreviewTab(), _CodeTab()],
            ),
          ),
          const SizedBox(height: 32),
          Text(
            'For a larger multi-feature reference app (auth, admin, '
            'feature toggles, history, inspector, theming, debug '
            'overlay), see armature_example.',
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 8),
          OutlinedButton.icon(
            onPressed: () =>
                openExternal('$kGitHubUrl/tree/main/examples/armature_example'),
            icon: const Icon(Icons.open_in_new),
            label: const Text('Open armature_example on GitHub'),
          ),
        ],
      ),
    );
  }
}

class _Tabs extends StatelessWidget {
  const _Tabs();

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.centerLeft,
      child: TabBar(
        isScrollable: true,
        tabAlignment: TabAlignment.start,
        dividerHeight: 0,
        tabs: const [
          Tab(text: 'Preview'),
          Tab(text: 'Code'),
        ],
      ),
    );
  }
}

class _PreviewTab extends StatefulWidget {
  const _PreviewTab();

  @override
  State<_PreviewTab> createState() => _PreviewTabState();
}

class _PreviewTabState extends State<_PreviewTab>
    with AutomaticKeepAliveClientMixin {
  @override
  bool get wantKeepAlive => true;

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return const Center(
      child: SingleChildScrollView(
        padding: EdgeInsets.symmetric(vertical: 16),
        child: _NotesAppEmbed(),
      ),
    );
  }
}

/// Embed-only wrapper — gives the demo a fixed-size phone-ish frame
/// so it renders nicely inside the website's max-width column. The
/// canonical user-facing source in `notes_app_widget.dart` skips this
/// wrapper and uses `runApp(MaterialApp(...))` directly.
class _NotesAppEmbed extends StatelessWidget {
  const _NotesAppEmbed();

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      constraints: const BoxConstraints(maxWidth: 520),
      height: 540,
      decoration: BoxDecoration(
        color: scheme.surfaceContainerLowest,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: scheme.outlineVariant),
      ),
      clipBehavior: Clip.antiAlias,
      child: ArmatureApp(
        features: [
          layoutFeature,
          notesFeature,
          searchFeature,
          featureTogglesFeature,
          analyticsFeature,
        ],
        child: layoutRoot(data: null),
      ),
    );
  }
}

class _CodeTab extends StatelessWidget {
  const _CodeTab();

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.only(top: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: const [
          _Caption('notes_app.dart'),
          LoadedCodeBlock(
            path: 'lib/examples/content/notes_app/notes_app_widget.dart',
          ),
        ],
      ),
    );
  }
}

class _Caption extends StatelessWidget {
  const _Caption(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Text(
        text,
        style: Theme.of(
          context,
        ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600),
      ),
    );
  }
}
