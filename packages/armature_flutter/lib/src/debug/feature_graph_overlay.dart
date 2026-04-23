import 'package:armature/armature.dart' show ContainerDebugExt;
import 'package:flutter/widgets.dart';

import '../contexts/container_context.dart' show ContainerContext;
import './debug_fab.dart';
import './debug_theme.dart';
import './graph_tab.dart';
import './legend.dart';
import './state_inspector.dart';

/// Debug overlay that visualizes the feature dependency graph.
///
/// ```dart
/// ArmatureApp(
///   features: [...],
///   child: FeatureGraphOverlay(
///     enabled: kDebugMode,
///     child: layoutRoot(data: null),
///   ),
/// );
/// ```
class FeatureGraphOverlay extends StatefulWidget {
  final Widget child;
  final bool enabled;

  const FeatureGraphOverlay({
    super.key,
    required this.child,
    this.enabled = true,
  });

  @override
  State<FeatureGraphOverlay> createState() => _FeatureGraphOverlayState();
}

class _FeatureGraphOverlayState extends State<FeatureGraphOverlay> {
  bool _visible = false;

  /// Monotonically-incrementing counter propagated down to [GraphTab].
  /// Bumping it triggers [GraphTab] to re-read the container snapshot
  /// (statuses + feature list) while preserving selection + zoom/pan.
  /// The `GraphTab.didUpdateWidget` compares old/new value.
  int _refreshToken = 0;

  @override
  Widget build(BuildContext context) {
    if (!widget.enabled) return widget.child;

    return Directionality(
      textDirection: TextDirection.ltr,
      child: Stack(
        children: [
          widget.child,
          Positioned(
            left: 16,
            bottom: 16,
            child: GestureDetector(
              onTap: () => setState(() => _visible = !_visible),
              child: const DebugFab(),
            ),
          ),
          if (_visible) ...[
            Positioned.fill(
              child: ColoredBox(
                color: kOverlayBg,
                child: _DebugPanel(refreshToken: _refreshToken),
              ),
            ),
            Positioned(
              left: 16,
              bottom: 16,
              child: GestureDetector(
                onTap: () => setState(() => _visible = false),
                child: const DebugFab(isClose: true),
              ),
            ),
            Positioned(
              // 16 (margin) + 32 (close FAB) + 8 (gap) = 56.
              left: 56,
              bottom: 16,
              child: GestureDetector(
                onTap: () => setState(() => _refreshToken++),
                child: const RefreshFab(),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

// --- Tab navigation ---

enum _DebugTab { graph, states }

class _DebugPanel extends StatefulWidget {
  final int refreshToken;

  const _DebugPanel({required this.refreshToken});

  @override
  State<_DebugPanel> createState() => _DebugPanelState();
}

class _DebugPanelState extends State<_DebugPanel> {
  _DebugTab _tab = _DebugTab.graph;

  @override
  Widget build(BuildContext context) {
    final container = ContainerContext.of(context).container;

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(8, 40, 8, 0),
          child: Row(
            children: [
              _tabButton('Graph', _DebugTab.graph),
              const SizedBox(width: 4),
              _tabButton('States', _DebugTab.states),
              const SizedBox(width: 12),
              if (_tab == _DebugTab.graph) const _GestureHint(),
              const Spacer(),
              const Flexible(child: GraphLegend()),
            ],
          ),
        ),
        const SizedBox(height: 4),
        Expanded(
          child: switch (_tab) {
            _DebugTab.graph => GraphTab(
              container: container,
              refreshToken: widget.refreshToken,
            ),
            _DebugTab.states => StateInspectorPanel(
              features: container.debug.features,
            ),
          },
        ),
      ],
    );
  }

  Widget _tabButton(String label, _DebugTab tab) {
    final active = _tab == tab;
    return GestureDetector(
      onTap: () => setState(() => _tab = tab),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: active ? kTabActiveBg : kTabInactiveBg,
          borderRadius: BorderRadius.circular(6),
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          child: Text(
            label,
            style: TextStyle(
              color: active ? kTextWhite : kTextGrey,
              fontSize: 12,
              fontWeight: active ? FontWeight.bold : FontWeight.normal,
              decoration: TextDecoration.none,
            ),
          ),
        ),
      ),
    );
  }
}

/// Gesture hint shown next to the tabs only while the Graph tab is
/// active. Tells the user which interactions the graph canvas wires
/// up (tap to select a node, long-press+drag to move one).
class _GestureHint extends StatelessWidget {
  const _GestureHint();

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: kFabBgClose,
        borderRadius: BorderRadius.circular(6),
      ),
      child: const Padding(
        padding: EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        child: Text(
          'Tap: select • Long-press: drag',
          style: TextStyle(
            color: kTextGrey,
            fontSize: 10,
            decoration: TextDecoration.none,
          ),
        ),
      ),
    );
  }
}
