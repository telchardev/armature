import 'package:flutter/material.dart';

import '../../widgets/code_block.dart';
import '../doc_typography.dart';

class FeatureRootContent extends StatelessWidget {
  const FeatureRootContent({super.key});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const DocTitle('createFeatureRoot'),
        const DocParagraph(
          'createFeatureRoot binds a feature to its root widget and '
          'returns a typed builder. The builder takes a per-render data '
          'payload, produces a FeatureRoot widget, and establishes the '
          'FeatureContext that slot widgets — SingleSlotProvider, '
          'PipeProvider, StoreContext.of<T>, MultiPortBuilder — read to '
          'know which feature\'s scope they run in.',
        ),
        const DocHeading('The signature'),
        const CodeBlock(code: _signatureSource, language: 'dart'),
        const DocParagraph(
          'TInputData is the per-render payload type — whatever your '
          'root widget needs that changes across mounts (layout mode, '
          'route arguments, test fixtures). Use void / Null when the '
          'root does not need one.',
        ),
        const DocHeading('Declaring a feature root'),
        const DocParagraph(
          'Declare the root once, next to the feature, so callers do '
          'not have to reconstruct FeatureRoot by hand:',
        ),
        const CodeBlock(code: _declareSource, language: 'dart'),
        const DocParagraph(
          'The returned builder is a plain function — call it like '
          'layoutRoot(data: ...) to produce a widget.',
        ),
        const DocHeading('Mounting under ArmatureApp'),
        const DocParagraph(
          'The root widget goes to ArmatureApp.child. The container '
          'builds first, then this widget mounts — by the time '
          'LayoutShell.build runs, layoutFeature is already active and '
          'its stores exist:',
        ),
        const CodeBlock(code: _mountSource, language: 'dart'),
        const DocHeading('The optional loader'),
        const DocParagraph(
          'Pass loader to show something while the feature is in '
          'pending state — long-running onStart, async activation '
          'setup. The loader replaces the root widget during that '
          'window and swaps out once the feature settles into active:',
        ),
        const CodeBlock(code: _loaderSource, language: 'dart'),
        const DocParagraph(
          'Without loader, the renderer\'s default loader (or empty '
          'space) is shown. Configure the default via '
          'FlutterRendererOptions.loaderBuilder on ArmatureApp for an '
          'app-wide style.',
        ),
        const DocHeading('Why this matters'),
        const DocParagraph(
          'FeatureRoot is the place where the widget tree meets the '
          'container. It sets up two InheritedWidgets — ContainerContext '
          '(which container owns this tree) and FeatureContext (which '
          'feature\'s scope is in effect). Every slot widget and '
          'StoreContext.of lookup walks up to find these. Without a '
          'feature root somewhere above, providers and lookups throw '
          'because they cannot figure out their scope.',
        ),
        const DocHeading('Multiple roots'),
        const DocParagraph(
          'Most apps declare a single root feature (often called '
          'LayoutFeature or AppShellFeature) and mount one '
          'createFeatureRoot. Nesting feature roots is supported — '
          'useful for embedded mini-containers, in-app modals, or '
          'testing a subtree in isolation. Each nested root establishes '
          'its own FeatureContext; descendant providers resolve against '
          'the nearest one.',
        ),
        const DocHeading('What is next?'),
        const DocBullet(
          'Slot widgets — the providers that resolve their scope '
          'against the FeatureContext set up here.',
        ),
        const DocBullet(
          'MultiPortBuilder — reads multiple ports from inside the '
          'scope this root establishes.',
        ),
        const DocBullet(
          'Debug overlay — visualises the graph rooted here with live '
          'per-feature status.',
        ),
      ],
    );
  }
}

const _signatureSource = '''FeatureRootBuilder<TInputData> createFeatureRoot<
  TInputData extends Object?
>({
  required Feature feature,
  required Widget widget,
  SlotLoaderBuilder? loader,
});

typedef FeatureRootBuilder<TInputData> =
    Widget Function({required TInputData data});''';

const _declareSource = '''// Beside the layout feature, e.g. layout/config.dart:
final layoutRoot = createFeatureRoot<LayoutMode>(
  feature: layoutFeature,
  widget: const LayoutShell(),
);''';

const _mountSource = '''void main() {
  runApp(
    ArmatureApp(
      features: [layoutFeature, counterFeature, /* ... */],
      child: layoutRoot(data: LayoutMode.tablet),
    ),
  );
}''';

const _loaderSource = '''final bootFeature = createFeature(
  name: 'Boot',
  stores: (_) => (config: ConfigStore()),
  exports: (api) => api.own,
)..onStart((api, cleanup) async {
  await api.own.config.loadFromDisk();
});

final bootRoot = createFeatureRoot<void>(
  feature: bootFeature,
  widget: const BootedShell(),
  loader: (context) => const Scaffold(
    body: Center(child: CircularProgressIndicator()),
  ),
);''';
