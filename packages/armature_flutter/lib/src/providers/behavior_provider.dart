import 'package:armature/armature.dart'
    show Behavior, BehaviorDescriptor, BehaviorHandler, PortSubscription;
import 'package:flutter/widgets.dart'
    show Widget, StatefulWidget, BuildContext, State;

import '../contexts/container_context.dart' show ContainerContext;
import '../contexts/feature_context.dart' show FeatureContext;
import './port_provider_base.dart';

/// Applies a [Behavior] reactively, rebuilding when the value changes.
///
/// ```dart
/// BehaviorProvider(
///   behavior: themeBehavior,
///   initialValue: BehaviorDescriptor(branch: .light, payload: lightTheme),
///   builder: (result, context) => ThemeWidget(theme: result.payload),
/// )
/// ```
class BehaviorProvider<TBranch extends Enum, TPayload> extends StatefulWidget {
  final Behavior<TBranch, TPayload, BehaviorHandler<TBranch, TPayload>>
  behavior;

  final BehaviorDescriptor<TBranch, TPayload> initialValue;

  final Widget Function(
    BehaviorDescriptor<TBranch, TPayload> value,
    BuildContext context,
  )
  builder;

  const BehaviorProvider({
    super.key,
    required this.behavior,
    required this.initialValue,
    required this.builder,
  });

  @override
  State<BehaviorProvider<TBranch, TPayload>> createState() =>
      _BehaviorProviderState<TBranch, TPayload>();
}

class _BehaviorProviderState<TBranch extends Enum, TPayload>
    extends
        PortProviderState<
          BehaviorDescriptor<TBranch, TPayload>,
          void,
          BehaviorProvider<TBranch, TPayload>
        > {
  @override
  BehaviorDescriptor<TBranch, TPayload> get fallbackValue =>
      widget.initialValue;

  @override
  PortSubscription<BehaviorDescriptor<TBranch, TPayload>, void>
  createSubscription() {
    final container = ContainerContext.of(context).container;
    final feature = FeatureContext.of(context).feature;

    return container.observe(
      rootFeature: feature,
      port: widget.behavior,
      initialValue: widget.initialValue,
      data: null,
      onChanged: safeSetState,
    );
  }

  @override
  void didUpdateWidget(BehaviorProvider<TBranch, TPayload> oldWidget) {
    super.didUpdateWidget(oldWidget);

    if (widget.behavior != oldWidget.behavior) {
      resubscribe();
    } else if (widget.initialValue != oldWidget.initialValue) {
      subscription?.reapply(initialValue: widget.initialValue, data: null);
    }
  }

  @override
  Widget build(BuildContext context) {
    return widget.builder(value, context);
  }
}
