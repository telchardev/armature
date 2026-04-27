import 'package:armature/armature.dart';
import 'package:armature_flutter/armature_flutter.dart';
import 'package:flutter/material.dart';

// ── Layout feature ──────────────────────────────────────────────────────────

typedef TabSpec = ({String id, String label, IconData icon});
typedef ActiveTabState = ({String id});

class ActiveTabStore extends Store<ActiveTabState> {
  ActiveTabStore() : super(state: (id: 'notes'));
  void select(String id) => update((_) => (id: id));
}

final tabsPipe = createPipe<List<TabSpec>>(name: 'layout.tabs');
final bodyKeyedSlot = createKeyedSingleSlot<String>(name: 'layout.body');
final fabSlot = createMultiSlot<String>(name: 'layout.fab');
final actionsSlot = createMultiSlot(name: 'layout.actions');

final layoutFeature = createFeature(
  name: 'Layout',
  ports: (
    tabs: tabsPipe,
    body: bodyKeyedSlot,
    fab: fabSlot,
    actions: actionsSlot,
  ),
  stores: (_) => (activeTab: ActiveTabStore()),
  exports: (api) => api.own,
);

final layoutRoot = createFeatureRoot(
  feature: layoutFeature,
  widget: const LayoutShell(),
);

class LayoutShell extends StatelessWidget {
  const LayoutShell({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Notes'),
        actions: [
          MultiSlotProvider(
            slot: actionsSlot,
            data: null,
            builder: (kids, _) => Row(children: kids),
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: StoreBuilder<ActiveTabStore>(
        builder: (_, store) => SingleSlotProvider(
          slot: bodyKeyedSlot(store.state.id),
          data: store.state.id,
          builder: (child, _) =>
              child ?? const Center(child: Text('Empty tab')),
        ),
      ),
      floatingActionButton: StoreBuilder<ActiveTabStore>(
        builder: (_, store) => MultiSlotProvider(
          slot: fabSlot,
          data: store.state.id,
          builder: (kids, _) {
            if (kids.isEmpty) return const SizedBox.shrink();
            return Column(mainAxisSize: MainAxisSize.min, children: kids);
          },
        ),
      ),
      bottomNavigationBar: PipeProvider<List<TabSpec>>(
        pipe: tabsPipe,
        initialValue: const <TabSpec>[],
        builder: (tabs, _) {
          // NavigationBar requires at least 2 destinations.
          if (tabs.length < 2) return const SizedBox.shrink();
          return StoreBuilder<ActiveTabStore>(
            builder: (_, store) {
              var selectedIdx = tabs.indexWhere((t) => t.id == store.state.id);
              if (selectedIdx == -1) {
                // Active tab vanished (e.g. Search deactivated when notes
                // emptied) — fall back to the first available tab so the
                // navbar stays in a valid state.
                selectedIdx = 0;
                WidgetsBinding.instance.addPostFrameCallback((_) {
                  store.select(tabs[0].id);
                });
              }
              return NavigationBar(
                selectedIndex: selectedIdx,
                destinations: [
                  for (final tab in tabs)
                    NavigationDestination(
                      icon: Icon(tab.icon),
                      label: tab.label,
                    ),
                ],
                onDestinationSelected: (idx) => store.select(tabs[idx].id),
              );
            },
          );
        },
      ),
    );
  }
}

// ── Notes feature ───────────────────────────────────────────────────────────

typedef Note = ({String id, String text});
typedef NotesState = ({List<Note> items});

class NotesStore extends Store<NotesState> {
  NotesStore() : super(state: (items: const []));

  void add(String text) {
    final id = 'n${DateTime.now().microsecondsSinceEpoch}';
    update((s) => (items: [...s.items, (id: id, text: text)]));
  }

  void remove(String id) {
    update((s) => (items: s.items.where((n) => n.id != id).toList()));
  }
}

final notesFeature =
    createFeature(
        name: 'Notes',
        dependsOn: [layoutFeature],
        stores: (_) => (notes: NotesStore()),
        exports: (api) => api.own,
      )
      ..usePipe(layoutFeature.ports.tabs, (tabs, _) {
        return [
          ...tabs,
          (id: 'notes', label: 'Notes', icon: Icons.note_outlined),
        ];
      })
      ..useSingleSlot(
        layoutFeature.ports.body('notes'),
        (_, api) => NotesTab(notes: api.own.notes),
      )
      ..useMultiSlot(layoutFeature.ports.fab, (activeTab, api) {
        if (activeTab != 'notes') return null;
        return FloatingActionButton(
          heroTag: 'notes-fab',
          onPressed: () =>
              api.own.notes.add('Note ${api.own.notes.state.items.length + 1}'),
          tooltip: 'Add note',
          child: const Icon(Icons.add),
        );
      });

class NotesTab extends StatelessWidget {
  const NotesTab({super.key, required this.notes});
  final NotesStore notes;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return StoreBuilder<NotesStore>(
      builder: (_, store) {
        if (store.state.items.isEmpty) {
          return Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  Icons.sticky_note_2_outlined,
                  size: 48,
                  color: scheme.onSurfaceVariant,
                ),
                const SizedBox(height: 12),
                Text(
                  'No notes yet',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: 4),
                Text(
                  'Tap the + button to add one.',
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: scheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          );
        }
        return ListView.builder(
          padding: const EdgeInsets.fromLTRB(12, 12, 12, 96),
          itemCount: store.state.items.length,
          itemBuilder: (_, i) {
            final note = store.state.items[i];
            return Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Material(
                color: scheme.surfaceContainerHigh,
                borderRadius: BorderRadius.circular(12),
                child: InkWell(
                  borderRadius: BorderRadius.circular(12),
                  onTap: () {},
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 12,
                    ),
                    child: Row(
                      children: [
                        Container(
                          width: 36,
                          height: 36,
                          decoration: BoxDecoration(
                            color: scheme.primaryContainer,
                            borderRadius: BorderRadius.circular(10),
                          ),
                          alignment: Alignment.center,
                          child: Icon(
                            Icons.sticky_note_2_outlined,
                            size: 20,
                            color: scheme.onPrimaryContainer,
                          ),
                        ),
                        const SizedBox(width: 14),
                        Expanded(
                          child: Text(
                            note.text,
                            style: Theme.of(context).textTheme.bodyLarge,
                          ),
                        ),
                        IconButton(
                          icon: Icon(
                            Icons.delete_outline,
                            color: scheme.onSurfaceVariant,
                          ),
                          onPressed: () => store.remove(note.id),
                          tooltip: 'Delete',
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }
}

// ── Search feature ──────────────────────────────────────────────────────────

typedef SearchState = ({String query});

class SearchStore extends Store<SearchState> {
  SearchStore({required NotesStore notes})
    : _notes = notes,
      super(state: (query: ''));

  final NotesStore _notes;

  /// Debounced search — coalesces a burst of keystrokes into a single
  /// run. While the quiet timer waits and while the fn runs, state is
  /// `TaskPending(latestParams)` — UI shows a spinner.
  late final run = createTask<String, List<Note>, Never>(
    fn: (query) async {
      // Simulate a slow search backend.
      await Future<void>.delayed(const Duration(milliseconds: 350));
      final q = query.toLowerCase().trim();
      if (q.isEmpty) return const [];
      return _notes.state.items
          .where((n) => n.text.toLowerCase().contains(q))
          .toList();
    },
    strategy: TaskStrategy.debounce(const Duration(milliseconds: 250)),
  );

  void setQuery(String q) {
    update((_) => (query: q));
    run(q);
  }
}

final searchFeature =
    createFeature(
        name: 'Search',
        dependsOn: [layoutFeature, notesFeature],
        stores: (api) =>
            (search: SearchStore(notes: api.of(notesFeature).notes)),
        exports: (api) => api.own,
      )
      ..activation(
        whenStoreState(
          feature: notesFeature,
          store: (exports) => exports.notes,
          predicate: (state) => state.items.isNotEmpty,
        ),
      )
      ..usePipe(layoutFeature.ports.tabs, (tabs, _) {
        return [...tabs, (id: 'search', label: 'Search', icon: Icons.search)];
      })
      ..useSingleSlot(layoutFeature.ports.body('search'), (_, api) {
        return SearchTab(search: api.own.search);
      });

class SearchTab extends StatelessWidget {
  const SearchTab({super.key, required this.search});
  final SearchStore search;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        children: [
          TextField(
            decoration: const InputDecoration(
              labelText: 'Search notes',
              prefixIcon: Icon(Icons.search),
            ),
            onChanged: search.setQuery,
          ),
          const SizedBox(height: 16),
          // search.run.state is the TaskState — TaskPending while
          // debouncing or running, TaskDone(hits) when settled.
          Expanded(
            child: StateObserver(
              builder: (_) {
                final query = search.state.query.trim();
                if (query.isEmpty) {
                  return const Center(child: Text('Type to search'));
                }
                return switch (search.run.state) {
                  TaskPending() => const Center(
                    child: CircularProgressIndicator(),
                  ),
                  TaskDone(result: final hits) when hits.isEmpty =>
                    const Center(child: Text('No matches')),
                  TaskDone(:final result) => ListView(
                    children: [
                      for (final n in result) ListTile(title: Text(n.text)),
                    ],
                  ),
                  _ => const Center(child: CircularProgressIndicator()),
                };
              },
            ),
          ),
        ],
      ),
    );
  }
}

// ── Feature toggles ─────────────────────────────────────────────────────────

typedef TogglesState = ({Set<String> enabled});

class FeatureTogglesStore extends Store<TogglesState> {
  FeatureTogglesStore() : super(state: (enabled: const {'analytics'}));

  void toggle(String name) => update((s) {
    final next = {...s.enabled};
    if (!next.add(name)) next.remove(name);
    return (enabled: next);
  });
}

final featureTogglesFeature =
    createFeature(
        name: 'FeatureToggles',
        dependsOn: [layoutFeature],
        stores: (_) => (toggles: FeatureTogglesStore()),
        exports: (api) => api.own,
      )
      ..usePipe(layoutFeature.ports.tabs, (tabs, _) {
        return [
          ...tabs,
          (id: 'settings', label: 'Settings', icon: Icons.settings_outlined),
        ];
      })
      ..useSingleSlot(
        layoutFeature.ports.body('settings'),
        (_, api) => SettingsTab(toggles: api.own.toggles),
      );

class SettingsTab extends StatelessWidget {
  const SettingsTab({super.key, required this.toggles});
  final FeatureTogglesStore toggles;

  @override
  Widget build(BuildContext context) {
    return StoreBuilder<FeatureTogglesStore>(
      builder: (_, store) => ListView(
        children: [
          SwitchListTile(
            title: const Text('Analytics'),
            subtitle: const Text(
              'Toggle to deactivate analyticsFeature via whenStoreState. '
              'The note-count chip in the AppBar appears / disappears.',
            ),
            value: store.state.enabled.contains('analytics'),
            onChanged: (_) => store.toggle('analytics'),
          ),
        ],
      ),
    );
  }
}

// ── Analytics feature ───────────────────────────────────────────────────────

final analyticsFeature =
    createFeature(
        name: 'Analytics',
        dependsOn: [layoutFeature, notesFeature, featureTogglesFeature],
      )
      ..activation(
        whenStoreState(
          feature: featureTogglesFeature,
          store: (exports) => exports.toggles,
          predicate: (state) => state.enabled.contains('analytics'),
        ),
      )
      ..useMultiSlot(layoutFeature.ports.actions, (_, api) {
        // Cross-feature read: notes lives in notesFeature. StateObserver
        // tracks it via direct ref (DI-typed StoreBuilder<NotesStore>
        // would miss — this handler renders in layoutFeature's scope).
        final notes = api.of(notesFeature).notes;
        return Center(
          child: StateObserver(
            builder: (_) => Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              child: Chip(
                avatar: const Icon(Icons.note, size: 18),
                label: Text('${notes.state.items.length}'),
              ),
            ),
          ),
        );
      });

void main() {
  runApp(
    ArmatureApp(
      features: [
        layoutFeature,
        notesFeature,
        searchFeature,
        featureTogglesFeature,
        analyticsFeature,
      ],
      child: MaterialApp(home: layoutRoot(data: null)),
    ),
  );
}
