import 'package:flutter/material.dart';

import '../../widgets/code_block.dart';
import '../doc_typography.dart';

class MultiPortBuilderContent extends StatelessWidget {
  const MultiPortBuilderContent({super.key});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const DocTitle('MultiPortBuilder'),
        const DocParagraph(
          'The per-kind providers — SingleSlotProvider, MultiSlotProvider, '
          'PipeProvider, BehaviorProvider — each subscribe to one port. '
          'When a widget depends on several ports, composing providers '
          'gets deep and noisy. MultiPortBuilder reads any mix of ports '
          'inside a single flat builder with fine-grained reactivity.',
        ),
        const DocHeading('The basic shape'),
        const DocParagraph(
          'You receive a PortReader plus the normal BuildContext. Each '
          'reader method reads one port and registers a subscription; '
          'the builder re-runs when any read port changes.',
        ),
        const CodeBlock(code: _basicSource, language: 'dart'),
        const DocParagraph('Four methods on PortReader, one per port kind:'),
        const DocBullet(
          'reader.single(slot, data: ..., fallback: ...) — one widget '
          'from a SingleSlot, or fallback (or null) when nobody '
          'contributes.',
        ),
        const DocBullet(
          'reader.multi(slot, data: ..., fallback: []) — the sorted '
          'list from a MultiSlot.',
        ),
        const DocBullet(
          'reader.pipe(pipe, initialValue: ...) — the composed value '
          'from a Pipe.',
        ),
        const DocBullet(
          'reader.behavior(behavior, initialValue: ...) — the winning '
          'descriptor from a Behavior.',
        ),
        const DocHeading('Why it rebuilds correctly'),
        const DocParagraph(
          'The widget owns one Reaction that tracks every atom the '
          'builder touches through reader calls. Atom changes — a store '
          'write, an ownActive flip — invalidate the reaction and '
          'schedule a rebuild. That covers the reactive case.',
        ),
        const DocParagraph(
          'Handler-set changes (a feature with handlers on the port '
          'activates or deactivates) do not touch atoms, so the widget '
          'also subscribes to each touched port\'s onPortChanged event. '
          'On every build the subscription set is reconciled to the '
          'ports the builder actually read — if a port stops being read, '
          'its subscription drops; a newly-read port picks one up.',
        ),
        const DocHeading('When to reach for it'),
        const DocBullet(
          'UI composed from three or more ports — app bar reading a '
          'title slot, an actions multi-slot, a tabs pipe. One builder '
          'beats three nested providers for readability.',
        ),
        const DocBullet(
          'Conditional reads — the builder only touches portB when some '
          'portA value is truthy. MultiPortBuilder drops the portB '
          'subscription automatically between builds.',
        ),
        const DocBullet(
          'One-place fallback rendering — all error / empty states live '
          'in the same builder instead of spreading across per-port '
          'providers.',
        ),
        const DocHeading('Error handling'),
        const DocParagraph(
          'A thrown port handler routes through the container\'s '
          'errorHandler as RenderError (wrapping the original '
          'exception) and the reader returns the fallback (or '
          'initialValue) for that call. Other reads in the same '
          'builder keep working — one broken port does not break the '
          'whole widget.',
        ),
        const DocHeading('Lifecycle'),
        const DocParagraph(
          'On unmount, MultiPortBuilder disposes its Reaction and every '
          'per-port subscription. No manual cleanup needed.',
        ),
        const DocHeading('What is next?'),
        const DocBullet(
          'Debug overlay — inspect the live graph and per-port handler '
          'counts to see what a MultiPortBuilder actually reads.',
        ),
      ],
    );
  }
}

const _basicSource = '''MultiPortBuilder(
  builder: (reader, context) {
    final title = reader.single(
      layoutFeature.ports.titleSlot,
      data: mode,
      fallback: const Text('armature'),
    );
    final actions = reader.multi(
      layoutFeature.ports.actionsSlot,
      data: mode,
    );
    final tabs = reader.pipe(
      layoutFeature.ports.tabsPipe,
      initialValue: const <TabSpec>[],
    );

    return Scaffold(
      appBar: AppBar(title: title, actions: actions),
      body: TabBar(tabs: [for (final t in tabs) Tab(text: t.label)]),
    );
  },
)''';
