import 'package:armature/advanced.dart' show PortSubscription;
import 'package:flutter/widgets.dart'
    show Widget, StatefulWidget, BuildContext, State;

import '../contexts/container_context.dart' show ContainerContext;
import '../contexts/feature_context.dart' show FeatureContext;
import '../ports/single_slot.dart' show SingleSlot, SingleSlotHandler;
import './port_provider_base.dart';

/// Builder for [SingleSlotProvider]: receives the currently-selected
/// child widget (or `null` when no handler matches) plus the build
/// context, and returns whatever should render around it.
typedef SingleSlotWidgetBuilder =
    Widget Function(Widget? child, BuildContext context);

/// Reactively subscribes to a [SingleSlot] and rebuilds when the
/// selected handler's widget or its tracked atoms change. The builder
/// receives the winning child widget (or `null`) and typically wraps it
/// in a layout widget.
class SingleSlotProvider<
  TInputData,
  TSlot extends SingleSlot<TInputData, SingleSlotHandler<TInputData>>
>
    extends StatefulWidget {
  final SingleSlotWidgetBuilder builder;

  final TInputData data;

  final TSlot slot;

  const SingleSlotProvider({
    super.key,
    required this.slot,
    required this.builder,
    required this.data,
  });

  @override
  State<SingleSlotProvider<TInputData, TSlot>> createState() =>
      _SingleSlotProviderState<TInputData, TSlot>();
}

class _SingleSlotProviderState<
  TInputData,
  TSlot extends SingleSlot<TInputData, SingleSlotHandler<TInputData>>
>
    extends
        PortProviderState<
          Widget?,
          TInputData,
          SingleSlotProvider<TInputData, TSlot>
        > {
  @override
  Widget? get fallbackValue => null;

  @override
  PortSubscription<Widget?, TInputData> createSubscription() {
    final container = ContainerContext.of(context).container;
    final feature = FeatureContext.of(context).feature;

    return container.observe(
      rootFeature: feature,
      port: widget.slot,
      initialValue: null,
      data: widget.data,
      onChanged: safeSetState,
    );
  }

  @override
  void didUpdateWidget(SingleSlotProvider<TInputData, TSlot> oldWidget) {
    super.didUpdateWidget(oldWidget);

    if (widget.slot != oldWidget.slot) {
      resubscribe();
    } else if (widget.data != oldWidget.data) {
      // Same slot, new data — reapply keeps the Reaction +
      // handler-set listener alive and just re-runs `port.apply`.
      subscription?.reapply(initialValue: null, data: widget.data);
    }
  }

  @override
  Widget build(BuildContext context) {
    return widget.builder(value, context);
  }
}
