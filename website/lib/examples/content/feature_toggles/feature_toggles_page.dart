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
          _Caption('toggle_demo.dart'),
          CodeBlock(code: _toggleDemoSource, language: 'dart'),
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

const _toggleDemoSource = r'''import 'package:armature/armature.dart';
import 'package:armature_flutter/armature_flutter.dart';
import 'package:flutter/material.dart';

/// Immutable state for four independent toggles.
class TogglesState {
  const TogglesState({
    this.beta = false,
    this.analytics = false,
    this.debug = false,
    this.tips = false,
  });

  final bool beta;
  final bool analytics;
  final bool debug;
  final bool tips;

  TogglesState copyWith({
    bool? beta,
    bool? analytics,
    bool? debug,
    bool? tips,
  }) {
    return TogglesState(
      beta: beta ?? this.beta,
      analytics: analytics ?? this.analytics,
      debug: debug ?? this.debug,
      tips: tips ?? this.tips,
    );
  }
}

/// Source of truth for all four toggles.
class TogglesStore extends Store<TogglesState> {
  TogglesStore() : super(state: const TogglesState());

  void setBeta(bool v) => state = state.copyWith(beta: v);
  void setAnalytics(bool v) => state = state.copyWith(analytics: v);
  void setDebug(bool v) => state = state.copyWith(debug: v);
  void setTips(bool v) => state = state.copyWith(tips: v);
}

/// Multi-slot the host exposes. Every active contributor renders into it,
/// sorted by `order`.
final extrasSlot = createMultiSlot<Null>(
  name: 'toggle.extras',
  orderDirection: MultiSlotOrderDirection.asc,
);

/// Host feature — owns the toggles store, declares the slot.
final toggleHostFeature = createFeature(
  name: 'ToggleHost',
  stores: (_) => (toggles: TogglesStore()),
  ports: (extras: extrasSlot),
  exports: (api) => api.own,
);

/// Four content features, each gated on one flag.
final betaFeature = createFeature(name: 'Beta', dependsOn: [toggleHostFeature])
  ..activation(
    whenStoreState(
      feature: toggleHostFeature,
      store: (exports) => exports.toggles,
      predicate: (state) => state.beta,
    ),
  )
  ..useMultiSlot(
    toggleHostFeature.ports.extras,
    (_, api) => const _ContribCard(
      icon: Icons.science_outlined,
      title: 'Beta preview',
      subtitle: 'Experimental surface — unlocked by the Beta feature.',
    ),
    order: 1,
  );

final analyticsFeature =
    createFeature(name: 'Analytics', dependsOn: [toggleHostFeature])
      ..activation(
        whenStoreState(
          feature: toggleHostFeature,
          store: (exports) => exports.toggles,
          predicate: (state) => state.analytics,
        ),
      )
      ..useMultiSlot(
        toggleHostFeature.ports.extras,
        (_, api) => const _ContribCard(
          icon: Icons.analytics_outlined,
          title: 'Analytics on',
          subtitle: 'Tracking is active.',
        ),
        order: 2,
      );

final debugFeature =
    createFeature(name: 'Debug', dependsOn: [toggleHostFeature])
      ..activation(
        whenStoreState(
          feature: toggleHostFeature,
          store: (exports) => exports.toggles,
          predicate: (state) => state.debug,
        ),
      )
      ..useMultiSlot(
        toggleHostFeature.ports.extras,
        (_, api) => const _ContribCard(
          icon: Icons.bug_report_outlined,
          title: 'Debug panel',
          subtitle: 'Mock counters, build info.',
        ),
        order: 3,
      );

final tipsFeature = createFeature(name: 'Tips', dependsOn: [toggleHostFeature])
  ..activation(
    whenStoreState(
      feature: toggleHostFeature,
      store: (exports) => exports.toggles,
      predicate: (state) => state.tips,
    ),
  )
  ..useMultiSlot(
    toggleHostFeature.ports.extras,
    (_, api) => const _ContribCard(
      icon: Icons.tips_and_updates_outlined,
      title: 'Daily tip',
      subtitle: 'Hint contributed by the Tips feature.',
    ),
    order: 4,
  );

class _ContribCard extends StatelessWidget {
  const _ContribCard({
    required this.icon,
    required this.title,
    required this.subtitle,
  });

  final IconData icon;
  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      margin: const EdgeInsets.only(top: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: theme.colorScheme.secondaryContainer,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        children: [
          Icon(icon, color: theme.colorScheme.onSecondaryContainer),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: const TextStyle(fontWeight: FontWeight.w600)),
                Text(subtitle, style: theme.textTheme.bodySmall),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _HostView extends StatelessWidget {
  const _HostView();

  @override
  Widget build(BuildContext context) {
    final store = StoreContext.of<TogglesStore>(context);
    return Column(
      children: [
        StateObserver(
          builder: (_) {
            final s = store.state;
            return Column(
              children: [
                SwitchListTile(
                  title: const Text('Beta preview'),
                  value: s.beta,
                  onChanged: store.setBeta,
                ),
                SwitchListTile(
                  title: const Text('Analytics'),
                  value: s.analytics,
                  onChanged: store.setAnalytics,
                ),
                SwitchListTile(
                  title: const Text('Debug panel'),
                  value: s.debug,
                  onChanged: store.setDebug,
                ),
                SwitchListTile(
                  title: const Text('Daily tips'),
                  value: s.tips,
                  onChanged: store.setTips,
                ),
              ],
            );
          },
        ),
        const Divider(),
        MultiSlotProvider(
          slot: toggleHostFeature.ports.extras,
          data: null,
          builder: (children, _) => children.isEmpty
              ? const Text('No active contributors — flip a toggle above.')
              : Column(children: children),
        ),
      ],
    );
  }
}

final _hostRoot = createFeatureRoot(
  feature: toggleHostFeature,
  widget: const _HostView(),
);

class FeatureTogglesDemoWidget extends StatelessWidget {
  const FeatureTogglesDemoWidget({super.key});

  @override
  Widget build(BuildContext context) {
    return ArmatureApp(
      features: [
        toggleHostFeature,
        betaFeature,
        analyticsFeature,
        debugFeature,
        tipsFeature,
      ],
      child: _hostRoot(data: null),
    );
  }
}
''';
