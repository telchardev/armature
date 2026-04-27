import 'package:armature/armature.dart';
import 'package:armature_flutter/armature_flutter.dart';
import 'package:flutter/material.dart';

/// Immutable state for four independent toggles.
///
/// Using a regular class (rather than a record) so we can expose a
/// `copyWith` — each setter on [TogglesStore] is a one-liner.
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
final extrasSlot = createMultiSlot<Null>(name: 'toggle.extras');

/// Host feature — owns the toggles store, declares the slot.
final toggleHostFeature = createFeature(
  name: 'ToggleHost',
  stores: (_) => (toggles: TogglesStore()),
  ports: (extras: extrasSlot),
  exports: (api) => api.own,
);

/// Four content features, each gated on one flag.
///
/// Each one:
///   * activates when its flag is true (`whenStoreState` helper),
///   * contributes exactly one widget into [extrasSlot],
///   * sets an explicit `order` so the visual stack is stable.
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
          subtitle:
              'Tracking is active. This banner is rendered only while '
              'the Analytics feature is active.',
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
          subtitle: 'Mock counters, build info — would be disabled in prod.',
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
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: theme.colorScheme.onSecondaryContainer),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: theme.textTheme.titleSmall?.copyWith(
                    color: theme.colorScheme.onSecondaryContainer,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  subtitle,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSecondaryContainer,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class HostView extends StatelessWidget {
  const HostView({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final store = StoreContext.of<TogglesStore>(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        StateObserver(
          builder: (_) {
            final s = store.state;
            return Column(
              children: [
                _ToggleTile(
                  title: 'Beta preview',
                  value: s.beta,
                  onChanged: store.setBeta,
                ),
                _ToggleTile(
                  title: 'Analytics',
                  value: s.analytics,
                  onChanged: store.setAnalytics,
                ),
                _ToggleTile(
                  title: 'Debug panel',
                  value: s.debug,
                  onChanged: store.setDebug,
                ),
                _ToggleTile(
                  title: 'Daily tips',
                  value: s.tips,
                  onChanged: store.setTips,
                ),
              ],
            );
          },
        ),
        const Divider(height: 24),
        MultiSlotProvider(
          slot: toggleHostFeature.ports.extras,
          data: null,
          builder: (children, _) {
            if (children.isEmpty) {
              return Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: theme.colorScheme.surfaceContainerHigh,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: theme.colorScheme.outlineVariant),
                ),
                child: Text(
                  'No active contributors — flip a toggle above.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: theme.colorScheme.onSurfaceVariant),
                ),
              );
            }
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: children,
            );
          },
        ),
      ],
    );
  }
}

class _ToggleTile extends StatelessWidget {
  const _ToggleTile({
    required this.title,
    required this.value,
    required this.onChanged,
  });

  final String title;
  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    return SwitchListTile(
      dense: true,
      contentPadding: EdgeInsets.zero,
      title: Text(title),
      value: value,
      onChanged: onChanged,
    );
  }
}

final hostRoot = createFeatureRoot(
  feature: toggleHostFeature,
  widget: const HostView(),
);

void main() {
  runApp(
    ArmatureApp(
      features: [
        toggleHostFeature,
        betaFeature,
        analyticsFeature,
        debugFeature,
        tipsFeature,
      ],
      child: MaterialApp(home: hostRoot(data: null)),
    ),
  );
}
