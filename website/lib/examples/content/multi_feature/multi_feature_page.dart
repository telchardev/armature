import 'package:flutter/material.dart';

import '../../../docs/doc_typography.dart';
import '../../../widgets/code_block.dart';
import 'menu_demo.dart';

class MultiFeaturePage extends StatelessWidget {
  const MultiFeaturePage({super.key});

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 2,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const DocTitle('Multi-feature wiring'),
          const DocParagraph(
            'Three features and one pipe. The host menu feature declares '
            'the port; Profile and Help both register handlers that '
            'transform the list. At render time the pipe runs every '
            'active contributor in registration order and the UI shows '
            'the composed result.',
          ),
          const DocParagraph(
            'This is the canonical Armature pattern for extension points '
            '— neither contributor knows about the other, and neither '
            'has to modify the host. Adding a fourth feature that drops '
            'another item into the menu means adding one more entry to '
            'the ArmatureApp features list.',
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
        child: MenuDemoWidget(),
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
          _Caption('The pipe and features'),
          CodeBlock(code: _featuresSource, language: 'dart'),
          SizedBox(height: 20),
          _Caption('The view'),
          CodeBlock(code: _viewSource, language: 'dart'),
          SizedBox(height: 20),
          _Caption('Bootstrap'),
          CodeBlock(code: _bootstrapSource, language: 'dart'),
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

const _featuresSource = '''typedef MenuItem = ({IconData icon, String label});

final menuItemsPipe = createPipe<List<MenuItem>>(name: 'menu.items');

final menuFeature = createFeature(
  name: 'Menu',
  ports: (items: menuItemsPipe),
);

final profileFeature = createFeature(
  name: 'Profile',
  dependsOn: [menuFeature],
)
  ..usePipe(menuItemsPipe, (items, _) => [
    ...items,
    (icon: Icons.person_outline, label: 'Profile'),
    (icon: Icons.settings_outlined, label: 'Settings'),
  ]);

final helpFeature = createFeature(
  name: 'Help',
  dependsOn: [menuFeature],
)
  ..usePipe(menuItemsPipe, (items, _) => [
    ...items,
    (icon: Icons.help_outline, label: 'Help'),
  ]);''';

const _viewSource = '''class MenuView extends StatelessWidget {
  const MenuView({super.key});

  @override
  Widget build(BuildContext context) {
    return PipeProvider(
      pipe: menuItemsPipe,
      initialValue: const <MenuItem>[
        (icon: Icons.home_outlined, label: 'Home'),
      ],
      builder: (items, context) => Column(
        children: [
          for (final item in items)
            ListTile(leading: Icon(item.icon), title: Text(item.label)),
        ],
      ),
    );
  }
}

final menuRoot = createFeatureRoot(
  feature: menuFeature,
  widget: const MenuView(),
);''';

const _bootstrapSource = '''runApp(
  ArmatureApp(
    features: [menuFeature, profileFeature, helpFeature],
    child: menuRoot(data: null),
  ),
);''';
