import 'package:armature/armature.dart' show BehaviorDescriptor;
import 'package:armature_flutter/armature_flutter.dart';
import 'package:flutter/material.dart';

import '../../app/theme.dart';
import '../active_tab_store.dart';
import '../layout_mode.dart';
import '../ports.dart';

const double _tabletBreakpoint = 780;

class LayoutShell extends StatelessWidget {
  const LayoutShell({super.key});

  @override
  Widget build(BuildContext context) {
    return BehaviorProvider<ThemeMode, ThemeData>(
      behavior: themeBehavior,
      initialValue: BehaviorDescriptor(
        branch: ThemeMode.light,
        payload: buildLightTheme(),
      ),
      builder: (descriptor, _) {
        return MaterialApp(
          title: 'armature Kitchen Sink',
          theme: descriptor.payload,
          debugShowCheckedModeBanner: false,
          home: const _Shell(),
        );
      },
    );
  }
}

class _Shell extends StatelessWidget {
  const _Shell();

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.sizeOf(context).width;
    final mode = width < _tabletBreakpoint
        ? LayoutMode.phone
        : LayoutMode.tablet;
    final activeTab = StoreContext.of<ActiveTabStore>(context);

    return StateObserver(
      builder: (_) {
        final current = activeTab.state;
        return MultiPortBuilder(
          builder: (reader, _) {
            final title = reader.single(titleSlot, data: mode);
            final actions = reader.multi(actionsSlot, data: mode);
            final tabs = reader.pipe(tabsPipe, initialValue: const <TabSpec>[]);
            final body = reader.single(bodyKeyedSlot(current), data: mode);
            final fab = reader.multi(fabSlot, data: mode);

            return Scaffold(
              appBar: AppBar(
                title: title ?? const Text('armature showcase'),
                actions: [
                  Row(mainAxisSize: MainAxisSize.min, children: actions),
                  const SizedBox(width: 8),
                ],
              ),
              body: Column(
                children: [
                  _TabBar(
                    tabs: tabs,
                    currentTab: current,
                    onTabChanged: activeTab.setTab,
                    mode: mode,
                  ),
                  Expanded(
                    child:
                        body ??
                        const Center(
                          child: Text(
                            'Select a tab',
                            style: TextStyle(color: Colors.grey),
                          ),
                        ),
                  ),
                ],
              ),
              floatingActionButton: fab.isEmpty
                  ? null
                  : Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        for (var i = 0; i < fab.length; i++) ...[
                          if (i > 0) const SizedBox(height: 12),
                          fab[i],
                        ],
                      ],
                    ),
            );
          },
        );
      },
    );
  }
}

class _TabBar extends StatelessWidget {
  final List<TabSpec> tabs;
  final String currentTab;
  final ValueChanged<String> onTabChanged;
  final LayoutMode mode;

  const _TabBar({
    required this.tabs,
    required this.currentTab,
    required this.onTabChanged,
    required this.mode,
  });

  @override
  Widget build(BuildContext context) {
    if (tabs.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: [
            for (final tab in tabs) ...[
              _TabChip(
                tab: tab,
                selected: tab.id == currentTab,
                compact: mode == LayoutMode.phone,
                onTap: () => onTabChanged(tab.id),
              ),
              const SizedBox(width: 8),
            ],
          ],
        ),
      ),
    );
  }
}

class _TabChip extends StatelessWidget {
  final TabSpec tab;
  final bool selected;
  final bool compact;
  final VoidCallback onTap;

  const _TabChip({
    required this.tab,
    required this.selected,
    required this.compact,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Material(
      color: selected ? scheme.primary : scheme.surface,
      shape: StadiumBorder(
        side: BorderSide(
          color: selected ? scheme.primary : scheme.outlineVariant,
        ),
      ),
      child: InkWell(
        customBorder: const StadiumBorder(),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                tab.icon,
                size: 16,
                color: selected ? scheme.onPrimary : scheme.onSurfaceVariant,
              ),
              if (!compact) ...[
                const SizedBox(width: 6),
                Text(
                  tab.label,
                  style: TextStyle(
                    color: selected
                        ? scheme.onPrimary
                        : scheme.onSurfaceVariant,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
