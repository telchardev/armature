import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../theme/theme_controller.dart';
import 'external_links.dart';

/// Top-level shell: responsive app bar + drawer on narrow, inline nav on wide.
class AppShell extends StatelessWidget {
  const AppShell({super.key, required this.child});

  final Widget child;

  static const double _navBreakpoint = 720;

  @override
  Widget build(BuildContext context) {
    final location = GoRouterState.of(context).uri.path;
    return LayoutBuilder(
      builder: (context, constraints) {
        final isWide = constraints.maxWidth >= _navBreakpoint;
        return Scaffold(
          appBar: AppBar(
            titleSpacing: isWide ? 24 : 8,
            title: const _BrandButton(),
            actions: [
              if (isWide) ...[
                _NavButton(label: 'Docs', path: '/docs', currentPath: location),
                _NavButton(
                  label: 'Examples',
                  path: '/examples',
                  currentPath: location,
                ),
                TextButton.icon(
                  onPressed: () => openExternal(kApiDocsUrl),
                  icon: const Icon(Icons.open_in_new, size: 14),
                  label: const Text('API'),
                  style: TextButton.styleFrom(
                    foregroundColor: Theme.of(context).colorScheme.onSurface,
                  ),
                ),
                const SizedBox(width: 8),
                IconButton(
                  tooltip: 'GitHub',
                  onPressed: () => openExternal(kGitHubUrl),
                  icon: const Icon(Icons.code),
                ),
              ],
              const _ThemeToggleButton(),
              const SizedBox(width: 8),
            ],
          ),
          drawer: isWide ? null : _NavDrawer(currentPath: location),
          // Enable text selection across all page content. Interactive
          // children (buttons, fields) handle their own gestures — the
          // SelectionArea only picks up plain text runs.
          body: SelectionArea(child: child),
        );
      },
    );
  }
}

class _BrandButton extends StatelessWidget {
  const _BrandButton();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return InkWell(
      onTap: () => context.go('/'),
      borderRadius: BorderRadius.circular(4),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
        child: Text(
          'Armature',
          style: theme.textTheme.titleLarge?.copyWith(
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
    );
  }
}

class _NavButton extends StatelessWidget {
  const _NavButton({
    required this.label,
    required this.path,
    required this.currentPath,
  });

  final String label;
  final String path;
  final String currentPath;

  @override
  Widget build(BuildContext context) {
    final selected = currentPath == path || currentPath.startsWith('$path/');
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4),
      child: TextButton(
        onPressed: () => context.go(path),
        style: TextButton.styleFrom(
          foregroundColor: selected
              ? theme.colorScheme.primary
              : theme.colorScheme.onSurface,
        ),
        child: Text(label),
      ),
    );
  }
}

class _ThemeToggleButton extends StatelessWidget {
  const _ThemeToggleButton();

  @override
  Widget build(BuildContext context) {
    final controller = ThemeScope.of(context);
    return IconButton(
      tooltip: 'Toggle theme (current: ${controller.mode.name})',
      onPressed: controller.cycle,
      icon: Icon(switch (controller.mode) {
        ThemeMode.system => Icons.brightness_auto_outlined,
        ThemeMode.light => Icons.light_mode_outlined,
        ThemeMode.dark => Icons.dark_mode_outlined,
      }),
    );
  }
}

class _NavDrawer extends StatelessWidget {
  const _NavDrawer({required this.currentPath});

  final String currentPath;

  @override
  Widget build(BuildContext context) {
    return Drawer(
      child: SafeArea(
        child: ListView(
          padding: const EdgeInsets.symmetric(vertical: 12),
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 12, 24, 20),
              child: Text(
                'Armature',
                style: Theme.of(
                  context,
                ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700),
              ),
            ),
            _DrawerTile(
              icon: Icons.home_outlined,
              label: 'Home',
              path: '/',
              currentPath: currentPath,
            ),
            _DrawerTile(
              icon: Icons.menu_book_outlined,
              label: 'Docs',
              path: '/docs',
              currentPath: currentPath,
            ),
            _DrawerTile(
              icon: Icons.play_arrow_outlined,
              label: 'Examples',
              path: '/examples',
              currentPath: currentPath,
            ),
            ListTile(
              leading: const Icon(Icons.api_outlined),
              title: const Text('API'),
              trailing: const Icon(Icons.open_in_new, size: 16),
              onTap: () {
                Navigator.of(context).pop();
                openExternal(kApiDocsUrl);
              },
            ),
            const Divider(height: 32),
            ListTile(
              leading: const Icon(Icons.code),
              title: const Text('GitHub'),
              trailing: const Icon(Icons.open_in_new, size: 16),
              onTap: () {
                Navigator.of(context).pop();
                openExternal(kGitHubUrl);
              },
            ),
          ],
        ),
      ),
    );
  }
}

class _DrawerTile extends StatelessWidget {
  const _DrawerTile({
    required this.icon,
    required this.label,
    required this.path,
    required this.currentPath,
  });

  final IconData icon;
  final String label;
  final String path;
  final String currentPath;

  @override
  Widget build(BuildContext context) {
    final selected =
        currentPath == path ||
        (path != '/' && currentPath.startsWith('$path/'));
    return ListTile(
      leading: Icon(icon),
      title: Text(label),
      selected: selected,
      onTap: () {
        Navigator.of(context).pop();
        context.go(path);
      },
    );
  }
}
