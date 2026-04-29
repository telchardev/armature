import 'dart:math' as math;

import 'package:armature/armature.dart' show AppContainer;
import 'package:flutter/widgets.dart';
import 'package:meta/meta.dart' show internal;

import './graph_data.dart';
import './graph_layout.dart';
import './graph_painter.dart';
import './minimap.dart';
import './node_detail_panel.dart';

/// Interactive graph canvas with pan/zoom, node selection, and drag.
/// Framework-internal.
///
/// Parent bumps [refreshToken] to request a fresh snapshot — the tab
/// re-reads the container and re-runs layout while preserving
/// selection and the current zoom / pan. Initial-build extraction is
/// one-shot by design so node positions stay stable under normal
/// interaction (drag wouldn't survive a per-rebuild relayout).
@internal
class GraphTab extends StatefulWidget {
  final AppContainer container;
  final int refreshToken;

  const GraphTab({
    super.key,
    required this.container,
    required this.refreshToken,
  });

  @override
  State<GraphTab> createState() => _GraphTabState();
}

class _GraphTabState extends State<GraphTab>
    with SingleTickerProviderStateMixin {
  final _controller = TransformationController();
  late final AnimationController _animController;
  late final Animation<double> _fadeAnim;
  late final Animation<double> _scaleAnim;
  Map<String, DebugFeatureNode>? _nodes;
  Size _canvasSize = Size.zero;
  bool _centered = false;
  String? _selectedNode;
  String? _draggingNode;
  Offset? _dragStart;

  @override
  void initState() {
    super.initState();
    _animController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 400),
    );
    _fadeAnim = CurvedAnimation(parent: _animController, curve: Curves.easeOut);
    _scaleAnim = Tween(begin: 0.92, end: 1.0).animate(
      CurvedAnimation(parent: _animController, curve: Curves.easeOutCubic),
    );
    _animController.forward();
  }

  @override
  void didUpdateWidget(GraphTab oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.refreshToken != oldWidget.refreshToken) {
      _refresh();
    }
  }

  @override
  void dispose() {
    _animController.dispose();
    _controller.dispose();
    super.dispose();
  }

  /// Re-reads the container snapshot and re-runs layout. User-dragged
  /// node positions and the current selection are preserved when the
  /// node still exists in the new snapshot.
  void _refresh() {
    setState(() {
      final previousPositions = <String, Offset>{
        if (_nodes != null)
          for (final MapEntry(:key, :value) in _nodes!.entries)
            key: value.position,
      };

      final fresh = extractGraphData(widget.container);
      final graphSize = layoutNodes(fresh);
      const padding = 600.0;
      _canvasSize = Size(
        graphSize.width + padding * 2,
        graphSize.height + padding * 2,
      );
      for (final node in fresh.values) {
        final previous = previousPositions[node.name];
        if (previous != null) {
          // User arranged this node manually — keep it where they put it.
          node.position = previous;
        } else {
          // Newly-added feature: use layout's seed position offset by
          // the canvas padding (same transform the first build applies).
          node.position = Offset(
            node.position.dx + padding,
            node.position.dy + padding,
          );
        }
      }
      _nodes = fresh;
      if (_selectedNode != null && !fresh.containsKey(_selectedNode)) {
        _selectedNode = null;
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_nodes == null) {
      _nodes = extractGraphData(widget.container);
      final graphSize = layoutNodes(_nodes!);
      const padding = 600.0;
      _canvasSize = Size(
        graphSize.width + padding * 2,
        graphSize.height + padding * 2,
      );
      for (final node in _nodes!.values) {
        node.position = Offset(
          node.position.dx + padding,
          node.position.dy + padding,
        );
      }
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        if (!_centered) {
          _centered = true;
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) {
              _centerGraph(constraints);
              setState(() {});
            }
          });
        }

        return Stack(
          children: [
            GestureDetector(
              onTapUp: (details) {
                final matrix = _controller.value.clone()..invert();
                final canvasPoint = MatrixUtils.transformPoint(
                  matrix,
                  details.localPosition,
                );
                final hit = GraphPainter(_nodes!).hitTestNode(canvasPoint);
                setState(() {
                  _selectedNode = hit == _selectedNode ? null : hit;
                });
              },
              child: FadeTransition(
                opacity: _fadeAnim,
                child: ScaleTransition(
                  scale: _scaleAnim,
                  child: InteractiveViewer(
                    transformationController: _controller,
                    constrained: false,
                    boundaryMargin: const EdgeInsets.all(double.infinity),
                    minScale: 0.2,
                    maxScale: 3.0,
                    child: GestureDetector(
                      onLongPressStart: (details) {
                        final hit = GraphPainter(
                          _nodes!,
                        ).hitTestNode(details.localPosition);
                        if (hit != null) {
                          setState(() {
                            _draggingNode = hit;
                            _dragStart = details.localPosition;
                          });
                        }
                      },
                      onLongPressMoveUpdate: (details) {
                        if (_draggingNode == null || _dragStart == null) return;
                        final node = _nodes![_draggingNode];
                        if (node == null) return;
                        final delta = details.localPosition - _dragStart!;
                        node.position = Offset(
                          node.position.dx + delta.dx,
                          node.position.dy + delta.dy,
                        );
                        _dragStart = details.localPosition;
                        setState(() {});
                      },
                      onLongPressEnd: (_) {
                        setState(() {
                          _draggingNode = null;
                          _dragStart = null;
                        });
                      },
                      child: SizedBox(
                        width: _canvasSize.width,
                        height: _canvasSize.height,
                        child: CustomPaint(
                          painter: GraphPainter(
                            _nodes!,
                            selectedNodeName: _selectedNode,
                            draggingNodeName: _draggingNode,
                          ),
                          size: _canvasSize,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
            if (_selectedNode != null && _nodes![_selectedNode] != null)
              Positioned(
                right: 8,
                top: 8,
                bottom: 8,
                child: ConstrainedBox(
                  constraints: BoxConstraints(
                    maxWidth: constraints.maxWidth * 0.45,
                  ),
                  child: NodeDetailPanel(
                    node: _nodes![_selectedNode]!,
                    onClose: () => setState(() => _selectedNode = null),
                  ),
                ),
              ),
            if (_selectedNode == null)
              Positioned(
                right: 8,
                bottom: 8,
                child: Minimap(
                  nodes: _nodes!,
                  canvasSize: _canvasSize,
                  controller: _controller,
                  screenSize: Size(constraints.maxWidth, constraints.maxHeight),
                ),
              ),
          ],
        );
      },
    );
  }

  void _centerGraph(BoxConstraints constraints) {
    final viewW = constraints.maxWidth;
    final viewH = constraints.maxHeight;

    final scaleX = viewW / _canvasSize.width;
    final scaleY = viewH / _canvasSize.height;
    final scale = math.min(scaleX, scaleY).clamp(0.2, 1.5);

    final scaledW = _canvasSize.width * scale;
    final scaledH = _canvasSize.height * scale;
    final dx = (viewW - scaledW) / 2;
    final dy = (viewH - scaledH) / 2;

    _controller.value = Matrix4.identity()
      ..storage[0] = scale
      ..storage[5] = scale
      ..storage[10] = scale
      ..storage[12] = dx
      ..storage[13] = dy;
  }
}
