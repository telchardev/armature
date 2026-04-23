import 'package:flutter/material.dart';

import '../../widgets/code_block.dart';
import '../doc_typography.dart';

class DebugOverlayContent extends StatelessWidget {
  const DebugOverlayContent({super.key});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const DocTitle('Debug overlay'),
        const DocParagraph(
          'FeatureGraphOverlay is a development-only widget that draws a '
          'floating action button over your app. Tap it to open a '
          'diagnostic panel with a live view of the feature graph and '
          'the stores attached to each feature.',
        ),
        const DocHeading('Enabling the overlay'),
        const DocParagraph(
          'Wrap your root widget with FeatureGraphOverlay inside '
          'ArmatureApp. Gate it on kDebugMode so release builds skip '
          'the overlay entirely:',
        ),
        const CodeBlock(code: _enableSource, language: 'dart'),
        const DocParagraph(
          'When enabled is false the widget is a pass-through — no FAB, '
          'no overlay, no ContainerContext reads. Safe to leave in the '
          'tree unconditionally.',
        ),
        const DocHeading('What you see'),
        const DocParagraph(
          'The FAB sits in the bottom-left corner. Tap it and a '
          'full-screen diagnostic panel slides over your UI:',
        ),
        const DocBullet(
          'Graph tab — nodes for every feature, edges for dependsOn / '
          'optionalDependsOn. Colour-coded by FeatureStatus (disabled, '
          'pending, active). Pan and zoom to inspect a large graph.',
        ),
        const DocBullet(
          'States tab — every store in the container with its current '
          'state value serialised for reading. Handy for confirming '
          'that a task actually transitioned or a port handler wrote '
          'what you expected.',
        ),
        const DocBullet('Legend — explains the node colours and edge styles.'),
        const DocBullet(
          'Refresh button — re-reads the container snapshot (status + '
          'store values) without losing your pan / zoom / selection.',
        ),
        const DocHeading('Gating for release'),
        const DocParagraph(
          'kDebugMode from flutter/foundation is true for debug and '
          'profile builds, false for release. The overlay reads the '
          'container via ContainerContext only when enabled is true, '
          'so the release path costs one boolean comparison per build.',
        ),
        const DocParagraph(
          'You can also wire the overlay to a feature flag, a URL '
          'parameter, or a long-press gesture if you want QA builds to '
          'see it too:',
        ),
        const CodeBlock(code: _flagSource, language: 'dart'),
        const DocHeading('What is next?'),
        const DocBullet(
          'Dependency graph — the structure you see in the Graph tab.',
        ),
        const DocBullet('Stores — the runtime values the States tab inspects.'),
        const DocBullet(
          'ArmatureApp — the root that exposes the container the '
          'overlay consumes.',
        ),
      ],
    );
  }
}

const _enableSource =
    '''import 'package:armature_flutter/armature_flutter.dart';
import 'package:flutter/foundation.dart' show kDebugMode;

void main() {
  runApp(
    ArmatureApp(
      features: [layoutFeature, /* ... */],
      child: FeatureGraphOverlay(
        enabled: kDebugMode,
        child: const AppShell(),
      ),
    ),
  );
}''';

const _flagSource = '''FeatureGraphOverlay(
  enabled: kDebugMode || featureToggles.showDebug.state,
  child: const AppShell(),
)''';
