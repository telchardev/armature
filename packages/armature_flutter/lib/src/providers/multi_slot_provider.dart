import 'package:armature/armature.dart' show PortSubscription;
import 'package:flutter/widgets.dart'
    show Widget, StatefulWidget, BuildContext, State;

import '../contexts/container_context.dart' show ContainerContext;
import '../contexts/feature_context.dart' show FeatureContext;
import '../ports/multi_slot.dart' show MultiSlot, MultiSlotHandler;
import './port_provider_base.dart';

/// Builder for [MultiSlotProvider]: receives the ordered list of
/// children produced by active handlers and the build context, and
/// returns whatever layout should host them (Row, Column, ListView, …).
typedef MultiSlotWidgetBuilder =
    Widget Function(List<Widget> children, BuildContext context);

/// Reactively subscribes to a [MultiSlot] and rebuilds when the set of
/// children or their tracked atoms change. The builder receives the
/// sorted widget list (empty when no handler contributes).
class MultiSlotProvider<
  TInputData,
  TSlot extends MultiSlot<TInputData, MultiSlotHandler<TInputData>>
>
    extends StatefulWidget {
  final MultiSlotWidgetBuilder builder;

  final TInputData data;

  final TSlot slot;

  const MultiSlotProvider({
    super.key,
    required this.slot,
    required this.builder,
    required this.data,
  });

  @override
  State<MultiSlotProvider<TInputData, TSlot>> createState() =>
      _MultiSlotProviderState<TInputData, TSlot>();
}

class _MultiSlotProviderState<
  TInputData,
  TSlot extends MultiSlot<TInputData, MultiSlotHandler<TInputData>>
>
    extends
        PortProviderState<
          List<Widget>,
          TInputData,
          MultiSlotProvider<TInputData, TSlot>
        > {
  @override
  List<Widget> get fallbackValue => const [];

  @override
  PortSubscription<List<Widget>, TInputData> createSubscription() {
    final container = ContainerContext.of(context).container;
    final feature = FeatureContext.of(context).feature;

    return container.observe(
      rootFeature: feature,
      port: widget.slot,
      initialValue: const <Widget>[],
      data: widget.data,
      onChanged: safeSetState,
    );
  }

  @override
  void didUpdateWidget(MultiSlotProvider<TInputData, TSlot> oldWidget) {
    super.didUpdateWidget(oldWidget);

    if (widget.slot != oldWidget.slot) {
      resubscribe();
    } else if (widget.data != oldWidget.data) {
      subscription?.reapply(initialValue: const <Widget>[], data: widget.data);
    }
  }

  @override
  Widget build(BuildContext context) {
    return widget.builder(value, context);
  }
}
