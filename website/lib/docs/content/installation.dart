import 'package:flutter/material.dart';

import '../../widgets/code_block.dart';
import '../doc_typography.dart';

class InstallationContent extends StatelessWidget {
  const InstallationContent({super.key});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const DocTitle('Installation'),
        const DocParagraph(
          'Armature is published to pub.dev as four packages. Pick the '
          'ones that match your project — most Flutter apps add '
          'armature and armature_flutter together.',
        ),
        const DocHeading('Packages'),
        const DocBullet(
          'armature — core runtime: features, container, stores, ports, '
          'tasks. Pure Dart.',
        ),
        const DocBullet(
          'armature_flutter — Flutter integration: ArmatureApp, slot '
          'widgets, providers, debug overlay. Depends on armature.',
        ),
        const DocBullet(
          'armature_reactive — standalone reactive primitives (Atom, '
          'Reaction, automatic dependency tracking). Pure Dart, no '
          'Armature runtime required.',
        ),
        const DocBullet(
          'armature_graph — DAG resolver with topological ordering. '
          'Pure Dart; used internally by armature, occasionally useful '
          'on its own.',
        ),
        const DocHeading('Flutter app'),
        const DocParagraph(
          'For a typical Flutter app, install both the core runtime and '
          'the Flutter bindings:',
        ),
        const CodeBlock(
          code: 'flutter pub add armature armature_flutter',
          language: 'bash',
        ),
        const DocHeading('Pure Dart'),
        const DocParagraph(
          'For a pure-Dart project (CLI tool, server, isolate), drop the '
          'Flutter integration:',
        ),
        const CodeBlock(code: 'dart pub add armature', language: 'bash'),
        const DocHeading('Reactive primitives only'),
        const DocParagraph(
          'If you only want Atom / Reaction for state tracking without '
          'the full framework:',
        ),
        const CodeBlock(
          code: 'dart pub add armature_reactive',
          language: 'bash',
        ),
        const DocHeading('Requirements'),
        const DocParagraph(
          'Dart SDK 3.9.0 or newer. Flutter 3.19.0 or newer for the '
          'armature_flutter integration. No platform-specific native '
          'dependencies — every package works on web, mobile, desktop, '
          'and pure Dart targets.',
        ),
        const DocHeading('What is next?'),
        const DocBullet(
          'Introduction — the same idea, extended to a Notes/Todo app '
          'that the rest of the docs build on.',
        ),
        const DocBullet(
          'Features — the core building block once the packages are '
          'installed.',
        ),
        const DocBullet(
          'Dependency graph — how Armature resolves init order across '
          'your feature list.',
        ),
      ],
    );
  }
}
