import 'package:flutter/material.dart';

import '../../widgets/code_block.dart';
import '../doc_typography.dart';

class PortsContent extends StatelessWidget {
  const PortsContent({super.key});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const DocTitle('Ports'),
        const DocParagraph(
          'A port is a typed extension point a feature exposes so other '
          'features can contribute to it. The owner declares the port; '
          'dependent features register handlers. Armature walks the '
          'handlers at apply time, respects activation status, and '
          'returns a composed value — a transformed data structure, a '
          'selected branch, or a rendered widget.',
        ),
        const DocParagraph(
          'Three kinds cover most integration patterns. Pick by how you '
          'want contributions combined:',
        ),
        const DocBullet(
          'Pipe — every active contributor transforms the value. Use for '
          'aggregations: lists of tabs, merged menu items, accumulated '
          'metadata.',
        ),
        const DocBullet(
          'Behavior — the highest-priority contributor wins. Use for '
          'branching decisions: auth gates, routing rules, variant '
          'selection.',
        ),
        const DocBullet(
          'Slot — same selection as Behavior, but the value is a '
          'Flutter widget. Single slots render one widget; multi slots '
          'render a sorted list.',
        ),
        const DocHeading('Pipe'),
        const DocParagraph(
          'A pipe chains handlers in registration order. Each handler '
          'receives the value produced by the previous one and returns '
          'the next. Inactive features are skipped transparently.',
        ),
        const DocParagraph('The owner declares the port and an initial value:'),
        const CodeBlock(code: _pipeOwnerSource, language: 'dart'),
        const DocParagraph('A dependent feature contributes:'),
        const CodeBlock(code: _pipeUseSource, language: 'dart'),
        const DocParagraph(
          'Order matters — the pipe runs handlers in registration order. '
          'Which features register first depends on their position in the '
          'dependency graph, so if you need a deterministic order, encode '
          'it in the contributions themselves (e.g. include a sort key in '
          'the record and sort at the consuming site).',
        ),
        const DocHeading('Behavior'),
        const DocParagraph(
          'A behavior picks exactly one descriptor from all active '
          'contributors. Handlers return a BehaviorDescriptor — or null '
          'to abstain — and the one with the greatest priority wins. '
          'Ties break in registration order.',
        ),
        const CodeBlock(code: _behaviorOwnerSource, language: 'dart'),
        const DocParagraph(
          'Contributors return a descriptor when they want to influence '
          'the outcome; otherwise they return null:',
        ),
        const CodeBlock(code: _behaviorUseSource, language: 'dart'),
        const DocParagraph(
          'If no handler produces a descriptor, the initialValue passed '
          'at the call site is used — so the owner always has a sane '
          'default.',
        ),
        const DocHeading('Slot'),
        const DocParagraph(
          'Slots are the Flutter-specific port kind. A single slot renders '
          'one widget; a multi slot renders a sorted list of widgets. Both '
          'come in "keyed" variants that return a slot per string key so '
          'the same declaration can host different content depending on '
          'context.',
        ),
        const DocParagraph('The owner declares the slot:'),
        const CodeBlock(code: _slotOwnerSource, language: 'dart'),
        const DocParagraph(
          'Dependants attach widgets. Return null to skip for this render:',
        ),
        const CodeBlock(code: _slotUseSource, language: 'dart'),
        const DocParagraph(
          'Multi slots take an order key and a direction (asc or desc). '
          'A feature can contribute several widgets to the same slot by '
          'calling useMultiSlot more than once.',
        ),
        const DocHeading('Ownership and dependencies'),
        const DocParagraph(
          'A port has exactly one owner — the feature that declares it. '
          'A feature that wants to register a handler must list the owner '
          'in its dependsOn (or optionalDependsOn). The framework checks '
          'this at registration time and throws PortError early if the '
          'relationship is missing.',
        ),
        const DocParagraph(
          'Handlers must be pure — no writes to reactive state during '
          'their body. Reads are tracked automatically and invalidate '
          'the reaction, so the port re-applies when source data changes. '
          'If you need to trigger a write, schedule it outside the '
          'handler.',
        ),
        const DocHeading('What is next?'),
        const DocBullet(
          'Tasks — async work inside stores, often the trigger for '
          'reactive port re-applies.',
        ),
        const DocBullet(
          'Activation helpers — gate features on states read through '
          'ports and parent status.',
        ),
        const DocBullet(
          'Error model — what PortError and RenderError carry when a '
          'port handler or slot build fails.',
        ),
      ],
    );
  }
}

const _pipeOwnerSource =
    '''// ports.dart — port instances live alongside the feature.
final tabsPipe = createPipe<List<TabSpec>>(name: 'layout.tabs');

// config.dart — wire them into the feature as a record.
final layoutFeature = createFeature(
  name: 'Layout',
  ports: (tabsPipe: tabsPipe),
  stores: (_) => (activeTab: ActiveTabStore()),
  exports: (api) => api.own,
);''';

const _pipeUseSource = '''..usePipe(layoutFeature.ports.tabsPipe, (tabs, _) => [
  ...tabs,
  (id: 'counter', label: 'Counter', icon: Icons.add),
])''';

const _behaviorOwnerSource = '''enum AuthBranch { guest, authed }

final authBehavior = createBehavior<AuthBranch, String?>(name: 'auth.gate');

final authFeature = createFeature(
  name: 'Auth',
  ports: (authBehavior: authBehavior),
  stores: (_) => (session: SessionStore()),
  exports: (api) => api.own,
);''';

const _behaviorUseSource = '''..useBehavior(
  authFeature.ports.authBehavior,
  (api) {
    final session = api.of(authFeature).session.state;
    if (session.user == null) return null;
    return (branch: AuthBranch.authed, payload: session.user!.id);
  },
  priority: 10,
)''';

const _slotOwnerSource =
    '''final fabSlot = createMultiSlot<LayoutMode>(name: 'layout.fab');

final layoutFeature = createFeature(
  name: 'Layout',
  ports: (fabSlot: fabSlot),
  stores: (_) => (activeTab: ActiveTabStore()),
  exports: (api) => api.own,
);''';

const _slotUseSource = '''..useMultiSlot(layoutFeature.ports.fabSlot, (_, api) {
  if (api.of(layoutFeature).activeTab.state != 'counter') return null;
  return FloatingActionButton(
    onPressed: () => api.own.counter.increment(),
    child: const Icon(Icons.add),
  );
}, order: 1)''';
