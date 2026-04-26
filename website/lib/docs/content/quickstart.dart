import 'package:flutter/material.dart';

import '../../widgets/code_block.dart';
import '../doc_typography.dart';

class QuickstartContent extends StatelessWidget {
  const QuickstartContent({super.key});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const DocTitle('Quickstart'),
        const DocParagraph(
          'A self-contained "hello world" with two features composing '
          'through a port. Drop this into lib/main.dart of a fresh '
          'Flutter project after running flutter pub add armature '
          'armature_flutter.',
        ),
        const CodeBlock(code: _quickstartCode, language: 'dart'),
        const DocHeading('What this shows'),
        const DocBullet(
          'createSingleSlot — declares a typed extension point (a slot) '
          'other features plug into. No type argument needed when the '
          'slot does not pass data; declare createSingleSlot<MyData>(...) '
          'when it does.',
        ),
        const DocBullet(
          'createFeature — declares an isolated module. layoutFeature '
          'exposes the slot port; counterFeature declares dependsOn: '
          '[layoutFeature] and uses the slot.',
        ),
        const DocBullet(
          'useSingleSlot(port, handler) — registers counterFeature\'s '
          'widget with layoutFeature\'s body slot. Neither feature '
          'imports the other\'s UI.',
        ),
        const DocBullet(
          'Store<CounterState> — observable state with update(...) for '
          'mutations; record state stays extensible (add fields without '
          'breaking equality).',
        ),
        const DocBullet(
          'StoreBuilder<T> — rebuilds when any tracked .state read '
          'inside builder changes.',
        ),
        const DocBullet(
          'api.own.counter — typed access to the feature\'s own stores '
          'from inside its handlers. Use api.of(parentFeature) to read a '
          'parent\'s exported API instead.',
        ),
        const DocBullet(
          'createFeatureRoot + ArmatureApp — bind layoutFeature to a '
          'root widget, then bootstrap the container with the full '
          'feature list.',
        ),
        const DocHeading('What is next?'),
        const DocBullet(
          'Mental model — the four-piece runtime picture every armature '
          'concept slots into.',
        ),
        const DocBullet(
          'Glossary — one-line definitions of every term you just saw '
          '(createSingleSlot, useSingleSlot, exports, api.own, ...).',
        ),
        const DocBullet(
          'Installation — the per-package breakdown if you want pure '
          'Dart, reactive primitives only, or the full Flutter setup.',
        ),
      ],
    );
  }
}

const _quickstartCode = '''import 'package:armature/armature.dart';
import 'package:armature_flutter/armature_flutter.dart';
import 'package:flutter/material.dart';

// 1. Counter state as a record — extensible without breaking equality.
typedef CounterState = ({int value});

class CounterStore extends Store<CounterState> {
  CounterStore() : super(state: (value: 0));
  void increment() => update((s) => (value: s.value + 1));
}

// 2. Layout feature owns the app shell and a body slot. No stores.
final bodySlot = createSingleSlot(name: 'layout.body');

final layoutFeature = createFeature(
  name: 'Layout',
  ports: (bodySlot: bodySlot),
);

final layoutRoot = createFeatureRoot(
  feature: layoutFeature,
  widget: Scaffold(
    appBar: AppBar(title: const Text('Counter')),
    body: SingleSlotProvider(
      slot: bodySlot,
      data: null,
      builder: (child, _) => child ?? const SizedBox.shrink(),
    ),
  ),
);

// 3. Counter feature owns state and plugs into the layout's body slot.
final counterFeature = createFeature(
  name: 'Counter',
  dependsOn: [layoutFeature],
  stores: (_) => (counter: CounterStore()),
  exports: (api) => api.own,
)..useSingleSlot(layoutFeature.ports.bodySlot, (_, api) {
  return Center(
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        StoreBuilder<CounterStore>(
          builder: (_, store) => Text(
            '\${store.state.value}',
            style: const TextStyle(fontSize: 64),
          ),
        ),
        const SizedBox(height: 16),
        FilledButton(
          onPressed: () => api.own.counter.increment(),
          child: const Text('Increment'),
        ),
      ],
    ),
  );
});

void main() {
  runApp(ArmatureApp(
    features: [layoutFeature, counterFeature],
    child: MaterialApp(home: layoutRoot(data: null)),
  ));
}''';
