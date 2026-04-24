/// Declarative structure of the examples navigation.
class ExampleSection {
  const ExampleSection({required this.title, required this.entries});

  final String title;
  final List<ExampleEntry> entries;
}

class ExampleEntry {
  const ExampleEntry({required this.slug, required this.title});

  final String slug;
  final String title;
}

const examplesTree = <ExampleSection>[
  ExampleSection(
    title: 'Basics',
    entries: [
      ExampleEntry(slug: 'counter', title: 'Counter'),
      ExampleEntry(slug: 'todo-list', title: 'Todo list'),
      ExampleEntry(slug: 'debounced-search', title: 'Debounced search'),
    ],
  ),
  ExampleSection(
    title: 'Composition',
    entries: [
      ExampleEntry(slug: 'feature-toggles', title: 'Feature toggles'),
      ExampleEntry(slug: 'auth-flow', title: 'Auth flow'),
    ],
  ),
];

final List<ExampleEntry> examplesFlat = [
  for (final section in examplesTree) ...section.entries,
];

ExampleEntry? findExample(String slug) {
  for (final entry in examplesFlat) {
    if (entry.slug == slug) {
      return entry;
    }
  }
  return null;
}
