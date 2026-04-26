/// Declarative structure of the documentation navigation.
///
/// The sidebar renders from [docsTree]; the page registry looks up content
/// widgets by [DocEntry.slug].
class DocSection {
  const DocSection({required this.title, required this.entries});

  final String title;
  final List<DocEntry> entries;
}

class DocEntry {
  const DocEntry({required this.slug, required this.title});

  final String slug;
  final String title;
}

const docsTree = <DocSection>[
  DocSection(
    title: 'Getting started',
    entries: [
      DocEntry(slug: 'quickstart', title: 'Quickstart'),
      DocEntry(slug: 'mental-model', title: 'Mental model'),
      DocEntry(slug: 'glossary', title: 'Glossary'),
      DocEntry(slug: 'installation', title: 'Installation'),
      DocEntry(slug: 'introduction', title: 'Introduction'),
    ],
  ),
  DocSection(
    title: 'Core concepts',
    entries: [
      DocEntry(slug: 'features', title: 'Features'),
      DocEntry(slug: 'dependency-graph', title: 'Dependency graph'),
      DocEntry(slug: 'stores', title: 'Stores'),
      DocEntry(slug: 'ports', title: 'Ports'),
      DocEntry(slug: 'tasks', title: 'Tasks'),
      DocEntry(slug: 'activation-helpers', title: 'Activation helpers'),
      DocEntry(slug: 'error-model', title: 'Error model'),
    ],
  ),
  DocSection(
    title: 'Flutter integration',
    entries: [
      DocEntry(slug: 'armature-app', title: 'ArmatureApp'),
      DocEntry(slug: 'feature-root', title: 'createFeatureRoot'),
      DocEntry(slug: 'slot-widgets', title: 'Slot widgets'),
      DocEntry(slug: 'multi-port-builder', title: 'MultiPortBuilder'),
      DocEntry(slug: 'debug-overlay', title: 'Debug overlay'),
    ],
  ),
];

/// Flat list of all entries in navigation order. Used for prev/next.
final List<DocEntry> docsFlat = [
  for (final section in docsTree) ...section.entries,
];

/// Returns the entry matching [slug], or null.
DocEntry? findEntry(String slug) {
  for (final entry in docsFlat) {
    if (entry.slug == slug) {
      return entry;
    }
  }
  return null;
}

/// Returns the entry immediately before [slug] in navigation order.
DocEntry? previousEntry(String slug) {
  final index = docsFlat.indexWhere((e) => e.slug == slug);
  if (index <= 0) {
    return null;
  }
  return docsFlat[index - 1];
}

/// Returns the entry immediately after [slug] in navigation order.
DocEntry? nextEntry(String slug) {
  final index = docsFlat.indexWhere((e) => e.slug == slug);
  if (index < 0 || index >= docsFlat.length - 1) {
    return null;
  }
  return docsFlat[index + 1];
}
