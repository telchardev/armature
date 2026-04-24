import 'package:meta/meta.dart';

import '../container/container.dart' show AppContainer;
import '../feature/feature.dart' show Feature;
import '../feature/feature_api.dart' show FeatureHandlerContext;
import '../feature/feature_status.dart' show FeatureStatus;
import './port.dart' show Port;
import './port_type.dart' show PortType;

/// Descriptor returned by a behavior handler, specifying branch and payload.
class BehaviorDescriptor<TBranch extends Enum, TPayload extends Object?> {
  final TBranch branch;

  final TPayload payload;

  /// Selection weight — **higher wins**. Default `1` so any descriptor
  /// beats the default branch (priority `0`). A descriptor with strictly
  /// higher priority overrides any descriptor already selected; on
  /// equal priority the **first registered** handler's descriptor wins
  /// (see [Behavior.apply]).
  final int priority;

  BehaviorDescriptor({
    required this.branch,
    required this.payload,
    this.priority = 1,
  });
}

/// Handler that produces a [BehaviorDescriptor] from feature context.
///
/// Return `null` to skip this handler.
typedef BehaviorHandler<TBranch extends Enum, TPayload extends Object?> =
    BehaviorDescriptor<TBranch, TPayload>? Function(FeatureHandlerContext ctx);

/// Port that selects the highest-priority handler descriptor.
///
/// `apply` walks every registered handler in **registration order**,
/// skipping handlers from inactive features and handlers that return
/// `null`. Among the remaining descriptors the one with the **strictly
/// greatest** [BehaviorDescriptor.priority] wins; ties are broken by
/// registration order — the **first registered** handler keeps its
/// descriptor. If no handler produces a descriptor, the `initialValue`
/// passed to `apply` is returned as the default branch.
class Behavior<
  TBranch extends Enum,
  TPayload extends Object?,
  THandler extends BehaviorHandler<TBranch, TPayload>
>
    extends Port<BehaviorDescriptor<TBranch, TPayload>, void, THandler> {
  @internal
  Behavior({required super.name, super.owner}) : super(type: PortType.behavior);

  @override
  BehaviorDescriptor<TBranch, TPayload> apply({
    required BehaviorDescriptor<TBranch, TPayload> initialValue,
    required AppContainer container,
    required void data,
  }) {
    BehaviorDescriptor<TBranch, TPayload>? result;
    int maxPriority = 0;

    final handlers = container.handlersOf(this);
    for (final MapEntry(:key, :value) in handlers.entries) {
      if (container.statusOf(key) != FeatureStatus.active) continue;

      final handler = value as BehaviorHandler<TBranch, TPayload>;
      final descriptor = handler(container.handlerContextFor(key));
      if (descriptor == null) continue;

      if (result != null && descriptor.priority <= maxPriority) continue;

      maxPriority = descriptor.priority;
      result = descriptor;
    }

    return result ?? initialValue;
  }
}

/// Creates a [Behavior] owned by [feature].
Behavior<TBranch, TPayload, BehaviorHandler<TBranch, TPayload>> createBehavior<
  TBranch extends Enum,
  TPayload extends Object?
>({required String name, Feature? feature}) {
  return Behavior(name: name, owner: feature);
}
