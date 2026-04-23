import 'package:armature/armature.dart';
import 'package:armature_flutter/armature_flutter.dart';
import 'package:flutter/material.dart';

/// Store that drives the activation toggle.
class ToggleStore extends Store<({bool showExtras})> {
  ToggleStore() : super(state: (showExtras: false));

  void toggle() {
    state = (showExtras: !state.showExtras);
  }
}

/// Slot the extras feature fills when it is active.
final extraContentSlot = createSingleSlot<Null>(name: 'toggle.extra');

/// Host feature — owns the toggle store and declares the slot.
final toggleHostFeature = createFeature(
  name: 'ToggleHost',
  stores: (_) => (toggle: ToggleStore()),
  ports: (extra: extraContentSlot),
  exports: (api) => api.own,
);

/// Extras feature — activation is gated on the host's toggle state.
///
/// The activation setup subscribes to the toggle store; every transition
/// flips this feature between active and inactive. While inactive, its
/// slot handler is skipped transparently — the UI sees no contribution.
final extrasFeature =
    createFeature(name: 'Extras', dependsOn: [toggleHostFeature])
      ..activation((parentApi, toggle, cleanup) {
        final toggleStore = parentApi.of(toggleHostFeature).toggle;
        final disposer = toggleStore.subscribe(
          (_, current) => toggle(
            current.showExtras ? ToggleState.active : ToggleState.inactive,
          ),
          fireImmediately: true,
        );
        cleanup.add(disposer);
      })
      ..useSingleSlot(extraContentSlot, (_, api) => const _ExtrasPanel());

class _ExtrasPanel extends StatelessWidget {
  const _ExtrasPanel();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      margin: const EdgeInsets.only(top: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: theme.colorScheme.secondaryContainer,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        children: [
          Icon(
            Icons.auto_awesome,
            color: theme.colorScheme.onSecondaryContainer,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              'Extras feature is ACTIVE — this panel is contributed to '
              'the slot by extrasFeature.',
              style: TextStyle(color: theme.colorScheme.onSecondaryContainer),
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
    final theme = Theme.of(context);
    final store = StoreContext.of<ToggleStore>(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        StateObserver(
          builder: (_) => SwitchListTile(
            title: const Text('Activate Extras feature'),
            subtitle: Text(
              store.state.showExtras
                  ? 'Feature is active — slot handler runs.'
                  : 'Feature is inactive — slot handler is skipped.',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            value: store.state.showExtras,
            onChanged: (_) => store.toggle(),
          ),
        ),
        const SizedBox(height: 8),
        SingleSlotProvider(
          slot: extraContentSlot,
          data: null,
          builder: (child, context) {
            if (child != null) {
              return child;
            }
            return Container(
              margin: const EdgeInsets.only(top: 12),
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: theme.colorScheme.surfaceContainerHigh,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: theme.colorScheme.outlineVariant),
              ),
              child: Text(
                '(No contributor — slot falls back to this placeholder.)',
                textAlign: TextAlign.center,
                style: TextStyle(color: theme.colorScheme.onSurfaceVariant),
              ),
            );
          },
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
        features: [toggleHostFeature, extrasFeature],
        child: _hostRoot(data: null),
      ),
    );
  }
}
