import 'package:flutter/material.dart';

import '../../widgets/code_block.dart';
import '../doc_typography.dart';

class IntroductionContent extends StatelessWidget {
  const IntroductionContent({super.key});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const DocTitle('Introduction'),
        const DocParagraph(
          'The Quickstart showed the smallest possible armature app: a '
          'counter and a layout, two features composing through one '
          'port. From here on the rest of the docs use a Notes/Todo app '
          'as the running example — same structure, just a more '
          'realistic store and room to grow into tasks, search, and a '
          'tabbed UI.',
        ),
        const DocHeading('From counter to notes'),
        const DocParagraph(
          'The shape is identical to the Quickstart. Only the store '
          'changes — instead of an int, we keep a list of notes:',
        ),
        const CodeBlock(code: _notesStoreCode, language: 'dart'),
        const DocParagraph(
          'NotesStore lives inside notesFeature, which still depends on '
          'a layoutFeature that owns the body slot. The wiring is the '
          'same, just plugging Notes UI instead of a counter:',
        ),
        const CodeBlock(code: _notesFeatureCode, language: 'dart'),
        const DocParagraph(
          'The bootstrap is unchanged — list both features, mount the '
          'layout root:',
        ),
        const CodeBlock(code: _bootstrapCode, language: 'dart'),
        const DocHeading('Where this is going'),
        const DocParagraph(
          'Each deeper docs page picks up this Notes app and adds one '
          'concept on top:',
        ),
        const DocBullet(
          'Stores — NotesStore in detail, plus a debounced persist task.',
        ),
        const DocBullet(
          'Tasks — the lifecycle (TaskIdle / TaskPending / TaskDone / '
          'TaskFailed), strategies, and TError choice.',
        ),
        const DocBullet(
          'Ports — a searchFeature joins the app, plugs a search field '
          'into a layout pipe, and reads notes through api.of(notesFeature).',
        ),
        const DocBullet(
          'Dependency graph — three features, two edges, one cycle '
          'detection error to walk through.',
        ),
        const DocBullet(
          'Activation helpers — search auto-disables when notes is empty '
          'using whenStoreState.',
        ),
        const DocBullet(
          'Slot widgets — the layout grows tabs (notes / search) via a '
          'keyed slot.',
        ),
        const DocHeading('What is next?'),
        const DocBullet(
          'Features — the createFeature signature in depth, with the '
          'Notes feature as the running example.',
        ),
        const DocBullet(
          'Dependency graph — how dependsOn resolves at startup.',
        ),
        const DocBullet(
          'Stores — NotesStore in full, plus the persist task pattern.',
        ),
      ],
    );
  }
}

const _notesStoreCode = '''typedef Note = ({String id, String text});
typedef NotesState = ({List<Note> items});

class NotesStore extends Store<NotesState> {
  NotesStore() : super(state: (items: const []));

  void add(String text) {
    final id = 'n\${state.items.length}';
    update((s) => (items: [...s.items, (id: id, text: text)]));
  }
}''';

const _notesFeatureCode =
    '''final bodySlot = createSingleSlot(name: 'layout.body');

final layoutFeature = createFeature(
  name: 'Layout',
  ports: (bodySlot: bodySlot),
);

final layoutRoot = createFeatureRoot(
  feature: layoutFeature,
  widget: Scaffold(
    appBar: AppBar(title: const Text('Notes')),
    body: SingleSlotProvider(
      slot: bodySlot,
      data: null,
      builder: (child, _) => child ?? const SizedBox.shrink(),
    ),
  ),
);

final notesFeature = createFeature(
  name: 'Notes',
  dependsOn: [layoutFeature],
  stores: (_) => (notes: NotesStore()),
  exports: (api) => api.own,
)..useSingleSlot(layoutFeature.ports.bodySlot, (_, api) {
  return Padding(
    padding: const EdgeInsets.all(16),
    child: Column(
      children: [
        FilledButton.icon(
          icon: const Icon(Icons.add),
          label: const Text('Add note'),
          onPressed: () => api.own.notes.add('Note \${DateTime.now()}'),
        ),
        const SizedBox(height: 16),
        Expanded(
          child: StoreBuilder<NotesStore>(
            builder: (_, store) => ListView(
              children: [
                for (final note in store.state.items)
                  ListTile(title: Text(note.text)),
              ],
            ),
          ),
        ),
      ],
    ),
  );
});''';

const _bootstrapCode = '''void main() {
  runApp(ArmatureApp(
    features: [layoutFeature, notesFeature],
    child: MaterialApp(home: layoutRoot(data: null)),
  ));
}''';
