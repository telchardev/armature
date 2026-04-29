import 'dart:ui' show ImageFilter;

import 'package:armature/advanced.dart' show FeatureDependency, PortDebugInfo;
import 'package:armature/armature.dart' show FeatureStatus, Store;
import 'package:flutter/widgets.dart';
import 'package:meta/meta.dart' show internal;

import '../stores/state_observer.dart' show StateObserver;
import './debug_theme.dart';
import './format_state.dart' show formatState;
import './graph_data.dart';

/// Detail panel shown when tapping a node in the graph. Framework-
/// internal.
@internal
class NodeDetailPanel extends StatelessWidget {
  final DebugFeatureNode node;
  final VoidCallback onClose;

  const NodeDetailPanel({super.key, required this.node, required this.onClose});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () {}, // prevent tap-through
      child: ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 16, sigmaY: 16),
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: kDetailPanelBg,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: _statusColor.withAlpha(120), width: 1),
            ),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 320, maxHeight: 420),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Header
                  Padding(
                    padding: const EdgeInsets.fromLTRB(12, 10, 8, 0),
                    child: Row(
                      children: [
                        Expanded(
                          child: Text(
                            node.name,
                            style: const TextStyle(
                              color: kTextWhite,
                              fontSize: 15,
                              fontWeight: FontWeight.bold,
                              decoration: TextDecoration.none,
                            ),
                          ),
                        ),
                        _badge(_statusLabel, _statusColor),
                        const SizedBox(width: 4),
                        if (node.resolveTime != null)
                          _badge(
                            '${node.resolveTime!.inMilliseconds}ms',
                            kTextAmber,
                          ),
                        GestureDetector(
                          onTap: onClose,
                          child: const Padding(
                            padding: EdgeInsets.all(4),
                            child: Text(
                              '✕',
                              style: TextStyle(
                                color: kTextGrey,
                                fontSize: 16,
                                decoration: TextDecoration.none,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 8),
                  // Content
                  Flexible(
                    child: SingleChildScrollView(
                      padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          if (node.dependencies.isNotEmpty) ...[
                            _sectionTitle('Dependencies'),
                            ...node.dependencies.map((d) => _depRow(d)),
                            const SizedBox(height: 8),
                          ],
                          if (node.storeEntries.isNotEmpty) ...[
                            _sectionTitle('Stores'),
                            ...node.storeEntries.map(
                              (s) => _StoreRow(store: s),
                            ),
                            const SizedBox(height: 8),
                          ],
                          if (node.ports.isNotEmpty) ...[
                            _sectionTitle('Ports'),
                            ...node.ports.map(
                              (id) => _PortRow(port: id, ownerName: node.name),
                            ),
                          ],
                          if (node.childNames.isNotEmpty) ...[
                            const SizedBox(height: 8),
                            _sectionTitle('Children'),
                            ...node.childNames.map(
                              (name) => _infoRow('→', name, kTextGrey),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Color get _statusColor => switch (node.status) {
    FeatureStatus.active => kEnabledColor,
    FeatureStatus.disabled => kDisabledColor,
    FeatureStatus.pending => kPendingColor,
  };

  String get _statusLabel => switch (node.status) {
    FeatureStatus.active => 'enabled',
    FeatureStatus.disabled => 'disabled',
    FeatureStatus.pending => 'pending',
  };

  static Widget _sectionTitle(String text) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Text(
        text,
        style: const TextStyle(
          color: kTextGrey,
          fontSize: 10,
          fontWeight: FontWeight.bold,
          decoration: TextDecoration.none,
          letterSpacing: 0.5,
        ),
      ),
    );
  }

  static Widget _depRow(FeatureDependency dep) {
    return Padding(
      padding: const EdgeInsets.only(left: 4, bottom: 2),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            dep.isRequired ? '●' : '○',
            style: TextStyle(
              color: dep.isRequired ? kTextWhite : kTextGrey,
              fontSize: 8,
              decoration: TextDecoration.none,
            ),
          ),
          const SizedBox(width: 6),
          Text(
            '${dep.featureName}${dep.isRequired ? '' : ' (optional)'}',
            style: TextStyle(
              color: dep.isRequired ? kTextWhite : kTextGrey,
              fontSize: 11,
              decoration: TextDecoration.none,
            ),
          ),
        ],
      ),
    );
  }

  static Widget _infoRow(String icon, String text, Color color) {
    return Padding(
      padding: const EdgeInsets.only(left: 4, bottom: 2),
      child: Text(
        '$icon $text',
        style: TextStyle(
          color: color,
          fontSize: 11,
          decoration: TextDecoration.none,
        ),
      ),
    );
  }

  static Widget _badge(String text, Color color) {
    return Padding(
      padding: const EdgeInsets.only(right: 4),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: color.withAlpha(30),
          borderRadius: BorderRadius.circular(4),
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
          child: Text(
            text,
            style: TextStyle(
              color: color,
              fontSize: 9,
              fontWeight: FontWeight.bold,
              decoration: TextDecoration.none,
            ),
          ),
        ),
      ),
    );
  }
}

/// Store row — tap to expand state.
class _StoreRow extends StatefulWidget {
  final Store store;

  const _StoreRow({required this.store});

  @override
  State<_StoreRow> createState() => _StoreRowState();
}

class _StoreRowState extends State<_StoreRow> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => setState(() => _expanded = !_expanded),
      child: Padding(
        padding: const EdgeInsets.only(left: 4, bottom: 4),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Text(
                  '📦 ${widget.store.runtimeType}',
                  style: const TextStyle(
                    color: kTextBlue,
                    fontSize: 11,
                    decoration: TextDecoration.none,
                  ),
                ),
                Text(
                  _expanded ? ' ▾' : ' ▸',
                  style: const TextStyle(
                    color: kTextGrey,
                    fontSize: 10,
                    decoration: TextDecoration.none,
                  ),
                ),
              ],
            ),
            if (_expanded)
              Padding(
                padding: const EdgeInsets.only(left: 20, top: 4),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxHeight: 150),
                  child: SingleChildScrollView(
                    physics: const ClampingScrollPhysics(),
                    child: StateObserver(
                      builder: (_) => Text(
                        formatState(widget.store.state),
                        style: const TextStyle(
                          color: kTextGrey,
                          fontSize: 10,
                          fontFamily: 'monospace',
                          decoration: TextDecoration.none,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// Port row — always shows handler list.
class _PortRow extends StatelessWidget {
  final PortDebugInfo port;
  final String ownerName;

  const _PortRow({required this.port, required this.ownerName});

  @override
  Widget build(BuildContext context) {
    final id = port;

    return Padding(
      padding: const EdgeInsets.only(left: 4, bottom: 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '🔌 ${id.name} (${id.type.name}) ×${id.handlerCount}',
            style: const TextStyle(
              color: kTextPurple,
              fontSize: 11,
              decoration: TextDecoration.none,
            ),
          ),
          if (id.handlerFeatureNames.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(left: 20, top: 2),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: id.handlerFeatureNames.map((name) {
                  final isSelf = name == ownerName;
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 1),
                    child: Text(
                      '↳ $name',
                      style: TextStyle(
                        color: isSelf ? kEnabledColor : kTextGrey,
                        fontSize: 10,
                        decoration: TextDecoration.none,
                      ),
                    ),
                  );
                }).toList(),
              ),
            ),
          if (id.handlerFeatureNames.isEmpty)
            const Padding(
              padding: EdgeInsets.only(left: 20, top: 2),
              child: Text(
                'No handlers registered',
                style: TextStyle(
                  color: kTextGrey,
                  fontSize: 10,
                  fontStyle: FontStyle.italic,
                  decoration: TextDecoration.none,
                ),
              ),
            ),
        ],
      ),
    );
  }
}
