import 'package:flutter/material.dart';

import '../../widgets/code_block.dart';
import '../doc_typography.dart';

class SlotWidgetsContent extends StatelessWidget {
  const SlotWidgetsContent({super.key});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const DocTitle('Slot widgets'),
        const DocParagraph(
          'The Ports page covered how a feature declares a port and how '
          'other features register handlers. Slot widgets are the '
          'Flutter side: providers that apply a port at render time and '
          'rebuild when the composed value changes.',
        ),
        const DocParagraph(
          'Four providers, one per port kind. All of them subscribe to '
          'the port through the container, so rebuilds are reactive — '
          'any reactive state a handler reads becomes a rebuild '
          'trigger.',
        ),
        const DocHeading('SingleSlotProvider'),
        const DocParagraph(
          'Renders the winning widget from a single slot. The builder '
          'receives the selected child (or null when no handler '
          'contributed) and typically wraps it in a layout container:',
        ),
        const CodeBlock(code: _singleSlotSource, language: 'dart'),
        const DocParagraph(
          'The data field is the payload passed to each handler. Use '
          'it to tell handlers what variant of the slot this is (a '
          'tab id, a layout mode, a route name).',
        ),
        const DocHeading('MultiSlotProvider'),
        const DocParagraph(
          'Renders the sorted list of contributions from a multi slot. '
          'The builder receives the list of widgets ordered by each '
          'handler\'s order key — use it inside a Row, Column, or Wrap:',
        ),
        const CodeBlock(code: _multiSlotSource, language: 'dart'),
        const DocHeading('PipeProvider'),
        const DocParagraph(
          'Applies a pipe and rebuilds when the composed value changes. '
          'initialValue seeds the first handler; if the pipe has no '
          'handlers (all optional parents absent, say), the builder '
          'sees initialValue:',
        ),
        const CodeBlock(code: _pipeSource, language: 'dart'),
        const DocHeading('BehaviorProvider'),
        const DocParagraph(
          'Picks the winning descriptor from a behavior and lets you '
          'branch on it. initialValue provides the fallback branch when '
          'no handler contributed:',
        ),
        const CodeBlock(code: _behaviorSource, language: 'dart'),
        const DocParagraph(
          'Pattern-match the enum to render per-branch UI. payload is '
          'the typed value the winning handler returned alongside its '
          'branch — use it to pass user ids, permissions, or any '
          'context the UI needs.',
        ),
        const DocHeading('Where they belong'),
        const DocParagraph(
          'Slot widgets resolve their container via ContainerContext, '
          'which ArmatureApp sets up at the root of the tree. They also '
          'read FeatureContext to know which feature\'s scope they run '
          'in — typically provided by createFeatureRoot, the helper '
          'that mounts a feature\'s root widget and binds it to that '
          'feature.',
        ),
        const CodeBlock(code: _rootSource, language: 'dart'),
        const DocParagraph(
          'Inside the root widget (and every descendant), slot '
          'providers can reference any port the owning feature is '
          'allowed to apply.',
        ),
        const DocHeading('What is next?'),
        const DocBullet(
          'MultiPortBuilder — reads several ports of different kinds '
          'in one flat builder when individual providers get noisy.',
        ),
        const DocBullet(
          'Debug overlay — FeatureGraphOverlay visualises the live '
          'graph and per-port handler counts.',
        ),
      ],
    );
  }
}

const _singleSlotSource = '''SingleSlotProvider(
  slot: layoutFeature.ports.bodySwitchSlot('counter'),
  data: mode, // LayoutMode.phone / .tablet / ...
  builder: (child, context) {
    return Center(child: child ?? const Text('No content'));
  },
)''';

const _multiSlotSource = '''MultiSlotProvider(
  slot: layoutFeature.ports.actionsSlot,
  data: mode,
  builder: (children, context) {
    return Row(
      children: children,
    );
  },
)''';

const _pipeSource = '''PipeProvider(
  pipe: layoutFeature.ports.tabsPipe,
  initialValue: const <TabSpec>[],
  builder: (tabs, context) {
    return TabBar(
      tabs: [
        for (final tab in tabs) Tab(text: tab.label, icon: Icon(tab.icon)),
      ],
    );
  },
)''';

const _behaviorSource = '''BehaviorProvider(
  behavior: layoutFeature.ports.themeBehavior,
  initialValue: BehaviorDescriptor(
    branch: ThemeMode.light,
    payload: ThemeData.light(),
  ),
  builder: (descriptor, context) {
    return Theme(
      data: descriptor.payload,
      child: MyContent(),
    );
  },
)''';

const _rootSource = '''final layoutRoot = createFeatureRoot(
  feature: layoutFeature,
  widget: const LayoutShell(),
);

// In main():
runApp(
  ArmatureApp(
    features: [layoutFeature, /* ... */],
    child: layoutRoot(data: null),
  ),
);''';
