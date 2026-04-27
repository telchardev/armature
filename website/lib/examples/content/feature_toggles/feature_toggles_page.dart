import 'package:armature_flutter/armature_flutter.dart';
import 'package:flutter/material.dart';

import '../../../docs/doc_typography.dart';
import '../../../widgets/loaded_code_block.dart';
import 'toggle_demo.dart';

class FeatureTogglesPage extends StatelessWidget {
  const FeatureTogglesPage({super.key});

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 2,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const DocTitle('Feature toggles'),
          const DocParagraph(
            'One host, four independent toggles, four content features. '
            'Each content feature has an activation gate tied to one '
            'flag on the host store — flip a switch, the feature '
            'activates, its multi-slot handler contributes a widget, and '
            'the composed list re-sorts by `order`. Flip it off and the '
            'contribution disappears with no manual wiring.',
          ),
          const DocParagraph(
            'This is how Armature handles feature flags, paywalls, '
            'role-gated sections, or any runtime on/off switch. Features '
            'stay loaded in the graph; only their runtime status changes.',
          ),
          const SizedBox(height: 8),
          const _Tabs(),
          const SizedBox(height: 24),
          const SizedBox(
            height: 560,
            child: TabBarView(
              physics: NeverScrollableScrollPhysics(),
              children: [_PreviewTab(), _CodeTab()],
            ),
          ),
        ],
      ),
    );
  }
}

class _Tabs extends StatelessWidget {
  const _Tabs();

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.centerLeft,
      child: TabBar(
        isScrollable: true,
        tabAlignment: TabAlignment.start,
        dividerHeight: 0,
        tabs: const [
          Tab(text: 'Preview'),
          Tab(text: 'Code'),
        ],
      ),
    );
  }
}

class _PreviewTab extends StatefulWidget {
  const _PreviewTab();

  @override
  State<_PreviewTab> createState() => _PreviewTabState();
}

class _PreviewTabState extends State<_PreviewTab>
    with AutomaticKeepAliveClientMixin {
  @override
  bool get wantKeepAlive => true;

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return const Center(
      child: SingleChildScrollView(
        padding: EdgeInsets.symmetric(vertical: 24),
        child: _FeatureTogglesEmbed(),
      ),
    );
  }
}

class _FeatureTogglesEmbed extends StatelessWidget {
  const _FeatureTogglesEmbed();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.all(20),
      constraints: const BoxConstraints(maxWidth: 480),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerLowest,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: theme.colorScheme.outlineVariant),
      ),
      child: ArmatureApp(
        features: [
          toggleHostFeature,
          betaFeature,
          analyticsFeature,
          debugFeature,
          tipsFeature,
        ],
        child: hostRoot(data: null),
      ),
    );
  }
}

class _CodeTab extends StatelessWidget {
  const _CodeTab();

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.only(top: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: const [
          _Caption('toggle_demo.dart'),
          LoadedCodeBlock(
            path: 'lib/examples/content/feature_toggles/toggle_demo.dart',
          ),
        ],
      ),
    );
  }
}

class _Caption extends StatelessWidget {
  const _Caption(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Text(
        text,
        style: Theme.of(
          context,
        ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600),
      ),
    );
  }
}
