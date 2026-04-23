import 'package:armature/armature.dart';
import 'package:armature_flutter/armature_flutter.dart';
import 'package:flutter/material.dart';

typedef MenuItem = ({IconData icon, String label});

/// Pipe owned by [menuFeature]; descendants contribute items by
/// transforming the accumulated list.
final menuItemsPipe = createPipe<List<MenuItem>>(name: 'demo.menu.items');

/// The host — declares the port and renders the composed menu.
final menuFeature = createFeature(name: 'Menu', ports: (items: menuItemsPipe));

/// Contributes two items to the menu.
final profileFeature = createFeature(name: 'Profile', dependsOn: [menuFeature])
  ..usePipe(
    menuItemsPipe,
    (items, _) => [
      ...items,
      (icon: Icons.person_outline, label: 'Profile'),
      (icon: Icons.settings_outlined, label: 'Settings'),
    ],
  );

/// Contributes one item to the menu.
final helpFeature = createFeature(name: 'Help', dependsOn: [menuFeature])
  ..usePipe(
    menuItemsPipe,
    (items, _) => [...items, (icon: Icons.help_outline, label: 'Help')],
  );

/// View mounted by the menu feature's root.
///
/// [PipeProvider] applies the pipe through the live container and
/// rebuilds whenever any contributor's reactive state changes.
class _MenuView extends StatelessWidget {
  const _MenuView();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return PipeProvider(
      pipe: menuItemsPipe,
      initialValue: const <MenuItem>[
        (icon: Icons.home_outlined, label: 'Home'),
      ],
      builder: (items, context) {
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Text(
                'Menu composed from ${items.length} contributions',
                style: theme.textTheme.labelMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                  fontWeight: FontWeight.w600,
                  letterSpacing: 0.8,
                ),
              ),
            ),
            for (final item in items)
              ListTile(
                dense: true,
                leading: Icon(item.icon, color: theme.colorScheme.primary),
                title: Text(item.label),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
          ],
        );
      },
    );
  }
}

final _menuRoot = createFeatureRoot(
  feature: menuFeature,
  widget: const _MenuView(),
);

/// Boots a mini Armature container with three features wired via one pipe.
class MenuDemoWidget extends StatelessWidget {
  const MenuDemoWidget({super.key});

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
        features: [menuFeature, profileFeature, helpFeature],
        child: _menuRoot(data: null),
      ),
    );
  }
}
