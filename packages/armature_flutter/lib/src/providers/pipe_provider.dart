import 'package:armature/armature.dart'
    show Pipe, PipeHandler, PortSubscription;
import 'package:flutter/widgets.dart'
    show Widget, StatefulWidget, BuildContext, State;

import '../contexts/container_context.dart' show ContainerContext;
import '../contexts/feature_context.dart' show FeatureContext;
import './port_provider_base.dart';

/// Applies a [Pipe] reactively, rebuilding when the value changes.
///
/// ```dart
/// PipeProvider(
///   pipe: tabsPipe,
///   initialValue: <String>[],
///   builder: (tabs, context) => TabBar(tabs: tabs),
/// )
/// ```
class PipeProvider<TValue extends Object> extends StatefulWidget {
  final Pipe<TValue, PipeHandler<TValue>> pipe;

  final TValue initialValue;

  final Widget Function(TValue value, BuildContext context) builder;

  const PipeProvider({
    super.key,
    required this.pipe,
    required this.initialValue,
    required this.builder,
  });

  @override
  State<PipeProvider<TValue>> createState() => _PipeProviderState<TValue>();
}

class _PipeProviderState<TValue extends Object>
    extends PortProviderState<TValue, void, PipeProvider<TValue>> {
  @override
  TValue get fallbackValue => widget.initialValue;

  @override
  PortSubscription<TValue, void> createSubscription() {
    final container = ContainerContext.of(context).container;
    final feature = FeatureContext.of(context).feature;

    return container.observe(
      rootFeature: feature,
      port: widget.pipe,
      initialValue: widget.initialValue,
      data: null,
      onChanged: safeSetState,
    );
  }

  @override
  void didUpdateWidget(PipeProvider<TValue> oldWidget) {
    super.didUpdateWidget(oldWidget);

    if (widget.pipe != oldWidget.pipe) {
      resubscribe();
    } else if (widget.initialValue != oldWidget.initialValue) {
      // Same pipe, new seed — reapply reuses the Reaction, diffing
      // atom deps instead of re-allocating the subscription.
      subscription?.reapply(initialValue: widget.initialValue, data: null);
    }
  }

  @override
  Widget build(BuildContext context) {
    return widget.builder(value, context);
  }
}
