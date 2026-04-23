import 'package:meta/meta.dart';

import '../container/container.dart' show AppContainer;
import '../feature/feature.dart' show Feature;
import '../feature/feature_api.dart' show FeatureHandlerContext;
import '../feature/feature_status.dart' show FeatureStatus;
import './port.dart' show Port;
import './port_type.dart' show PortType;

/// Handler that transforms a pipe value with access to feature context.
typedef PipeHandler<TValue> =
    TValue Function(TValue value, FeatureHandlerContext ctx);

/// Port that chains handlers to transform a value sequentially.
///
/// Handlers run in **registration order** (insertion order on the
/// underlying handler map). Each handler receives the value produced by
/// the previous one; the return value of the last handler is what
/// `AppContainer.apply` observes. Handlers whose owning feature is not
/// `FeatureStatus.active` are skipped transparently — the value passes
/// through unchanged.
class Pipe<TValue extends Object, THandler extends PipeHandler<TValue>>
    extends Port<TValue, void, THandler> {
  @internal
  Pipe({required super.name, super.owner}) : super(type: PortType.pipe);

  @override
  TValue apply({
    required TValue initialValue,
    required AppContainer container,
    required void data,
  }) {
    TValue resultValue = initialValue;

    for (final MapEntry(:key, :value) in handlers.entries) {
      if (container.statusOf(key) == FeatureStatus.active) {
        resultValue = value(resultValue, container.handlerContextFor(key));
      }
    }

    return resultValue;
  }
}

/// Creates a [Pipe], optionally owned by [feature].
Pipe<TValue, PipeHandler<TValue>> createPipe<TValue extends Object>({
  required String name,
  Feature? feature,
}) {
  return Pipe(name: name, owner: feature);
}
