import 'package:flutter/material.dart';

import '../../widgets/code_block.dart';
import '../doc_typography.dart';

class MentalModelContent extends StatelessWidget {
  const MentalModelContent({super.key});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const DocTitle('Mental model'),
        const DocParagraph(
          'Before you read API docs, get the runtime model in your head. '
          'Armature has four moving parts that always sit in the same '
          'shape — once you see them, the API surface stops feeling like '
          'a grab bag and starts feeling like one idea.',
        ),
        const DocHeading('The picture'),
        const CodeBlock(code: _diagram, language: 'text'),
        const DocHeading('The four pieces'),
        const DocSubheading('Container'),
        const DocParagraph(
          'Runtime root. One per app (or one per test). Owns the '
          'dependency graph, the lifecycle, the error handler, and the '
          'logger. You rarely interact with it directly — ArmatureApp '
          'builds it from your feature list, features live inside it, '
          'and dispose() tears everything down at the end.',
        ),
        const DocSubheading('Features'),
        const DocParagraph(
          'Isolated modules. Each feature owns its stores (state) and '
          'tasks (async work). Three contracts connect a feature to the '
          'rest of the app: dependsOn (parents that must be ready '
          'first), exports (the typed API a feature publishes to its '
          'dependents — read via api.of(parent)), and ports (extension '
          'points dependents plug handlers into). Features never reach '
          'into each other outside these three.',
        ),
        const DocParagraph(
          'exports is required whenever a feature declares stores. The '
          'common form is exports: (api) => api.own — passthrough that '
          're-exports the feature\'s own stores record unchanged. '
          'Narrow it to hide internal stores from dependents.',
        ),
        const DocSubheading('Stores and tasks'),
        const DocParagraph(
          'A Store is the source of truth for a slice of state. Reads '
          'from .state inside a tracked scope auto-subscribe — no '
          'setState, no notifyListeners, no listener bookkeeping. A Task '
          'wraps async work owned by a store with strategy-aware '
          'concurrency (once, queue, latest, debounce, throttle) and '
          'exposes its own observable state machine (TaskIdle, '
          'TaskPending, TaskDone, TaskFailed).',
        ),
        const DocSubheading('Ports'),
        const DocParagraph(
          'How features compose without knowing about each other. Three '
          'shapes: pipes (chain handlers like middleware over a value), '
          'behaviors (priority-based selection of one handler), and '
          'slots (widget injection — single or multi). A layout feature '
          'declares tabsPipe; a counter feature uses it to push a tab. '
          'Neither imports the other.',
        ),
        const DocHeading('Data flow'),
        const DocParagraph(
          'One direction: user event → store update → reactive read → '
          'widget rebuild. Tasks wrap the async parts of that loop. '
          'The widget tree stays "dumb" — it reads stores via '
          'StoreBuilder / StoreSelector and renders ports via slot '
          'providers. All business logic stays inside features.',
        ),
        const DocParagraph(
          'You never call notifyListeners and you never wire a stream '
          'subscription by hand. Reactivity is the default; you opt out '
          'only when you explicitly want a one-shot read.',
        ),
        const DocHeading('What is next?'),
        const DocBullet(
          'Glossary — one-line definitions of every term used on this '
          'page.',
        ),
        const DocBullet(
          'Installation — pick the packages that match your project.',
        ),
        const DocBullet(
          'Introduction — define your first feature, bootstrap the app, '
          'render reactive state from a store.',
        ),
      ],
    );
  }
}

const _diagram = '''
┌──────────────────────────────────────────────────────────────────┐
│                          AppContainer                            │
│   one per app — owns lifecycle, dependency graph, errorHandler   │
│                                                                  │
│   ┌─────────────────┐   dependsOn    ┌─────────────────┐         │
│   │   Feature A     │ ──────────────▶│   Feature B     │         │
│   │  ┌───────────┐  │                │  ┌───────────┐  │         │
│   │  │  Store    │  │                │  │  Store    │  │         │
│   │  └─────┬─────┘  │                │  └───────────┘  │         │
│   │  ┌─────▼─────┐  │                │                 │         │
│   │  │  Task     │  │                │                 │         │
│   │  └───────────┘  │                │                 │         │
│   │  Ports:         │ ───── use ────▶│  Ports:         │         │
│   │   • pipe        │                │   • slot        │         │
│   │   • behavior    │                │   • behavior    │         │
│   │   • slot        │                │                 │         │
│   └────────┬────────┘                └────────┬────────┘         │
└────────────┼──────────────────────────────────┼──────────────────┘
             │                                  │
        ┌────▼──────────────────────────────────▼────┐
        │           Widget tree (Flutter)            │
        │  StoreBuilder · StoreSelector · slot       │
        │  providers · MultiPortBuilder              │
        └────────────────────────────────────────────┘
''';
