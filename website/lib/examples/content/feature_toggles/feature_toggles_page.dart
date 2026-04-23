import 'package:flutter/material.dart';

import '../../../docs/doc_typography.dart';
import '../../../widgets/code_block.dart';
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
            'Activation gating in action. The extras feature has an '
            'activation callback that subscribes to a toggle store and '
            'flips the feature between active and inactive on every '
            'change. While inactive, its slot handler is skipped — the '
            'contribution disappears from the composed UI without any '
            'manual wiring.',
          ),
          const DocParagraph(
            'This is how Armature handles feature flags, paywalls, '
            'role-gated sections, or any runtime on/off switch. The '
            'feature stays loaded in the graph; only its runtime state '
            'changes.',
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
        child: FeatureTogglesDemoWidget(),
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
          _Caption('Toggle store'),
          CodeBlock(code: _storeSource, language: 'dart'),
          SizedBox(height: 20),
          _Caption('Activation-gated feature'),
          CodeBlock(code: _featuresSource, language: 'dart'),
          SizedBox(height: 20),
          _Caption('Reading the store from a widget'),
          CodeBlock(code: _viewSource, language: 'dart'),
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

const _storeSource = '''class ToggleStore extends Store<({bool showExtras})> {
  ToggleStore() : super(state: (showExtras: false));

  void toggle() {
    state = (showExtras: !state.showExtras);
  }
}''';

const _featuresSource =
    '''final extraContentSlot = createSingleSlot<Null>(name: 'host.extra');

final hostFeature = createFeature(
  name: 'Host',
  stores: (_) => (toggle: ToggleStore()),
  ports: (extra: extraContentSlot),
  exports: (api) => api.own,
);

final extrasFeature = createFeature(
  name: 'Extras',
  dependsOn: [hostFeature],
)
  ..activation((parentApi, toggle, cleanup) {
    final toggleStore = parentApi.of(hostFeature).toggle;
    final disposer = toggleStore.subscribe(
      (_, current) => toggle(
        current.showExtras ? ToggleState.active : ToggleState.inactive,
      ),
      fireImmediately: true,
    );
    cleanup.add(disposer);
  })
  ..useSingleSlot(
    extraContentSlot,
    (_, api) => const ExtrasPanel(),
  );''';

const _viewSource = '''class HostView extends StatelessWidget {
  const HostView({super.key});

  @override
  Widget build(BuildContext context) {
    final store = StoreContext.of<ToggleStore>(context);
    return Column(
      children: [
        StateObserver(
          builder: (_) => SwitchListTile(
            title: const Text('Activate Extras'),
            value: store.state.showExtras,
            onChanged: (_) => store.toggle(),
          ),
        ),
        SingleSlotProvider(
          slot: extraContentSlot,
          data: null,
          builder: (child, _) => child ?? const Text('(inactive)'),
        ),
      ],
    );
  }
}''';
